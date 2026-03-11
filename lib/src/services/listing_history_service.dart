import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ListingHistoryService extends ChangeNotifier {
  static const String _prefsKey = 'listing_history_v1';
  static const int _maxItems = 300;

  final Set<String> _viewedIds = <String>{};
  bool _loaded = false;

  ListingHistoryService() {
    _load();
  }

  bool get isLoaded => _loaded;

  bool hasViewed(String listingId) {
    return _viewedIds.contains(listingId.trim());
  }

  Future<void> markViewed(String listingId) async {
    final id = listingId.trim();
    if (id.isEmpty) return;

    final before = _viewedIds.length;
    _viewedIds.remove(id);
    _viewedIds.add(id);

    if (_viewedIds.length > _maxItems) {
      final overflow = _viewedIds.length - _maxItems;
      _viewedIds.removeAll(_viewedIds.take(overflow));
    }

    if (_viewedIds.length != before || !_loaded) {
      notifyListeners();
    }

    await _save();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsKey) ?? const <String>[];
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
    await prefs.setStringList(_prefsKey, _viewedIds.toList(growable: false));
  }
}
