class ApiConfig {
  static const String baseUrl = 'http://5.42.125.179';
  static const String websocketUrl = 'ws://5.42.125.179';
  static const bool enablePhoneAuth = true;
  static const bool enableEmailSignup = false;
  static const bool enableEmailLogin = false;
  static const String emailAuthDisabledMessage =
      'Вход по email временно недоступен.';

  static const bool useTimewebBackend = true;

  static const Duration requestTimeout = Duration(seconds: 20);

  static Uri uri(String path, [Map<String, dynamic>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse(
      '$baseUrl$normalizedPath',
    ).replace(
      queryParameters: queryParameters?.map(
        (key, value) => MapEntry(key, value?.toString()),
      ),
    );
  }
}
