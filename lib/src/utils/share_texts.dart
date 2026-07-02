import 'package:atta/src/constants/app_install_url.dart';
import 'package:atta/src/utils/price_formatter.dart';

const String appInstallUrlNotConfiguredMessage =
    'Ссылка на приложение пока не настроена.';

class ShareTextResult {
  const ShareTextResult._({
    this.text,
    this.errorMessage,
  });

  const ShareTextResult.ready(String text) : this._(text: text);

  const ShareTextResult.error(String message) : this._(errorMessage: message);

  final String? text;
  final String? errorMessage;

  bool get isReady => text != null;
}

ShareTextResult buildListingShareText({
  required String title,
  required int price,
  required String city,
  String? installUrl,
}) {
  final resolvedInstallUrl =
      resolveConfiguredAppInstallUrl(overrideUrl: installUrl);
  if (resolvedInstallUrl == null) {
    return const ShareTextResult.error(appInstallUrlNotConfiguredMessage);
  }

  final normalizedTitle = title.trim().isEmpty ? 'Без названия' : title.trim();
  final normalizedCity = city.trim().isEmpty ? 'Не указан' : city.trim();
  return ShareTextResult.ready(
    'Посмотри объявление в ATTA:\n\n'
    '$normalizedTitle\n'
    'Цена: ${formatPrice(price)}\n'
    'Город: $normalizedCity\n\n'
    'Открыть ATTA:\n'
    '$resolvedInstallUrl',
  );
}

ShareTextResult buildInviteShareText({
  required String currentUserId,
  String? installUrl,
}) {
  final resolvedInstallUrl =
      resolveConfiguredAppInstallUrl(overrideUrl: installUrl);
  if (resolvedInstallUrl == null) {
    return const ShareTextResult.error(appInstallUrlNotConfiguredMessage);
  }

  // TODO: When the public domain is ready, replace the generic app link with
  // https://attamarket.online/listing/{listingId} and the main install page.
  return ShareTextResult.ready(
    'Присоединяйся к ATTA — удобные объявления рядом.\n\n'
    'Скачать приложение:\n'
    '$resolvedInstallUrl',
  );
}
