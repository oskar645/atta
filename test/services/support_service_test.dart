import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/support_api.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/support_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
      'sendMessage keeps old support messages visible while request is in flight',
      () async {
    final api = _FakeSupportApi(
      initialMessages: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'msg-1',
          'ticket_id': 'ticket-1',
          'sender': 'admin',
          'text': 'Старое сообщение',
          'created_at': '2026-06-13T09:00:00.000Z',
        },
      ],
    );
    final service = SupportService(api: api);

    await service.refreshMessages('ticket-1');
    final states = <List<Map<String, dynamic>>>[];
    final sub = service.streamMessages('ticket-1').listen(states.add);

    final completer = Completer<void>();
    api.onSend = () => completer.future;

    final operation = service.sendMessage(
      ticketId: 'ticket-1',
      text: 'Новое сообщение',
    );

    await Future<void>.delayed(Duration.zero);

    expect(service.peekMessages('ticket-1').map((item) => item['text']),
        contains('Старое сообщение'));
    expect(service.peekMessages('ticket-1').map((item) => item['text']),
        contains('Новое сообщение'));

    completer.complete();
    await operation;
    await Future<void>.delayed(Duration.zero);

    expect(states.last.where((item) => item['text'] == 'Старое сообщение'),
        hasLength(1));
    expect(states.last.where((item) => item['text'] == 'Новое сообщение'),
        hasLength(1));

    await sub.cancel();
  });

  test('logged out state does not call SupportApi.adminList', () async {
    final api =
        _FakeSupportApi(initialMessages: const <Map<String, dynamic>>[]);
    final service = SupportService(api: api);

    final items = await service.streamTicketsForAdmin().first;

    expect(items, isEmpty);
    expect(api.adminListCalls, 0);
  });

  test('401 from adminList does not throw unhandled exception', () async {
    final api = _FakeSupportApi(initialMessages: const <Map<String, dynamic>>[])
      ..adminListError = const ApiException(
        'Требуется авторизация',
        statusCode: 401,
      );
    final service = SupportService(
      api: api,
      adminPollInterval: const Duration(milliseconds: 10),
    );
    await _seedAdminSession();
    service.activateAdminSession(isAdmin: true);

    final items = await service.refreshAdminTickets();

    expect(items, isEmpty);
    expect(api.adminListCalls, 1);
  });

  test('logout stops admin support refresh', () async {
    final api =
        _FakeSupportApi(initialMessages: const <Map<String, dynamic>>[]);
    final service = SupportService(api: api);
    await _seedAdminSession();
    service.activateAdminSession(isAdmin: true);

    final sub = service.streamTicketsForAdmin().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 25));
    final callsBeforeLogout = api.adminListCalls;

    service.resetSession();
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(api.adminListCalls, callsBeforeLogout);
    await sub.cancel();
  });

  test('send failure does not clear history and marks message as failed',
      () async {
    final api = _FakeSupportApi(
      initialMessages: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'msg-1',
          'ticket_id': 'ticket-1',
          'sender': 'admin',
          'text': 'Старое сообщение',
          'created_at': '2026-06-13T09:00:00.000Z',
        },
      ],
    )..sendError = const ApiException(
        'offline',
        code: 'network',
      );
    final service = SupportService(api: api);

    await service.refreshMessages('ticket-1');
    await expectLater(
      () => service.sendMessage(ticketId: 'ticket-1', text: 'Новое сообщение'),
      throwsA(isA<ApiException>()),
    );

    final items = service.peekMessages('ticket-1');
    expect(items.map((item) => item['text']), contains('Старое сообщение'));
    expect(
      items.where((item) => item['local_status'] == 'failed').length,
      1,
    );
  });

  test('404 ticket stops support polling spam', () async {
    final api = _FakeSupportApi(initialMessages: const <Map<String, dynamic>>[])
      ..missingTicketIds.add('missing-ticket');
    final service = SupportService(
      api: api,
      messagePollInterval: const Duration(milliseconds: 10),
    );

    await service.refreshMessages('missing-ticket');
    final callsAfterFirstAttempt = api.ticketCalls['missing-ticket'] ?? 0;

    final sub = service.streamMessages('missing-ticket').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 35));

    expect(callsAfterFirstAttempt, 1);
    expect(api.ticketCalls['missing-ticket'], 1);
    await sub.cancel();
  });

  test('support ticket polling runs only while screen stream is subscribed',
      () async {
    final api =
        _FakeSupportApi(initialMessages: const <Map<String, dynamic>>[]);
    final service = SupportService(
      api: api,
      messagePollInterval: const Duration(milliseconds: 10),
    );

    final sub = service.streamMessages('ticket-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 35));
    final callsWhileOpen = api.ticketCalls['ticket-1'] ?? 0;

    expect(callsWhileOpen, greaterThanOrEqualTo(2));
    expect(service.activeMessagePollerCount, 1);

    await sub.cancel();
    final callsAfterDispose = api.ticketCalls['ticket-1'] ?? 0;
    await Future<void>.delayed(const Duration(milliseconds: 35));

    expect(service.activeMessagePollerCount, 0);
    expect(api.ticketCalls['ticket-1'], callsAfterDispose);
  });

  test('reopening support screen does not create two pollers for same ticket',
      () async {
    final api =
        _FakeSupportApi(initialMessages: const <Map<String, dynamic>>[]);
    final service = SupportService(
      api: api,
      messagePollInterval: const Duration(milliseconds: 10),
    );

    final subOne = service.streamMessages('ticket-1').listen((_) {});
    final subTwo = service.streamMessages('ticket-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 15));

    expect(service.activeMessagePollerCount, 1);

    await subOne.cancel();
    expect(service.activeMessagePollerCount, 1);

    await subTwo.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(service.activeMessagePollerCount, 0);
  });

  test('admin ticket stream uses admin endpoint', () async {
    final api = _FakeSupportApi(
      initialMessages: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'admin-msg-1',
          'ticket_id': 'ticket-admin',
          'sender': 'user',
          'text': 'Нужно помочь',
          'created_at': '2026-06-13T09:00:00.000Z',
        },
      ],
    );
    final service = SupportService(api: api);

    final items = await service.streamAdminMessages('ticket-admin').first;

    expect(items, isNotEmpty);
    expect(api.adminTicketCalls, contains('ticket-admin'));
    expect(api.ticketCalls['ticket-admin'] ?? 0, 0);
  });

  test('reopening admin ticket keeps history and refreshes again', () async {
    final api = _FakeSupportApi(
      initialMessages: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'admin-msg-1',
          'ticket_id': 'ticket-1',
          'sender': 'user',
          'text': 'История обращения',
          'created_at': '2026-06-13T09:00:00.000Z',
        },
      ],
    );
    final service = SupportService(api: api);

    final firstStates = <List<Map<String, dynamic>>>[];
    final firstSub = service.streamAdminMessages('ticket-1').listen(
          firstStates.add,
        );
    await Future<void>.delayed(Duration.zero);
    await firstSub.cancel();

    expect(firstStates.last.map((item) => item['text']),
        contains('История обращения'));

    final secondStates = <List<Map<String, dynamic>>>[];
    final secondSub = service.streamAdminMessages('ticket-1').listen(
          secondStates.add,
        );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(secondStates.first.map((item) => item['text']),
        contains('История обращения'));
    expect(api.adminTicketCalls.where((id) => id == 'ticket-1'), hasLength(2));

    await secondSub.cancel();
  });

  test('empty admin refresh does not replace existing messages', () async {
    final api = _FakeSupportApi(
      initialMessages: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'admin-msg-1',
          'ticket_id': 'ticket-1',
          'sender': 'user',
          'text': 'Не исчезает',
          'created_at': '2026-06-13T09:00:00.000Z',
        },
      ],
    );
    final service = SupportService(api: api);

    await service.refreshAdminMessages('ticket-1');
    api._messages.clear();
    await service.refreshAdminMessages('ticket-1');

    expect(service.peekMessages('ticket-1').map((item) => item['text']),
        contains('Не исчезает'));
  });

  test('different admin support ids keep separate histories', () async {
    final api = _FakeSupportApi(
      initialMessages: const <Map<String, dynamic>>[],
      messagesByTicket: <String, List<Map<String, dynamic>>>{
        'ticket-1': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'msg-1',
            'ticket_id': 'ticket-1',
            'sender': 'user',
            'text': 'Первое обращение',
            'created_at': '2026-06-13T09:00:00.000Z',
          },
        ],
        'ticket-2': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'msg-2',
            'ticket_id': 'ticket-2',
            'sender': 'user',
            'text': 'Второе обращение',
            'created_at': '2026-06-13T09:01:00.000Z',
          },
        ],
      },
    );
    final service = SupportService(api: api);

    await service.refreshAdminMessages('ticket-1');
    await service.refreshAdminMessages('ticket-2');

    expect(service.peekMessages('ticket-1').map((item) => item['text']),
        contains('Первое обращение'));
    expect(service.peekMessages('ticket-1').map((item) => item['text']),
        isNot(contains('Второе обращение')));
    expect(service.peekMessages('ticket-2').map((item) => item['text']),
        contains('Второе обращение'));
  });

  test('admin reply remains visible after reopening ticket stream', () async {
    final api =
        _FakeSupportApi(initialMessages: const <Map<String, dynamic>>[]);
    final service = SupportService(api: api);

    await service.adminReply(ticketId: 'ticket-1', text: 'Ответ сохранён');

    final states = <List<Map<String, dynamic>>>[];
    final sub = service.streamAdminMessages('ticket-1').listen(states.add);
    await Future<void>.delayed(Duration.zero);

    expect(
        states.first.map((item) => item['text']), contains('Ответ сохранён'));

    await sub.cancel();
  });

  test('stale empty admin refresh does not overwrite newer reply', () async {
    final api =
        _FakeSupportApi(initialMessages: const <Map<String, dynamic>>[]);
    final service = SupportService(api: api);
    final staleRefresh = Completer<void>();
    api.onAdminTicket = () => staleRefresh.future;

    final sub = service.streamAdminMessages('ticket-1').listen((_) {});
    await Future<void>.delayed(Duration.zero);

    await service.adminReply(ticketId: 'ticket-1', text: 'Свежий ответ');
    staleRefresh.complete();
    await Future<void>.delayed(Duration.zero);

    expect(service.peekMessages('ticket-1').map((item) => item['text']),
        contains('Свежий ответ'));

    await sub.cancel();
  });

  test('hideAdminTicket removes ticket and keeps it hidden until new update',
      () async {
    final api = _FakeSupportApi(initialMessages: const <Map<String, dynamic>>[])
      ..adminTickets = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'ticket-1',
          'name': 'Пользователь',
          'last_message': 'Старое обращение',
          'updated_at': '2026-07-02T10:00:00.000Z',
        },
      ];
    final service = SupportService(api: api);
    await _seedAdminSession();
    service.activateAdminSession(isAdmin: true);

    final initial = await service.refreshAdminTickets(force: true);
    expect(initial, hasLength(1));

    await service.hideAdminTicket(
      ticketId: 'ticket-1',
      updatedAt: '2026-07-02T10:00:00.000Z',
    );
    expect(await service.streamTicketsForAdmin().first, isEmpty);

    api.adminTickets = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'ticket-1',
        'name': 'Пользователь',
        'last_message': 'Старое обращение',
        'updated_at': '2026-07-02T10:00:00.000Z',
      },
    ];
    expect(await service.refreshAdminTickets(force: true), isEmpty);

    api.adminTickets = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'ticket-1',
        'name': 'Пользователь',
        'last_message': 'Новое сообщение',
        'updated_at': '2026-07-02T10:05:00.000Z',
      },
    ];
    final restored = await service.refreshAdminTickets(force: true);
    expect(restored, hasLength(1));
    expect(restored.single['last_message'], 'Новое сообщение');
  });

  test('sendMessage with image keeps old messages and stores image url',
      () async {
    final api = _FakeSupportApi(
      initialMessages: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'msg-1',
          'ticket_id': 'ticket-1',
          'sender': 'admin',
          'text': 'Старое сообщение',
          'created_at': '2026-06-13T09:00:00.000Z',
        },
      ],
    );
    final service = SupportService(api: api);
    final tempDir = await Directory.systemTemp.createTemp('support_test_');
    final imageFile = File('${tempDir.path}/photo.jpg')
      ..writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9]);

    await service.refreshMessages('ticket-1');
    await service.sendMessage(
      ticketId: 'ticket-1',
      text: 'Фото',
      imageFile: imageFile,
    );

    final items = service.peekMessages('ticket-1');
    expect(items.map((item) => item['text']), contains('Старое сообщение'));
    expect(
      items.any((item) =>
          (item['text'] ?? '').toString() == 'Фото' &&
          (item['image_url'] ?? '').toString().isNotEmpty),
      isTrue,
    );
    expect(api.uploadTicketIds, equals(<String?>['ticket-1']));
  });

  test('retryMessage reuses failed message and does not duplicate it',
      () async {
    final api = _FakeSupportApi(
      initialMessages: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'msg-1',
          'ticket_id': 'ticket-1',
          'sender': 'admin',
          'text': 'Старое сообщение',
          'created_at': '2026-06-13T09:00:00.000Z',
        },
      ],
    )..sendError = const ApiException(
        'offline',
        code: 'network',
      );
    final service = SupportService(api: api);

    await service.refreshMessages('ticket-1');
    await expectLater(
      () => service.sendMessage(ticketId: 'ticket-1', text: 'Фото'),
      throwsA(isA<ApiException>()),
    );

    final failedItems = service.peekMessages('ticket-1');
    final failed = failedItems.firstWhere(
      (item) => (item['local_status'] ?? '').toString() == 'failed',
    );

    api.sendError = null;
    await service.retryMessage(
      ticketId: 'ticket-1',
      messageId: (failed['id'] ?? '').toString(),
    );

    final retried = service.peekMessages('ticket-1');
    expect(
      retried.where((item) => (item['text'] ?? '').toString() == 'Фото'),
      hasLength(1),
    );
    expect(
      retried
          .any((item) => (item['local_status'] ?? '').toString() == 'failed'),
      isFalse,
    );
  });

  test('refreshMessages normalizes legacy text fields for support UI',
      () async {
    final api = _FakeSupportApi(
      initialMessages: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'msg-legacy',
          'ticket_id': 'ticket-1',
          'sender': 'admin',
          'body': 'Текст из body',
          'createdAt': '2026-06-13T09:00:00.000Z',
        },
      ],
    );
    final service = SupportService(api: api);

    final items = await service.refreshMessages('ticket-1');

    expect(items.single['text'], 'Текст из body');
    expect(items.single['body'], 'Текст из body');
    expect(items.single['created_at'], '2026-06-13T09:00:00.000Z');
  });

  test('admin reply plus refresh does not create duplicate sender message',
      () async {
    final api =
        _FakeSupportApi(initialMessages: const <Map<String, dynamic>>[]);
    final service = SupportService(api: api);
    final completer = Completer<void>();
    api.onAdminSend = () => completer.future;

    final reply = service.adminReply(
      ticketId: 'ticket-1',
      text: 'Ответ админа',
    );
    await Future<void>.delayed(Duration.zero);

    api._messages.insert(0, <String, dynamic>{
      'id': 'admin-msg-server',
      'ticket_id': 'ticket-1',
      'sender': 'admin',
      'text': 'Ответ админа',
      'created_at': '2026-06-13T10:00:00.000Z',
    });
    await service.refreshAdminMessages('ticket-1');
    completer.complete();
    await reply;

    final items = service.peekMessages('ticket-1');
    expect(
      items.where((item) => (item['text'] ?? '').toString() == 'Ответ админа'),
      hasLength(1),
    );
  });
}

Future<void> _seedAdminSession() async {
  final storage = TokenStorage();
  await storage.saveSession(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    currentUser: const AuthUser(uid: 'admin-1', isAdmin: true),
  );
}

class _FakeSupportApi extends SupportApi {
  _FakeSupportApi({
    required List<Map<String, dynamic>> initialMessages,
    Map<String, List<Map<String, dynamic>>>? messagesByTicket,
  })  : _messages = List<Map<String, dynamic>>.from(initialMessages),
        _messagesByTicket = messagesByTicket?.map(
              (key, value) => MapEntry(
                key,
                List<Map<String, dynamic>>.from(value),
              ),
            ) ??
            <String, List<Map<String, dynamic>>>{},
        super(
          ApiClient(
            tokenStorage: TokenStorage(),
          ),
        );

  final List<Map<String, dynamic>> _messages;
  final Map<String, List<Map<String, dynamic>>> _messagesByTicket;
  Future<void> Function()? onSend;
  Object? adminListError;
  Object? sendError;
  int adminListCalls = 0;
  List<Map<String, dynamic>> adminTickets = const <Map<String, dynamic>>[];
  final List<String?> uploadTicketIds = <String?>[];
  final Set<String> missingTicketIds = <String>{};
  final Map<String, int> ticketCalls = <String, int>{};
  final List<String> adminTicketCalls = <String>[];
  Future<void> Function()? onAdminSend;
  Future<void> Function()? onAdminTicket;

  @override
  Future<Map<String, dynamic>> getTicket(String ticketId) async {
    ticketCalls[ticketId] = (ticketCalls[ticketId] ?? 0) + 1;
    if (missingTicketIds.contains(ticketId)) {
      throw const ApiException(
        'Тикет не найден',
        statusCode: 404,
      );
    }
    return <String, dynamic>{
      'items': _messagesFor(ticketId),
    };
  }

  @override
  Future<Map<String, dynamic>> sendMessage({
    required String ticketId,
    String text = '',
    String? imageUrl,
  }) async {
    await onSend?.call();
    if (sendError != null) {
      throw sendError!;
    }
    final item = <String, dynamic>{
      'id': 'msg-${_messages.length + 1}',
      'ticket_id': ticketId,
      'sender': 'user',
      'text': text,
      if ((imageUrl ?? '').trim().isNotEmpty) 'image_url': imageUrl,
      'created_at': '2026-06-13T10:00:00.000Z',
    };
    _messages.insert(0, item);
    _messagesByTicket[ticketId]?.insert(0, item);
    return <String, dynamic>{
      'item': item,
    };
  }

  @override
  Future<Map<String, dynamic>> uploadImage({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    String? ticketId,
  }) async {
    uploadTicketIds.add(ticketId);
    return <String, dynamic>{
      'url': 'https://example.com/$fileName',
    };
  }

  @override
  Future<Map<String, dynamic>> adminList() async {
    adminListCalls += 1;
    if (adminListError != null) {
      throw adminListError!;
    }
    return <String, dynamic>{
      'items': adminTickets,
    };
  }

  @override
  Future<Map<String, dynamic>> adminTicket(String ticketId) async {
    await onAdminTicket?.call();
    adminTicketCalls.add(ticketId);
    return <String, dynamic>{
      'items': _messagesFor(ticketId),
    };
  }

  @override
  Future<Map<String, dynamic>> adminSendMessage({
    required String ticketId,
    String text = '',
    String? imageUrl,
  }) async {
    await onAdminSend?.call();
    final item = <String, dynamic>{
      'id': 'admin-msg-${_messages.length + 1}',
      'ticket_id': ticketId,
      'sender': 'admin',
      'text': text,
      if ((imageUrl ?? '').trim().isNotEmpty) 'image_url': imageUrl,
      'created_at': '2026-06-13T10:00:00.000Z',
    };
    _messages.insert(0, item);
    _messagesByTicket[ticketId]?.insert(0, item);
    return <String, dynamic>{
      'item': item,
    };
  }

  List<Map<String, dynamic>> _messagesFor(String ticketId) {
    return _messagesByTicket[ticketId] ?? _messages;
  }
}
