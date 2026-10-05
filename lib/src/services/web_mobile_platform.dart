import 'web_mobile_platform_environment_stub.dart'
    if (dart.library.html) 'web_mobile_platform_environment_web.dart'
    as environment;

enum WebMobilePlatform {
  ios,
  android,
  other,
}

WebMobilePlatform detectWebMobilePlatform({
  required String userAgent,
  String navigatorPlatform = '',
  int maxTouchPoints = 0,
}) {
  final normalizedUserAgent = userAgent.toLowerCase();
  if (normalizedUserAgent.contains('android')) {
    return WebMobilePlatform.android;
  }
  if (normalizedUserAgent.contains('iphone') ||
      normalizedUserAgent.contains('ipad') ||
      normalizedUserAgent.contains('ipod')) {
    return WebMobilePlatform.ios;
  }

  // Since iPadOS 13, Safari can identify an iPad as a Mac. Touch support is
  // the reliable distinction from an actual desktop Mac.
  if (navigatorPlatform.toLowerCase().contains('mac') && maxTouchPoints > 1) {
    return WebMobilePlatform.ios;
  }
  return WebMobilePlatform.other;
}

WebMobilePlatform currentWebMobilePlatform() => detectWebMobilePlatform(
      userAgent: environment.webUserAgent,
      navigatorPlatform: environment.webNavigatorPlatform,
      maxTouchPoints: environment.webMaxTouchPoints,
    );
