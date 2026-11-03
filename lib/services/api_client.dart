import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import '../models/auth_models.dart';
import 'auth_service.dart';

// Pozivi sa access tokenom. Istekao access token se osvježava refresh
// tokenom (jednom, i za više istovremenih poziva); ako ni to ne uspije,
// korisnik se odjavljuje.

class ApiClient {
  static Future<bool>? _osvjezavanje;

  final AuthService _authService = AuthService();

  AuthController get _auth => Get.find<AuthController>();

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _request('GET', path, query: query);

  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, dynamic>? body,
  ]) => _request('POST', path, body: body);

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) =>
      _request('PATCH', path, body: body);

  // DELETE vraća 204 bez tijela.
  Future<void> delete(String path) => _request('DELETE', path);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}$path',
    ).replace(queryParameters: query);

    final tokens = _auth.tokens.value;
    if (tokens != null && DateTime.now().isAfter(tokens.accessTokenExpiresAt)) {
      await _osvjeziToken();
    }

    var response = await _send(method, uri, body);
    if (response.statusCode == 401 && await _osvjeziToken()) {
      response = await _send(method, uri, body);
    }

    final decoded = _decode(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    if (response.statusCode == 401) {
      _auth.logout();
      throw ApiException(
        'Sesija je istekla. Prijavite se ponovo.',
        statusCode: 401,
      );
    }

    throw _error(response.statusCode, decoded);
  }

  Future<http.Response> _send(
    String method,
    Uri uri,
    Map<String, dynamic>? body,
  ) async {
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer ${_auth.tokens.value?.accessToken}',
      });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    try {
      return await http.Response.fromStream(
        await request.send().timeout(ApiConfig.timeout),
      );
    } on TimeoutException {
      throw ApiException('Server ne odgovara. Pokušajte ponovo.');
    } catch (e) {
      debugPrint('$method $uri nije uspio: $e');
      throw ApiException('Nije moguće povezati se sa serverom.');
    }
  }

  Future<bool> _osvjeziToken() {
    return _osvjezavanje ??= _refresh().whenComplete(
      () => _osvjezavanje = null,
    );
  }

  Future<bool> _refresh() async {
    final tokens = _auth.tokens.value;
    if (tokens == null || tokens.isRefreshExpired) return false;

    try {
      _auth.tokens.value = await _authService.refresh(tokens.refreshToken);
      return true;
    } catch (e) {
      debugPrint('Osvježavanje tokena nije uspjelo: $e');
      return false;
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  // 422 nosi greške po poljima (errors); prva se prikazuje kao poruka.
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
      422 when errors.isNotEmpty => errors.values.first.first,
      429 => 'Previše zahtjeva. Sačekajte minut pa pokušajte ponovo.',
      _ => (body['message'] as String?) ?? 'Greška na serveru ($status).',
    };

    return ApiException(message, statusCode: status, fieldErrors: errors);
  }
}
