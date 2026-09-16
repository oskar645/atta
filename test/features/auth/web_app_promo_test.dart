import 'package:atta/src/services/web_app_promo_storage.dart';
import 'package:atta/src/services/web_viewer_device_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('web app promo store URLs are correct', () {
    expect(
      webAppPromoAppStoreUrl,
      'https://apps.apple.com/us/app/atta/id6762604298',
    );
    expect(
      webAppPromoGooglePlayUrl,
      'https://play.google.com/store/apps/details?id=online.attomarket.atta',
    );
  });

  test('web app promo cooldown is 48 hours', () {
    expect(webAppPromoCooldown, const Duration(hours: 48));
  });

  test('web app promo shows first time and respects cooldown', () {
    final now = DateTime(2026, 9, 13, 12);

    expect(shouldShowWebAppPromoForTimestamp(null, now: now), isTrue);
    expect(
      shouldShowWebAppPromoForTimestamp(
        now
            .subtract(const Duration(hours: 47, minutes: 59))
            .millisecondsSinceEpoch,
        now: now,
      ),
      isFalse,
    );
    expect(
      shouldShowWebAppPromoForTimestamp(
        now.subtract(const Duration(hours: 48)).millisecondsSinceEpoch,
        now: now,
      ),
      isTrue,
    );
  });

  test('guest viewer device id is random and stable in local storage',
      () async {
    final first = await getWebViewerDeviceId();
    final second = await getWebViewerDeviceId();

    expect(first, isNotNull);
    expect(first, isNotEmpty);
    expect(second, first);
  });
}
