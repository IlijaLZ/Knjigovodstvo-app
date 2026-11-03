// Adresa API-ja se zadaje pri pokretanju:
//   flutter run --dart-define=APP_URL=https://api.example.com
// Ako nije zadata, koristi se produkcioni server.

class ApiConfig {
  static const String appUrl = String.fromEnvironment(
    'APP_URL',
    defaultValue: 'https://lavistabeddingaccounting.com',
  );

  static const String baseUrl = '$appUrl/api/v1';

  static const Duration timeout = Duration(seconds: 20);
}
