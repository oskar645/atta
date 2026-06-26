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
  })  : _messages = List<Map<String, dynamic>>.from(initialMessages),
        super(
          ApiClient(
            tokenStorage: TokenStorage(),
          ),
        );

  final List<Map<String, dynamic>> _messages;
  Future<void> Function()? onSend;
  Object? adminListError;
  Object? sendError;
  int adminListCalls = 0;
  final List<String?> uploadTicketIds = <String?>[];
  final Set<String> missingTicketIds = <String>{};
  final Map<String, int> ticketCalls = <String, int>{};
  final List<String> adminTicketCalls = <String>[];

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
      'items': _messages,
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
    return const <String, dynamic>{
      'items': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> adminTicket(String ticketId) async {
    adminTicketCalls.add(ticketId);
    return <String, dynamic>{
      'items': _messages,
    };
  }
}
