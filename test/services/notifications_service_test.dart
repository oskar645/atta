import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/in_app_notifications_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('streamPersonal uses Timeweb notifications list immediately', () async {
    final api = _FakeInAppNotificationsApi(
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'global-1',
          'scope': 'global',
          'title': 'Global',
          'created_at': '2026-06-18T10:00:00.000Z',
          'is_read': false,
        },
        <String, dynamic>{
          'id': 'personal-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Personal',
          'created_at': '2026-06-18T11:00:00.000Z',
          'is_read': false,
        },
      ],
    );
    final service = NotificationsService(
      api: api,
      pollInterval: const Duration(milliseconds: 1),
    );
    service.activateSession('user-1');

    final items = await service.streamPersonal('user-1').first;

    expect(items.length, 1);
    expect(items.first['id'], 'personal-1');
    expect(api.listCalls, 1);
  });

  test('same notifications stream supports multiple listeners', () async {
    final api = _FakeInAppNotificationsApi(
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'personal-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Personal',
          'created_at': '2026-06-18T11:00:00.000Z',
          'is_read': false,
        },
      ],
    );
    final service = NotificationsService(
      api: api,
      pollInterval: const Duration(milliseconds: 50),
    );
    service.activateSession('user-1');
    final stream = service.streamPersonal('user-1');

    final results = await Future.wait([
      stream.first,
      stream.first,
    ]);

    expect(results[0].first['id'], 'personal-1');
    expect(results[1].first['id'], 'personal-1');
  });

  test('sendPersonal uses Timeweb endpoint', () async {
    final api =
        _FakeInAppNotificationsApi(items: const <Map<String, dynamic>>[]);
    final service = NotificationsService(api: api);
    service.activateSession('user-1');

    await service.sendPersonal(
      userId: 'user-1',
      title: 'Hello',
      body: 'World',
    );

    expect(api.sentUserId, 'user-1');
    expect(api.sentTitle, 'Hello');
    expect(api.sentBody, 'World');
  });

  test('markAllSeen uses bulk read endpoint for personal notifications',
      () async {
    final api = _FakeInAppNotificationsApi(
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'global-1',
          'scope': 'global',
          'title': 'Global',
          'created_at': '2026-06-18T10:00:00.000Z',
          'is_read': false,
        },
        <String, dynamic>{
          'id': 'personal-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Personal',
          'created_at': '2026-06-18T11:00:00.000Z',
          'is_read': false,
        },
      ],
    );
    final service = NotificationsService(api: api);
    service.activateSession('user-1');

    await service.preload('user-1');
    await service.markAllSeen('user-1');

    expect(api.markAllReadCalls, 1);
    expect(await service.streamUnreadPersonalCount('user-1').first, 0);
    expect(await service.streamUnreadGlobalCount('user-1').first, 0);
  });

  test('401 stops notifications polling and resets session', () async {
    final api = _FakeInAppNotificationsApi(
      items: const <Map<String, dynamic>>[],
      listError: const ApiException(
        'Требуется авторизация',
        statusCode: 401,
      ),
    );
    final service = NotificationsService(
      api: api,
      pollInterval: const Duration(milliseconds: 1),
    );
    service.activateSession('user-1');

    final items = await service.streamPersonal('user-1').first;

    expect(items, isEmpty);
    expect(api.listCalls, 1);
    expect(service.streamPersonal('user-1').first, completion(isEmpty));
  });

  test('realtime message notification appears immediately in personal stream',
      () async {
    final api =
        _FakeInAppNotificationsApi(items: const <Map<String, dynamic>>[]);
    final service = NotificationsService(
      api: api,
      pollInterval: const Duration(seconds: 1),
    );
    service.activateSession('user-1');
    final stream = service.streamPersonal('user-1');

    await stream.first;
    service.ingestRealtimeNotification(
      userId: 'user-1',
      notification: <String, dynamic>{
        'id': 'notif-1',
        'type': 'chat_message',
        'title': 'Новое сообщение от Mansur',
        'body': 'Привет',
        'chatId': 'chat-1',
        'senderName': 'Mansur',
      },
    );

    final items = await stream.firstWhere((rows) => rows.isNotEmpty);

    expect(items.single['id'], 'notif-1');
    expect(items.single['chatId'], 'chat-1');
    expect(items.single['senderName'], 'Mansur');
  });

  test('realtime notification affects unread badge count immediately',
      () async {
    final api =
        _FakeInAppNotificationsApi(items: const <Map<String, dynamic>>[]);
    final service = NotificationsService(
      api: api,
      pollInterval: const Duration(seconds: 1),
    );
    service.activateSession('user-1');
    final stream = service.streamUnreadBadgeCount('user-1');

    await stream.first;
    service.ingestRealtimeNotification(
      userId: 'user-1',
      notification: <String, dynamic>{
        'id': 'notif-2',
        'type': 'chat_message',
        'title': 'Новое сообщение от Mansur',
        'chatId': 'chat-1',
      },
    );

    final count = await stream.firstWhere((value) => value > 0);
    expect(count, 1);
  });

  test('global and personal streams share the same fetch cycle', () async {
    final api = _FakeInAppNotificationsApi(
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'global-1',
          'scope': 'global',
          'title': 'Global',
          'created_at': '2026-06-18T10:00:00.000Z',
          'is_read': false,
        },
        <String, dynamic>{
          'id': 'personal-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Personal',
          'created_at': '2026-06-18T11:00:00.000Z',
          'is_read': false,
        },
      ],
    );
    final service = NotificationsService(api: api);
    service.activateSession('user-1');

    await service.preload('user-1');
    await Future.wait([
      service.streamGlobal().first,
      service.streamPersonal('user-1').first,
    ]);

    expect(api.listCalls, 1);
  });
}

class _FakeInAppNotificationsApi extends InAppNotificationsApi {
  _FakeInAppNotificationsApi({
    required this.items,
    this.listError,
  }) : super(ApiClient(tokenStorage: TokenStorage()));

  final List<Map<String, dynamic>> items;
  final Object? listError;
  int listCalls = 0;
  String? sentUserId;
  String? sentTitle;
  String? sentBody;
  int markAllReadCalls = 0;

  @override
  Future<Map<String, dynamic>> list() async {
    listCalls++;
    if (listError != null) {
      throw listError!;
    }
    return <String, dynamic>{
      'items': items,
    };
  }

  @override
  Future<Map<String, dynamic>> sendUser({
    required String userId,
    required String title,
    required String body,
    String type = 'update',
  }) async {
    sentUserId = userId;
    sentTitle = title;
    sentBody = body;
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> markAllRead() async {
    markAllReadCalls++;
    for (final item in items) {
      if (item['scope'] == 'personal') {
        item['is_read'] = true;
      }
    }
    return <String, dynamic>{'updated': markAllReadCalls};
  }
}
