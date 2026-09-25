import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/web_viewer_device_id.dart';

class UsageAnalyticsService {
  UsageAnalyticsService({ApiClient? api})
      : _api = api ?? ApiClient(tokenStorage: TokenStorage());
  final ApiClient _api;
  static final instance = UsageAnalyticsService();

  Future<void> guestActivity() async {
    if (!ApiConfig.useTimewebBackend) return;
    try {
      final id = await getWebViewerDeviceId();
      if (id == null) return;
      await _api.post('/analytics/guest-activity',
          body: {'guestId': id}, sendAuthIfAvailable: true);
    } catch (_) {
      // Best effort; a later app resume retries the same stable identity.
    }
  }

  Future<void> listingOpen(String listingId, String eventId) async {
    if (!ApiConfig.useTimewebBackend) return;
    try {
      await _api.post('/analytics/listing-open',
          body: {'listingId': listingId, 'eventId': eventId},
          sendAuthIfAvailable: true);
    } catch (_) {
      // Analytics never blocks a listing or changes its public view counter.
    }
  }

  Future<Map<String, dynamic>> dashboard() async => Map<String, dynamic>.from(
      await _api.get('/admin/dashboard/usage', authorized: true) as Map);
}
