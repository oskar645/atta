import 'package:atta/src/constants/app_install_url.dart';
import 'package:atta/src/services/api/api_config.dart';
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
  required String listingId,
  required String title,
  required int price,
  required String city,
}) {
  final normalizedListingId = listingId.trim();
  if (normalizedListingId.isEmpty) {
    return const ShareTextResult.error('Ссылка на объявление пока недоступна.');
  }

  final normalizedTitle = title.trim().isEmpty ? 'Без названия' : title.trim();
  final normalizedCity = city.trim().isEmpty ? 'Не указан' : city.trim();
  final listingUrl =
      '${ApiConfig.publicWebUrl}/listing/${Uri.encodeComponent(normalizedListingId)}';
  return ShareTextResult.ready(
    'Посмотри объявление в ATTA:\n\n'
    '$normalizedTitle\n'
    'Цена: ${formatPrice(price)}\n'
    'Город: $normalizedCity\n\n'
    'Открыть объявление:\n'
    '$listingUrl',
  );
}

ShareTextResult buildInviteShareText({
  required String referralCode,
  String? installUrl,
}) {
  final resolvedInstallUrl =
      resolveConfiguredInviteShareUrl(overrideUrl: installUrl);
  if (resolvedInstallUrl == null) {
    return const ShareTextResult.error(appInstallUrlNotConfiguredMessage);
  }
  final normalizedReferralCode = referralCode.trim();
  final inviteUrl = normalizedReferralCode.isEmpty
      ? resolvedInstallUrl
      : Uri.parse(resolvedInstallUrl).replace(
          queryParameters: <String, String>{
            ...Uri.parse(resolvedInstallUrl).queryParameters,
            'ref': normalizedReferralCode,
          },
        ).toString();

  return ShareTextResult.ready(
    'Привет! Я пользуюсь ATTA — приложением для объявлений. Попробуй тоже:\n'
    '$inviteUrl',
  );
}
