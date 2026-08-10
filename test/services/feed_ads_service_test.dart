import 'dart:typed_data';

import 'package:atta/src/models/feed_ad.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/feed_ads_api.dart';
import 'package:atta/src/services/api/media_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/feed_ads_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new feed ad with selected image creates record then uploads image once',
      () async {
    final api = _FakeFeedAdsApi();
    final mediaApi = _FakeMediaApi();
    final service = FeedAdsService(api: api, mediaApi: mediaApi);

    final result = await service.createAdWithImage(
      ad: FeedAd.createDraft(
        title: 'Промо',
        imageUrl: '',
        targetUrl: 'https://example.com',
        durationDays: 10,
      ),
      imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
      imageContentType: 'image/png',
    );

    expect(api.createCalls, 1);
    expect(api.removeCalls, 0);
    expect(mediaApi.uploadCalls, 1);
    expect(mediaApi.uploadedFeedAdIds, <String>['server-ad-1']);
    expect(result.id, 'server-ad-1');
    expect(result.imageUrl, 'https://cdn.example.com/feed-ad.png');
  });

  test(
      'admin feed ads stream fetches immediately without an initial empty list',
      () async {
    final api = _FakeFeedAdsApi()
      ..adminListResponses = <List<Map<String, dynamic>>>[
        <Map<String, dynamic>>[
          _feedAdMap(id: 'server-ad-1', title: 'Промо'),
        ],
      ];
    final service = FeedAdsService(api: api, mediaApi: _FakeMediaApi());

    final firstItems = await service.streamAllAds().first;

    expect(api.adminListCalls, 1);
    expect(firstItems.map((ad) => ad.id), <String>['server-ad-1']);
  });

  test('admin feed ads stream is one-shot and does not keep polling', () async {
    final api = _FakeFeedAdsApi()
      ..adminListResponses = <List<Map<String, dynamic>>>[
        <Map<String, dynamic>>[
          _feedAdMap(id: 'server-ad-1', title: 'Промо'),
        ],
      ];
    final service = FeedAdsService(api: api, mediaApi: _FakeMediaApi());
    final emitted = <List<FeedAd>>[];
    Object? streamError;

    final sub = service
        .streamAllAds(pollingInterval: const Duration(milliseconds: 10))
        .listen(emitted.add, onError: (Object error) => streamError = error);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    await sub.cancel();

    expect(streamError, isNull);
    expect(api.adminListCalls, 1);
    expect(emitted.single.single.id, 'server-ad-1');
  });

  test('activateAd calls backend activate and returns updated active ad',
      () async {
    final api = _FakeFeedAdsApi();
    final service = FeedAdsService(api: api, mediaApi: _FakeMediaApi());

    final ad = await service.activateAd('server-ad-1');

    expect(api.activatedIds, <String>['server-ad-1']);
    expect(ad.id, 'server-ad-1');
    expect(ad.isActive, isTrue);
    expect(ad.expiresAt, isNotNull);
  });

  test('active ad stream exposes active backend ad', () async {
    final api = _FakeFeedAdsApi()
      ..activeResponse = _feedAdMap(
        id: 'server-ad-1',
        title: 'Промо',
        isActive: true,
        activatedAt: '2026-08-10T10:00:00.000Z',
        expiresAt: '2026-08-20T10:00:00.000Z',
      );
    final service = FeedAdsService(api: api, mediaApi: _FakeMediaApi());

    final ad = await service.streamActiveAd().first;

    expect(api.activeCalls, 1);
    expect(ad?.id, 'server-ad-1');
    expect(ad?.isVisibleNow, isTrue);
  });

  test('successful deactivate immediately clears cached active ad stream',
      () async {
    final api = _FakeFeedAdsApi();
    final service = FeedAdsService(api: api, mediaApi: _FakeMediaApi());
    await service.activateAd('server-ad-1');

    final emitted = <FeedAd?>[];
    final sub = service.streamActiveAd().listen(emitted.add);

    await pumpEventQueue();
    await service.deactivateAd('server-ad-1');
    await pumpEventQueue();
    await sub.cancel();

    expect(api.deactivatedIds, <String>['server-ad-1']);
    expect(emitted.last, isNull);
  });

  test('failed deactivate does not clear cached active ad stream', () async {
    final api = _FakeFeedAdsApi();
    final service = FeedAdsService(api: api, mediaApi: _FakeMediaApi());
    await service.activateAd('server-ad-1');

    final emitted = <FeedAd?>[];
    final sub = service.streamActiveAd().listen(emitted.add);

    await pumpEventQueue();
    api.deactivateError = const ApiException(
      'deactivate failed',
      statusCode: 500,
    );

    await expectLater(
      service.deactivateAd('server-ad-1'),
      throwsA(isA<ApiException>()),
    );
    await pumpEventQueue();
    await sub.cancel();

    expect(emitted.last?.id, 'server-ad-1');
    expect(emitted.last?.isVisibleNow, isTrue);
  });

  test('activate after deactivate makes feed ad active again', () async {
    final api = _FakeFeedAdsApi();
    final service = FeedAdsService(api: api, mediaApi: _FakeMediaApi());
    final emitted = <FeedAd?>[];
    final sub = service.streamActiveAd().listen(emitted.add);

    await service.activateAd('server-ad-1');
    await service.deactivateAd('server-ad-1');
    await service.activateAd('server-ad-1');
    await pumpEventQueue();
    await sub.cancel();

    expect(emitted.last?.id, 'server-ad-1');
    expect(emitted.last?.isVisibleNow, isTrue);
    expect(api.activatedIds, <String>['server-ad-1', 'server-ad-1']);
  });
}

class _FakeFeedAdsApi extends FeedAdsApi {
  _FakeFeedAdsApi() : super(ApiClient(tokenStorage: TokenStorage()));

  int createCalls = 0;
  int removeCalls = 0;
  int adminListCalls = 0;
  int activeCalls = 0;
  final List<String> activatedIds = <String>[];
  final List<String> deactivatedIds = <String>[];
  List<List<Map<String, dynamic>>> adminListResponses =
      <List<Map<String, dynamic>>>[];
  Map<String, dynamic>? activeResponse;
  ApiException? adminListErrorAfterResponses;
  ApiException? deactivateError;

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async {
    createCalls += 1;
    return <String, dynamic>{
      'source': 'timeweb',
      'ad': <String, dynamic>{
        'id': 'server-ad-1',
        'title': body['title'],
        'image_url': body['image_url'],
        'target_url': body['target_url'],
        'is_active': false,
        'duration_days': body['duration_days'],
        'placement': 'home',
        'created_at': '2026-08-10T10:00:00.000Z',
        'updated_at': '2026-08-10T10:00:00.000Z',
        'impression_count': 0,
        'click_count': 0,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> remove(String id) async {
    removeCalls += 1;
    return <String, dynamic>{'deleted': true, 'id': id};
  }

  @override
  Future<Map<String, dynamic>> adminList({String placement = 'home'}) async {
    adminListCalls += 1;
    if (adminListResponses.isNotEmpty) {
      return <String, dynamic>{
        'source': 'timeweb',
        'items': adminListResponses.removeAt(0),
      };
    }
    final error = adminListErrorAfterResponses;
    if (error != null) throw error;
    return const <String, dynamic>{
      'source': 'timeweb',
      'items': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> active({String placement = 'home'}) async {
    activeCalls += 1;
    return <String, dynamic>{
      'source': 'timeweb',
      'ad': activeResponse,
    };
  }

  @override
  Future<Map<String, dynamic>> activate(String id) async {
    activatedIds.add(id);
    return <String, dynamic>{
      'source': 'timeweb',
      'ad': _feedAdMap(
        id: id,
        title: 'Промо',
        isActive: true,
        activatedAt: '2026-08-10T10:00:00.000Z',
        expiresAt: '2026-08-20T10:00:00.000Z',
      ),
    };
  }

  @override
  Future<Map<String, dynamic>> deactivate(String id) async {
    deactivatedIds.add(id);
    final error = deactivateError;
    if (error != null) throw error;
    return <String, dynamic>{
      'source': 'timeweb',
      'ad': _feedAdMap(
        id: id,
        title: 'Промо',
        isActive: false,
        activatedAt: '2026-08-10T10:00:00.000Z',
        expiresAt: '2026-08-20T10:00:00.000Z',
      ),
    };
  }
}

class _FakeMediaApi extends MediaApi {
  _FakeMediaApi() : super(ApiClient(tokenStorage: TokenStorage()));

  int uploadCalls = 0;
  final List<String> uploadedFeedAdIds = <String>[];

  @override
  Future<Map<String, dynamic>> uploadFeedAdImage({
    required String feedAdId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    uploadCalls += 1;
    uploadedFeedAdIds.add(feedAdId);
    return <String, dynamic>{
      'source': 'timeweb',
      'ad': <String, dynamic>{
        'id': feedAdId,
        'image_url': 'https://cdn.example.com/feed-ad.png',
      },
    };
  }
}

Map<String, dynamic> _feedAdMap({
  required String id,
  required String title,
  bool isActive = false,
  String? activatedAt,
  String? expiresAt,
}) {
  return <String, dynamic>{
    'id': id,
    'title': title,
    'image_url': 'https://cdn.example.com/$id.png',
    'target_url': 'https://example.com',
    'is_active': isActive,
    'duration_days': 10,
    'placement': 'home',
    'created_at': '2026-08-10T10:00:00.000Z',
    'activated_at': activatedAt,
    'expires_at': expiresAt,
    'updated_at': '2026-08-10T10:00:00.000Z',
    'impression_count': 0,
    'click_count': 0,
  };
}
