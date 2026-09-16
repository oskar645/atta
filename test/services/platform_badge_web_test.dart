@TestOn('browser')
library;

import 'package:atta/src/services/platform_badge_web.dart' as badge;
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser feature detection and real Badging API calls', () async {
    final supported = await badge.isBadgeSupported();
    // Capability is browser/OS dependent; unsupported is a valid result.
    // ignore: avoid_print
    print('ATTA browser Badging API supported=$supported');
    if (!supported) return;
    try {
      for (final count in [1, 2, 3, 0]) {
        await badge.updateBadge(count);
      }
    } on web.DOMException catch (error) {
      // A browser can expose the API but deny it outside an installed PWA.
      expect(error.name, anyOf('NotAllowedError', 'SecurityError'));
    }
  });
}
