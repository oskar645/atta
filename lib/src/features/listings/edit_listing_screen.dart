import 'package:chestore2/src/data/auto_catalog.dart';

import 'package:chestore2/src/features/listings/pick_location_screen.dart';
import 'package:chestore2/src/models/car_specs.dart';
import 'package:chestore2/src/models/listing.dart';
import 'package:chestore2/src/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditListingScreen extends StatefulWidget {
  final String listingId;
  const EditListingScreen({super.key, required this.listingId});

  @override
  State<EditListingScreen> createState() => _EditListingScreenState();
}

class _EditListingScreenState extends State<EditListingScreen> {
  bool _inited = false;
  bool _saving = false;

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
  String _carBody = 'Седан';
  String _carFuel = 'Бензин';
  String _carTransmission = 'Автомат';
  String _carDrive = 'Передний';
  String _carCondition = 'Хорошее';
  String _carColor = 'Чёрный';
  bool? _carCleared;

  latlng.LatLng? _pickedLatLng;

  SupabaseClient get _sb => Supabase.instance.client;

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
    'Седан','Хэтчбек','Универсал','Кроссовер','Внедорожник','Купе','Кабриолет','Минивэн','Пикап','Фургон','Лифтбек','Другое',
  ];

  static const _fuelTypes = <String>[
    'Бензин','Дизель','Гибрид','Электро','Газ','Другое',
  ];

  static const _transmissions = <String>[
    'Механика','Автомат','Вариатор','Робот','Другое',
  ];

  static const _drives = <String>[
    'Передний','Задний','Полный',
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
    'Чёрный','Белый','Серый','Серебристый','Синий','Красный','Зелёный','Жёлтый','Коричневый','Бежевый','Оранжевый','Фиолетовый','Другой',
  ];

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

  // -------- listing stream (supabase) --------
  Stream<Map<String, dynamic>?> _streamListingRow(String id) {
    return _sb
        .from('listings')
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map((rows) => rows.isEmpty ? null : Map<String, dynamic>.from(rows.first));
  }

  void _initFromListing(Listing l) {
    if (_inited) return;
    _inited = true;

    _category = l.category;
    _subcategory = l.subcategory;

    _title.text = l.title;
    _city.text = l.city;
    _desc.text = l.description;
    _price.text = l.price.toString();
    _phone.text = l.phone;
    _phoneHidden = l.phoneHidden;

    for (final k in _delivery.keys) {
      _delivery[k] = l.delivery[k] == true;
    }

    if (l.car != null) {
      final c = l.car!;
      _autoBrand = c.brand;
      _autoModel = c.model;
      _autoGen = c.generation.trim().isEmpty ? null : c.generation;

      _carYear.text = '${c.year}';
      _carMileage.text = '${c.mileageKm}';
      _carEngine.text = c.engineVolume.toStringAsFixed(1);
      _carPower.text = '${c.powerHp}';
      _carOwners.text = c.owners?.toString() ?? '';
      _carVin.text = c.vin ?? '';
      _carNote.text = c.note ?? '';

      _carBody = c.bodyType;
      _carFuel = c.fuel;
      _carTransmission = c.transmission;
      _carDrive = c.drive;
      _carCondition = c.condition;
      _carColor = c.color;
      _carCleared = c.isCleared;
    }

    _lastTitleSuggestion = _buildTitleSuggestion();
  }

  Future<void> _fillCityFromLatLng(latlng.LatLng p) async {
    try {
      final placemarks = await placemarkFromCoordinates(p.latitude, p.longitude);
      if (placemarks.isEmpty) return;
      final pm = placemarks.first;

      final parts = <String>[
        if ((pm.administrativeArea ?? '').trim().isNotEmpty) pm.administrativeArea!,
        if ((pm.subAdministrativeArea ?? '').trim().isNotEmpty) pm.subAdministrativeArea!,
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
                  child: Text('Выберите доставку', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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

  Future<String?> _askText({required String title, required String hint}) async {
    final c = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Ок')),
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
    if (_isPassengerCar) {
      return [
        if ((_autoBrand ?? '').trim().isNotEmpty) _autoBrand!.trim(),
        if ((_autoModel ?? '').trim().isNotEmpty) _autoModel!.trim(),
        if ((_autoGen ?? '').trim().isNotEmpty) _autoGen!.trim(),
      ].join(' ').trim();
    }

    return _subcategory.trim().isNotEmpty ? _subcategory.trim() : _category.trim();
  }

  void _applyTitleSuggestion(String suggestion) {
    final nextSuggestion = suggestion.trim();
    final current = _title.text;
    final previous = _lastTitleSuggestion.trim();

    if (nextSuggestion.isEmpty) {
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
                .where((x) => q.trim().isEmpty ? true : x.toLowerCase().contains(q.trim().toLowerCase()))
                .toList();

            String title() => step == 0 ? 'Выбор марки' : (step == 1 ? 'Выбор модели' : 'Поколение / серия');

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
                        Expanded(child: Text(title(), style: const TextStyle(fontWeight: FontWeight.w800))),
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
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
                        return ListTile(title: Text(v), onTap: () => pickItem(v));
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
                              const SnackBar(content: Text('Выберите марку и модель')),
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
  bool _validDouble(String s) => double.tryParse(s.trim().replaceAll(',', '.')) != null;

  Future<void> _save(Listing listing) async {
    final me = context.read<AuthService>().currentUser!;
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
    final price = int.tryParse(_price.text.trim()) ?? 0;

    if (title.isEmpty || desc.isEmpty || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните название, описание и цену')),
      );
      return;
    }

    CarSpecs? car;
    if (_isAuto) {
      if (_isPassengerCar && (_autoBrand == null || _autoModel == null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Выберите марку и модель')),
        );
        return;
      }

      if (!_validInt(_carYear.text) ||
          !_validInt(_carMileage.text) ||
          !_validDouble(_carEngine.text) ||
          !_validInt(_carPower.text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Заполните авто: год, пробег, объём (л) и мощность (л.с.)')),
        );
        return;
      }

      final year = int.parse(_carYear.text.trim());
      final mileage = int.parse(_carMileage.text.trim());
      final engine = double.parse(_carEngine.text.trim().replaceAll(',', '.'));
      final power = int.parse(_carPower.text.trim());

      final owners = _carOwners.text.trim().isEmpty ? null : int.tryParse(_carOwners.text.trim());
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

    setState(() => _saving = true);
    try {
      // ✅ Supabase UPDATE вместо Firestore
      await _sb.from('listings').update({
        'title': title,
        'description': desc,
        'price': price,
        'phone': phone,
        'phone_hidden': _phoneHidden,
        'city': city,
        'delivery': _delivery,

        // авто параметры (json)
        'car': _isAuto ? (car?.toMap() ?? {}) : null,

        // снова на модерацию
        'status': 'pending',
        'moderated_at': null,
        'rejection_reason': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', listing.id);

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено. Объявление снова на модерации')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
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
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      items: items.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _streamListingRow(widget.listingId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final row = snap.data;
        if (row == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Объявление удалено')));
        }

        final listing = Listing.fromMap(row);
        _initFromListing(listing);

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
                  'Категория: ${listing.category}\nФото не редактируем. После сохранения — снова модерация.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
                decoration: const InputDecoration(labelText: 'Цена (₽)'),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _selectTile(
                      title: 'Город / регион / село (выбрать)',
                      value: _city.text.trim(),
                      onTap: () {}, // у тебя был большой city picker — если надо, вставишь обратно
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
                const Text('Параметры авто', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),

                TextField(
                  controller: _carYear,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Год выпуска (например: 2018)'),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _carMileage,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Пробег (км)'),
                ),
                const SizedBox(height: 12),

                _drop(label: 'Кузов', value: _carBody, items: _bodyTypes, onChanged: (v) => setState(() => _carBody = v ?? _carBody)),
                const SizedBox(height: 12),

                _drop(label: 'Топливо', value: _carFuel, items: _fuelTypes, onChanged: (v) => setState(() => _carFuel = v ?? _carFuel)),
                const SizedBox(height: 12),

                TextField(
                  controller: _carEngine,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Объём двигателя (л), например: 2.5'),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _carPower,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Мощность (л.с.), например: 181'),
                ),
                const SizedBox(height: 12),

                _drop(label: 'Коробка передач', value: _carTransmission, items: _transmissions, onChanged: (v) => setState(() => _carTransmission = v ?? _carTransmission)),
                const SizedBox(height: 12),

                _drop(label: 'Привод', value: _carDrive, items: _drives, onChanged: (v) => setState(() => _carDrive = v ?? _carDrive)),
                const SizedBox(height: 12),

                _drop(label: 'Состояние', value: _carCondition, items: _conditions, onChanged: (v) => setState(() => _carCondition = v ?? _carCondition)),
                const SizedBox(height: 12),

                _drop(label: 'Цвет', value: _carColor, items: _colors, onChanged: (v) => setState(() => _carColor = v ?? _carColor)),
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 12),

              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Телефон (для звонка)'),
              ),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Скрывать номер в объявлении'),
                subtitle: const Text('Номер не будет виден, но кнопка “Позвонить” останется'),
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

              Text('Доставка', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 8),

              InkWell(
                onTap: _openDeliveryPicker,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
                          style: TextStyle(color: Theme.of(context).colorScheme.outline),
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
      },
    );
  }
}
