import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AttaDeepLinkType {
  listing,
  invite,
}

class AttaDeepLink {
  const AttaDeepLink.listing({
    required this.uri,
    required this.listingId,
  })  : type = AttaDeepLinkType.listing,
        referrerId = null;

  const AttaDeepLink.invite({
    required this.uri,
    required this.referrerId,
  })  : type = AttaDeepLinkType.invite,
        listingId = null;

  final AttaDeepLinkType type;
  final Uri uri;
  final String? listingId;
  final String? referrerId;
}

class DeepLinkService {
  DeepLinkService({
    AppLinks? appLinks,
  }) : _appLinks = appLinks ?? AppLinks();

  static const String pendingListingIdKey = 'pending_deep_link_listing_id';
  static const String pendingInviteReferrerIdKey =
      'pending_deep_link_invite_referrer_id';

  final AppLinks _appLinks;
  final StreamController<AttaDeepLink> _links =
      StreamController<AttaDeepLink>.broadcast();

  StreamSubscription<Uri>? _uriSub;
  bool _initialized = false;

  Stream<AttaDeepLink> get links => _links.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      final parsed = parseAttaDeepLink(initialUri);
      if (parsed != null) {
        _links.add(parsed);
      }
    }

    _uriSub = _appLinks.uriLinkStream.listen((uri) {
      final parsed = parseAttaDeepLink(uri);
      if (parsed != null) {
        _links.add(parsed);
      }
    });
  }

  Future<void> savePendingListingId(String listingId) async {
    final normalized = listingId.trim();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(pendingListingIdKey, normalized);
  }

  Future<String?> readPendingListingId() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(pendingListingIdKey)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<String?> consumePendingListingId() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(pendingListingIdKey)?.trim();
    await prefs.remove(pendingListingIdKey);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> clearPendingListingIdIfMatches(String listingId) async {
    final normalized = listingId.trim();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(pendingListingIdKey)?.trim();
    if (current == normalized) {
      await prefs.remove(pendingListingIdKey);
    }
  }

  Future<void> savePendingInviteReferrerId(String referrerId) async {
    final normalized = referrerId.trim();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(pendingInviteReferrerIdKey, normalized);
  }

  Future<String?> readPendingInviteReferrerId() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(pendingInviteReferrerIdKey)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> dispose() async {
    await _uriSub?.cancel();
    await _links.close();
  }
}

AttaDeepLink? parseAttaDeepLink(Uri uri) {
  final scheme = uri.scheme.trim().toLowerCase();
  if (scheme != 'atta') return null;

  final host = uri.host.trim().toLowerCase();
  if (host == 'listing') {
    final listingId = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    final normalizedListingId = listingId.trim();
    if (normalizedListingId.isEmpty) return null;
    return AttaDeepLink.listing(
      uri: uri,
      listingId: normalizedListingId,
    );
  }

  if (host == 'invite') {
    final referrerId = (uri.queryParameters['ref'] ?? '').trim();
    if (referrerId.isEmpty) return null;
    return AttaDeepLink.invite(
      uri: uri,
      referrerId: referrerId,
    );
  }

  return null;
}
