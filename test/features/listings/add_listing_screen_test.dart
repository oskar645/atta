import 'dart:io';

import 'package:atta/src/features/listings/add_listing_screen.dart';
import 'package:atta/src/models/car_specs.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/image_preparation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('create listing screen hides additional section', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ProfileService>.value(value: ProfileService()),
          Provider<ListingsService>.value(value: ListingsService()),
        ],
        child: const MaterialApp(
          home: AddListingScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Дополнительно (необязательно)'), findsNothing);
    expect(find.text('Опубликовать'), findsOneWidget);
    expect(find.text('Параметры авто'), findsOneWidget);
    expect(find.text('Необязательно'), findsOneWidget);
    expect(_textFieldWithLabel('Пробег (необязательно)'), findsNothing);

    await tester.tap(find.text('Параметры авто'));
    await tester.pumpAndSettle();

    expect(_textFieldWithLabel('Пробег (необязательно)'), findsOneWidget);
    expect(_dropdownWithLabel('Кузов (необязательно)'), findsOneWidget);
    expect(_dropdownWithLabel('Топливо (необязательно)'), findsOneWidget);
    expect(
      _textWithOptionalLabel('Объём двигателя (необязательно)'),
      findsOneWidget,
    );
    expect(
      _dropdownWithLabel('Коробка передач (необязательно)'),
      findsOneWidget,
    );
    expect(
      _dropdownWithLabel('Привод (необязательно)'),
      findsOneWidget,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(
      _dropdownWithLabel('Состояние (необязательно)'),
      findsOneWidget,
    );
    expect(
      _dropdownWithLabel('Цвет (необязательно)'),
      findsOneWidget,
    );
    expect(
      _dropdownWithLabel('ПТС (необязательно)'),
      findsOneWidget,
    );
  });

  testWidgets('publishes car listing without opening car parameters',
      (tester) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    final photo = _createTestPng();
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickMultiImage') {
        return <String>[photo.path];
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      if (photo.existsSync()) photo.deleteSync();
      final photoDir = photo.parent;
      if (photoDir.existsSync()) photoDir.deleteSync();
    });

    final listings = _CapturingListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ProfileService>.value(value: ProfileService()),
          Provider<ListingsService>.value(value: listings),
        ],
        child: const MaterialApp(
          home: AddListingScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Параметры авто'), findsOneWidget);
    expect(find.text('Необязательно'), findsOneWidget);

    await _enterTextWithLabel(
      tester,
      'Название (автозаполнение можно править)',
      'Toyota Camry',
    );
    await _enterTextWithLabel(tester, 'Цена (₽)', '1500000');
    await _enterTextWithLabel(tester, 'Город / адрес (Яндекс)', 'Москва');
    await _enterTextWithLabel(tester, 'Телефон (для звонка)', '79288888645');
    await _enterTextWithLabel(tester, 'Описание', 'Надежный автомобиль');

    await _scrollUntilBuilt(tester, find.text('Фото (0/10)').first);
    await tester.tap(find.text('Фото (0/10)').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать несколько из галереи'));
    await tester.pumpAndSettle();

    expect(find.text('Фото (1/10)'), findsOneWidget);

    await tester.tap(find.text('Опубликовать'));
    await tester.pumpAndSettle();

    expect(listings.createCalled, isTrue);
    expect(listings.capturedCar, isNotNull);
    expect(listings.capturedCar!.mileageKm, isNull);
    expect(listings.capturedCar!.bodyType, isNull);
    expect(listings.capturedCar!.fuel, isNull);
    expect(listings.capturedCar!.engineVolume, isNull);
    expect(listings.capturedCar!.powerHp, isNull);
    expect(listings.capturedCar!.transmission, isNull);
    expect(listings.capturedCar!.drive, isNull);
    expect(listings.capturedCar!.condition, isNull);
    expect(listings.capturedCar!.color, isNull);
    expect(listings.capturedCar!.pts, isNull);
    expect(listings.capturedCar!.owners, isNull);
    expect(listings.capturedCar!.vin, isNull);
  });

  testWidgets('create listing without selected photo is blocked',
      (tester) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    final listings = _CapturingListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ProfileService>.value(value: ProfileService()),
          Provider<ListingsService>.value(value: listings),
        ],
        child: const MaterialApp(
          home: AddListingScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await _enterTextWithLabel(
      tester,
      'Название (автозаполнение можно править)',
      'Toyota Camry',
    );
    await _enterTextWithLabel(tester, 'Цена (₽)', '1500000');
    await _enterTextWithLabel(tester, 'Город / адрес (Яндекс)', 'Москва');
    await _enterTextWithLabel(tester, 'Телефон (для звонка)', '79288888645');
    await _enterTextWithLabel(tester, 'Описание', 'Надежный автомобиль');

    await tester.tap(find.text('Опубликовать'));
    await tester.pumpAndSettle();

    expect(find.text('Добавьте минимум 1 фото'), findsOneWidget);
    expect(listings.createCalled, isFalse);
  });

  testWidgets('real estate listing uses product kind without separate type',
      (tester) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    final photo = _createTestPng();
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickMultiImage') {
        return <String>[photo.path];
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      if (photo.existsSync()) photo.deleteSync();
      final photoDir = photo.parent;
      if (photoDir.existsSync()) photoDir.deleteSync();
    });

    final listings = _CapturingListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ProfileService>.value(value: ProfileService()),
          Provider<ListingsService>.value(value: listings),
        ],
        child: const MaterialApp(
          home: AddListingScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(_dropdownWithLabel('Категория'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Недвижимость').last);
    await tester.pumpAndSettle();

    expect(_dropdownWithLabel('Вид товара'), findsOneWidget);
    expect(_dropdownWithLabel('Сделка'), findsOneWidget);
    expect(_dropdownWithLabel('Тип недвижимости'), findsNothing);

    await tester.tap(_dropdownWithLabel('Сделка'));
    await tester.pumpAndSettle();
    expect(find.text('Продажа'), findsWidgets);
    expect(find.text('Аренда'), findsWidgets);
    expect(find.text('Посуточно'), findsOneWidget);
    expect(find.text('Обмен'), findsOneWidget);
    await tester.tap(find.text('Продажа').last);
    await tester.pumpAndSettle();

    await _enterTextWithLabel(tester, 'Название', 'Квартира у парка');
    await _enterTextWithLabel(tester, 'Цена (₽)', '5500000');
    await _enterTextWithLabel(tester, 'Город / адрес (Яндекс)', 'Москва');
    await _enterTextWithLabel(tester, 'Телефон (для звонка)', '79288888645');
    await _enterTextWithLabel(tester, 'Описание', 'Светлая квартира');

    await _scrollUntilBuilt(tester, find.text('Фото (0/10)').first);
    await tester.tap(find.text('Фото (0/10)').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать несколько из галереи'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Опубликовать'));
    await tester.pumpAndSettle();

    expect(listings.createCalled, isTrue);
    expect(listings.capturedCategory, 'Недвижимость');
    expect(listings.capturedSubcategory, 'Квартиры');
    expect(listings.capturedDealType, 'Продажа');
  });
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is TextField && _decorationHasLabel(widget.decoration, label),
  );
}

Finder _dropdownWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        _decorationHasLabel(widget.decoration, label),
  );
}

Finder _textWithOptionalLabel(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        _normalizeLabel(widget.data ?? widget.textSpan?.toPlainText()) ==
            _normalizeLabel(label),
  );
}

bool _decorationHasLabel(InputDecoration? decoration, String expected) {
  final actual = decoration?.labelText ?? _labelWidgetText(decoration?.label);
  return _normalizeLabel(actual) == _normalizeLabel(expected);
}

String _labelWidgetText(Widget? widget) {
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText() ?? '';
  }
  return '';
}

String _normalizeLabel(String? text) {
  return (text ?? '').replaceAll(RegExp(r'[\s()]'), '').toLowerCase();
}

Future<void> _enterTextWithLabel(
  WidgetTester tester,
  String label,
  String text,
) async {
  final finder = _textFieldWithLabel(label).first;
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.drag(scrollable, const Offset(0, -120));
    await tester.pump();
  }
  expect(finder, findsOneWidget);
  await tester.enterText(finder, text);
  await tester.pump();
}

Future<void> _scrollUntilBuilt(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.drag(scrollable, const Offset(0, -120));
    await tester.pump();
  }
  expect(finder, findsOneWidget);
}

File _createTestPng() {
  final dir = Directory.systemTemp.createTempSync('atta_listing_test_');
  final file = File('${dir.path}/photo.png');
  file.writeAsBytesSync(const <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
  return file;
}

class _CapturingListingsService extends ListingsService {
  bool createCalled = false;
  CarSpecs? capturedCar;
  String? capturedCategory;
  String? capturedSubcategory;
  String? capturedDealType;

  @override
  Future<CreateListingResult> createDraftListing({
    required String ownerEmail,
    required String ownerName,
    required String category,
    required String subcategory,
    required String city,
    required String phone,
    required bool phoneHidden,
    required Map<String, bool> delivery,
  }) async {
    return const CreateListingResult(listingId: 'listing-1');
  }

  @override
  Future<ListingPhotoUploadResponse> uploadListingPhotoItem({
    required String listingId,
    required File file,
    int? sortOrder,
    PreparedImage? preparedImage,
  }) async {
    return ListingPhotoUploadResponse(
      listing: _listing(),
      photoId: 'photo-$sortOrder',
    );
  }

  @override
  Future<Listing?> updateListing({
    required String listingId,
    required String title,
    required String description,
    required int price,
    required String phone,
    required bool phoneHidden,
    required String city,
    required Map<String, bool> delivery,
    String? category,
    String? subcategory,
    CarSpecs? car,
    String? dealType,
    String? clothesType,
    String? clothesSize,
  }) async {
    createCalled = true;
    capturedCar = car;
    capturedCategory = category ?? '';
    capturedSubcategory = subcategory ?? '';
    capturedDealType = dealType;
    return _listing();
  }

  @override
  Future<Listing?> getListingById(String id) async => _listing();

  @override
  Future<Listing?> deleteListing({required Listing listing}) async => listing;

  Listing _listing() {
    return Listing.fromMap(const <String, dynamic>{
      'id': 'listing-1',
      'owner_id': 'user-1',
      'title': 'Toyota Camry',
      'description': 'Описание',
      'category': 'Авто',
      'subcategory': 'Легковые автомобили',
      'price': 1500000,
      'phone': '+79288888645',
      'phone_hidden': false,
      'city': 'Москва',
      'delivery': <String, dynamic>{},
      'photo_urls': ['https://cdn.example.com/photo.jpg'],
      'photo_items': [
        {
          'id': 'photo-0',
          'url': 'https://cdn.example.com/photo.jpg',
          'sort_order': 0,
        },
      ],
    });
  }
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(
        uid: 'user-1',
        phone: '79288888645',
      );
}
