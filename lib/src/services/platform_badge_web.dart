import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

@JS()
extension type _BadgeNavigator(JSObject _) implements JSObject {
  external JSPromise<JSAny?> setAppBadge(JSNumber count);
  external JSPromise<JSAny?> clearAppBadge();
}

Future<bool> isBadgeSupported() async =>
    web.window.isSecureContext &&
    web.window.navigator.hasProperty('setAppBadge'.toJS).toDart &&
    web.window.navigator.hasProperty('clearAppBadge'.toJS).toDart;
Future<void> updateBadge(int count) async {
  final navigator = _BadgeNavigator(web.window.navigator);
  await (count == 0
          ? navigator.clearAppBadge()
          : navigator.setAppBadge(count.toJS))
      .toDart;
}
