import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:atta/src/models/listing.dart';
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

  test('broken heic image returns russian error instead of silent loss',
      () async {
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
      'Не удалось обработать фото. Попробуйте выбрать другое фото.',
    );
    expect(mediaApi.uploadCalls, 0);
    await file.delete();
  });

  test('upload status reports preparing then uploading then uploaded',
      () async {
    final mediaApi = _FakeMediaApi();
    final service = ListingsService(
      api: _FakeListingsApi(),
      mediaApi: mediaApi,
    );
    final files = await _createPhotos(1);
    final states = <String>[];
    final messages = <String>[];

    final result = await service.uploadListingPhotos(
      listingId: 'listing-1',
      photos: files,
      onStatusChanged: (status) {
        states.add(status.state);
        messages.add(status.message);
      },
    );

    expect(result.failedCount, 0);
    expect(states, <String>['preparing', 'uploading', 'uploaded']);
    expect(messages, <String>['Сжимаем фото...', 'Загружаем...', 'Загружено']);
    await _deleteFiles(files);
  });

  test('newest listing appears first by publishedAt and createdAt', () async {
    final service = ListingsService(
      api: _FakeListingsApi(
        listItems: <Map<String, dynamic>>[
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
            id: 'old',
            status: 'approved',
            publishedAt: '2026-06-19T10:00:05.000Z',
            createdAt: '2026-06-19T10:00:00.000Z',
            updatedAt: '2026-06-19T12:00:00.000Z',
            viewCount: 999,
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

  test(
      'public feed preserves backend paid ordering instead of resorting by time',
      () async {
    final service = ListingsService(
      api: _FakeListingsApi(
        listItems: <Map<String, dynamic>>[
          for (var i = 0; i < 8; i++)
            _listingMap(
              const <String>[],
              id: 'head-${i + 1}',
              status: 'approved',
              publishedAt:
                  '2026-06-19T10:${(59 - i).toString().padLeft(2, '0')}:00.000Z',
            ),
          _listingMap(
            const <String>[],
            id: 'vip',
            status: 'approved',
            publishedAt: '2026-06-19T01:00:00.000Z',
            promotions: <String, dynamic>{
              'activeVip': <String, dynamic>{
                'id': 'promo-vip',
                'type': 'vip',
                'title': 'VIP',
                'status': 'active',
                'startsAt': '2026-06-19T12:00:00.000Z',
                'endsAt': '2099-06-19T12:00:00.000Z',
              },
            },
          ),
          _listingMap(
            const <String>[],
            id: 'tail',
            status: 'approved',
            publishedAt: '2026-06-19T09:00:00.000Z',
          ),
        ],
      ),
      mediaApi: _FakeMediaApi(),
    );

    final items = await service.getListings(category: 'Все', search: '');

    expect(
      items.map((item) => item.id).toList(),
      [
        'head-1',
        'head-2',
        'head-3',
        'head-4',
        'head-5',
        'head-6',
        'head-7',
        'head-8',
        'vip',
        'tail'
      ],
    );
  });

  test('refreshFeedAfterPromotion clears feed cache and reloads updated order',
      () async {
    final api = _FakeListingsApi(
      listItems: <Map<String, dynamic>>[
        _listingMap(
          const <String>[],
          id: 'fresh',
          status: 'approved',
          publishedAt: '2026-06-19T10:00:00.000Z',
        ),
        _listingMap(
          const <String>[],
          id: 'promoted',
          status: 'approved',
          publishedAt: '2026-06-19T09:00:00.000Z',
        ),
      ],
      findByIdItems: <String, Map<String, dynamic>>{
        'promoted': _listingMap(
          const <String>[],
          id: 'promoted',
          status: 'approved',
          publishedAt: '2026-06-19T09:00:00.000Z',
          promotions: <String, dynamic>{
            'activeVip': <String, dynamic>{
              'id': 'promo-vip',
              'type': 'vip',
              'title': 'VIP',
              'status': 'active',
              'startsAt': '2026-06-19T12:00:00.000Z',
              'endsAt': '2099-06-19T12:00:00.000Z',
            },
          },
        ),
      },
    );
    final service = ListingsService(api: api, mediaApi: _FakeMediaApi());

    final firstLoad = await service.getListings(category: 'Все', search: '');
    expect(firstLoad.map((item) => item.id).toList(), ['fresh', 'promoted']);
    expect(api.listQueries, hasLength(1));

    api.listItems
      ..clear()
      ..addAll(<Map<String, dynamic>>[
        for (var i = 0; i < 7; i++)
          _listingMap(
            const <String>[],
            id: 'head-${i + 1}',
            status: 'approved',
            publishedAt:
                '2026-06-19T10:${(59 - i).toString().padLeft(2, '0')}:00.000Z',
          ),
        _listingMap(
          const <String>[],
          id: 'fresh',
          status: 'approved',
          publishedAt: '2026-06-19T10:00:00.000Z',
        ),
        _listingMap(
          const <String>[],
          id: 'promoted',
          status: 'approved',
          publishedAt: '2026-06-19T09:00:00.000Z',
          promotions: <String, dynamic>{
            'activeVip': <String, dynamic>{
              'id': 'promo-vip',
              'type': 'vip',
              'title': 'VIP',
              'status': 'active',
              'startsAt': '2026-06-19T12:00:00.000Z',
              'endsAt': '2099-06-19T12:00:00.000Z',
            },
          },
        ),
      ]);

    service.refreshFeedAfterPromotion(
      listing: Listing.fromMap(api.findByIdItems['promoted']!),
    );
    final secondLoad = await service.getListings(category: 'Все', search: '');

    expect(api.listQueries.length, greaterThan(1));
    expect(secondLoad.map((item) => item.id).toList().take(9), [
      'head-1',
      'head-2',
      'head-3',
      'head-4',
      'head-5',
      'head-6',
      'head-7',
      'fresh',
      'promoted',
    ]);
  });

  test('my listings use private endpoint and keep favorites count', () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'token',
      refreshToken: 'refresh',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final api = _FakeListingsApi(
      myListItems: <Map<String, dynamic>>[
        _listingMap(
          const <String>[],
          id: 'mine-1',
          status: 'approved',
          viewCount: 3,
          favoriteCount: 2,
        ),
      ],
    );
    final service = ListingsService(
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final items = await service.getMyListingsByStatuses(
      'user-1',
      statuses: const {'approved'},
    );

    expect(api.myListingsCalls, 1);
    expect(api.listQueries, isEmpty);
    expect(items.single.favoriteCount, 2);
  });

  test('my listings filter out foreign owner rows and deduplicate results',
      () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'token',
      refreshToken: 'refresh',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final api = _FakeListingsApi(
      myListItems: <Map<String, dynamic>>[
        _listingMap(
          const <String>[],
          id: 'mine-1',
          status: 'approved',
          ownerId: 'user-1',
        ),
        _listingMap(
          const <String>[],
          id: 'mine-1',
          status: 'approved',
          ownerId: 'user-1',
        ),
        _listingMap(
          const <String>[],
          id: 'foreign-1',
          status: 'approved',
          ownerId: 'user-2',
        ),
      ],
    );
    final service = ListingsService(
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final items = await service.getMyListingsByStatuses(
      'user-1',
      statuses: const {'approved'},
    );

    expect(items.map((item) => item.id).toList(), <String>['mine-1']);
  });

  test('my listings use requested uid even before cached current user restore',
      () async {
    await TokenStorage().clear();
    final api = _FakeListingsApi(
      myListItems: <Map<String, dynamic>>[
        _listingMap(
          const <String>[],
          id: 'mine-1',
          status: 'approved',
          ownerId: 'user-1',
        ),
        _listingMap(
          const <String>[],
          id: 'foreign-1',
          status: 'approved',
          ownerId: 'user-2',
        ),
      ],
    );
    final service = ListingsService(
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final items = await service.getMyListingsByStatuses(
      'user-1',
      statuses: const {'approved'},
    );

    expect(items.map((item) => item.id).toList(), <String>['mine-1']);
    expect(api.myListingsCalls, 1);
  });

  test('my listings single-flight reuses one in-flight request', () async {
    await TokenStorage().saveSession(
      accessToken: 'token',
      refreshToken: 'refresh',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final completer = Completer<Map<String, dynamic>>();
    final api = _DelayedMyListingsApi(responseCompleter: completer);
    final service = ListingsService(
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final first = service.getMyListingsByStatuses(
      'user-1',
      statuses: const {'approved'},
    );
    final second = service.getMyListingsByStatuses(
      'user-1',
      statuses: const {'approved'},
    );

    expect(api.myListingsCalls, 1);

    completer.complete(
      <String, dynamic>{
        'items': <Map<String, dynamic>>[
          _listingMap(
            const <String>[],
            id: 'mine-1',
            status: 'approved',
            ownerId: 'user-1',
          ),
        ],
        'nextCursor': null,
        'hasMore': false,
      },
    );

    final results = await Future.wait(<Future<List<Listing>>>[first, second]);
    expect(results[0].single.id, 'mine-1');
    expect(results[1].single.id, 'mine-1');
    expect(api.myListingsCalls, 1);
  });

  test('resetSession clears previous account my listings cache', () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'token-1',
      refreshToken: 'refresh-1',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final api = _FakeListingsApi(
      myListItems: <Map<String, dynamic>>[
        _listingMap(
          const <String>[],
          id: 'mine-user-1',
          status: 'approved',
          ownerId: 'user-1',
        ),
      ],
    );
    final service = ListingsService(
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final firstItems = await service.getMyListingsByStatuses(
      'user-1',
      statuses: const {'approved'},
    );

    await storage.saveSession(
      accessToken: 'token-2',
      refreshToken: 'refresh-2',
      currentUser: const AuthUser(uid: 'user-2', isAdmin: true),
    );
    service.resetSession();
    api.myListItems
      ..clear()
      ..add(
        _listingMap(
          const <String>[],
          id: 'mine-user-2',
          status: 'approved',
          ownerId: 'user-2',
        ),
      );

    final secondItems = await service.getMyListingsByStatuses(
      'user-2',
      statuses: const {'approved'},
    );

    expect(firstItems.map((item) => item.id).toList(), <String>['mine-user-1']);
    expect(
        secondItems.map((item) => item.id).toList(), <String>['mine-user-2']);
    expect(api.myListingsCalls, 2);
  });

  test('my listings timeout returns cached items and allows next refresh',
      () async {
    await TokenStorage().saveSession(
      accessToken: 'token',
      refreshToken: 'refresh',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final api = _FakeListingsApi(
      myListItems: <Map<String, dynamic>>[
        _listingMap(
          const <String>[],
          id: 'mine-1',
          status: 'approved',
          ownerId: 'user-1',
        ),
      ],
    );
    final service = ListingsService(
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final first = await service.getMyListingsByStatuses(
      'user-1',
      statuses: const {'approved'},
    );
    expect(first.single.id, 'mine-1');

    api.myListingsError = TimeoutException('Future not completed');
    final cached = await service.getMyListingsByStatuses(
      'user-1',
      statuses: const {'approved'},
      forceRefresh: true,
    );
    expect(cached.single.id, 'mine-1');
    expect(
        service.lastMyListingsErrorForUser('user-1'), isA<TimeoutException>());

    api.myListingsError = null;
    api.myListItems
      ..clear()
      ..add(
        _listingMap(
          const <String>[],
          id: 'mine-2',
          status: 'approved',
          ownerId: 'user-1',
        ),
      );
    final refreshed = await service.getMyListingsByStatuses(
      'user-1',
      statuses: const {'approved'},
      forceRefresh: true,
    );
    expect(refreshed.single.id, 'mine-2');
    expect(service.lastMyListingsErrorForUser('user-1'), isNull);
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

  test('refreshListingsByOwner deduplicates and keeps newest approved first',
      () async {
    final api = _FakeListingsApi(
      listItems: <Map<String, dynamic>>[
        _listingMap(
          const <String>[],
          id: 'listing-old',
          status: 'approved',
          publishedAt: '2026-06-19T10:00:00.000Z',
        ),
      ],
    );
    final service = ListingsService(
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final firstLoad = await service.getListingsByOwnerAll('user-1');
    api.listItems
      ..clear()
      ..addAll(<Map<String, dynamic>>[
        _listingMap(
          const <String>[],
          id: 'listing-old',
          status: 'approved',
          publishedAt: '2026-06-19T10:00:00.000Z',
        ),
        _listingMap(
          const <String>[],
          id: 'listing-old',
          status: 'approved',
          publishedAt: '2026-06-19T10:00:00.000Z',
        ),
        _listingMap(
          const <String>[],
          id: 'listing-new',
          status: 'approved',
          publishedAt: '2026-06-19T11:00:00.000Z',
        ),
      ]);

    final refreshed = await service.refreshListingsByOwner('user-1');

    expect(firstLoad.map((item) => item.id).toList(), <String>['listing-old']);
    expect(
      refreshed.map((item) => item.id).toList(),
      <String>['listing-new', 'listing-old'],
    );
    expect(
      service.peekListingsByOwner('user-1').map((item) => item.id).toList(),
      <String>['listing-new', 'listing-old'],
    );
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
      myListItems: <Map<String, dynamic>>[
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
      myListItems: <Map<String, dynamic>>[
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

  test('getListingsPage returns first page with cursor metadata', () async {
    final api = _FakeListingsApi(
      listItems: List<Map<String, dynamic>>.generate(
        25,
        (index) => _listingMap(
          const <String>[],
          id: 'listing-$index',
          status: 'approved',
          publishedAt:
              '2026-07-01T10:${(59 - index).toString().padLeft(2, '0')}:00.000Z',
        ),
      ),
    );
    final service = ListingsService(api: api, mediaApi: _FakeMediaApi());

    final page = await service.getListingsPage(
      category: 'Все',
      search: '',
      limit: 20,
    );

    expect(page.items, hasLength(20));
    expect(page.hasMore, isTrue);
    expect((page.nextCursor ?? '').isNotEmpty, isTrue);
  });

  test('getListingsPage preserves search and category on next page', () async {
    final api = _FakeListingsApi(
      listItems: List<Map<String, dynamic>>.generate(
        30,
        (index) => _listingMap(
          const <String>[],
          id: 'listing-$index',
          status: 'approved',
          publishedAt:
              '2026-07-01T10:${(59 - index).toString().padLeft(2, '0')}:00.000Z',
        ),
      ),
    );
    final service = ListingsService(api: api, mediaApi: _FakeMediaApi());

    final firstPage = await service.getListingsPage(
      category: 'Электроника',
      search: 'Товар',
      limit: 20,
    );
    final secondPage = await service.getListingsPage(
      category: 'Электроника',
      search: 'Товар',
      limit: 20,
      cursor: firstPage.nextCursor,
    );

    expect(firstPage.items, hasLength(20));
    expect(secondPage.items, hasLength(10));
    expect(api.listQueries.first['category'], 'Электроника');
    expect(api.listQueries.first['search'], 'Товар');
    expect(api.listQueries.last['category'], 'Электроника');
    expect(api.listQueries.last['search'], 'Товар');
    expect(api.listQueries.last['cursor'], firstPage.nextCursor);
  });
}

class _FakeListingsApi extends ListingsApi {
  _FakeListingsApi({
    this.listItems = const <Map<String, dynamic>>[],
    this.myListItems = const <Map<String, dynamic>>[],
    this.findByIdItems = const <String, Map<String, dynamic>>{},
  }) : super(ApiClient(tokenStorage: TokenStorage()));

  final List<Map<String, dynamic>> listItems;
  final List<Map<String, dynamic>> myListItems;
  final Map<String, Map<String, dynamic>> findByIdItems;
  final List<Map<String, dynamic>> listQueries = <Map<String, dynamic>>[];
  int myListingsCalls = 0;
  Object? myListingsError;

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
    final query = Map<String, dynamic>.from(queryParameters ?? const {});
    listQueries.add(query);
    final limit = (query['limit'] as int?) ?? int.tryParse('${query['limit']}');
    final cursor = (query['cursor'] ?? '').toString().trim();
    final start = cursor.isEmpty ? 0 : int.tryParse(cursor) ?? 0;
    final effectiveLimit = limit ?? listItems.length;
    final end = (start + effectiveLimit).clamp(0, listItems.length);
    final slice = listItems.sublist(start, end);
    return <String, dynamic>{
      'items': slice,
      'nextCursor': end < listItems.length ? '$end' : null,
      'hasMore': end < listItems.length,
    };
  }

  @override
  Future<Map<String, dynamic>> myListings() async {
    myListingsCalls += 1;
    if (myListingsError != null) {
      throw myListingsError!;
    }
    return <String, dynamic>{
      'items': myListItems,
      'nextCursor': null,
      'hasMore': false,
    };
  }
}

class _DelayedMyListingsApi extends _FakeListingsApi {
  _DelayedMyListingsApi({
    required this.responseCompleter,
  });

  final Completer<Map<String, dynamic>> responseCompleter;

  @override
  Future<Map<String, dynamic>> myListings() {
    myListingsCalls += 1;
    return responseCompleter.future;
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
  String ownerId = 'user-1',
  String? publishedAt,
  String createdAt = '2026-06-19T10:00:00.000Z',
  String updatedAt = '2026-06-19T10:00:00.000Z',
  int viewCount = 0,
  int favoriteCount = 0,
  Map<String, dynamic>? promotions,
}) =>
    <String, dynamic>{
      'id': id,
      'owner_id': ownerId,
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
      'favorites_count': favoriteCount,
      'promotions': promotions ?? const <String, dynamic>{},
      'delivery': const <String, bool>{'pickup': true},
      'owner': <String, dynamic>{'id': ownerId},
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
