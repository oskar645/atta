import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:atta/src/models/feed_ad.dart';

class FeedAdsService {
  final SupabaseClient _db = Supabase.instance.client;
  final Uuid _uuid = const Uuid();

  static const String _bucket = 'feed-ads';

  Stream<List<FeedAd>> streamAllAds({String placement = 'home'}) {
    return _db
        .from('feed_ads')
        .stream(primaryKey: ['id'])
        .eq('placement', placement)
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map((row) => FeedAd.fromMap(row))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  Stream<FeedAd?> streamActiveAd({String placement = 'home'}) {
    return streamAllAds(placement: placement).map((ads) {
      final visible = ads.where((ad) => ad.isVisibleNow).toList()
        ..sort((a, b) {
          final aTime = a.activatedAt ?? a.createdAt;
          final bTime = b.activatedAt ?? b.createdAt;
          return bTime.compareTo(aTime);
        });
      return visible.isEmpty ? null : visible.first;
    });
  }

  Future<void> createAd(FeedAd ad) async {
    await _db.from('feed_ads').insert(ad.toMap());
  }

  Future<void> updateAd({
    required String adId,
    required String title,
    required String imageUrl,
    required String targetUrl,
    required int durationDays,
  }) async {
    await _db.from('feed_ads').update({
      'title': title.trim(),
      'image_url': imageUrl.trim(),
      'target_url': targetUrl.trim(),
      'duration_days': durationDays,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', adId);
  }

  Future<void> activateAd(String adId, {String placement = 'home'}) async {
    final now = DateTime.now().toUtc();
    final row = await _db.from('feed_ads').select('*').eq('id', adId).maybeSingle();
    if (row == null) {
      throw Exception('Реклама не найдена');
    }

    final ad = FeedAd.fromMap(row);
    final expiresAt = now.add(Duration(days: ad.durationDays));

    await _db.from('feed_ads').update({
      'is_active': false,
      'updated_at': now.toIso8601String(),
    }).eq('placement', placement);

    await _db.from('feed_ads').update({
      'is_active': true,
      'activated_at': now.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'updated_at': now.toIso8601String(),
    }).eq('id', adId);
  }

  Future<void> deactivateAd(String adId) async {
    await _db.from('feed_ads').update({
      'is_active': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', adId);
  }

  Future<void> deleteAd(String adId) async {
    await _db.from('feed_ads').delete().eq('id', adId);
  }

  Future<void> recordImpression(String adId) async {
    await _trackEvent(adId: adId, event: 'impression');
  }

  Future<void> recordClick(String adId) async {
    await _trackEvent(adId: adId, event: 'click');
  }

  Future<void> _trackEvent({
    required String adId,
    required String event,
  }) async {
    await _db.rpc('track_feed_ad_event', params: {
      'p_ad_id': adId,
      'p_event': event,
    });
  }

  Future<String> uploadAdImage({
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final ext = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path = 'home/${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}.$ext';

    await _db.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: false,
            contentType: contentType,
          ),
        );

    return _db.storage.from(_bucket).getPublicUrl(path);
  }
}
