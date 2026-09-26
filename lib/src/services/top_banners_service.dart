import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/top_banner.dart';
import '../utils/media_url.dart';
import 'api/api_client.dart';
import 'api/top_banners_api.dart';
import 'auth/token_storage.dart';

class TopBannersService {
  TopBannersService({TopBannersApi? api})
      : _api = api ?? TopBannersApi(ApiClient(tokenStorage: TokenStorage()));
  final TopBannersApi _api;
  final String sessionId = const Uuid().v4();
  Future<TopBanner?>? _sessionSelection;
  Future<TopBanner?>? _displayReady;
  final Set<String> _impressions = {};

  Future<TopBanner?> selectForColdStart() => _sessionSelection ??= _select();

  /// Resolves and preloads the selected image once for this app session.
  /// The returned future completes with a banner only after its image is ready.
  Future<TopBanner?> prepareForDisplay(
    Future<void> Function(String imageUrl) preload,
  ) =>
      _displayReady ??= _prepareForDisplay(preload);

  Future<TopBanner?> _prepareForDisplay(
    Future<void> Function(String imageUrl) preload,
  ) async {
    final banner = await selectForColdStart();
    if (banner == null || banner.imageUrl.trim().isEmpty) return null;
    final imageUrl = resolvePublicMediaUrl(
      banner.imageUrl,
      categoryHint: 'top-banners',
    );
    try {
      await preload(imageUrl);
      return banner;
    } catch (_) {
      return null;
    }
  }

  Future<TopBanner?> _select() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final response =
          await _api.active(prefs.getString('top_banner_last_id') ?? '');
      final raw = response['banner'];
      if (raw is! Map) return null;
      final banner = TopBanner.fromMap(Map<String, dynamic>.from(raw));
      await prefs.setString('top_banner_last_id', banner.id);
      return banner;
    } catch (_) {
      return null;
    }
  }

  Future<void> impression(TopBanner banner) async {
    if (!_impressions.add(banner.id)) return;
    try {
      await _api.track(banner.id, 'impression', sessionId);
    } catch (_) {}
  }

  Future<void> click(TopBanner banner) async {
    try {
      await _api.track(banner.id, 'click', sessionId);
    } catch (_) {}
  }

  Future<List<TopBanner>> list() async {
    final r = await _api.list();
    return (r['items'] as List? ?? [])
        .whereType<Map>()
        .map((e) => TopBanner.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<TopBanner> save(
      {TopBanner? existing,
      required String title,
      required String url,
      required DateTime start,
      required DateTime end,
      required int order}) async {
    final body = {
      'title': title,
      'target_url': url,
      'start_at': start.toUtc().toIso8601String(),
      'end_at': end.toUtc().toIso8601String(),
      'sort_order': order
    };
    final r = existing == null
        ? await _api.create(body)
        : await _api.update(existing.id, body);
    return TopBanner.fromMap(Map<String, dynamic>.from(r['banner'] as Map));
  }

  Future<TopBanner> upload(
      TopBanner banner, Uint8List bytes, String name, String type) async {
    final r = await _api.upload(banner.id, bytes, name, type);
    return TopBanner.fromMap(Map<String, dynamic>.from(r['banner'] as Map));
  }

  Future<void> start(String id) => _api.action(id, 'start');
  Future<void> stop(String id) => _api.action(id, 'stop');
  Future<void> extend(String id, {int? days, DateTime? end}) =>
      _api.action(id, 'extend', {
        if (days != null) 'days': days,
        if (end != null) 'end_at': end.toUtc().toIso8601String()
      });
  Future<void> delete(String id) => _api.delete(id);
  Future<Map<String, dynamic>> stats(String id) => _api.stats(id);
}
