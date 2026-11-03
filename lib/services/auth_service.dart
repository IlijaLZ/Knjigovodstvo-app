import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/auth_models.dart';

// Pozivi ka /auth rutama i čuvanje tokena na uređaju.

class AuthService {
  static const _tokensKey = 'auth_tokens';
  static const _userKey = 'auth_user';

  static const Map<String, String> _jsonHeaders = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  static String get deviceName =>
      'Knjigovodstvo (${kIsWeb ? 'web' : defaultTargetPlatform.name})';

  // POST /auth/login
  Future<(User, AuthTokens)> login({
    required String email,
    required String password,
  }) async {
    final http.Response response;

    try {
      response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/auth/login'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'email': email.trim(),
              'password': password,
              'device_name': deviceName,
            }),
          )
          .timeout(ApiConfig.timeout);
    } on TimeoutException {
      throw ApiException('Server ne odgovara. Pokušajte ponovo.');
    } catch (e) {
      debugPrint('Login na ${ApiConfig.baseUrl}/auth/login nije uspio: $e');
      throw ApiException(
        kDebugMode
            ? 'Nije moguće povezati se sa serverom (${ApiConfig.appUrl}).\n$e'
            : 'Nije moguće povezati se sa serverom.',
      );
    }

    final body = _decode(response);

    if (response.statusCode == 200) {
      final user = User.fromJson(body['user'] as Map<String, dynamic>);
      final tokens = AuthTokens.fromJson(
        body['tokens'] as Map<String, dynamic>,
      );
      await _save(user, tokens);
      return (user, tokens);
    }

    throw _error(response.statusCode, body);
  }

  // POST /auth/refresh — šalje refresh token, vraća novi par tokena
  // (stari par se na serveru poništava).
  Future<AuthTokens> refresh(String refreshToken) async {
    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/auth/refresh'),
          headers: {..._jsonHeaders, 'Authorization': 'Bearer $refreshToken'},
        )
        .timeout(ApiConfig.timeout);

    final body = _decode(response);

    if (response.statusCode != 200) throw _error(response.statusCode, body);

    final tokens = AuthTokens.fromJson(body['tokens'] as Map<String, dynamic>);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokensKey, jsonEncode(tokens.toJson()));
    return tokens;
  }

  // POST /auth/logout — briše sesiju na serveru (ako access token još važi)
  // i uvijek briše lokalne tokene.
  Future<void> logout() async {
    final tokens = await savedTokens();

    if (tokens != null) {
      try {
        await http
            .post(
              Uri.parse('${ApiConfig.baseUrl}/auth/logout'),
              headers: {
                ..._jsonHeaders,
                'Authorization': 'Bearer ${tokens.accessToken}',
              },
            )
            .timeout(ApiConfig.timeout);
      } catch (_) {
        // Lokalna odjava ide i bez odgovora servera.
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokensKey);
    await prefs.remove(_userKey);
  }

  Future<AuthTokens?> savedTokens() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tokensKey);
    if (raw == null) return null;

    try {
      return AuthTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<User?> savedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;

    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(User user, AuthTokens tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokensKey, jsonEncode(tokens.toJson()));
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  ApiException _error(int status, Map<String, dynamic> body) {
    final errors = <String, List<String>>{};
    final rawErrors = body['errors'];
    if (rawErrors is Map) {
      rawErrors.forEach((key, value) {
        if (value is List) {
          errors[key.toString()] = value.map((e) => e.toString()).toList();
        }
      });
    }

    final message = switch (status) {
      422 when errors.containsKey('email') => 'Pogrešan email ili lozinka.',
      422 => 'Provjerite unesene podatke.',
      429 => 'Previše pokušaja. Sačekajte minut pa pokušajte ponovo.',
      _ => (body['message'] as String?) ?? 'Greška na serveru ($status).',
    };

    return ApiException(message, statusCode: status, fieldErrors: errors);
  }
}
