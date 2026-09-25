// Browser storage is intentionally tested in an isolated Flutter test browser.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
@TestOn('browser')
library;

import 'dart:html' as html;
import 'package:atta/src/services/web_viewer_device_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web uses persisted random ID on repeated fresh storage reads',
      () async {
    const key = 'atta.viewerDeviceId';
    final before = html.window.localStorage[key];
    try {
      html.window.localStorage.remove(key);
      final id = await getWebViewerDeviceId();
      expect(id, isNotNull);
      expect(html.window.localStorage[key], id);
      final ids =
          await Future.wait(List.generate(20, (_) => getWebViewerDeviceId()));
      expect(ids.toSet(), {id});
      // Same localStorage survives document reload; reads do not depend on IP or auth.
      expect(await getWebViewerDeviceId(), id);
    } finally {
      if (before == null) {
        html.window.localStorage.remove(key);
      } else {
        html.window.localStorage[key] = before;
      }
    }
  });
}
