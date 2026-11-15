import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:url_launcher/url_launcher.dart';

enum PhoneCallFailure { none, unavailable, network, unsupported }

class PhoneCallResult {
  const PhoneCallResult._(this.failure);
  const PhoneCallResult.opened() : this._(PhoneCallFailure.none);
  const PhoneCallResult.failed(PhoneCallFailure failure) : this._(failure);

  final PhoneCallFailure failure;
  bool get opened => failure == PhoneCallFailure.none;
}

typedef PhoneUriLauncher = Future<bool> Function(Uri uri, LaunchMode mode);

class PhoneCallService {
  const PhoneCallService({PhoneUriLauncher? launcher}) : _launcher = launcher;

  final PhoneUriLauncher? _launcher;

  Future<PhoneCallResult> callListing({
    required ListingsService listings,
    required String listingId,
  }) async {
    try {
      final phone = await listings.getCallContact(listingId);
      if (normalizeRuPhoneForApi(phone).isEmpty) {
        return const PhoneCallResult.failed(PhoneCallFailure.unavailable);
      }
      return openNumber(phone);
    } catch (_) {
      return const PhoneCallResult.failed(PhoneCallFailure.network);
    }
  }

  Future<PhoneCallResult> callSeller({
    required ListingsService listings,
    required String sellerId,
  }) async {
    try {
      final phone = await listings.getOwnerCallContact(sellerId);
      if (normalizeRuPhoneForApi(phone).isEmpty) {
        return const PhoneCallResult.failed(PhoneCallFailure.unavailable);
      }
      return openNumber(phone);
    } catch (_) {
      return const PhoneCallResult.failed(PhoneCallFailure.network);
    }
  }

  Future<PhoneCallResult> openNumber(String rawPhone) async {
    final trimmed = rawPhone.trim();
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const PhoneCallResult.failed(PhoneCallFailure.unavailable);
    }
    final dialable = digits.length == 11 && digits.startsWith('8')
        ? '+7${digits.substring(1)}'
        : (trimmed.startsWith('+') ||
                (digits.length == 11 && digits.startsWith('7')))
            ? '+$digits'
            : digits;
    final uri = Uri(scheme: 'tel', path: dialable);
    try {
      final opened = await (_launcher ?? _launch)(
        uri,
        LaunchMode.externalApplication,
      );
      return opened
          ? const PhoneCallResult.opened()
          : const PhoneCallResult.failed(PhoneCallFailure.unsupported);
    } catch (_) {
      return const PhoneCallResult.failed(PhoneCallFailure.unsupported);
    }
  }

  static Future<bool> _launch(Uri uri, LaunchMode mode) =>
      launchUrl(uri, mode: mode);
}
