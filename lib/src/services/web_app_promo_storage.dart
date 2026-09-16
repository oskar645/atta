import 'web_app_promo_storage_stub.dart'
    if (dart.library.html) 'web_app_promo_storage_web.dart';

const Duration webAppPromoCooldown = Duration(hours: 48);
const String webAppPromoAppStoreUrl =
    'https://apps.apple.com/us/app/atta/id6762604298';
const String webAppPromoGooglePlayUrl =
    'https://play.google.com/store/apps/details?id=online.attomarket.atta';

bool shouldShowWebAppPromo({DateTime? now}) {
  final stored = readWebAppPromoDismissedAt();
  return shouldShowWebAppPromoForTimestamp(stored, now: now);
}

bool shouldShowWebAppPromoForTimestamp(int? stored, {DateTime? now}) {
  if (stored == null || stored <= 0) return true;
  final current = (now ?? DateTime.now()).millisecondsSinceEpoch;
  return current - stored >= webAppPromoCooldown.inMilliseconds;
}

void markWebAppPromoDismissed({DateTime? now}) {
  writeWebAppPromoDismissedAt(
    (now ?? DateTime.now()).millisecondsSinceEpoch,
  );
}
