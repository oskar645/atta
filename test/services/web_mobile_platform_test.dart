import 'package:atta/src/services/web_mobile_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects Android browsers', () {
    expect(
      detectWebMobilePlatform(
        userAgent:
            'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36',
      ),
      WebMobilePlatform.android,
    );
  });

  test('detects iPhone and iPad browsers', () {
    expect(
      detectWebMobilePlatform(
        userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)',
      ),
      WebMobilePlatform.ios,
    );
    expect(
      detectWebMobilePlatform(
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15)',
        navigatorPlatform: 'MacIntel',
        maxTouchPoints: 5,
      ),
      WebMobilePlatform.ios,
    );
  });

  test('keeps desktop and unknown browsers neutral', () {
    expect(
      detectWebMobilePlatform(
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15)',
        navigatorPlatform: 'MacIntel',
      ),
      WebMobilePlatform.other,
    );
  });
}
