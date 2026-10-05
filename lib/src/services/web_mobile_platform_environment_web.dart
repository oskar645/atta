import 'package:web/web.dart' as web;

String get webUserAgent => web.window.navigator.userAgent;
String get webNavigatorPlatform => web.window.navigator.platform;
int get webMaxTouchPoints => web.window.navigator.maxTouchPoints;
