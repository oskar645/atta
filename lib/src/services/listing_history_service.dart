import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/api/viewed_listings_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';

class ListingHistoryService extends ChangeNotifier {
  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);
  static final ViewedListingsApi _api = ViewedListingsApi(_apiClient);
  static const String _legacyPrefsKey = 'listing_history_v1';
  static const String _prefsKeyPrefix = 'listing_history_v2';
  static const int _maxItems = 300;

  final Set<String> _viewedIds = <String>{};
  bool _loaded = false;

  ListingHistoryService() {
    _load();
  }

  bool get isLoaded => _loaded;

  List<String> get viewedIdsNewestFirst =>
      _viewedIds.toList(growable: false).reversed.toList(growable: false);

  bool hasViewed(String listingId) {
    return _viewedIds.contains(listingId.trim());
  }

  Future<void> markViewed(String listingId) async {
    final id = listingId.trim();
    if (id.isEmpty) return;

    final before = _viewedIds.toList(growable: false);
    _viewedIds.remove(id);
    _viewedIds.add(id);

    if (_viewedIds.length > _maxItems) {
      final overflow = _viewedIds.length - _maxItems;
      _viewedIds.removeAll(_viewedIds.take(overflow));
    }

    if (!_listEquals(before, _viewedIds.toList(growable: false)) || !_loaded) {
      notifyListeners();
    }

    await _save();
    if (ApiConfig.useTimewebBackend) {
      try {
        await _api.mark(id);
      } catch (_) {}
    }
  }

  Future<void> activateSession() async {
    await _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(await _prefsKey()) ?? const <String>[];
    _viewedIds
      ..clear()
      ..addAll(
        stored.map((e) => e.trim()).where((e) => e.isNotEmpty).take(_maxItems),
      );
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      await _prefsKey(),
      _viewedIds.toList(growable: false),
    );
  }

  Future<void> resetSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _prefsKey());
    await prefs.remove(_legacyPrefsKey);
    _viewedIds.clear();
    _loaded = true;
    notifyListeners();
  }

  Future<String> _prefsKey() async {
    final user = await _tokenStorage.readCurrentUser();
    final uid = user?.uid.trim() ?? '';
    if (uid.isEmpty) {
      return '$_prefsKeyPrefix:anonymous';
    }
    return '$_prefsKeyPrefix:$uid';
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
