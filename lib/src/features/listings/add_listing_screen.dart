// lib/src/features/listings/add_listing_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:atta/src/constants/categories.dart';
import 'package:atta/src/data/auto_catalog.dart';
import 'package:atta/src/data/electronics_catalog.dart';
import 'package:atta/src/features/listings/car_parameters_screen.dart';
import 'package:atta/src/features/listings/pick_location_screen.dart';
import 'package:atta/src/models/car_specs.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:atta/src/utils/vehicle_specs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

enum _ListingDraftPhotoState {
  waiting,
  preparing,
  uploading,
  uploaded,
  failed,
  deleting
}

class _ListingDraftPhotoItem {
  const _ListingDraftPhotoItem({
    required this.localId,
    required this.file,
    required this.sourceIndex,
    this.state = _ListingDraftPhotoState.waiting,
    this.statusText,
    this.photoId = '',
  });

  final String localId;
  final File file;
  final int sourceIndex;
  final _ListingDraftPhotoState state;
  final String? statusText;
  final String photoId;

  _ListingDraftPhotoItem copyWith({
    _ListingDraftPhotoState? state,
    String? statusText,
    bool clearStatusText = false,
    int? sourceIndex,
    String? photoId,
  }) {
    return _ListingDraftPhotoItem(
      localId: localId,
      file: file,
      sourceIndex: sourceIndex ?? this.sourceIndex,
      state: state ?? this.state,
      statusText: clearStatusText ? null : (statusText ?? this.statusText),
      photoId: photoId ?? this.photoId,
    );
  }
}

class _CustomClothesSizeDialog extends StatefulWidget {
  const _CustomClothesSizeDialog({this.initialValue});

  final String? initialValue;

  @override
  State<_CustomClothesSizeDialog> createState() =>
      _CustomClothesSizeDialogState();
}

class _CustomClothesSizeDialogState extends State<_CustomClothesSizeDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Другой размер'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 24,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Размер',
          hintText: 'One Size',
          counterText: '',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Готово'),
        ),
      ],
    );
  }
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
  final _photoItems = <_ListingDraftPhotoItem>[];
  bool _saving = false;
  String _draftListingId = '';
  Future<String>? _draftListingInFlight;
  bool _publishedDraft = false;
  ListingsService? _listingsServiceForCleanup;
  int _nextPhotoLocalId = 0;

  final _picker = ImagePicker();
  bool _phoneHidden = true;

  // ===== “умные” поля =====
  String? _autoBrand;
  String? _autoModel;
  String? _autoGen;

  String? _electronicsSub;
  String _lastTitleSuggestion = '';

  // ✅ НОВОЕ: Недвижимость
  String _dealType = 'Продажа';

  // ✅ НОВОЕ: Одежда
  String _clothesType = 'Верхняя одежда';
  String? _clothesSize;

  // ✅ доп. селекты для авто
  String? _carBody;
  String? _carFuel;
  String? _carTransmission;
  String? _carDrive;
  String? _carCondition;
  String? _carColor;
  bool? _carCleared; // растаможен (null = не указано)
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
  bool get _isElectronics => _category == 'Электроника';
  bool get _isRealEstate => _category == 'Недвижимость';
  bool get _isClothes => _category == 'Одежда';
  String _categoryLabel(String value) => value == 'Авто' ? 'Транспорт' : value;
  bool get _isUploadingPhotos => _photoItems.any(
        (item) =>
            item.state == _ListingDraftPhotoState.preparing ||
            item.state == _ListingDraftPhotoState.uploading,
      );
  bool get _hasFailedPhotos => _photoItems.any(
        (item) => item.state == _ListingDraftPhotoState.failed,
      );
  bool get _hasUploadedPhotos => _photoItems.any(
        (item) => item.state == _ListingDraftPhotoState.uploaded,
      );
  bool get _canEditPhotoSelection => !_saving;
  String get _submitLabel {
    if (_saving || _isUploadingPhotos) {
      return 'Загружаем фото...';
    }
    if (_hasFailedPhotos) {
      return 'Сначала загрузите все фото';
    }
    return 'Опубликовать';
  }

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

  static const _ptsTypes = <String>[
    'Оригинал',
    'Дубликат',
    'Электронный',
    'Нет',
  ];

  static const _engineVolumes = <String>[
    '0.5',
    '0.6',
    '0.7',
    '0.8',
    '0.9',
    '1.0',
    '1.1',
    '1.2',
    '1.3',
    '1.4',
    '1.5',
    '1.6',
    '1.7',
    '1.8',
    '1.9',
    '2.0',
    '2.1',
    '2.2',
    '2.3',
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
    '4.5',
    '4.6',
    '4.7',
    '5.0',
    '5.5',
    '5.7',
    '6.0',
    '6.2',
    '6.3',
    '6.5',
    '6.7',
    '7.0',
    '8.0',
    '20',
    '25',
    '30',
    '49',
    '50',
    '65',
    '70',
    '80',
    '85',
    '90',
    '100',
    '110',
    '125',
    '150',
    '160',
    '172',
    '180',
    '190',
    '200',
    '230',
    '250',
    '300',
    '350',
    '400',
    '450',
    '500',
    '600',
    '650',
    '700',
    '750',
    '800',
    '850',
    '900',
    '1000',
    '1100',
    '1200',
    '1300',
    '1500',
    '1800',
    '2000',
    '2500',
  ];

  static const _powerValues = <String>[
    '20',
    '23',
    '25',
    '30',
    '35',
    '40',
    '45',
    '50',
    '55',
    '60',
    '65',
    '70',
    '75',
    '80',
    '85',
    '90',
    '95',
    '100',
    '105',
    '110',
    '115',
    '120',
    '125',
    '130',
    '135',
    '140',
    '145',
    '150',
    '155',
    '160',
    '165',
    '170',
    '175',
    '180',
    '185',
    '190',
    '193',
    '197',
    '200',
    '210',
    '220',
    '230',
    '240',
    '250',
    '260',
    '270',
    '280',
    '290',
    '300',
    '320',
    '340',
    '350',
    '360',
    '380',
    '400',
    '420',
    '450',
    '480',
    '500',
    '550',
    '600',
    '650',
    '700',
    '750',
    '800',
    '850',
    '900',
    '950',
    '1000',
    '1100',
    '1200',
    '1300',
    '1500',
    '2000',
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
  static const _dealTypes = <String>[
    'Продажа',
    'Аренда',
    'Посуточно',
    'Обмен',
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

  static const _clothesSizes = <String>[
    'XXS',
    'XS',
    'S',
    'M',
    'L',
    'XL',
    '2XL',
    '3XL',
    '4XL',
    '5XL',
    '38',
    '40',
    '42',
    '44',
    '46',
    '48',
    '50',
    '52',
    '54',
    '56',
    '58',
    '60',
    '62',
    '64',
    '66',
  ];

  @override
  void initState() {
    super.initState();
    final phone = context.read<AuthService>().currentUser?.phone?.trim() ?? '';
    if (phone.isNotEmpty) {
      _phone.text = formatRuPhoneForField(phone);
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _prefillPhoneFromProfile());
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
      _phone.text = formatRuPhoneForField(phone);
      setState(() {});
    } catch (_) {}
  }

  String _friendlyError(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 413) {
        return 'Фото слишком большое. Попробуйте другое фото.';
      }
      if (error.message.trim().isNotEmpty) {
        return error.message.trim();
      }
    }
    final text = error.toString().toLowerCase();
    if (text.contains('413') || text.contains('too large')) {
      return 'Фото слишком большое. Попробуйте другое фото.';
    }
    return 'Не удалось создать объявление. Попробуйте ещё раз.';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listingsServiceForCleanup = context.read<ListingsService>();
  }

  @override
  void dispose() {
    if (!_publishedDraft && _draftListingId.isNotEmpty) {
      final svc = _listingsServiceForCleanup;
      final draftId = _draftListingId;
      if (svc != null) {
        unawaited(
          svc.getListingById(draftId).then((listing) {
            if (listing != null) {
              return svc.deleteListing(listing: listing);
            }
            return null;
          }).catchError((_) => null),
        );
      }
    }
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
    if (!_canEditPhotoSelection || _photoItems.length >= 10) return;

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
    if (!_canEditPhotoSelection) return;
    final remain = 10 - _photoItems.length;
    if (remain <= 0) return;

    final xs = await _picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (xs.isEmpty) return;

    final added = <_ListingDraftPhotoItem>[];
    setState(() {
      for (final x in xs.take(remain)) {
        final item = _newPhotoItem(File(x.path));
        _photoItems.add(item);
        added.add(item);
      }
    });
    for (final item in added) {
      unawaited(_uploadPhotoItem(item.localId));
    }

    if (xs.length > remain && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Можно максимум 10 фото. Добавлено: $remain')),
      );
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (!_canEditPhotoSelection) return;
    final x = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (x == null) return;
    if (_photoItems.length >= 10) return;
    late final _ListingDraftPhotoItem item;
    setState(() {
      item = _newPhotoItem(File(x.path));
      _photoItems.add(item);
    });
    unawaited(_uploadPhotoItem(item.localId));
  }

  _ListingDraftPhotoItem _newPhotoItem(File file) {
    return _ListingDraftPhotoItem(
      localId: 'photo_${_nextPhotoLocalId++}',
      file: file,
      sourceIndex: _photoItems.length,
    );
  }

  Future<void> _removePhotoAt(int index) async {
    final item = _photoItems[index];
    if (!_canEditPhotoSelection ||
        item.state == _ListingDraftPhotoState.deleting) {
      return;
    }
    if (item.photoId.isNotEmpty && _draftListingId.isNotEmpty) {
      setState(() {
        _photoItems[index] = item.copyWith(
          state: _ListingDraftPhotoState.deleting,
          statusText: 'Удаляем...',
        );
      });
      try {
        await context.read<ListingsService>().deleteListingPhoto(
              listingId: _draftListingId,
              photoId: item.photoId,
            );
      } catch (_) {
        if (!mounted) return;
        setState(() {
          final currentIndex = _photoItems.indexWhere(
            (current) => current.localId == item.localId,
          );
          if (currentIndex != -1) {
            _photoItems[currentIndex] = _photoItems[currentIndex].copyWith(
              state: _ListingDraftPhotoState.uploaded,
              statusText: 'Не удалось удалить',
            );
          }
        });
        return;
      }
      if (!mounted) return;
    }
    setState(() {
      _photoItems.removeWhere((current) => current.localId == item.localId);
      for (var i = 0; i < _photoItems.length; i++) {
        _photoItems[i] = _photoItems[i].copyWith(sourceIndex: i);
      }
    });
  }

  void _setPhotoStateByLocalId(
    String localId,
    _ListingDraftPhotoState state, {
    String? statusText,
    bool clearStatusText = false,
    String? photoId,
  }) {
    final index = _photoItems.indexWhere((item) => item.localId == localId);
    if (index == -1) return;
    _photoItems[index] = _photoItems[index].copyWith(
      state: state,
      statusText: statusText,
      clearStatusText: clearStatusText,
      photoId: photoId,
    );
  }

  Future<String> _ensureDraftListingId() async {
    if (_draftListingId.isNotEmpty) return _draftListingId;
    final inFlight = _draftListingInFlight;
    if (inFlight != null) return inFlight;
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) throw StateError('Auth user is required');
    final ownerName = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : (user.email ?? 'Пользователь');
    final future = context
        .read<ListingsService>()
        .createDraftListing(
          ownerEmail: user.email ?? '',
          ownerName: ownerName,
          category: _category,
          subcategory: _subcategory,
          city: _city.text.trim(),
          phone: _phone.text.trim(),
          phoneHidden: _phoneHidden,
          delivery: _delivery,
        )
        .then((result) {
      if (result.listingId.isEmpty) {
        throw Exception('Не удалось подготовить загрузку фото');
      }
      _draftListingId = result.listingId;
      return _draftListingId;
    });
    _draftListingInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_draftListingInFlight, future)) {
        _draftListingInFlight = null;
      }
    }
  }

  Future<void> _uploadPhotoItem(String localId) async {
    final index = _photoItems.indexWhere((item) => item.localId == localId);
    if (index == -1) return;
    final item = _photoItems[index];
    if (item.state == _ListingDraftPhotoState.uploading ||
        item.state == _ListingDraftPhotoState.preparing ||
        item.state == _ListingDraftPhotoState.deleting) {
      return;
    }
    if (item.photoId.isNotEmpty) {
      await _removePhotoAt(index);
    }
    if (!mounted) return;
    setState(() {
      _setPhotoStateByLocalId(
        localId,
        _ListingDraftPhotoState.preparing,
        statusText: 'Сжимаем фото...',
      );
    });
    try {
      final listingId = await _ensureDraftListingId();
      if (!mounted ||
          !_photoItems.any((current) => current.localId == localId)) {
        return;
      }
      setState(() {
        _setPhotoStateByLocalId(
          localId,
          _ListingDraftPhotoState.uploading,
          statusText: 'Загружаем...',
        );
      });
      final currentIndex =
          _photoItems.indexWhere((current) => current.localId == localId);
      final response =
          await context.read<ListingsService>().uploadListingPhotoItem(
                listingId: listingId,
                file: item.file,
                sortOrder: currentIndex == -1 ? item.sourceIndex : currentIndex,
              );
      if (!mounted) return;
      if (!_photoItems.any((current) => current.localId == localId)) {
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
        _setPhotoStateByLocalId(
          localId,
          _ListingDraftPhotoState.uploaded,
          statusText: null,
          clearStatusText: true,
          photoId: response.photoId,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _setPhotoStateByLocalId(
          localId,
          _ListingDraftPhotoState.failed,
          statusText: _friendlyPhotoError(error),
        );
      });
    }
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

  String _photoStatusLabel(_ListingDraftPhotoItem item) {
    switch (item.state) {
      case _ListingDraftPhotoState.waiting:
        return 'Ожидает';
      case _ListingDraftPhotoState.preparing:
        return item.statusText?.trim().isNotEmpty == true
            ? item.statusText!.trim()
            : 'Подготовка...';
      case _ListingDraftPhotoState.uploading:
        return item.statusText?.trim().isNotEmpty == true
            ? item.statusText!.trim()
            : 'Загружаем...';
      case _ListingDraftPhotoState.uploaded:
        return item.statusText?.trim().isNotEmpty == true
            ? item.statusText!.trim()
            : 'Загружено';
      case _ListingDraftPhotoState.failed:
        return item.statusText?.trim().isNotEmpty == true
            ? item.statusText!.trim()
            : 'Ошибка загрузки';
      case _ListingDraftPhotoState.deleting:
        return item.statusText?.trim().isNotEmpty == true
            ? item.statusText!.trim()
            : 'Удаляем...';
    }
  }

  Color _photoStatusColor(
    BuildContext context,
    _ListingDraftPhotoItem item,
  ) {
    switch (item.state) {
      case _ListingDraftPhotoState.waiting:
        return Theme.of(context).colorScheme.onSurfaceVariant;
      case _ListingDraftPhotoState.preparing:
      case _ListingDraftPhotoState.uploading:
        return Theme.of(context).colorScheme.primary;
      case _ListingDraftPhotoState.uploaded:
        return Colors.green.shade700;
      case _ListingDraftPhotoState.failed:
        return Theme.of(context).colorScheme.error;
      case _ListingDraftPhotoState.deleting:
        return Theme.of(context).colorScheme.outline;
    }
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
      await _fillCityFromLatLng(res);
      if (mounted) setState(() {});
      return;
    }
    if (res is String) {
      _city.text = res;
      if (mounted) setState(() {});
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

    _carBody = null;
    _carFuel = null;
    _carTransmission = null;
    _carDrive = null;
    _carCondition = null;
    _carColor = null;
    _carCleared = null;
    _carPts = null;

    // ✅ сброс недвижимость/одежда
    _dealType = 'Продажа';
    _clothesType = 'Верхняя одежда';
    _clothesSize = null;
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
          engineVolumes: _engineVolumes,
          powerValues: _powerValues,
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

  Future<void> _save() async {
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
        const SnackBar(content: Text('Укажите город')),
      );
      return;
    }

    if (_photoItems.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Добавьте минимум 1 фото')));
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

    if (!_hasUploadedPhotos || _draftListingId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Добавьте минимум 1 фото')));
      return;
    }

    // ✅ обязательные авто поля
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

    // ✅ новые поля
    final dealType = _isRealEstate ? _dealType : null;
    final clothesType = _isClothes ? _clothesType : null;
    final clothesSize = _isClothes ? _clothesSize?.trim() : null;

    final svc = context.read<ListingsService>();

    setState(() => _saving = true);
    try {
      await svc.updateListing(
        listingId: _draftListingId,
        title: title,
        description: desc,
        category: _category,
        subcategory: _subcategory,
        price: price,
        phone: phone,
        phoneHidden: _phoneHidden,
        city: city,
        delivery: _delivery,
        car: _isAuto ? car : null,
        dealType: dealType,
        clothesType: clothesType,
        clothesSize: clothesSize,
      );

      if (!mounted) return;
      _publishedDraft = true;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Объявление отправлено на модерацию')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
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
              child: _fieldText(
                value.isEmpty ? title : value,
                TextStyle(
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

  Future<void> _openClothesSizePicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                'Размер',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final size in _clothesSizes)
                    ChoiceChip(
                      label: Text(size),
                      selected: _clothesSize == size,
                      onSelected: (_) => Navigator.of(sheetContext).pop(size),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Другой размер'),
                onTap: () async {
                  final custom =
                      await _openCustomClothesSizeDialog(sheetContext);
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop(custom);
                },
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null) return;
    final normalized = selected.trim();
    setState(() {
      _clothesSize = normalized.isEmpty ? null : normalized;
    });
  }

  Future<String?> _openCustomClothesSizeDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => _CustomClothesSizeDialog(initialValue: _clothesSize),
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
      decoration: InputDecoration(label: _fieldLabel(label)),
    );
  }

  Widget _fieldLabel(String label) => _fieldText(label, null);

  /// Keeps the field name at the normal Material size and makes only the
  /// optional suffix smaller. The price field never uses this helper.
  Widget _fieldText(String text, TextStyle? style) {
    const suffix = ' (необязательно)';
    if (!text.endsWith(suffix)) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final name = text.substring(0, text.length - suffix.length);
    return Text.rich(
      TextSpan(
        text: '$name ',
        style: style,
        children: const [
          TextSpan(
            text: 'Необязательно',
            style: TextStyle(fontSize: 8),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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
            onPressed: (_saving || _isUploadingPhotos || _hasFailedPhotos)
                ? null
                : _save,
            child: Text(_submitLabel),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            items: categories
                .map(
                  (c) => DropdownMenuItem(
                    value: c,
                    child: Text(_categoryLabel(c)),
                  ),
                )
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
              initialValue: _subcategory,
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

          // ✅ Недвижимость: сделка
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

          if (_isClothes) ...[
            _selectTile(
              title: 'Размер',
              value: _clothesSize?.trim() ?? '',
              onTap: _openClothesSizePicker,
              leading: const Icon(Icons.straighten_outlined),
            ),
            const SizedBox(height: 4),
            Text(
              'Необязательно',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
          ],

          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            inputFormatters: [PriceThousandsInputFormatter()],
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
                  onSelected: (_) => setState(() {}),
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

          if (_isAuto) ...[
            const SizedBox(height: 18),
            TextField(
              controller: _carYear,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Год выпуска (например: 2018)',
              ),
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
                  ? 'Номер из профиля подставляется автоматически, его можно изменить для этого объявления'
                  : 'Будет показано как: ${formatRussianPhone(_phone.text)}',
            ),
          ),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _phoneHidden
                  ? 'Номер скрыт в объявлении'
                  : 'Номер показан в объявлении',
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
                onPressed: (!_canEditPhotoSelection || _photoItems.length >= 10)
                    ? null
                    : _openPhotoMenu,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text('Фото (${_photoItems.length}/10)'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _draftListingId.isEmpty
                      ? 'Добавьте минимум 1 фото — так лучше продаётся.'
                      : (_hasFailedPhotos
                          ? 'Есть ошибки загрузки. Повторите только отмеченные фото.'
                          : 'Фото привязаны к черновику объявления.'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),

          if (_hasFailedPhotos) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving || _isUploadingPhotos ? null : _save,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить загрузку фото'),
            ),
          ],

          const SizedBox(height: 12),

          if (_photoItems.isNotEmpty)
            SizedBox(
              height: 138,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _photoItems.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final item = _photoItems[i];
                  final statusColor = _photoStatusColor(context, item);
                  return SizedBox(
                    width: 110,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: kIsWeb
                                    ? Container(
                                        width: 110,
                                        height: 110,
                                        color: Colors.black12,
                                        alignment: Alignment.center,
                                        child:
                                            const Icon(Icons.photo, size: 28),
                                      )
                                    : Image.file(
                                        item.file,
                                        width: 110,
                                        height: 110,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                              if (item.state ==
                                      _ListingDraftPhotoState.preparing ||
                                  item.state ==
                                      _ListingDraftPhotoState.uploading)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.28),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                ),
                              if (item.state == _ListingDraftPhotoState.failed)
                                Positioned.fill(
                                  child: InkWell(
                                    onTap: () => _uploadPhotoItem(item.localId),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.42),
                                        borderRadius: BorderRadius.circular(12),
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
                              if (item.state ==
                                  _ListingDraftPhotoState.deleting)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.28),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: item.state ==
                                          _ListingDraftPhotoState.deleting
                                      ? null
                                      : () => _removePhotoAt(i),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _photoStatusLabel(item),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor,
                            fontWeight:
                                item.state == _ListingDraftPhotoState.failed
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 90),
        ],
      ),
    );
  }
}
