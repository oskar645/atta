class ApiConfig {
  static const String publicWebUrl = 'https://attamarket.online';
  static const String publicWebHost = 'attamarket.online';
  static const String publicWebAltHost = 'www.attamarket.online';
  static const String baseUrl = publicWebUrl;
  static const String websocketUrl = 'wss://attamarket.online';
  static const String legacyBackendHost = '5.42.125.179';
  static const bool enablePhoneAuth = true;
  static const bool enableEmailSignup = false;
  static const bool enableEmailLogin = false;
  static const String emailAuthDisabledMessage =
      'Вход по email временно недоступен.';

  static const bool useTimewebBackend = true;

  static const Duration requestTimeout = Duration(seconds: 20);

  static Uri get baseUri => Uri.parse(baseUrl);
  static Uri get publicWebUri => Uri.parse(publicWebUrl);

  static bool isLegacyBackendHost(String host) {
    return host.trim().toLowerCase() == legacyBackendHost;
  }

  static bool isCurrentBackendHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == publicWebHost ||
        normalized == publicWebAltHost ||
        normalized == baseUri.host ||
        normalized == publicWebUri.host;
  }

  static bool isKnownBackendHost(String host) {
    return isCurrentBackendHost(host) || isLegacyBackendHost(host);
  }

  static String normalizeBackendUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty || trimmed.startsWith('file://')) {
      return trimmed;
    }

    final prefixedLegacyUrl = RegExp(r'^5\.42\.125\.179(?::\d+)?(?:[/?#]|$)');
    if (prefixedLegacyUrl.hasMatch(trimmed)) {
      final suffix =
          trimmed.replaceFirst(RegExp(r'^5\.42\.125\.179(?::\d+)?/?'), '');
      return suffix.isEmpty ? publicWebUrl : '$publicWebUrl/$suffix';
    }

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null ||
        parsed.host.isEmpty ||
        !isKnownBackendHost(parsed.host)) {
      return trimmed;
    }

    return publicWebUri
        .replace(
          path: parsed.path,
          query: parsed.hasQuery ? parsed.query : null,
          fragment: parsed.hasFragment ? parsed.fragment : null,
        )
        .toString();
  }

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
