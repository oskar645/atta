import 'dart:async';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/top_banners_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/top_banners_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends TopBannersApi {
  _FakeApi() : super(ApiClient(tokenStorage: TokenStorage()));
  final afterIds = <String>[];
  final tracked = <String>[];

  @override
  Future<Map<String, dynamic>> active(String lastId) async {
    afterIds.add(lastId);
    final id = lastId == 'a' ? 'b' : 'a';
    return {
      'banner': {
        'id': id,
        'title': id,
        'image_url': 'https://cdn.example/$id.jpg',
        'target_url': '',
        'enabled': true,
        'start_at': '2026-09-01T00:00:00Z',
        'end_at': '2026-10-01T00:00:00Z',
        'sort_order': id == 'a' ? 1 : 2,
        'status': 'active',
        'impression_count': 0,
        'click_count': 0,
      }
    };
  }

  @override
  Future<void> track(String id, String event, String sessionId) async {
    tracked.add('$id:$event:$sessionId');
  }
}

class _PendingApi extends _FakeApi {
  final activeStarted = Completer<void>();
  final activeResult = Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> active(String lastId) {
    afterIds.add(lastId);
    activeStarted.complete();
    return activeResult.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('selection is stable in one session and rotates at next cold start',
      () async {
    SharedPreferences.setMockInitialValues({});
    final api = _FakeApi();
    final firstSession = TopBannersService(api: api);
    final first = await firstSession.selectForColdStart();
    final rebuilt = await firstSession.selectForColdStart();
    expect(first?.id, 'a');
    expect(rebuilt?.id, 'a');
    expect(api.afterIds, ['']);

    final secondSession = TopBannersService(api: api);
    expect((await secondSession.selectForColdStart())?.id, 'b');
    expect(api.afterIds, ['', 'a']);
  });

  test('impression is sent once per selected banner in app session', () async {
    SharedPreferences.setMockInitialValues({});
    final api = _FakeApi();
    final service = TopBannersService(api: api);
    final banner = (await service.selectForColdStart())!;
    await service.impression(banner);
    await service.impression(banner);
    expect(api.tracked, hasLength(1));
    expect(api.tracked.single, contains(':impression:'));
  });

  test('selection starts independently and display waits for image preload',
      () async {
    SharedPreferences.setMockInitialValues({});
    final api = _PendingApi();
    final service = TopBannersService(api: api);

    final selection = service.selectForColdStart();
    await api.activeStarted.future;
    var preloadStarted = false;
    final display = service.prepareForDisplay((_) async {
      preloadStarted = true;
    });

    expect(api.afterIds, ['']);
    expect(preloadStarted, isFalse);
    api.activeResult.complete(await _FakeApi().active(''));
    expect((await selection)?.id, 'a');
    expect((await display)?.id, 'a');
    expect(preloadStarted, isTrue);
  });

  test('rebuild-style prepare calls reuse selection and image preload',
      () async {
    SharedPreferences.setMockInitialValues({});
    final api = _FakeApi();
    final service = TopBannersService(api: api);
    var preloads = 0;

    Future<void> preload(String _) async => preloads++;
    final first = service.prepareForDisplay(preload);
    final rebuilt = service.prepareForDisplay(preload);

    expect((await first)?.id, 'a');
    expect((await rebuilt)?.id, 'a');
    expect(api.afterIds, ['']);
    expect(preloads, 1);
  });

  test('image error keeps display fallback empty', () async {
    SharedPreferences.setMockInitialValues({});
    final api = _FakeApi();
    final service = TopBannersService(api: api);

    final banner = await service.prepareForDisplay(
      (_) => Future<void>.error(StateError('image failed')),
    );

    expect(banner, isNull);
    expect(api.tracked, isEmpty);
  });
}
