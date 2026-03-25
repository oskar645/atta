// lib/src/features/listings/add_listing_screen.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:atta/src/constants/categories.dart';
import 'package:atta/src/data/auto_catalog.dart';
import 'package:atta/src/data/electronics_catalog.dart';
import 'package:atta/src/features/listings/pick_location_screen.dart';
import 'package:atta/src/models/car_specs.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:provider/provider.dart';
import 'package:atta/src/widgets/yandex_address_field.dart';

class AddListingScreen extends StatefulWidget {
  const AddListingScreen({super.key});

  @override
  State<AddListingScreen> createState() => _AddListingScreenState();
}

class _AddListingScreenState extends State<AddListingScreen> {
  final _title = TextEditingController();
  final _city = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _phone = TextEditingController();

  // ✅ авто-поля
  final _carYear = TextEditingController();
  final _carMileage = TextEditingController();
  final _carEngine = TextEditingController(); // литры
  final _carPower = TextEditingController(); // л.с.
  final _carOwners = TextEditingController();
  final _carVin = TextEditingController();
  final _carNote = TextEditingController();

  String _category = 'Авто';
  String _subcategory = 'Легковые автомобили'; // ✅ ДОБАВИЛИ подкатегорию
  final _photos = <File>[];
  bool _saving = false;

  final _picker = ImagePicker();
  latlng.LatLng? _pickedLatLng;

  bool _phoneHidden = true;

  // ===== “умные” поля =====
  String? _autoBrand;
  String? _autoModel;
  String? _autoGen;

  String? _electronicsSub;
  String _lastTitleSuggestion = '';

  // ✅ НОВОЕ: Недвижимость
  String _dealType = 'Продажа';
  String _realEstateType = 'Квартира';

  // ✅ НОВОЕ: Одежда
  String _clothesType = 'Верхняя одежда';

  // ✅ доп. селекты для авто
  String _carBody = 'Седан';
  String _carFuel = 'Бензин';
  String _carTransmission = 'Автомат';
  String _carDrive = 'Передний';
  String _carCondition = 'Все';
  String _carColor = 'Чёрный';
  bool? _carCleared; // растаможен (null = не указано)

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
  bool get _isElectronics => _category == 'Электроника';
  bool get _isRealEstate => _category == 'Недвижимость';
  bool get _isClothes => _category == 'Одежда';

  // ✅ справочники авто
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

  static const _drives = <String>['Передний', 'Задний', 'Полный'];

  static const _conditions = <String>[
    'Все',
    'Битые',
    'Не битый',
  ];

  static const _engineVolumes = <String>[
    '0.6',
    '0.7',
    '0.8',
    '1.0',
    '1.2',
    '1.3',
    '1.4',
    '1.5',
    '1.6',
    '1.8',
    '2.0',
    '2.2',
    '2.4',
    '2.5',
    '2.7',
    '3.0',
    '3.2',
    '3.5',
    '3.7',
    '4.0',
    '4.2',
    '4.4',
    '4.6',
    '5.0',
    '5.5',
    '6.0',
    '6.2',
    '6.5',
    '7.0',
    '8.0',
    '10.0',
    '12.0',
    '15.0',
  ];

  static final _powerValues = <String>[
    for (int i = 50; i <= 200; i += 10) '$i',
    for (int i = 225; i <= 500; i += 25) '$i',
    for (int i = 550; i <= 1500; i += 50) '$i',
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

  // ✅ НОВОЕ: недвижимость / одежда
  static const _dealTypes = <String>['Продажа', 'Аренда'];

  static const _realEstateTypes = <String>[
    'Квартира',
    'Дом',
    'Участок',
    'Дача',
    'Комната',
    'Гараж',
    'Коммерческая',
  ];

  static const _clothesTypes = <String>[
    'Верхняя одежда',
    'Футболки / рубашки',
    'Толстовки / свитшоты',
    'Брюки / джинсы',
    'Платья / юбки',
    'Обувь',
    'Детская одежда',
    'Аксессуары',
    'Другое',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillPhoneFromProfile());
  }

  Future<void> _prefillPhoneFromProfile() async {
    final auth = context.read<AuthService>();
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.isEmpty || _phone.text.trim().isNotEmpty) return;

    try {
      final profile = context.read<ProfileService>();
      final data = await profile.getProfile(uid);
      final phone = (data['phone'] ?? '').toString().trim();
      if (!mounted || phone.isEmpty || _phone.text.trim().isNotEmpty) return;
      _phone.text = phone;
      setState(() {});
    } catch (_) {}
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

  // ================== ФОТО ==================
  void _openPhotoMenu() {
    if (_photos.length >= 6) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать несколько из галереи'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickPhotosFromGalleryMulti();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Снять на камеру'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickPhoto(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhotosFromGalleryMulti() async {
    final remain = 6 - _photos.length;
    if (remain <= 0) return;

    final xs = await _picker.pickMultiImage(imageQuality: 80);
    if (xs.isEmpty) return;

    setState(() {
      for (final x in xs.take(remain)) {
        _photos.add(File(x.path));
      }
    });

    if (xs.length > remain && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Можно максимум 6 фото. Добавлено: $remain')),
      );
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await _picker.pickImage(source: source, imageQuality: 80);
    if (x == null) return;
    if (_photos.length >= 6) return;
    setState(() => _photos.add(File(x.path)));
  }

  // ================== КАРТА -> АДРЕС ==================
  Future<void> _fillCityFromLatLng(latlng.LatLng p) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        p.latitude,
        p.longitude,
      );
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
      setState(() => _pickedLatLng = res);
      await _fillCityFromLatLng(res);
      if (mounted) setState(() {});
      return;
    }
    if (res is String) {
      _city.text = res;
      if (mounted) setState(() => _pickedLatLng = null);
    }
  }

  // ================== ДОСТАВКА ==================
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
                  child: Text(
                    'Выберите доставку',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
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

  // ================== УМНЫЕ ПОЛЯ ==================
  void _resetSmartFields() {
    _autoBrand = null;
    _autoModel = null;
    _autoGen = null;
    _electronicsSub = null;
    _lastTitleSuggestion = '';
    _title.clear();

    // ✅ сброс авто параметров
    _carYear.clear();
    _carMileage.clear();
    _carEngine.clear();
    _carPower.clear();
    _carOwners.clear();
    _carVin.clear();
    _carNote.clear();

    _carBody = 'Седан';
    _carFuel = 'Бензин';
    _carTransmission = 'Автомат';
    _carDrive = 'Передний';
    _carCondition = 'Все';
    _carColor = 'Чёрный';
    _carCleared = null;

    // ✅ сброс недвижимость/одежда
    _dealType = 'Продажа';
    _realEstateType = 'Квартира';
    _clothesType = 'Верхняя одежда';
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
    if (current.trim().isEmpty || (previous.isNotEmpty && current.trim() == previous)) {
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

  Future<String?> _askText({
    required String title,
    required String hint,
  }) async {
    final c = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Ок'),
          ),
        ],
      ),
    );
    final t = (res ?? '').trim();
    if (t.isEmpty) return null;
    return t;
  }

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
                final models = kAutoModels[brand!];
                if (models == null || models.isEmpty) {
                  return const [kAutoCustomModelLabel];
                }
                return models;
              }
              final key = '${brand ?? ''}|${model ?? ''}';
              final gens = kAutoGenerations[key] ?? const [];
              return [
                kAutoSkipGenerationLabel,
                ...gens,
                kAutoCustomGenerationLabel,
              ];
            }

            final items = currentItems()
                .where(
                  (x) => q.trim().isEmpty
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
                  brand = v;
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
	                          child: Text(
	                            title(),
	                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Закрыть'),
                        ),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () => setM(() {
                              step = 0;
                              q = '';
                            }),
                            child: Text(brand == null ? 'Марка' : 'Марка ✓'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: (brand == null)
                                ? null
                                : () => setM(() {
                                    step = 1;
                                    q = '';
                                  }),
                            child: Text(model == null ? 'Модель' : 'Модель ✓'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: (brand == null || model == null)
                                ? null
                                : () => setM(() {
                                    step = 2;
                                    q = '';
                                  }),
                            child: const Text('Поколение'),
                          ),
                        ),
                      ],
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
                          title: Text(v),
                          onTap: () => pickItem(v),
                        );
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
                                content: Text('Выберите марку и модель'),
                              ),
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

  // ✅ ОДНО ОКНО выбора электроники
  Future<void> _openElectronicsPickerOneWindow() async {
    String? sub = _electronicsSub;
    String q = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setM) {
            final items = kElectronicsSubcategories
                .where(
                  (x) => q.trim().isEmpty
                      ? true
                      : x.toLowerCase().contains(q.trim().toLowerCase()),
                )
                .toList();

            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Выбор подкатегории (Электроника)',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Закрыть'),
                        ),
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
                        final sel = v == sub;
                        return ListTile(
                          title: Text(v),
                          trailing: sel ? const Icon(Icons.check) : null,
                          onTap: () => setM(() => sub = v),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton(
                        onPressed: () {
                          if (sub == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Выберите подкатегорию'),
                              ),
                            );
                            return;
                          }
                          setState(() => _electronicsSub = sub);
                          _rebuildTitleFromSelections();
                          Navigator.pop(ctx);
                        },
                        child: Text(
                          sub == null
                              ? 'Выбери подкатегорию'
                              : 'Применить: $sub',
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

  // ================== СОХРАНЕНИЕ ==================
  bool _validInt(String s) => int.tryParse(s.trim()) != null;
  bool _validDouble(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.')) != null;

  List<String> _itemsWithCurrentValue(List<String> items, String current) {
    final normalized = current.trim().replaceAll(',', '.');
    if (normalized.isEmpty || items.contains(normalized)) return items;
    return [normalized, ...items];
  }

  Future<void> _openValuePickerSheet({
    required String title,
    required List<String> items,
    required String currentValue,
    required ValueChanged<String> onSelected,
    String Function(String value)? labelBuilder,
  }) async {
    var selected = currentValue.trim();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setModal) => SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.52,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        tooltip: 'Назад',
                      ),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final value = items[i];
                      final isSelected = value == selected;
                      final text = labelBuilder?.call(value) ?? value;
                      return ListTile(
                        title: Text(text),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Colors.blue)
                            : null,
                        onTap: () => setModal(() => selected = value),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: FilledButton(
                    onPressed: () {
                      if (selected.isEmpty && items.isNotEmpty) {
                        selected = items.first;
                      }
                      onSelected(selected);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Выбрать'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final city = _city.text.trim();
    final desc = _desc.text.trim();
    final phone = _phone.text.trim();
    final price = int.tryParse(_price.text.trim()) ?? 0;

    if (_isPassengerCar && (_autoBrand == null || _autoModel == null)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Выберите марку и модель')));
      return;
    }

    if (title.isEmpty || desc.isEmpty || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните название, описание и цену')),
      );
      return;
    }

    if (city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите город или адрес объявления')),
      );
      return;
    }

    if (_photos.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Добавьте минимум 1 фото')));
      return;
    }

    // ✅ обязательные авто поля
    CarSpecs? car;
    if (_isAuto) {
      if (!_validInt(_carYear.text) ||
          !_validInt(_carMileage.text) ||
          !_validDouble(_carEngine.text) ||
          !_validInt(_carPower.text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Заполните авто: год, пробег, объём (л) и мощность (л.с.)',
            ),
          ),
        );
        return;
      }

      final year = int.parse(_carYear.text.trim());
      final mileage = int.parse(_carMileage.text.trim());
      final engine = double.parse(_carEngine.text.trim().replaceAll(',', '.'));
      final power = int.parse(_carPower.text.trim());

      final owners = _carOwners.text.trim().isEmpty
          ? null
          : int.tryParse(_carOwners.text.trim());
      final vin = _carVin.text.trim().isEmpty ? null : _carVin.text.trim();
      final note = _carNote.text.trim().isEmpty ? null : _carNote.text.trim();

      final autoBrand = ((_autoBrand ?? '').trim().isNotEmpty)
          ? _autoBrand!.trim()
          : _subcategory.trim();
      final autoModel = ((_autoModel ?? '').trim().isNotEmpty)
          ? _autoModel!.trim()
          : title;

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
        owners: owners,
        vin: vin,
        note: note,
      );
    }

    // ✅ новые поля
    final dealType = _isRealEstate ? _dealType : null;
    final realEstateType = _isRealEstate ? _realEstateType : null;
    final clothesType = _isClothes ? _clothesType : null;

    final auth = context.read<AuthService>();
    final svc = context.read<ListingsService>();

    final ownerName =
        (auth.currentUser!.displayName?.trim().isNotEmpty ?? false)
        ? auth.currentUser!.displayName!.trim()
        : (auth.currentUser!.email ?? 'Пользователь');

    setState(() => _saving = true);
    try {
      await svc.createListing(
        ownerId: auth.currentUser!.uid,
        ownerEmail: auth.currentUser!.email ?? '',
        ownerName: ownerName,
        title: title,
        description: desc,
        category: _category,
        subcategory: _subcategory, // ✅ ДОБАВИЛИ
        price: price,
        phone: phone,
        phoneHidden: _phoneHidden,
        city: city,
        delivery: _delivery,
        photos: _photos,

        // авто
        car: car,

        // ✅ новые поля
        dealType: dealType,
        realEstateType: realEstateType,
        clothesType: clothesType,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Объявление отправлено на модерацию')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
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
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 10)],
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
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      items: items
          .map((x) => DropdownMenuItem(value: x, child: Text(x)))
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = kCategories.where((c) => c != 'Все').toList();

    final autoLine = [
      if ((_autoBrand ?? '').trim().isNotEmpty) _autoBrand!.trim(),
      if ((_autoModel ?? '').trim().isNotEmpty) _autoModel!.trim(),
      if ((_autoGen ?? '').trim().isNotEmpty) _autoGen!.trim(),
    ].join(' ').trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Новое объявление')),
      bottomNavigationBar: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Сохраняем...' : 'Опубликовать'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _category,
            items: categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
              onChanged: (v) {
                setState(() {
                  _category = v ?? _category;
                  // Сбросить подкатегорию при смене категории
                  final subs = kSubcategories[_category] ?? [];
                  _subcategory = subs.isNotEmpty ? subs.first : '';
                  _resetSmartFields();
                  _rebuildTitleFromSelections();
                });
              },
            decoration: const InputDecoration(labelText: 'Категория'),
          ),

          const SizedBox(height: 12),

          // ✅ Подкатегория (если она есть)
          if (kSubcategories.containsKey(_category))
            DropdownButtonFormField<String>(
              value: _subcategory,
              items: (kSubcategories[_category] ?? [])
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _subcategory = v ?? _subcategory;
                  if (!_isPassengerCar) {
                    _autoBrand = null;
                    _autoModel = null;
                    _autoGen = null;
                  }
                  _rebuildTitleFromSelections();
                });
              },
              decoration: const InputDecoration(labelText: 'Вид товара'),
            ),

          if (kSubcategories.containsKey(_category)) const SizedBox(height: 12),

          // ✅ Недвижимость: сделка + тип
          if (_isRealEstate) ...[
            _drop(
              label: 'Сделка',
              value: _dealType,
              items: _dealTypes,
              onChanged: (v) => setState(() {
                _dealType = v ?? _dealType;
                _rebuildTitleFromSelections();
              }),
            ),
            const SizedBox(height: 12),
            _drop(
              label: 'Тип недвижимости',
              value: _realEstateType,
              items: _realEstateTypes,
              onChanged: (v) => setState(() {
                _realEstateType = v ?? _realEstateType;
                _rebuildTitleFromSelections();
              }),
            ),
            const SizedBox(height: 12),
          ],

          // ✅ Одежда: тип
          if (_isClothes) ...[
            _drop(
              label: 'Тип одежды',
              value: _clothesType,
              items: _clothesTypes,
              onChanged: (v) => setState(() {
                _clothesType = v ?? _clothesType;
                _rebuildTitleFromSelections();
              }),
            ),
            const SizedBox(height: 12),
          ],

          // ✅ Авто: марка/модель/поколение
          if (_isPassengerCar) ...[
            _selectTile(
              title: 'Марка • Модель • Поколение (в одном окне)',
              value: autoLine,
              onTap: _openAutoPickerOneWindow,
            ),
            const SizedBox(height: 12),
          ],

          // ✅ Электроника: подкатегория
          if (_isElectronics) ...[
            _selectTile(
              title: 'Подкатегория (в одном окне)',
              value: _electronicsSub ?? '',
              onTap: _openElectronicsPickerOneWindow,
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
            decoration: const InputDecoration(labelText: 'Цена (₽)'),
          ),

          const SizedBox(height: 12),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: YandexAddressField(
                  controller: _city,
                  label: 'Город / адрес (Яндекс)',
                  onSelected: (_) => setState(() => _pickedLatLng = null),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Выбрать на карте',
                child: Material(
                  color: const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _openMap,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.map_outlined, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ✅ БЛОК “ПАРАМЕТРЫ АВТО”
          if (_isAuto) ...[
            const SizedBox(height: 18),
            const Text(
              'Параметры авто',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _carYear,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Год выпуска (например: 2018)',
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _carMileage,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Пробег (км)'),
            ),
            const SizedBox(height: 12),

            _drop(
              label: 'Кузов',
              value: _carBody,
              items: _bodyTypes,
              onChanged: (v) => setState(() => _carBody = v ?? _carBody),
            ),
            const SizedBox(height: 12),

            _drop(
              label: 'Топливо',
              value: _carFuel,
              items: _fuelTypes,
              onChanged: (v) => setState(() => _carFuel = v ?? _carFuel),
            ),
            const SizedBox(height: 12),

            _selectTile(
              title: 'Объём двигателя',
              value: _carEngine.text.trim().isEmpty
                  ? ''
                  : '${_carEngine.text.trim().replaceAll(',', '.')} л',
              onTap: () => _openValuePickerSheet(
                title: 'Объём двигателя',
                items: _itemsWithCurrentValue(_engineVolumes, _carEngine.text),
                currentValue: _carEngine.text.trim().replaceAll(',', '.'),
                labelBuilder: (value) => '$value л',
                onSelected: (value) => setState(() => _carEngine.text = value),
              ),
            ),
            const SizedBox(height: 12),

            _selectTile(
              title: 'Мощность',
              value:
                  _carPower.text.trim().isEmpty ? '' : '${_carPower.text.trim()} л.с.',
              onTap: () => _openValuePickerSheet(
                title: 'Мощность',
                items: _itemsWithCurrentValue(_powerValues, _carPower.text),
                currentValue: _carPower.text.trim(),
                labelBuilder: (value) => '$value л.с.',
                onSelected: (value) => setState(() => _carPower.text = value),
              ),
            ),
            const SizedBox(height: 12),

            _drop(
              label: 'Коробка передач',
              value: _carTransmission,
              items: _transmissions,
              onChanged: (v) =>
                  setState(() => _carTransmission = v ?? _carTransmission),
            ),
            const SizedBox(height: 12),

            _drop(
              label: 'Привод',
              value: _carDrive,
              items: _drives,
              onChanged: (v) => setState(() => _carDrive = v ?? _carDrive),
            ),
            const SizedBox(height: 12),

            _drop(
              label: 'Состояние',
              value: _carCondition,
              items: _conditions,
              onChanged: (v) =>
                  setState(() => _carCondition = v ?? _carCondition),
            ),
            const SizedBox(height: 12),

            _drop(
              label: 'Цвет',
              value: _carColor,
              items: _colors,
              onChanged: (v) => setState(() => _carColor = v ?? _carColor),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _carCleared == null
                  ? 'Не указано'
                  : (_carCleared! ? 'Да' : 'Нет'),
              items: const [
                DropdownMenuItem(
                  value: 'Не указано',
                  child: Text('Растаможен: не указано'),
                ),
                DropdownMenuItem(value: 'Да', child: Text('Растаможен: да')),
                DropdownMenuItem(value: 'Нет', child: Text('Растаможен: нет')),
              ],
              onChanged: (v) {
                setState(() {
                  if (v == 'Да') {
                    _carCleared = true;
                  } else if (v == 'Нет') {
                    _carCleared = false;
                  } else {
                    _carCleared = null;
                  }
                });
              },
              decoration: const InputDecoration(
                labelText: 'Растаможен (необязательно)',
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _carOwners,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Владельцев (необязательно)',
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _carVin,
              decoration: const InputDecoration(
                labelText: 'VIN (необязательно)',
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _carNote,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Дополнительно (необязательно)',
              ),
            ),
          ],

          const SizedBox(height: 12),

          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Телефон (для звонка)',
              helperText: 'Номер из профиля подставляется автоматически, его можно изменить для этого объявления',
            ),
          ),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _phoneHidden ? 'Номер скрыт в объявлении' : 'Номер показан в объявлении',
            ),
            subtitle: Text(
              _phoneHidden
                  ? 'Покупатель не увидит номер в карточке, но сможет нажать “Позвонить”'
                  : 'Покупатель увидит ваш номер прямо в объявлении',
            ),
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

          Text(
            'Доставка',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),

          InkWell(
            onTap: _openDeliveryPicker,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
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
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              FilledButton.icon(
                onPressed: _photos.length >= 6 ? null : _openPhotoMenu,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text('Фото (${_photos.length}/6)'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Добавь минимум 1 фото — так лучше продаётся.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (_photos.isNotEmpty)
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: kIsWeb
                          ? Container(
                              width: 110,
                              height: 110,
                              color: Colors.black12,
                              alignment: Alignment.center,
                              child: const Icon(Icons.photo, size: 28),
                            )
                          : Image.file(
                              _photos[i],
                              width: 110,
                              height: 110,
                              fit: BoxFit.cover,
                            ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _photos.removeAt(i)),
                      ),
                    ),
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
