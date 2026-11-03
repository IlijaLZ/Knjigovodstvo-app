class User {
  final int id;
  final String name;
  final String email;

  User({required this.id, required this.name, required this.email});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}

class AuthTokens {
  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
  final String sessionId;

  AuthTokens({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
    required this.sessionId,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['access_token'] as String,
      accessTokenExpiresAt: DateTime.parse(
        json['access_token_expires_at'] as String,
      ),
      refreshToken: json['refresh_token'] as String,
      refreshTokenExpiresAt: DateTime.parse(
        json['refresh_token_expires_at'] as String,
      ),
      sessionId: json['session_id'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'access_token_expires_at': accessTokenExpiresAt.toIso8601String(),
    'refresh_token': refreshToken,
    'refresh_token_expires_at': refreshTokenExpiresAt.toIso8601String(),
    'session_id': sessionId,
  };

  bool get isRefreshExpired => DateTime.now().isAfter(refreshTokenExpiresAt);
}

// Greška iz API-ja: poruka + greške po poljima (422).
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final Map<String, List<String>> fieldErrors;

  ApiException(this.message, {this.statusCode, this.fieldErrors = const {}});

  String? fieldError(String field) => fieldErrors[field]?.first;

  @override
  String toString() => message;
}
