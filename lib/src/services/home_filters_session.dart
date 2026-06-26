import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class HomeFiltersState {
  final String category;
  final String subcategory;
  final String location;
  final bool preferLocationFirst;
  final int? radiusKm;
  final String autoBrand;
  final String autoModel;
  final String autoCondition;
  final int? autoMileageTo;
  final bool onlyUncrashed;
  final String search;

  const HomeFiltersState({
    required this.category,
    required this.subcategory,
    required this.location,
    required this.preferLocationFirst,
    required this.radiusKm,
    required this.autoBrand,
    required this.autoModel,
    required this.autoCondition,
    required this.autoMileageTo,
    required this.onlyUncrashed,
    required this.search,
  });

  Map<String, dynamic> toJson() => {
        'category': category,
        'subcategory': subcategory,
        'location': location,
        'preferLocationFirst': preferLocationFirst,
        'radiusKm': radiusKm,
        'autoBrand': autoBrand,
        'autoModel': autoModel,
        'autoCondition': autoCondition,
        'autoMileageTo': autoMileageTo,
        'onlyUncrashed': onlyUncrashed,
        'search': search,
      };

  static HomeFiltersState fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return HomeFiltersState(
      category: (json['category'] ?? 'Все').toString(),
      subcategory: (json['subcategory'] ?? 'Все').toString(),
      location: (json['location'] ?? '').toString(),
      preferLocationFirst: json['preferLocationFirst'] == true,
      radiusKm: parseInt(json['radiusKm']),
      autoBrand: (json['autoBrand'] ?? '').toString(),
      autoModel: (json['autoModel'] ?? '').toString(),
      autoCondition: (json['autoCondition'] ?? '').toString(),
      autoMileageTo: parseInt(json['autoMileageTo']),
      onlyUncrashed: json['onlyUncrashed'] == true,
      search: (json['search'] ?? '').toString(),
    );
  }
}

class HomeFiltersSession {
  HomeFiltersSession._();

  static final HomeFiltersSession instance = HomeFiltersSession._();

  static const _prefix = 'home_filters_';

  String _normalizeUid(String uid) {
    final t = uid.trim();
    return t.isEmpty ? 'guest' : t;
  }

  Future<HomeFiltersState?> read(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix${_normalizeUid(uid)}');
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      return HomeFiltersState.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> write({
    required String uid,
    required String category,
    required String subcategory,
    required String location,
    required bool preferLocationFirst,
    required int? radiusKm,
    required String autoBrand,
    required String autoModel,
    required String autoCondition,
    required int? autoMileageTo,
    required bool onlyUncrashed,
    required String search,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final state = HomeFiltersState(
      category: category,
      subcategory: subcategory,
      location: location,
      preferLocationFirst: preferLocationFirst,
      radiusKm: radiusKm,
      autoBrand: autoBrand,
      autoModel: autoModel,
      autoCondition: autoCondition,
      autoMileageTo: autoMileageTo,
      onlyUncrashed: onlyUncrashed,
      search: search,
    );
    await prefs.setString(
        '$_prefix${_normalizeUid(uid)}', json.encode(state.toJson()));
  }

  Future<void> clear(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix${_normalizeUid(uid)}');
  }
}

final homeFiltersSession = HomeFiltersSession.instance;
