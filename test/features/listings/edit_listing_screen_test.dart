import 'dart:io';

import 'package:atta/src/features/listings/edit_listing_screen.dart';
import 'package:atta/src/models/car_specs.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/image_preparation_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('edit listing screen shows optional transport labels',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ListingsService>.value(value: _FakeListingsService()),
        ],
        child: const MaterialApp(
          home: EditListingScreen(listingId: 'listing-1'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Параметры авто'), findsOneWidget);
    expect(find.text('Необязательно'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Пробег (необязательно)',
      ),
      findsNothing,
    );

    await tester.tap(find.text('Параметры авто'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            _decorationHasLabel(widget.decoration, 'Пробег (необязательно)'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            _decorationHasLabel(widget.decoration, 'Кузов (необязательно)'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            _decorationHasLabel(widget.decoration, 'Топливо (необязательно)'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            _decorationHasLabel(
              widget.decoration,
              'Объём двигателя (необязательно)',
            ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('edit blocks saving when final photo count is zero',
      (tester) async {
    final listings = _FakeListingsService(
      photoUrls: const ['https://cdn.example.com/photo-1.jpg'],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ListingsService>.value(value: listings),
        ],
        child: const MaterialApp(
          home: EditListingScreen(listingId: 'listing-1'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(find.text('Добавьте минимум 1 фото'), findsOneWidget);
    expect(listings.calls, isEmpty);
  });

  testWidgets('edit uploads new photos before deleting old photos',
      (tester) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    final photo = _createTestPng();
    _mockImagePicker(photo);
    addTearDown(() => _clearImagePicker(photo));

    final listings = _FakeListingsService(
      photoUrls: const ['https://cdn.example.com/photo-1.jpg'],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ListingsService>.value(value: listings),
        ],
        child: const MaterialApp(
          home: EditListingScreen(listingId: 'listing-1'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_a_photo_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(listings.calls, ['upload:1', 'update', 'delete:photo-0']);
  });

  testWidgets('edit upload failure does not delete old photos', (tester) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    final photo = _createTestPng();
    _mockImagePicker(photo);
    addTearDown(() => _clearImagePicker(photo));

    final listings = _FakeListingsService(
      photoUrls: const ['https://cdn.example.com/photo-1.jpg'],
      failUploads: true,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ListingsService>.value(value: listings),
        ],
        child: const MaterialApp(
          home: EditListingScreen(listingId: 'listing-1'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_a_photo_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(
        find.text('Повторите загрузку фотографий с ошибкой'), findsOneWidget);
    expect(listings.calls, ['upload:1']);
  });
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

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'user-1');
}

class _FakeListingsService extends ListingsService {
  _FakeListingsService({
    this.photoUrls = const <String>[],
    this.failUploads = false,
  });

  final List<String> photoUrls;
  final bool failUploads;
  final calls = <String>[];
  int? uploadStartIndex;

  @override
  Future<Listing?> getListingById(String id) async {
    return Listing.fromMap(<String, dynamic>{
      'id': id,
      'owner_id': 'user-1',
      'title': 'Toyota Camry',
      'description': 'Описание',
      'category': 'Авто',
      'subcategory': 'Легковые автомобили',
      'price': 1500000,
      'phone': '+79990000000',
      'phone_hidden': false,
      'city': 'Москва',
      'delivery': <String, dynamic>{'pickup': true},
      'photo_urls': photoUrls,
      'photo_items': [
        for (var i = 0; i < photoUrls.length; i++)
          {
            'id': 'photo-$i',
            'url': photoUrls[i],
            'sort_order': i,
          },
      ],
      'car': <String, dynamic>{
        'brand': 'Toyota',
        'model': 'Camry',
        'generation': 'XV70',
      },
    });
  }

  @override
  Future<Listing> updateListing({
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
    String? oemPartNumber,
  }) async {
    calls.add('update');
    return (await getListingById(listingId))!;
  }

  @override
  Future<ListingPhotoUploadResponse> uploadListingPhotoItem({
    required String listingId,
    required File file,
    int? sortOrder,
    PreparedImage? preparedImage,
  }) async {
    calls.add('upload:1');
    if (failUploads) {
      throw Exception('upload failed');
    }
    return ListingPhotoUploadResponse(
      listing: (await getListingById(listingId))!,
      photoId: 'new-photo-${sortOrder ?? 0}',
    );
  }

  @override
  Future<ListingPhotoUploadResult> uploadListingPhotos({
    required String listingId,
    required List<File> photos,
    List<int>? sortOrders,
    int? startIndex,
    ListingPhotoUploadStatusCallback? onStatusChanged,
  }) async {
    calls.add('upload:${photos.length}');
    uploadStartIndex = startIndex;
    if (failUploads) {
      return ListingPhotoUploadResult(
        requestedCount: photos.length,
        failures: [
          for (var i = 0; i < photos.length; i++)
            ListingPhotoUploadFailure(
              index: i,
              file: photos[i],
              message: 'upload failed',
            ),
        ],
      );
    }
    return ListingPhotoUploadResult(
      requestedCount: photos.length,
      uploadedCount: photos.length,
      listing: (await getListingById(listingId))!,
    );
  }

  @override
  Future<Listing> deleteListingPhoto({
    required String listingId,
    required String photoId,
  }) async {
    calls.add('delete:$photoId');
    return (await getListingById(listingId))!;
  }
}

void _mockImagePicker(File photo) {
  const channel = MethodChannel('plugins.flutter.io/image_picker');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'pickMultiImage') {
      return <String>[photo.path];
    }
    return null;
  });
}

void _clearImagePicker(File photo) {
  const channel = MethodChannel('plugins.flutter.io/image_picker');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
  if (photo.existsSync()) photo.deleteSync();
  final photoDir = photo.parent;
  if (photoDir.existsSync()) photoDir.deleteSync();
}

File _createTestPng() {
  final dir = Directory.systemTemp.createTempSync('atta_edit_listing_test_');
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
