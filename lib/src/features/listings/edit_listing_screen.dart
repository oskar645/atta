import 'dart:async';
import 'dart:io';

import 'package:atta/src/data/auto_catalog.dart';

import 'package:atta/src/features/listings/car_parameters_screen.dart';
import 'package:atta/src/features/listings/pick_location_screen.dart';
import 'package:atta/src/models/car_specs.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:atta/src/utils/vehicle_specs.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:provider/provider.dart';

class EditListingScreen extends StatefulWidget {
  final String listingId;
  const EditListingScreen({super.key, required this.listingId});

  @override
  State<EditListingScreen> createState() => _EditListingScreenState();
}

enum _EditPhotoState {
  waiting,
  preparing,
  uploading,
  uploaded,
  failed,
  deleting
}

class _EditNewPhotoItem {
  const _EditNewPhotoItem({
    required this.localId,
    required this.file,
    required this.sourceIndex,
    this.state = _EditPhotoState.waiting,
    this.statusText,
    this.photoId = '',
  });

  final String localId;
  final File file;
  final int sourceIndex;
  final _EditPhotoState state;
  final String? statusText;
  final String photoId;

  _EditNewPhotoItem copyWith({
    _EditPhotoState? state,
    String? statusText,
    bool clearStatusText = false,
    int? sourceIndex,
    String? photoId,
  }) {
    return _EditNewPhotoItem(
      localId: localId,
      file: file,
      sourceIndex: sourceIndex ?? this.sourceIndex,
      state: state ?? this.state,
      statusText: clearStatusText ? null : (statusText ?? this.statusText),
      photoId: photoId ?? this.photoId,
    );
  }
}

class _EditListingScreenState extends State<EditListingScreen> {
  bool _inited = false;
  bool _saving = false;
  bool _loading = true;
  String? _loadError;
  Listing? _listing;
  final _newPhotos = <_EditNewPhotoItem>[];
  final _removedPhotoIds = <String>{};
  final _picker = ImagePicker();
  int _nextPhotoLocalId = 0;

  final _title = TextEditingController();
  final _city = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _phone = TextEditingController();

  // авто
  final _carYear = TextEditingController();
  final _carMileage = TextEditingController();
  final _carEngine = TextEditingController();
  final _carPower = TextEditingController();
  final _carOwners = TextEditingController();
  final _carVin = TextEditingController();
  final _carNote = TextEditingController();

  String _category = '';
  bool _phoneHidden = true;
  String _subcategory = '';
  String _lastTitleSuggestion = '';

  // smart авто
  String? _autoBrand;
  String? _autoModel;
  String? _autoGen;

  // авто selects
  String? _carBody;
  String? _carFuel;
  String? _carTransmission;
  String? _carDrive;
  String? _carCondition;
  String? _carColor;
  bool? _carCleared;
  String? _carPts;

  final Map<String, String> _deliveryNames = const {
    'cdek': 'СДЭК',
    'ozon': 'Ozon',
    'pek': 'ПЭК',
    'boxberry': 'Boxberry',
    'dpd': 'DPD',
    'delovie': 'Деловые линии',
    'energia': 'Энергия',
    'kit': 'КИТ',
    'pochta': 'Почта России',
    'pickup': 'Самовывоз',
  };

  late final Map<String, bool> _delivery = {
    for (final k in _deliveryNames.keys) k: false,
  };

  bool get _isAuto => _category == 'Авто';

  bool get _isPassengerCar =>
      _isAuto && isPassengerCarsSubcategory(_subcategory);
  bool get _isUploadingPhotos => _newPhotos.any(
        (item) =>
            item.state == _EditPhotoState.preparing ||
            item.state == _EditPhotoState.uploading,
      );
  bool get _hasFailedPhotos => _newPhotos.any(
        (item) => item.state == _EditPhotoState.failed,
      );
  bool get _hasUploadedNewPhotos => _newPhotos.any(
        (item) => item.state == _EditPhotoState.uploaded,
      );

  static const _bodyTypes = <String>[
    'Седан',
    'Хэтчбек',
    'Универсал',
    'Кроссовер',
    'Внедорожник',
    'Купе',
    'Кабриолет',
    'Минивэн',
    'Пикап',
    'Фургон',
    'Лифтбек',
    'Другое',
  ];

  static const _fuelTypes = <String>[
    'Бензин',
    'Дизель',
    'Гибрид',
    'Электро',
    'Газ',
    'Другое',
  ];

  static const _transmissions = <String>[
    'Механика',
    'Автомат',
    'Вариатор',
    'Робот',
    'Другое',
  ];

  static const _drives = <String>[
    'Передний',
    'Задний',
    'Полный',
  ];

  static const _conditions = <String>[
    'Отличное',
    'Хорошее',
    'Среднее',
    'Требует ремонта',
    'Небитый',
    'Битый',
  ];

  static const _colors = <String>[
    'Чёрный',
    'Белый',
    'Серый',
    'Серебристый',
    'Синий',
    'Красный',
    'Зелёный',
    'Жёлтый',
    'Коричневый',
    'Бежевый',
    'Оранжевый',
    'Фиолетовый',
    'Другой',
  ];

  static const _ptsTypes = <String>[
    'Оригинал',
    'Дубликат',
    'Электронный',
    'Нет',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadListing());
  }

  @override
  void dispose() {
    _title.dispose();
    _city.dispose();
    _desc.dispose();
    _price.dispose();
    _phone.dispose();

    _carYear.dispose();
    _carMileage.dispose();
    _carEngine.dispose();
    _carPower.dispose();
    _carOwners.dispose();
    _carVin.dispose();
    _carNote.dispose();
    super.dispose();
  }

  Future<void> _loadListing() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final listing = await context
          .read<ListingsService>()
          .getListingById(widget.listingId);
      if (!mounted) return;
      if (listing == null) {
        setState(() {
          _loadError = 'Не удалось загрузить объявление';
          _loading = false;
        });
        return;
      }
      _initFromListing(listing);
      setState(() {
        _listing = listing;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Не удалось загрузить объявление';
        _loading = false;
      });
    }
  }

  void _initFromListing(Listing l) {
    if (_inited) return;
    _inited = true;

    _category = l.category;
    _subcategory = l.subcategory;

    _title.text = l.title;
    _city.text = l.city;
    _desc.text = l.description;
    _price.text = formatPrice(l.price);
    _phone.text = formatRuPhoneForField(l.phone);
    _phoneHidden = l.phoneHidden;

    for (final k in _delivery.keys) {
      _delivery[k] = l.delivery[k] == true;
    }

    if (l.car != null) {
      final c = l.car!;
      _autoBrand = c.brand;
      _autoModel = c.model;
      _autoGen = c.generation.trim().isEmpty ? null : c.generation;

      _carYear.text = c.year?.toString() ?? '';
      _carMileage.text = c.mileageKm?.toString() ?? '';
      _carEngine.text =
          c.engineVolume == null ? '' : formatEngineVolume(c.engineVolume);
      _carPower.text = c.powerHp?.toString() ?? '';
      _carOwners.text = c.owners?.toString() ?? '';
      _carVin.text = c.vin ?? '';
      _carNote.text = c.note ?? '';

      _carBody = (c.bodyType ?? '').trim().isEmpty ? null : c.bodyType;
      _carFuel = (c.fuel ?? '').trim().isEmpty ? null : c.fuel;
      _carTransmission =
          (c.transmission ?? '').trim().isEmpty ? null : c.transmission;
      _carDrive = (c.drive ?? '').trim().isEmpty ? null : c.drive;
      _carCondition = (c.condition ?? '').trim().isEmpty ? null : c.condition;
      _carColor = (c.color ?? '').trim().isEmpty ? null : c.color;
      _carCleared = c.isCleared;
      _carPts = (c.pts ?? '').trim().isEmpty ? null : c.pts;
    }

    _lastTitleSuggestion = _buildTitleSuggestion();
  }

  Future<void> _fillCityFromLatLng(latlng.LatLng p) async {
    try {
      final placemarks =
          await placemarkFromCoordinates(p.latitude, p.longitude);
      if (placemarks.isEmpty) return;
      final pm = placemarks.first;

      final parts = <String>[
        if ((pm.administrativeArea ?? '').trim().isNotEmpty)
          pm.administrativeArea!,
        if ((pm.subAdministrativeArea ?? '').trim().isNotEmpty)
          pm.subAdministrativeArea!,
        if ((pm.locality ?? '').trim().isNotEmpty) pm.locality!,
        if ((pm.subLocality ?? '').trim().isNotEmpty) pm.subLocality!,
      ];

      final text = parts.join(', ').trim();
      if (text.isNotEmpty) _city.text = text;
    } catch (_) {}
  }

  Future<void> _openMap() async {
    final res = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(builder: (_) => const PickLocationScreen()),
    );
    if (res == null) return;
    if (res is latlng.LatLng) {
      await _fillCityFromLatLng(res);
      if (mounted) setState(() {});
      return;
    }
    if (res is String) {
      _city.text = res;
      if (mounted) setState(() {});
    }
  }

  String _deliverySummary() {
    final selected = _delivery.entries
        .where((e) => e.value == true)
        .map((e) => _deliveryNames[e.key] ?? e.key)
        .toList();

    if (selected.isEmpty) return 'Не выбрано';
    return selected.join(', ');
  }

  Future<void> _openDeliveryPicker() async {
    final tmp = Map<String, bool>.from(_delivery);

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setModal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Выберите доставку',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _deliveryNames.entries.map((e) {
                    final key = e.key;
                    return CheckboxListTile(
                      value: tmp[key] ?? false,
                      onChanged: (v) => setModal(() => tmp[key] = v ?? false),
                      title: Text(e.value),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  }).toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Готово'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    setState(() {
      _delivery
        ..clear()
        ..addAll(tmp);
    });
  }

  Future<void> _openCarParameters() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CarParametersScreen(
          mileageController: _carMileage,
          engineController: _carEngine,
          powerController: _carPower,
          ownersController: _carOwners,
          vinController: _carVin,
          bodyTypes: _bodyTypes,
          fuelTypes: _fuelTypes,
          transmissions: _transmissions,
          drives: _drives,
          conditions: _conditions,
          colors: _colors,
          ptsTypes: _ptsTypes,
          body: _carBody,
          fuel: _carFuel,
          transmission: _carTransmission,
          drive: _carDrive,
          condition: _carCondition,
          color: _carColor,
          pts: _carPts,
          cleared: _carCleared,
          onBodyChanged: (v) => _carBody = v,
          onFuelChanged: (v) => _carFuel = v,
          onTransmissionChanged: (v) => _carTransmission = v,
          onDriveChanged: (v) => _carDrive = v,
          onConditionChanged: (v) => _carCondition = v,
          onColorChanged: (v) => _carColor = v,
          onPtsChanged: (v) => _carPts = v,
          onClearedChanged: (v) => _carCleared = v,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  String _carParametersSummary() {
    final count = [
      _carMileage.text.trim(),
      _carBody,
      _carFuel,
      _carEngine.text.trim(),
      _carPower.text.trim(),
      _carTransmission,
      _carDrive,
      _carCondition,
      _carColor,
      _carPts,
      _carCleared,
      _carOwners.text.trim(),
      _carVin.text.trim(),
    ].where((value) {
      if (value == null) return false;
      return value.toString().trim().isNotEmpty;
    }).length;

    return count == 0 ? 'Необязательно' : 'Заполнено: $count параметров';
  }

  List<ListingPhotoItem> get _visibleExistingPhotos {
    final listing = _listing;
    if (listing == null) return const <ListingPhotoItem>[];
    return listing.photoItems
        .where((item) => !_removedPhotoIds.contains(item.id))
        .toList();
  }

  int get _totalPhotoCount => _visibleExistingPhotos.length + _newPhotos.length;

  Future<void> _pickMorePhotos() async {
    final listing = _listing;
    if (listing == null) return;
    final remain = 10 - _totalPhotoCount;
    if (remain <= 0) return;

    final picked = await _picker.pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) return;
    if (!mounted) return;

    final added = <_EditNewPhotoItem>[];
    setState(() {
      for (final photo in picked.take(remain)) {
        final item = _EditNewPhotoItem(
          localId: 'photo_${_nextPhotoLocalId++}',
          file: File(photo.path),
          sourceIndex: _visibleExistingPhotos.length + _newPhotos.length,
        );
        _newPhotos.add(item);
        added.add(item);
      }
    });
    for (final item in added) {
      unawaited(_uploadNewPhotoItem(item.localId, listing.id));
    }

    if (picked.length > remain) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Можно максимум 10 фото. Добавлено: $remain')),
      );
    }
  }

  void _setNewPhotoStateByLocalId(
    String localId,
    _EditPhotoState state, {
    String? statusText,
    bool clearStatusText = false,
    String? photoId,
  }) {
    final index = _newPhotos.indexWhere((item) => item.localId == localId);
    if (index == -1) return;
    _newPhotos[index] = _newPhotos[index].copyWith(
      state: state,
      statusText: statusText,
      clearStatusText: clearStatusText,
      photoId: photoId,
    );
  }

  Future<void> _uploadNewPhotoItem(String localId, String listingId) async {
    final index = _newPhotos.indexWhere((item) => item.localId == localId);
    if (index == -1) return;
    final item = _newPhotos[index];
    if (item.state == _EditPhotoState.preparing ||
        item.state == _EditPhotoState.uploading ||
        item.state == _EditPhotoState.deleting) {
      return;
    }
    if (item.photoId.isNotEmpty) {
      await _removeNewPhoto(item);
      if (!mounted) return;
    }
    setState(() {
      _setNewPhotoStateByLocalId(
        localId,
        _EditPhotoState.preparing,
        statusText: 'Сжимаем фото...',
      );
    });
    try {
      if (!mounted ||
          !_newPhotos.any((current) => current.localId == localId)) {
        return;
      }
      setState(() {
        _setNewPhotoStateByLocalId(
          localId,
          _EditPhotoState.uploading,
          statusText: 'Загружаем...',
        );
      });
      final currentIndex =
          _newPhotos.indexWhere((current) => current.localId == localId);
      final response =
          await context.read<ListingsService>().uploadListingPhotoItem(
                listingId: listingId,
                file: item.file,
                sortOrder: currentIndex == -1
                    ? item.sourceIndex
                    : _visibleExistingPhotos.length + currentIndex,
              );
      if (!mounted) return;
      if (!_newPhotos.any((current) => current.localId == localId)) {
        if (response.photoId.isNotEmpty) {
          unawaited(
            context.read<ListingsService>().deleteListingPhoto(
                  listingId: listingId,
                  photoId: response.photoId,
                ),
          );
        }
        return;
      }
      setState(() {
        _setNewPhotoStateByLocalId(
          localId,
          _EditPhotoState.uploaded,
          clearStatusText: true,
          photoId: response.photoId,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _setNewPhotoStateByLocalId(
          localId,
          _EditPhotoState.failed,
          statusText: _friendlyPhotoError(error),
        );
      });
    }
  }

  Future<void> _removeNewPhoto(_EditNewPhotoItem item) async {
    final listing = _listing;
    final index = _newPhotos.indexWhere(
      (current) => current.localId == item.localId,
    );
    if (index == -1) return;
    if (item.photoId.isNotEmpty && listing != null) {
      setState(() {
        _newPhotos[index] = item.copyWith(
          state: _EditPhotoState.deleting,
          statusText: 'Удаляем...',
        );
      });
      try {
        await context.read<ListingsService>().deleteListingPhoto(
              listingId: listing.id,
              photoId: item.photoId,
            );
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _setNewPhotoStateByLocalId(
            item.localId,
            _EditPhotoState.uploaded,
            statusText: 'Не удалось удалить',
          );
        });
        return;
      }
      if (!mounted) return;
    }
    setState(() {
      _newPhotos.removeWhere((current) => current.localId == item.localId);
      for (var i = 0; i < _newPhotos.length; i++) {
        _newPhotos[i] = _newPhotos[i].copyWith(
          sourceIndex: _visibleExistingPhotos.length + i,
        );
      }
    });
  }

  String _friendlyPhotoError(Object error) {
    if (error is ApiException && error.message.trim().isNotEmpty) {
      return error.message.trim();
    }
    final text = error.toString().toLowerCase();
    if (text.contains('413') || text.contains('too large')) {
      return 'Фото слишком большое. Попробуйте другое фото.';
    }
    return 'Не удалось загрузить фото';
  }

  String _friendlyError(Object error) {
    if (error is ApiException && error.message.trim().isNotEmpty) {
      return error.message.trim();
    }
    return 'Не удалось обновить объявление';
  }

  Future<String?> _askText(
      {required String title, required String hint}) async {
    final c = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          decoration: InputDecoration(
              hintText: hint, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Ок')),
        ],
      ),
    );
    final t = (res ?? '').trim();
    if (t.isEmpty) return null;
    return t;
  }

  void _rebuildTitleFromSelections() {
    _applyTitleSuggestion(_buildTitleSuggestion());
  }

  String _buildTitleSuggestion() {
    if (!_isPassengerCar) return '';
    return [
      if ((_autoBrand ?? '').trim().isNotEmpty) _autoBrand!.trim(),
      if ((_autoModel ?? '').trim().isNotEmpty) _autoModel!.trim(),
      if ((_autoGen ?? '').trim().isNotEmpty) _autoGen!.trim(),
    ].join(' ').trim();
  }

  void _applyTitleSuggestion(String suggestion) {
    final nextSuggestion = suggestion.trim();
    final current = _title.text;
    final previous = _lastTitleSuggestion.trim();

    if (nextSuggestion.isEmpty) {
      if (previous.isNotEmpty && current.trim() == previous) {
        _title.clear();
      }
      _lastTitleSuggestion = '';
      return;
    }

    String? nextText;
    if (current.trim().isEmpty ||
        (previous.isNotEmpty && current.trim() == previous)) {
      nextText = nextSuggestion;
    } else if (previous.isNotEmpty && current.startsWith(previous)) {
      nextText = '$nextSuggestion${current.substring(previous.length)}';
    }

    _lastTitleSuggestion = nextSuggestion;
    if (nextText == null || nextText == current) return;

    _title.value = _title.value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
      composing: TextRange.empty,
    );
  }

  // ----------- auto picker (как у тебя было) -----------
  Future<void> _openAutoPickerOneWindow() async {
    String? brand = _autoBrand;
    String? model = _autoModel;
    String? gen = _autoGen;

    int step = 0;
    String q = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setM) {
            List<String> currentItems() {
              if (step == 0) return kAutoBrandsPopular;
              if (step == 1) {
                if (brand == null) return const [];
                return autoModelsForBrand(brand);
              }
              final gens = autoGenerationsForBrandModel(brand, model);
              return [
                kAutoSkipGenerationLabel,
                ...gens,
                kAutoCustomGenerationLabel,
              ];
            }

            final items = currentItems()
                .where(
                  (x) => step == 0
                      ? autoBrandMatchesQuery(x, q)
                      : q.trim().isEmpty
                          ? true
                          : x.toLowerCase().contains(q.trim().toLowerCase()),
                )
                .toList();

            String title() => step == 0
                ? 'Выбор марки'
                : (step == 1 ? 'Выбор модели' : 'Поколение / серия');

            Future<void> pickItem(String v) async {
              if (step == 0) {
                if (v == kAutoCustomBrandLabel) {
                  final custom = await _askText(
                    title: kAutoCustomBrandLabel,
                    hint: 'Например: Porsche',
                  );
                  if (custom == null) return;
                  v = custom;
                }
                setM(() {
                  brand = canonicalAutoBrand(v);
                  model = null;
                  gen = null;
                  step = 1;
                  q = '';
                });
                return;
              }

              if (step == 1) {
                if (v == kAutoCustomModelLabel) {
                  final custom = await _askText(
                    title: kAutoCustomModelLabel,
                    hint: 'Например: Camry',
                  );
                  if (custom == null) return;
                  v = custom;
                }
                setM(() {
                  model = v;
                  gen = null;
                  step = 2;
                  q = '';
                });
                return;
              }

              if (v == kAutoCustomGenerationLabel) {
                final custom = await _askText(
                  title: kAutoCustomGenerationLabel,
                  hint: 'Например: XV70, рестайлинг 2, Series II',
                );
                if (custom == null) return;
                v = custom;
              }

              setM(() => gen = (v == kAutoSkipGenerationLabel) ? null : v);
            }

            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.86,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: step == 0
                              ? null
                              : () => setM(() {
                                    step -= 1;
                                    q = '';
                                  }),
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          iconSize: 18,
                          tooltip: 'Назад',
                        ),
                        Expanded(
                            child: Text(title(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800))),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Закрыть')),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Поиск',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setM(() => q = v),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final v = items[i];
                        return ListTile(
                            title: Text(v), onTap: () => pickItem(v));
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton(
                        onPressed: () {
                          if (brand == null || model == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Выберите марку и модель')),
                            );
                            return;
                          }
                          setState(() {
                            _autoBrand = brand;
                            _autoModel = model;
                            _autoGen = gen;
                          });
                          _rebuildTitleFromSelections();
                          Navigator.pop(ctx);
                        },
                        child: Text(
                          (brand == null || model == null)
                              ? 'Выбери марку и модель'
                              : 'Применить: $brand $model ${gen ?? ''}'.trim(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  bool _validInt(String s) => int.tryParse(s.trim()) != null;
  Future<void> _save(Listing listing) async {
    final me = context.read<AuthService>().currentUser!;
    final listingsService = context.read<ListingsService>();
    if (listing.ownerId != me.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нельзя редактировать чужое объявление')),
      );
      return;
    }

    final title = _title.text.trim();
    final city = _city.text.trim();
    final desc = _desc.text.trim();
    final phone = _phone.text.trim();
    final price = parseFormattedPrice(_price.text);

    if (title.isEmpty || desc.isEmpty || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните название, описание и цену')),
      );
      return;
    }

    if (city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Укажите город или адрес объявления'),
        ),
      );
      return;
    }

    if (_totalPhotoCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте минимум 1 фото')),
      );
      return;
    }

    if (_isUploadingPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Дождитесь загрузки фотографий')),
      );
      return;
    }

    if (_hasFailedPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Повторите загрузку фотографий с ошибкой'),
        ),
      );
      return;
    }

    if (_visibleExistingPhotos.isEmpty && !_hasUploadedNewPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте минимум 1 фото')),
      );
      return;
    }

    CarSpecs? car;
    if (_isAuto) {
      final year =
          _validInt(_carYear.text) ? int.parse(_carYear.text.trim()) : null;
      final mileage = _validInt(_carMileage.text)
          ? int.parse(_carMileage.text.trim())
          : null;
      final engine = _carEngine.text.trim().isEmpty
          ? null
          : parseEngineVolumeInput(_carEngine.text);
      final power = _carPower.text.trim().isEmpty
          ? null
          : parsePowerHpInput(_carPower.text);

      final owners = _carOwners.text.trim().isEmpty
          ? null
          : int.tryParse(_carOwners.text.trim());
      final vin = _carVin.text.trim().isEmpty ? null : _carVin.text.trim();
      final note = _carNote.text.trim().isEmpty ? null : _carNote.text.trim();

      final autoBrand = ((_autoBrand ?? '').trim().isNotEmpty)
          ? _autoBrand!.trim()
          : _subcategory.trim();
      final autoModel =
          ((_autoModel ?? '').trim().isNotEmpty) ? _autoModel!.trim() : title;

      car = CarSpecs(
        brand: autoBrand,
        model: autoModel,
        generation: _isPassengerCar ? (_autoGen ?? '').trim() : '',
        year: year,
        mileageKm: mileage,
        bodyType: _carBody,
        fuel: _carFuel,
        engineVolume: engine,
        powerHp: power,
        transmission: _carTransmission,
        drive: _carDrive,
        condition: _carCondition,
        color: _carColor,
        isCleared: _carCleared,
        pts: _carPts,
        owners: owners,
        vin: vin,
        note: note,
      );
    }

    setState(() => _saving = true);
    try {
      await listingsService.updateListing(
        listingId: listing.id,
        title: title,
        description: desc,
        price: price,
        phone: phone,
        phoneHidden: _phoneHidden,
        city: city,
        delivery: _delivery,
        car: _isAuto ? car : null,
      );

      if (!mounted) return;
      for (final photoId in _removedPhotoIds.where((id) => id.isNotEmpty)) {
        await listingsService.deleteListingPhoto(
          listingId: listing.id,
          photoId: photoId,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Объявление обновлено')),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _selectTile({
    required String title,
    required String value,
    required VoidCallback? onTap,
    Widget? leading,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading,
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                value.isEmpty ? title : value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value.isEmpty
                      ? Theme.of(context).colorScheme.outline
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _carParametersTile() {
    return InkWell(
      onTap: _openCarParameters,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Параметры авто',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _carParametersSummary(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null || _listing == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError ?? 'Не удалось загрузить объявление'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadListing,
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final listing = _listing!;
    final autoLine = [
      if ((_autoBrand ?? '').trim().isNotEmpty) _autoBrand!.trim(),
      if ((_autoModel ?? '').trim().isNotEmpty) _autoModel!.trim(),
      if ((_autoGen ?? '').trim().isNotEmpty) _autoGen!.trim(),
    ].join(' ').trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Редактирование')),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: FilledButton(
            onPressed: _saving ? null : () => _save(listing),
            child: Text(_saving ? 'Сохраняем...' : 'Сохранить'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Text(
              'Категория: ${listing.category}\nПосле сохранения изменения применятся к объявлению.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Фотографии',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _visibleExistingPhotos.length + _newPhotos.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index ==
                    _visibleExistingPhotos.length + _newPhotos.length) {
                  return InkWell(
                    onTap: _totalPhotoCount >= 10 ? null : _pickMorePhotos,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 92,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.add_a_photo_outlined),
                    ),
                  );
                }

                if (index < _visibleExistingPhotos.length) {
                  final photo = _visibleExistingPhotos[index];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CachedNetworkImage(
                          imageUrl: photo.url,
                          width: 92,
                          height: 92,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            width: 92,
                            height: 92,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: InkWell(
                          onTap: photo.id.isEmpty
                              ? null
                              : () {
                                  setState(() {
                                    _removedPhotoIds.add(photo.id);
                                  });
                                },
                          child: const CircleAvatar(
                            radius: 12,
                            child: Icon(Icons.close, size: 14),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                final localPhoto =
                    _newPhotos[index - _visibleExistingPhotos.length];
                return Stack(
                  children: [
                    InkWell(
                      onTap: localPhoto.state == _EditPhotoState.failed
                          ? () => _uploadNewPhotoItem(
                                localPhoto.localId,
                                listing.id,
                              )
                          : null,
                      borderRadius: BorderRadius.circular(14),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(
                          localPhoto.file,
                          width: 92,
                          height: 92,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 92,
                            height: 92,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            alignment: Alignment.center,
                            child:
                                const Icon(Icons.image_not_supported_outlined),
                          ),
                        ),
                      ),
                    ),
                    if (localPhoto.state == _EditPhotoState.preparing ||
                        localPhoto.state == _EditPhotoState.uploading ||
                        localPhoto.state == _EditPhotoState.deleting)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    if (localPhoto.state == _EditPhotoState.failed)
                      Positioned.fill(
                        child: InkWell(
                          onTap: () => _uploadNewPhotoItem(
                            localPhoto.localId,
                            listing.id,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.42),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.center,
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Повторить',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: InkWell(
                        onTap: localPhoto.state == _EditPhotoState.deleting
                            ? null
                            : () => _removeNewPhoto(localPhoto),
                        child: const CircleAvatar(
                          radius: 12,
                          child: Icon(Icons.close, size: 14),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          if (_isPassengerCar) ...[
            _selectTile(
              title: 'Марка • Модель • Поколение (в одном окне)',
              value: autoLine,
              onTap: _openAutoPickerOneWindow,
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: _isPassengerCar
                  ? 'Название (автозаполнение можно править)'
                  : 'Название',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            inputFormatters: [PriceThousandsInputFormatter()],
            decoration: const InputDecoration(labelText: 'Цена (₽)'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _selectTile(
                  title: 'Город / регион / село (выбрать)',
                  value: _city.text.trim(),
                  onTap:
                      () {}, // у тебя был большой city picker — если надо, вставишь обратно
                  leading: const Icon(Icons.location_city_outlined),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _openMap,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.map_outlined, color: Colors.green),
                ),
              ),
            ],
          ),
          if (_isAuto) ...[
            const SizedBox(height: 18),
            TextField(
              controller: _carYear,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Год выпуска (например: 2018)'),
            ),
            const SizedBox(height: 12),
            _carParametersTile(),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
            inputFormatters: const <TextInputFormatter>[
              RuPhoneInputFormatter(),
            ],
            decoration: InputDecoration(
              labelText: 'Телефон (для звонка)',
              helperText: _phone.text.trim().isEmpty
                  ? null
                  : 'Будет показано как: ${formatRussianPhone(_phone.text)}',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Скрывать номер в объявлении'),
            subtitle: const Text(
                'Номер не будет виден, но кнопка “Позвонить” останется'),
            value: _phoneHidden,
            onChanged: (v) => setState(() => _phoneHidden = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Описание'),
          ),
          const SizedBox(height: 16),
          Text('Доставка',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          InkWell(
            onTap: _openDeliveryPicker,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _deliverySummary(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
          const SizedBox(height: 90),
        ],
      ),
    );
  }
}
