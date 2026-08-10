import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/in_app_notifications_api.dart';
import 'package:atta/src/services/api/media_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/image_preparation_service.dart';
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

  test('unread count streams support multiple listeners', () async {
    final api = _FakeInAppNotificationsApi(
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'global-1',
          'scope': 'global',
          'title': 'Global',
          'created_at': '2026-06-18T13:00:00.000Z',
          'is_read': false,
        },
        <String, dynamic>{
          'id': 'personal-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Personal',
          'created_at': '2026-06-18T13:05:00.000Z',
          'is_read': false,
        },
      ],
      globalSeenAt: '2026-06-18T12:00:00.000Z',
    );
    final service = NotificationsService(api: api);
    service.activateSession('user-1');

    final badgeStream = service.streamUnreadBadgeCount('user-1');
    final globalStream = service.streamUnreadGlobalCount('user-1');
    final personalStream = service.streamUnreadPersonalCount('user-1');

    final results = await Future.wait([
      badgeStream.first,
      badgeStream.first,
      globalStream.first,
      globalStream.first,
      personalStream.first,
      personalStream.first,
    ]);

    expect(results[0], 2);
    expect(results[1], 2);
    expect(results[2], 1);
    expect(results[3], 1);
    expect(results[4], 1);
    expect(results[5], 1);
  });

  test('personal unread count is available after personal list stream exists',
      () async {
    final api = _FakeInAppNotificationsApi(
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'personal-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Personal',
          'created_at': '2026-06-18T13:05:00.000Z',
          'is_read': false,
        },
      ],
    );
    final service = NotificationsService(api: api);
    service.activateSession('user-1');

    expect(await service.streamPersonal('user-1').first, hasLength(1));

    final count = await service.streamUnreadPersonalCount('user-1').first;

    expect(count, 1);
    expect(api.listCalls, 1);
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

  test('sendGlobal forwards optional payload for broadcast notification',
      () async {
    final api =
        _FakeInAppNotificationsApi(items: const <Map<String, dynamic>>[]);
    final service = NotificationsService(api: api);

    await service.sendGlobal(
      title: 'Новость',
      body: 'Текст',
      payload: const <String, dynamic>{
        'description': 'Подробности',
        'imageUrl': 'https://example.com/notification.jpg',
        'actionUrl': 'https://t.me/atta_app',
      },
    );

    expect(api.sentAllTitle, 'Новость');
    expect(api.sentAllBody, 'Текст');
    expect(api.sentAllPayload?['description'], 'Подробности');
    expect(api.sentAllPayload?['actionUrl'], 'https://t.me/atta_app');
  });

  test('uploadNotificationImage returns russian notification-specific error',
      () async {
    final service = NotificationsService(
      api: _FakeInAppNotificationsApi(items: const <Map<String, dynamic>>[]),
      mediaApi: _FakeNotificationMediaApi(
        uploadError: const ApiException('Not found', statusCode: 404),
      ),
      imagePreparationService: _FakeNotificationImagePreparationService(),
    );

    expect(
      () => service.uploadNotificationImage(File('notification.jpg')),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Не удалось загрузить фото для уведомления. Попробуйте позже.',
        ),
      ),
    );
  });

  test('uploadNotificationImage prepares notification photo before upload',
      () async {
    final imagePreparationService = _FakeNotificationImagePreparationService();
    final mediaApi = _FakeNotificationMediaApi();
    final service = NotificationsService(
      api: _FakeInAppNotificationsApi(items: const <Map<String, dynamic>>[]),
      mediaApi: mediaApi,
      imagePreparationService: imagePreparationService,
    );

    final result = await service.uploadNotificationImage(
      File('notification.jpg'),
    );

    expect(imagePreparationService.prepareNotificationCalls, 1);
    expect(mediaApi.lastUploadedContentType, 'image/jpeg');
    expect(result, 'https://example.com/notification.jpg');
  });

  test('sendPersonal forwards optional payload for personal notification',
      () async {
    final api =
        _FakeInAppNotificationsApi(items: const <Map<String, dynamic>>[]);
    final service = NotificationsService(api: api);

    await service.sendPersonal(
      userId: 'user-1',
      title: 'Hello',
      body: 'World',
      payload: const <String, dynamic>{
        'description': 'Подробности',
      },
    );

    expect(api.sentPayload?['description'], 'Подробности');
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

    expect(api.markAllSeenCalls, 1);
    expect(await service.streamUnreadPersonalCount('user-1').first, 0);
    expect(await service.streamUnreadGlobalCount('user-1').first, 0);
  });

  test('markAllSeen keeps unread count until delayed retry succeeds', () async {
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
    final service = NotificationsService(api: api);
    service.activateSession('user-1');
    final emittedCounts = <int>[];
    final sub = service.streamUnreadPersonalCount('user-1').listen(
          emittedCounts.add,
        );

    await service.preload('user-1');
    await Future<void>.delayed(Duration.zero);
    expect(emittedCounts.last, 1);

    api.markAllSeenCompleter = Completer<void>();
    final markSeen = service.markAllSeen('user-1');
    await Future<void>.delayed(Duration.zero);

    expect(emittedCounts.last, 1);

    api.markAllSeenCompleter!.complete();
    await markSeen;
    await Future<void>.delayed(Duration.zero);

    expect(emittedCounts.last, 0);
    await sub.cancel();
  });

  test('personal unread count stays positive while unread personal remains',
      () async {
    final api = _FakeInAppNotificationsApi(
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'personal-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Личное 1',
          'created_at': '2026-06-18T11:00:00.000Z',
          'is_read': false,
        },
        <String, dynamic>{
          'id': 'personal-2',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Личное 2',
          'created_at': '2026-06-18T12:00:00.000Z',
          'is_read': false,
        },
      ],
    );
    final service = NotificationsService(api: api);
    service.activateSession('user-1');
    final emittedCounts = <int>[];
    final sub = service.streamUnreadPersonalCount('user-1').listen(
          emittedCounts.add,
        );

    await service.preload('user-1');
    await Future<void>.delayed(Duration.zero);
    expect(emittedCounts.last, 2);

    await service.markPersonalReadById('personal-1');
    await Future<void>.delayed(Duration.zero);

    expect(emittedCounts.last, 1);
    await sub.cancel();
  });

  test('mark read clears one personal unread immediately from cached list',
      () async {
    final api = _FakeInAppNotificationsApi(
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'personal-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Личное 1',
          'created_at': '2026-06-18T11:00:00.000Z',
          'is_read': false,
        },
        <String, dynamic>{
          'id': 'personal-2',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Личное 2',
          'created_at': '2026-06-18T12:00:00.000Z',
          'is_read': false,
        },
      ],
    );
    final service = NotificationsService(api: api);
    service.activateSession('user-1');
    final emittedCounts = <int>[];
    final sub = service.streamUnreadPersonalCount('user-1').listen(
          emittedCounts.add,
        );

    await service.preload('user-1');
    await Future<void>.delayed(Duration.zero);
    expect(emittedCounts.last, 2);

    await service.markPersonalReadById('personal-1');
    await Future<void>.delayed(Duration.zero);

    expect(emittedCounts.last, 1);
    await sub.cancel();
  });

  test('global badge uses backend seen timestamp after relogin', () async {
    final api = _FakeInAppNotificationsApi(
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'global-1',
          'scope': 'global',
          'title': 'Global old',
          'created_at': '2026-06-18T10:00:00.000Z',
          'is_read': false,
        },
      ],
      globalSeenAt: '2026-06-18T12:00:00.000Z',
    );
    final service = NotificationsService(api: api);
    service.activateSession('user-1');

    await service.preload('user-1');

    expect(await service.streamUnreadBadgeCount('user-1').first, 0);
    expect(await service.streamUnreadGlobalCount('user-1').first, 0);
  });

  test('logout login does not mix unread state between accounts', () async {
    final api = _FakeInAppNotificationsApi(
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'user-1-personal',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'User 1',
          'created_at': '2026-06-18T11:00:00.000Z',
          'is_read': false,
        },
      ],
    );
    final service = NotificationsService(api: api);

    service.activateSession('user-1');
    await service.preload('user-1');
    expect(await service.streamUnreadBadgeCount('user-1').first, 1);

    service.resetSession();
    api.items
      ..clear()
      ..add(
        <String, dynamic>{
          'id': 'user-2-personal',
          'scope': 'personal',
          'user_id': 'user-2',
          'title': 'User 2',
          'created_at': '2026-06-18T12:00:00.000Z',
          'is_read': false,
        },
      );

    service.activateSession('user-2');
    await service.preload('user-2');

    expect(await service.streamUnreadBadgeCount('user-2').first, 1);
    expect(await service.streamPersonal('user-2').first, hasLength(1));
    expect(
      (await service.streamPersonal('user-2').first).single['id'],
      'user-2-personal',
    );
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
    );
    service.activateSession('user-1');

    final items = await service.streamPersonal('user-1').first;

    expect(items, isEmpty);
    expect(api.listCalls, 1);
    expect(service.streamPersonal('user-1').first, completion(isEmpty));
  });

  test('realtime chat notification is ignored by personal stream', () async {
    final api =
        _FakeInAppNotificationsApi(items: const <Map<String, dynamic>>[]);
    final service = NotificationsService(
      api: api,
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

    final items = await stream.first.timeout(
      const Duration(milliseconds: 50),
      onTimeout: () => const <Map<String, dynamic>>[],
    );

    expect(items, isEmpty);
  });

  test('realtime chat notification does not affect unread badge count',
      () async {
    final api =
        _FakeInAppNotificationsApi(items: const <Map<String, dynamic>>[]);
    final service = NotificationsService(
      api: api,
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

    final count = await stream.first.timeout(
      const Duration(milliseconds: 50),
      onTimeout: () => 0,
    );
    expect(count, 0);
  });

  test('chat notifications from backend list are filtered out', () async {
    final api = _FakeInAppNotificationsApi(
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'message-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'type': 'chat_message',
          'title': 'Новое сообщение',
          'created_at': '2026-06-18T11:00:00.000Z',
          'is_read': false,
        },
        <String, dynamic>{
          'id': 'system-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'type': 'support',
          'title': 'Поддержка',
          'created_at': '2026-06-18T12:00:00.000Z',
          'is_read': false,
        },
      ],
    );
    final service = NotificationsService(api: api);
    service.activateSession('user-1');

    final personal = await service.streamPersonal('user-1').first;
    final badge = await service.streamUnreadBadgeCount('user-1').first;

    expect(personal.map((item) => item['id']), ['system-1']);
    expect(badge, 1);
  });

  test('new global notification after seen-all lights bell badge again',
      () async {
    final api = _FakeInAppNotificationsApi(
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'global-old',
          'scope': 'global',
          'type': 'generic',
          'title': 'Старое',
          'created_at': '2026-06-18T10:00:00.000Z',
          'is_read': false,
        },
      ],
      globalSeenAt: '2026-06-18T12:00:00.000Z',
    );
    final service = NotificationsService(api: api);
    service.activateSession('user-1');

    await service.preload('user-1');
    expect(await service.streamUnreadBadgeCount('user-1').first, 0);

    service.ingestRealtimeNotification(
      userId: 'user-1',
      notification: <String, dynamic>{
        'id': 'global-new',
        'scope': 'global',
        'type': 'generic',
        'title': 'Новое общее',
        'created_at': '2026-06-18T12:45:00.000Z',
      },
    );

    expect(await service.streamUnreadBadgeCount('user-1').first, 1);
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

  test('activateSession does not start background notifications polling',
      () async {
    final api =
        _FakeInAppNotificationsApi(items: const <Map<String, dynamic>>[]);
    final service = NotificationsService(api: api);

    service.activateSession('user-1');
    service.activateSession('user-1');

    expect(service.hasActivePollingTimer, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(api.listCalls, 0);
  });

  test('resetSession keeps notifications polling disabled', () async {
    final api =
        _FakeInAppNotificationsApi(items: const <Map<String, dynamic>>[]);
    final service = NotificationsService(api: api);

    service.activateSession('user-1');
    expect(service.hasActivePollingTimer, isFalse);

    service.resetSession();
    final callsBeforeWait = api.listCalls;
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(service.hasActivePollingTimer, isFalse);
    expect(api.listCalls, callsBeforeWait);
  });

  test('forced refresh is throttled to avoid duplicate notifications GETs',
      () async {
    final api = _FakeInAppNotificationsApi(
      items: const <Map<String, dynamic>>[],
    );
    final service = NotificationsService(api: api);

    service.activateSession('user-1');
    await Future.wait([
      service.refreshActiveSession(force: true),
      service.refreshActiveSession(force: true),
    ]);

    expect(api.listCalls, 1);
  });

  test('second notifications refresh joins the in-flight request', () async {
    final api =
        _FakeInAppNotificationsApi(items: const <Map<String, dynamic>>[])
          ..listCompleter = Completer<void>();
    final service = NotificationsService(api: api);

    service.activateSession('user-1');
    final refreshOne = service.refreshActiveSession(force: true);
    final refreshTwo = service.refreshActiveSession(force: true);

    await Future<void>.delayed(Duration.zero);
    expect(api.listCalls, 1);

    api.listCompleter!.complete();
    await Future.wait([refreshOne, refreshTwo]);
    expect(api.listCalls, 1);
  });
}

class _FakeInAppNotificationsApi extends InAppNotificationsApi {
  _FakeInAppNotificationsApi({
    required this.items,
    this.listError,
    this.globalSeenAt,
  }) : super(ApiClient(tokenStorage: TokenStorage()));

  final List<Map<String, dynamic>> items;
  final Object? listError;
  String? globalSeenAt;
  Completer<void>? listCompleter;
  Completer<void>? markAllSeenCompleter;
  int listCalls = 0;
  String? sentUserId;
  String? sentTitle;
  String? sentBody;
  Map<String, dynamic>? sentPayload;
  String? sentAllTitle;
  String? sentAllBody;
  Map<String, dynamic>? sentAllPayload;
  int markAllReadCalls = 0;
  int markAllSeenCalls = 0;
  int markReadCalls = 0;

  @override
  Future<Map<String, dynamic>> list() async {
    listCalls++;
    if (listCompleter != null) {
      await listCompleter!.future;
      listCompleter = null;
    }
    if (listError != null) {
      throw listError!;
    }
    return <String, dynamic>{
      'items': items,
      'global_seen_at': globalSeenAt,
    };
  }

  @override
  Future<Map<String, dynamic>> sendUser({
    required String userId,
    String? title,
    String? body,
    String type = 'update',
    Map<String, dynamic>? payload,
  }) async {
    sentUserId = userId;
    sentTitle = title;
    sentBody = body;
    sentPayload = payload == null ? null : Map<String, dynamic>.from(payload);
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> sendAll({
    String? title,
    String? body,
    String type = 'update',
    Map<String, dynamic>? payload,
  }) async {
    sentAllTitle = title;
    sentAllBody = body;
    sentAllPayload =
        payload == null ? null : Map<String, dynamic>.from(payload);
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

  @override
  Future<Map<String, dynamic>> markAllSeen() async {
    markAllSeenCalls++;
    if (markAllSeenCompleter != null) {
      await markAllSeenCompleter!.future;
      markAllSeenCompleter = null;
    }
    globalSeenAt = DateTime.utc(2026, 6, 18, 12, 30).toIso8601String();
    for (final item in items) {
      if (item['scope'] == 'personal') {
        item['is_read'] = true;
      }
    }
    return <String, dynamic>{
      'updated_personal': markAllSeenCalls,
      'global_seen_at': globalSeenAt,
    };
  }

  @override
  Future<Map<String, dynamic>> markRead(String notificationId) async {
    markReadCalls++;
    for (final item in items) {
      if ((item['id'] ?? '').toString() == notificationId) {
        item['is_read'] = true;
      }
    }
    return <String, dynamic>{'id': notificationId};
  }
}

class _FakeNotificationMediaApi extends MediaApi {
  _FakeNotificationMediaApi({this.uploadError})
      : super(ApiClient(tokenStorage: TokenStorage()));

  final Object? uploadError;
  String? lastUploadedContentType;

  @override
  Future<Map<String, dynamic>> uploadNotificationImage({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    lastUploadedContentType = contentType;
    if (uploadError != null) {
      throw uploadError!;
    }
    return <String, dynamic>{'url': 'https://example.com/notification.jpg'};
  }
}

class _FakeNotificationImagePreparationService extends ImagePreparationService {
  int prepareNotificationCalls = 0;

  @override
  Future<PreparedImage> prepareNotificationImage(File file) async {
    prepareNotificationCalls += 1;
    return PreparedImage(
      bytes: Uint8List.fromList(const <int>[1, 2, 3]),
      fileName: 'notification.jpg',
      contentType: 'image/jpeg',
      originalBytes: 3,
      compressedBytes: 3,
    );
  }
}
