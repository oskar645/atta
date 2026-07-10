import 'dart:io';

import 'package:atta/src/data/auto_catalog.dart';

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

class _EditListingScreenState extends State<EditListingScreen> {
  bool _inited = false;
  bool _saving = false;
  bool _loading = true;
  String? _loadError;
  Listing? _listing;
  final _newPhotos = <XFile>[];
  final _removedPhotoIds = <String>{};
  final _picker = ImagePicker();

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

  List<ListingPhotoItem> get _visibleExistingPhotos {
    final listing = _listing;
    if (listing == null) return const <ListingPhotoItem>[];
    return listing.photoItems
        .where((item) => !_removedPhotoIds.contains(item.id))
        .toList();
  }

  int get _totalPhotoCount => _visibleExistingPhotos.length + _newPhotos.length;

  Future<void> _pickMorePhotos() async {
    final remain = 10 - _totalPhotoCount;
    if (remain <= 0) return;

    final picked = await _picker.pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) return;
    if (!mounted) return;

    setState(() {
      _newPhotos.addAll(picked.take(remain));
    });

    if (picked.length > remain) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Можно максимум 10 фото. Добавлено: $remain')),
      );
    }
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

      for (final photoId in _removedPhotoIds.where((id) => id.isNotEmpty)) {
        await listingsService.deleteListingPhoto(
          listingId: listing.id,
          photoId: photoId,
        );
      }

      final uploadResult = await listingsService.uploadListingPhotos(
        listingId: listing.id,
        photos: _newPhotos.map((photo) => File(photo.path)).toList(),
        startIndex: _visibleExistingPhotos.length,
      );

      if (!mounted) return;
      if (uploadResult.hasFailures) {
        final retry = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Часть фото не загрузилась'),
                content: Text(
                  uploadResult.allFailed
                      ? 'Не удалось загрузить фото. Попробовать ещё раз?'
                      : 'Загружено ${uploadResult.uploadedCount} из ${uploadResult.requestedCount} фото. Повторить загрузку?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Позже'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ) ??
            false;

        if (retry) {
          final retried = await listingsService.uploadListingPhotos(
            listingId: listing.id,
            photos: uploadResult.failures.map((item) => item.file).toList(),
            sortOrders:
                uploadResult.failures.map((item) => item.index).toList(),
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                retried.hasFailures
                    ? 'Объявление обновлено, но ${retried.failedCount} фото не загрузились'
                    : 'Объявление обновлено',
              ),
            ),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                uploadResult.allFailed
                    ? 'Не удалось загрузить фото. Попробуйте ещё раз.'
                    : 'Объявление обновлено, но ${uploadResult.failedCount} фото не загрузились',
              ),
            ),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Объявление обновлено')),
        );
      }
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

  Widget _drop({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items:
          items.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        File(localPhoto.path),
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
                          child: const Icon(Icons.image_not_supported_outlined),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _newPhotos.remove(localPhoto);
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
            const Text('Параметры авто',
                style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            TextField(
              controller: _carYear,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Год выпуска (например: 2018)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _carMileage,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Пробег (необязательно)'),
            ),
            const SizedBox(height: 12),
            _drop(
                label: 'Кузов (необязательно)',
                value: _carBody,
                items: _bodyTypes,
                onChanged: (v) => setState(() => _carBody = v)),
            const SizedBox(height: 12),
            _drop(
                label: 'Топливо (необязательно)',
                value: _carFuel,
                items: _fuelTypes,
                onChanged: (v) => setState(() => _carFuel = v)),
            const SizedBox(height: 12),
            TextField(
              controller: _carEngine,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText:
                      'Объём двигателя (необязательно), например: 2.2 или 300 куб. см'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _carPower,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Мощность (л.с.), например: 193'),
            ),
            const SizedBox(height: 12),
            _drop(
                label: 'Коробка (необязательно)',
                value: _carTransmission,
                items: _transmissions,
                onChanged: (v) => setState(() => _carTransmission = v)),
            const SizedBox(height: 12),
            _drop(
                label: 'Привод (необязательно)',
                value: _carDrive,
                items: _drives,
                onChanged: (v) => setState(() => _carDrive = v)),
            const SizedBox(height: 12),
            _drop(
                label: 'Состояние (необязательно)',
                value: _carCondition,
                items: _conditions,
                onChanged: (v) => setState(() => _carCondition = v)),
            const SizedBox(height: 12),
            _drop(
                label: 'Цвет (необязательно)',
                value: _carColor,
                items: _colors,
                onChanged: (v) => setState(() => _carColor = v)),
            const SizedBox(height: 12),
            _drop(
                label: 'ПТС (необязательно)',
                value: _carPts,
                items: _ptsTypes,
                onChanged: (v) => setState(() => _carPts = v)),
            const SizedBox(height: 12),
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
