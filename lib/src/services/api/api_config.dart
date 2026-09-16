import 'package:atta/src/services/api/runtime_origin.dart' as runtime_origin;

class ApiConfig {
  static const String publicWebUrl = 'https://attamarket.online';
  static const String publicWebHost = 'attamarket.online';
  static const String publicWebAltHost = 'www.attamarket.online';
  static String get baseUrl {
    final origin = runtime_origin.currentOrigin().trim();
    return origin.isEmpty ? publicWebUrl : origin;
  }

  static String get websocketUrl {
    final origin = runtime_origin.currentOrigin().trim();
    if (origin.isEmpty) {
      return 'wss://attamarket.online';
    }
    final uri = Uri.parse(origin);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return uri.replace(scheme: scheme).toString();
  }

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

    final currentOrigin = runtime_origin.currentOrigin().trim();
    final targetBaseUri = currentOrigin.isEmpty ? publicWebUri : baseUri;
    return targetBaseUri
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
