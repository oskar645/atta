import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class HomeFiltersState {
  final String category;
  final String subcategory;
  final int? priceFrom;
  final int? priceTo;
  final String location;
  final bool preferLocationFirst;
  final int? radiusKm;
  final String autoBrand;
  final String autoModel;
  final String autoCondition;
  final int? autoYearFrom;
  final int? autoYearTo;
  final int? autoMileageFrom;
  final int? autoMileageTo;
  final String autoTransmission;
  final String autoDrive;
  final String autoBodyType;
  final String autoFuel;
  final String autoColor;
  final double? autoEngineVolumeFrom;
  final double? autoEngineVolumeTo;
  final int? autoOwners;
  final bool? autoCleared;
  final bool onlyUncrashed;
  final bool onlyWithPhoto;
  final String search;

  const HomeFiltersState({
    required this.category,
    required this.subcategory,
    required this.priceFrom,
    required this.priceTo,
    required this.location,
    required this.preferLocationFirst,
    required this.radiusKm,
    required this.autoBrand,
    required this.autoModel,
    required this.autoCondition,
    required this.autoYearFrom,
    required this.autoYearTo,
    required this.autoMileageFrom,
    required this.autoMileageTo,
    required this.autoTransmission,
    required this.autoDrive,
    required this.autoBodyType,
    required this.autoFuel,
    required this.autoColor,
    required this.autoEngineVolumeFrom,
    required this.autoEngineVolumeTo,
    required this.autoOwners,
    required this.autoCleared,
    required this.onlyUncrashed,
    required this.onlyWithPhoto,
    required this.search,
  });

  Map<String, dynamic> toJson() => {
        'category': category,
        'subcategory': subcategory,
        'priceFrom': priceFrom,
        'priceTo': priceTo,
        'location': location,
        'preferLocationFirst': preferLocationFirst,
        'radiusKm': radiusKm,
        'autoBrand': autoBrand,
        'autoModel': autoModel,
        'autoCondition': autoCondition,
        'autoYearFrom': autoYearFrom,
        'autoYearTo': autoYearTo,
        'autoMileageFrom': autoMileageFrom,
        'autoMileageTo': autoMileageTo,
        'autoTransmission': autoTransmission,
        'autoDrive': autoDrive,
        'autoBodyType': autoBodyType,
        'autoFuel': autoFuel,
        'autoColor': autoColor,
        'autoEngineVolumeFrom': autoEngineVolumeFrom,
        'autoEngineVolumeTo': autoEngineVolumeTo,
        'autoOwners': autoOwners,
        'autoCleared': autoCleared,
        'onlyUncrashed': onlyUncrashed,
        'onlyWithPhoto': onlyWithPhoto,
        'search': search,
      };

  static HomeFiltersState fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    double? parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return HomeFiltersState(
      category: (json['category'] ?? 'Все').toString(),
      subcategory: (json['subcategory'] ?? 'Все').toString(),
      priceFrom: parseInt(json['priceFrom']),
      priceTo: parseInt(json['priceTo']),
      location: (json['location'] ?? '').toString(),
      preferLocationFirst: json['preferLocationFirst'] == true,
      radiusKm: parseInt(json['radiusKm']),
      autoBrand: (json['autoBrand'] ?? '').toString(),
      autoModel: (json['autoModel'] ?? '').toString(),
      autoCondition: (json['autoCondition'] ?? '').toString(),
      autoYearFrom: parseInt(json['autoYearFrom']),
      autoYearTo: parseInt(json['autoYearTo']),
      autoMileageFrom: parseInt(json['autoMileageFrom']),
      autoMileageTo: parseInt(json['autoMileageTo']),
      autoTransmission: (json['autoTransmission'] ?? '').toString(),
      autoDrive: (json['autoDrive'] ?? '').toString(),
      autoBodyType: (json['autoBodyType'] ?? '').toString(),
      autoFuel: (json['autoFuel'] ?? '').toString(),
      autoColor: (json['autoColor'] ?? '').toString(),
      autoEngineVolumeFrom: parseDouble(json['autoEngineVolumeFrom']),
      autoEngineVolumeTo: parseDouble(json['autoEngineVolumeTo']),
      autoOwners: parseInt(json['autoOwners']),
      autoCleared:
          json['autoCleared'] is bool ? json['autoCleared'] as bool : null,
      onlyUncrashed: json['onlyUncrashed'] == true,
      onlyWithPhoto: json['onlyWithPhoto'] == true,
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
    required int? priceFrom,
    required int? priceTo,
    required String location,
    required bool preferLocationFirst,
    required int? radiusKm,
    required String autoBrand,
    required String autoModel,
    required String autoCondition,
    required int? autoYearFrom,
    required int? autoYearTo,
    required int? autoMileageFrom,
    required int? autoMileageTo,
    required String autoTransmission,
    required String autoDrive,
    required String autoBodyType,
    required String autoFuel,
    required String autoColor,
    required double? autoEngineVolumeFrom,
    required double? autoEngineVolumeTo,
    required int? autoOwners,
    required bool? autoCleared,
    required bool onlyUncrashed,
    required bool onlyWithPhoto,
    required String search,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final state = HomeFiltersState(
      category: category,
      subcategory: subcategory,
      priceFrom: priceFrom,
      priceTo: priceTo,
      location: location,
      preferLocationFirst: preferLocationFirst,
      radiusKm: radiusKm,
      autoBrand: autoBrand,
      autoModel: autoModel,
      autoCondition: autoCondition,
      autoYearFrom: autoYearFrom,
      autoYearTo: autoYearTo,
      autoMileageFrom: autoMileageFrom,
      autoMileageTo: autoMileageTo,
      autoTransmission: autoTransmission,
      autoDrive: autoDrive,
      autoBodyType: autoBodyType,
      autoFuel: autoFuel,
      autoColor: autoColor,
      autoEngineVolumeFrom: autoEngineVolumeFrom,
      autoEngineVolumeTo: autoEngineVolumeTo,
      autoOwners: autoOwners,
      autoCleared: autoCleared,
      onlyUncrashed: onlyUncrashed,
      onlyWithPhoto: onlyWithPhoto,
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
