import 'dart:io';
import 'dart:typed_data';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/listings_api.dart';
import 'package:atta/src/services/api/media_api.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('publishing with 3 valid photos uploads all 3', () async {
    final mediaApi = _FakeMediaApi();
    final service = ListingsService(
      api: _FakeListingsApi(),
      mediaApi: mediaApi,
    );
    final files = await _createPhotos(3);

    final result = await service.createListing(
      ownerId: 'user-1',
      ownerEmail: 'user@example.com',
      ownerName: 'User',
      title: 'Товар',
      description: 'Описание',
      category: 'Электроника',
      subcategory: 'Телефоны',
      price: 1000,
      phone: '+79990000000',
      phoneHidden: false,
      city: 'Москва',
      delivery: const <String, bool>{'pickup': true},
      photos: files,
    );

    expect(mediaApi.uploadCalls, 3);
    expect(mediaApi.sortOrders, [0, 1, 2]);
    expect(result.photoUploadResult.uploadedCount, 3);
    expect(result.photoUploadResult.failedCount, 0);
    await _deleteFiles(files);
  });

  test('one failed photo reports partial failure without silent drop',
      () async {
    final mediaApi = _FakeMediaApi(failIndexes: <int>{1});
    final service = ListingsService(
      api: _FakeListingsApi(),
      mediaApi: mediaApi,
    );
    final files = await _createPhotos(3);

    final result = await service.createListing(
      ownerId: 'user-1',
      ownerEmail: 'user@example.com',
      ownerName: 'User',
      title: 'Товар',
      description: 'Описание',
      category: 'Электроника',
      subcategory: 'Телефоны',
      price: 1000,
      phone: '+79990000000',
      phoneHidden: false,
      city: 'Москва',
      delivery: const <String, bool>{'pickup': true},
      photos: files,
    );

    expect(mediaApi.uploadCalls, 3);
    expect(result.photoUploadFailed, isTrue);
    expect(result.photoUploadResult.uploadedCount, 2);
    expect(result.photoUploadResult.failedCount, 1);
    expect(result.photoUploadResult.failures.single.index, 1);
    expect(
      result.photoUploadResult.failures.single.message,
      'Не удалось загрузить фото. Попробуйте ещё раз.',
    );
    await _deleteFiles(files);
  });

  test('heic image returns russian error instead of silent loss', () async {
    final mediaApi = _FakeMediaApi();
    final service = ListingsService(
      api: _FakeListingsApi(),
      mediaApi: mediaApi,
    );
    final file = File(
      '${Directory.systemTemp.path}/atta-photo-${DateTime.now().microsecondsSinceEpoch}.heic',
    );
    await file.writeAsBytes(const <int>[0, 1, 2, 3, 4]);

    final result = await service.uploadListingPhotos(
      listingId: 'listing-1',
      photos: <File>[file],
    );

    expect(result.uploadedCount, 0);
    expect(result.failedCount, 1);
    expect(
      result.failures.single.message,
      'Формат HEIC пока не поддерживается на этом устройстве. Пересохраните фото как JPEG или PNG и попробуйте ещё раз.',
    );
    expect(mediaApi.uploadCalls, 0);
    await file.delete();
  });

  test('newest listing appears first by publishedAt and createdAt', () async {
    final service = ListingsService(
      api: _FakeListingsApi(
        listItems: <Map<String, dynamic>>[
          _listingMap(
            const <String>[],
            id: 'old',
            status: 'approved',
            publishedAt: '2026-06-19T10:00:05.000Z',
            createdAt: '2026-06-19T10:00:00.000Z',
            updatedAt: '2026-06-19T12:00:00.000Z',
            viewCount: 999,
          ),
          _listingMap(
            const <String>[],
            id: 'new',
            status: 'approved',
            publishedAt: '2026-06-19T10:00:10.000Z',
            createdAt: '2026-06-19T09:00:00.000Z',
            updatedAt: '2026-06-19T09:30:00.000Z',
          ),
          _listingMap(
            const <String>[],
            id: 'draft',
            status: 'pending',
            publishedAt: null,
            createdAt: '2026-06-19T10:00:20.000Z',
            updatedAt: '2026-06-19T13:00:00.000Z',
          ),
        ],
      ),
      mediaApi: _FakeMediaApi(),
    );

    final items = await service.getListings(
      category: 'Все',
      search: '',
    );

    expect(items.map((item) => item.id).toList(), ['new', 'old']);
  });

  test('opening old listing does not move it to top locally', () async {
    final api = _FakeListingsApi(
      listItems: <Map<String, dynamic>>[
        _listingMap(
          const <String>[],
          id: 'fresh',
          status: 'approved',
          publishedAt: '2026-06-19T10:00:10.000Z',
          createdAt: '2026-06-19T10:00:10.000Z',
          updatedAt: '2026-06-19T10:00:10.000Z',
        ),
        _listingMap(
          const <String>[],
          id: 'old',
          status: 'approved',
          publishedAt: '2026-06-19T10:00:00.000Z',
          createdAt: '2026-06-19T10:00:00.000Z',
          updatedAt: '2026-06-19T10:00:00.000Z',
        ),
      ],
      findByIdItems: <String, Map<String, dynamic>>{
        'old': _listingMap(
          const <String>[],
          id: 'old',
          status: 'approved',
          publishedAt: '2026-06-19T10:00:00.000Z',
          createdAt: '2026-06-19T10:00:00.000Z',
          updatedAt: '2026-06-19T13:00:00.000Z',
          viewCount: 500,
        ),
      },
    );
    final service = ListingsService(
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final firstLoad = await service.getListings(category: 'Все', search: '');
    final opened = await service.getListingById('old');
    final secondLoad = await service.getListings(category: 'Все', search: '');

    expect(firstLoad.map((item) => item.id).toList(), ['fresh', 'old']);
    expect(opened?.id, 'old');
    expect(secondLoad.map((item) => item.id).toList(), ['fresh', 'old']);
  });

  test('archive removes listing from cached public feed immediately', () async {
    final api = _FakeListingsApi(
      listItems: <Map<String, dynamic>>[
        _listingMap(
          const <String>[],
          id: 'listing-1',
          status: 'approved',
          publishedAt: '2026-06-19T10:00:10.000Z',
        ),
      ],
      findByIdItems: <String, Map<String, dynamic>>{
        'listing-1': _listingMap(
          const <String>[],
          id: 'listing-1',
          status: 'archived',
          publishedAt: '2026-06-19T10:00:10.000Z',
        ),
      },
    );
    final service = ListingsService(
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final before = await service.getListings(category: 'Все', search: '');
    await service.archiveListing(listingId: 'listing-1', status: 'archived');
    final after = await service.getListings(category: 'Все', search: '');

    expect(before.map((item) => item.id).toList(), ['listing-1']);
    expect(after, isEmpty);
  });

  test('uploaded photo updates cached listing immediately', () async {
    final api = _FakeListingsApi(
      listItems: <Map<String, dynamic>>[
        _listingMap(
          const <String>[],
          id: 'listing-1',
          status: 'approved',
          publishedAt: '2026-06-19T10:00:10.000Z',
        ),
      ],
      findByIdItems: <String, Map<String, dynamic>>{
        'listing-1': _listingMap(
          const <String>[],
          id: 'listing-1',
          status: 'approved',
          publishedAt: '2026-06-19T10:00:10.000Z',
        ),
      },
    );
    final service = ListingsService(
      api: api,
      mediaApi: _FakeMediaApi(),
    );
    final files = await _createPhotos(1);

    await service.getListings(category: 'Все', search: '');
    final updated = await service.uploadListingPhotos(
      listingId: 'listing-1',
      photos: files,
    );
    final cached = await service.getListings(category: 'Все', search: '');

    expect(updated.listing?.photoUrls.length, 1);
    expect(cached.single.photoUrls.length, 1);
    await _deleteFiles(files);
  });

  test('archive removes listing from active cache immediately', () async {
    await TokenStorage().saveSession(
      accessToken: 'token',
      refreshToken: 'refresh',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final api = _FakeListingsApi(
      listItems: <Map<String, dynamic>>[
        _listingMap(
          const <String>[],
          id: 'listing-1',
          status: 'approved',
          publishedAt: '2026-06-19T10:00:10.000Z',
        ),
      ],
    );
    final service = ListingsService(
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    await service.getMyListingsByStatuses(
      'user-1',
      statuses: const {'approved'},
    );
    await service.archiveListing(
      listingId: 'listing-1',
      status: 'archived',
    );

    expect(
      service.peekMyListingsByStatuses(statuses: const {'approved'}),
      isEmpty,
    );
    expect(
      service.peekMyListingsByStatuses(statuses: const {'archived'}).single.id,
      'listing-1',
    );
  });

  test('sold moves listing into sold cache immediately', () async {
    await TokenStorage().saveSession(
      accessToken: 'token',
      refreshToken: 'refresh',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final api = _FakeListingsApi(
      listItems: <Map<String, dynamic>>[
        _listingMap(
          const <String>[],
          id: 'listing-1',
          status: 'approved',
          publishedAt: '2026-06-19T10:00:10.000Z',
        ),
      ],
    );
    final service = ListingsService(
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    await service.getMyListingsByStatuses(
      'user-1',
      statuses: const {'approved'},
    );
    await service.archiveListing(
      listingId: 'listing-1',
      status: 'sold',
    );

    expect(
      service.peekMyListingsByStatuses(statuses: const {'approved'}),
      isEmpty,
    );
    expect(
      service.peekMyListingsByStatuses(statuses: const {'sold'}).single.id,
      'listing-1',
    );
  });
}

class _FakeListingsApi extends ListingsApi {
  _FakeListingsApi({
    this.listItems = const <Map<String, dynamic>>[],
    this.findByIdItems = const <String, Map<String, dynamic>>{},
  }) : super(ApiClient(tokenStorage: TokenStorage()));

  final List<Map<String, dynamic>> listItems;
  final Map<String, Map<String, dynamic>> findByIdItems;

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async {
    return <String, dynamic>{
      'listing': _listingMap(const <String>[]),
    };
  }

  @override
  Future<Map<String, dynamic>> getById(String listingId) async {
    return <String, dynamic>{
      'listing': findByIdItems[listingId] ??
          _listingMap(const <String>[], id: listingId),
    };
  }

  @override
  Future<Map<String, dynamic>> archive(
    String id, {
    String? status,
    String? note,
  }) async {
    return <String, dynamic>{
      'listing': _listingMap(
        const <String>[],
        id: id,
        status: status ?? 'archived',
      ),
    };
  }

  @override
  Future<Map<String, dynamic>> list({
    Map<String, dynamic>? queryParameters,
  }) async {
    return <String, dynamic>{
      'items': listItems,
    };
  }
}

class _FakeMediaApi extends MediaApi {
  _FakeMediaApi({this.failIndexes = const <int>{}})
      : super(ApiClient(tokenStorage: TokenStorage()));

  final Set<int> failIndexes;
  int uploadCalls = 0;
  final List<int> sortOrders = <int>[];

  @override
  Future<Map<String, dynamic>> uploadListingPhoto({
    required String listingId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    int? sortOrder,
  }) async {
    final currentIndex = uploadCalls;
    uploadCalls += 1;
    if (sortOrder != null) {
      sortOrders.add(sortOrder);
    }
    if (failIndexes.contains(currentIndex)) {
      throw const ApiException(
          'Не удалось загрузить фото. Попробуйте ещё раз.');
    }
    return <String, dynamic>{
      'listing': _listingMap(
        List<String>.generate(
          currentIndex + 1,
          (i) => 'https://cdn.example.com/$i.jpg',
        ),
        status: 'approved',
        publishedAt: '2026-06-19T10:00:10.000Z',
      ),
    };
  }
}

Map<String, dynamic> _listingMap(
  List<String> photoUrls, {
  String id = 'listing-1',
  String status = 'pending',
  String? publishedAt,
  String createdAt = '2026-06-19T10:00:00.000Z',
  String updatedAt = '2026-06-19T10:00:00.000Z',
  int viewCount = 0,
}) =>
    <String, dynamic>{
      'id': id,
      'owner_id': 'user-1',
      'title': 'Товар',
      'description': 'Описание',
      'category': 'Электроника',
      'subcategory': 'Телефоны',
      'price': 1000,
      'city': 'Москва',
      'address': 'Москва',
      'phone': '+79990000000',
      'phone_hidden': false,
      'status': status,
      'published_at': publishedAt,
      'created_at': DateTime.parse(createdAt).toIso8601String(),
      'updated_at': DateTime.parse(updatedAt).toIso8601String(),
      'view_count': viewCount,
      'delivery': const <String, bool>{'pickup': true},
      'owner': const <String, dynamic>{'id': 'user-1'},
      'photo_urls': photoUrls,
      'photo_items': [
        for (var i = 0; i < photoUrls.length; i++)
          <String, dynamic>{
            'id': 'photo-$i',
            'url': photoUrls[i],
            'sort_order': i,
          },
      ],
    };

Future<List<File>> _createPhotos(int count) async {
  final files = <File>[];
  final prefix = DateTime.now().microsecondsSinceEpoch;
  for (var i = 0; i < count; i++) {
    final file = File(
      '${Directory.systemTemp.path}/atta-listing-$prefix-$i.jpg',
    );
    final image = img.Image(width: 320, height: 240);
    img.fill(image, color: img.ColorRgb8(150 + i, 180, 200));
    await file.writeAsBytes(img.encodeJpg(image, quality: 95));
    files.add(file);
  }
  return files;
}

Future<void> _deleteFiles(List<File> files) async {
  for (final file in files) {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
