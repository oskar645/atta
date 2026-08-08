import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/models/message.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/chats_api.dart';
import 'package:atta/src/services/api/media_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('active chat marks incoming message as delivered and read', () async {
    final socket = _FakeChatSocketService();
    final service = ChatService(
      socketService: socket,
      api: _FakeChatsApi(),
      mediaApi: _FakeMediaApi(),
    );

    final sub = service.streamMessages('chat-1').listen((_) {});
    service.setForegroundChat('chat-1');
    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'chat': _chatMap(unreadCount: 1),
        'message': <String, dynamic>{
          'id': 'message-1',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'text': 'Привет',
          'createdAt': DateTime.now().toIso8601String(),
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(socket.deliveredIds, contains('message-1'));
    expect(socket.readIds, isEmpty);
    await sub.cancel();
  });

  test('inactive chat marks incoming message only as delivered', () async {
    final socket = _FakeChatSocketService();
    ChatService(
      socketService: socket,
      api: _FakeChatsApi(),
      mediaApi: _FakeMediaApi(),
    );

    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'chat': _chatMap(unreadCount: 1),
        'message': <String, dynamic>{
          'id': 'message-2',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'text': 'Привет снова',
          'createdAt': DateTime.now().toIso8601String(),
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(socket.deliveredIds, contains('message-2'));
    expect(socket.readIds, isNot(contains('message-2')));
  });

  test('active subscription without foreground chat does not mark read',
      () async {
    final socket = _FakeChatSocketService();
    final service = ChatService(
      socketService: socket,
      api: _FakeChatsApi(),
      mediaApi: _FakeMediaApi(),
    );

    final sub = service.streamMessages('chat-1').listen((_) {});
    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'chat': _chatMap(unreadCount: 1),
        'message': <String, dynamic>{
          'id': 'message-2b',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'text': 'Сообщение под скрытым экраном',
          'createdAt': DateTime.now().toIso8601String(),
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(socket.deliveredIds, contains('message-2b'));
    expect(socket.readIds, isNot(contains('message-2b')));
    await sub.cancel();
  });

  test('large chat image is compressed before upload', () async {
    final mediaApi = _FakeMediaApi();
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: _FakeChatsApi(),
      mediaApi: mediaApi,
    );
    final file = File('${Directory.systemTemp.path}/atta-chat-too-large.jpg');
    final bigImage = img.Image(width: 2800, height: 2200);
    img.fill(bigImage, color: img.ColorRgb8(220, 180, 140));
    await file.writeAsBytes(img.encodeJpg(bigImage, quality: 100));

    await service.sendImage(
      chatId: 'chat-1',
      senderId: 'user-1',
      file: file,
    );
    expect(mediaApi.uploadCalls, 1);
    expect(mediaApi.lastUploadBytes, lessThanOrEqualTo(2 * 1024 * 1024));
    await file.delete();
  });

  test('notification bridge refreshes missing chat by chatId', () async {
    final api = _FakeChatsApi();
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    service.ingestMessageNotification(
      currentUserId: 'user-1',
      notification: <String, dynamic>{
        'chatId': 'chat-42',
        'type': 'chat_message',
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(api.getChatCalls, contains('chat-42'));
  });

  test('unread.changed to zero clears unread total for active user', () async {
    final socket = _FakeChatSocketService();
    final service = ChatService(
      socketService: socket,
      api: _FakeChatsApi(),
      mediaApi: _FakeMediaApi(),
    );

    final stream = service.streamUnreadTotal('user-1');
    await stream.first;
    socket.emitEvent(
      'chat.updated',
      <String, dynamic>{
        'chat': _chatMap(unreadCount: 3),
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    socket.emitEvent(
      'unread.changed',
      <String, dynamic>{
        'chatId': 'chat-1',
        'unreadCount': 0,
      },
    );

    final unread = await stream.firstWhere((value) => value == 0);
    expect(unread, 0);
  });

  test('socket read update does not erase existing message text', () async {
    final socket = _FakeChatSocketService();
    final service = ChatService(
      socketService: socket,
      api: _FakeChatsApi(),
      mediaApi: _FakeMediaApi(),
    );

    final sub = service.streamMessages('chat-1').listen((_) {});
    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'chat': _chatMap(unreadCount: 1),
        'message': <String, dynamic>{
          'id': 'message-3',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'text': 'Важный текст',
          'createdAt': DateTime.now().toIso8601String(),
        },
      },
    );
    socket.emitEvent(
      'message.read',
      <String, dynamic>{
        'message': <String, dynamic>{
          'id': 'message-3',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'text': '',
          'readAt': DateTime.now().toIso8601String(),
          'createdAt': DateTime.now().toIso8601String(),
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final messages = await service.streamMessages('chat-1').first;
    expect(messages.single.text, 'Важный текст');
    expect(messages.single.status, 'read');
    await sub.cancel();
  });

  test('socket status update before message does not create placeholder',
      () async {
    final socket = _FakeChatSocketService();
    final service = ChatService(
      socketService: socket,
      api: _FakeChatsApi(),
      mediaApi: _FakeMediaApi(),
    );

    final states = <List<ChatMessage>>[];
    final sub = service.streamMessages('chat-1').listen(
          (items) => states.add(List<ChatMessage>.from(items)),
        );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    socket.emitEvent(
      'message.delivered',
      <String, dynamic>{
        'message': <String, dynamic>{
          'id': 'message-status-first',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'status': 'delivered',
          'deliveredAt': DateTime.now().toIso8601String(),
          'createdAt': DateTime.now().toIso8601String(),
        },
      },
    );
    socket.emitEvent(
      'message.read',
      <String, dynamic>{
        'message': <String, dynamic>{
          'id': 'message-status-first',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'status': 'read',
          'readAt': DateTime.now().toIso8601String(),
          'createdAt': DateTime.now().toIso8601String(),
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      states.expand((items) => items).where(
            (message) => message.id == 'message-status-first',
          ),
      isEmpty,
    );

    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'chat': _chatMap(),
        'message': <String, dynamic>{
          'id': 'message-status-first',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'text': 'Полное сообщение',
          'createdAt': DateTime.now().toIso8601String(),
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final messages = await service.streamMessages('chat-1').first;
    expect(messages.where((item) => item.id == 'message-status-first'),
        hasLength(1));
    expect(messages.single.text, 'Полное сообщение');
    await sub.cancel();
  });

  test('socket status placeholder is not emitted before REST message load',
      () async {
    final socket = _FakeChatSocketService();
    final api = _FakeChatsApi(
      listMessageItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'message-from-rest',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'text': 'Пришло из REST',
          'createdAt': DateTime.now().toIso8601String(),
        },
      ],
    );
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    socket.emitEvent(
      'message.read',
      <String, dynamic>{
        'message': <String, dynamic>{
          'id': 'message-from-rest',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'status': 'read',
          'readAt': DateTime.now().toIso8601String(),
          'createdAt': DateTime.now().toIso8601String(),
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final states = <List<ChatMessage>>[];
    final sub = service.streamMessages('chat-1').listen(
          (items) => states.add(List<ChatMessage>.from(items)),
        );
    final messages = await service.streamMessages('chat-1').firstWhere(
          (items) => items.isNotEmpty,
        );

    expect(states.first, isEmpty);
    expect(
        messages.where((item) => item.id == 'message-from-rest'), hasLength(1));
    expect(messages.single.text, 'Пришло из REST');
    await sub.cancel();
  });

  test('failed text message remains visible instead of disappearing', () async {
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: _FakeChatsApi(sendMessageError: const ApiException('Сбой сети')),
      mediaApi: _FakeMediaApi(),
    );

    await expectLater(
      () => service.sendMessage(
        chatId: 'chat-1',
        senderId: 'user-1',
        text: 'Не пропадай',
      ),
      throwsA(isA<ApiException>()),
    );

    final messages = await service.streamMessages('chat-1').first;
    expect(messages.single.text, 'Не пропадай');
    expect(messages.single.status, 'failed');
  });

  test('retry failed text message reuses local message without duplicate',
      () async {
    final api =
        _FakeChatsApi(sendMessageError: const ApiException('Сбой сети'));
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    await expectLater(
      () => service.sendMessage(
        chatId: 'chat-1',
        senderId: 'user-1',
        text: 'Повтори меня',
      ),
      throwsA(isA<ApiException>()),
    );
    final failed = (await service.streamMessages('chat-1').first).single;
    api.sendMessageError = null;

    await service.retryMessage(
      chatId: 'chat-1',
      senderId: 'user-1',
      message: failed,
    );

    final messages = await service.streamMessages('chat-1').first;
    expect(api.sendMessageCalls, 3);
    expect(messages.where((item) => item.text == 'Повтори меня'), hasLength(1));
    expect(messages.single.status, 'sent');
    expect(messages.single.clientMessageId, failed.clientMessageId);
  });

  test('repeated tap on failed message does not create duplicate', () async {
    final api =
        _FakeChatsApi(sendMessageError: const ApiException('Сбой сети'));
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    await expectLater(
      () => service.sendMessage(
        chatId: 'chat-1',
        senderId: 'user-1',
        text: 'Без дубля retry',
      ),
      throwsA(isA<ApiException>()),
    );
    final failed = (await service.streamMessages('chat-1').first).single;
    api.sendMessageError = null;

    await Future.wait([
      service.retryMessage(
        chatId: 'chat-1',
        senderId: 'user-1',
        message: failed,
      ),
      service.retryMessage(
        chatId: 'chat-1',
        senderId: 'user-1',
        message: failed,
      ),
    ]);

    final messages = await service.streamMessages('chat-1').first;
    expect(
      messages.where((item) => item.text == 'Без дубля retry'),
      hasLength(1),
    );
    expect(messages.single.status, 'sent');
    expect(messages.single.clientMessageId, failed.clientMessageId);
  });

  test('network recovery retries failed text message automatically', () async {
    final api = _FakeChatsApi(sendMessageError: const ApiException('Нет сети'));
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    await expectLater(
      () => service.sendMessage(
        chatId: 'chat-1',
        senderId: 'user-1',
        text: 'Уйду после сети',
      ),
      throwsA(isA<ApiException>()),
    );
    api.sendMessageError = null;

    await service.handleNetworkChanged('user-1');

    final messages = await service.streamMessages('chat-1').first;
    expect(
        messages.where((item) => item.text == 'Уйду после сети'), hasLength(1));
    expect(messages.single.status, 'sent');
  });

  test('markChatsDelivered ignores message refresh network failure', () async {
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: _FakeChatsApi(
        listMessagesError: const ApiException(
          'Проверьте интернет-соединение и попробуйте снова.',
        ),
      ),
      mediaApi: _FakeMediaApi(),
    );

    await expectLater(
      service.markChatsDelivered(
        chatIds: const ['chat-1'],
        uid: 'user-1',
      ),
      completes,
    );
  });

  test('same timestamp messages keep stable outgoing order', () async {
    final socket = _FakeChatSocketService();
    final service = ChatService(
      socketService: socket,
      api: _FakeChatsApi(),
      mediaApi: _FakeMediaApi(),
    );
    final createdAt = DateTime.now().toIso8601String();

    final sub = service.streamMessages('chat-1').listen((_) {});
    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'message': <String, dynamic>{
          'id': 'image-1',
          'chatId': 'chat-1',
          'senderId': 'user-1',
          'type': 'image',
          'imageUrl': 'https://cdn.example.com/1.jpg',
          'createdAt': createdAt,
        },
      },
    );
    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'message': <String, dynamic>{
          'id': 'text-1',
          'chatId': 'chat-1',
          'senderId': 'user-1',
          'text': 'RRR',
          'createdAt': createdAt,
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final messages = await service.streamMessages('chat-1').first;
    expect(messages.map((item) => item.id).toList(), ['text-1', 'image-1']);
    await sub.cancel();
  });

  test('resolveMessageImageUrl appends token for protected backend media',
      () async {
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(
        uid: 'user-1',
        email: 'user@example.com',
        displayName: 'User',
      ),
    );
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: _FakeChatsApi(),
      mediaApi: _FakeMediaApi(),
    );

    final resolved = await service.resolveMessageImageUrl(
      'https://attamarket.online/media/chats/file?key=chats%2Fchat-1%2Fphoto.jpg',
    );

    expect(
      resolved,
      'https://attamarket.online/media/chats/file?key=chats%2Fchat-1%2Fphoto.jpg&token=access-token',
    );
  });

  test('pending text message is merged with server message without duplicate',
      () async {
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: _FakeChatsApi(),
      mediaApi: _FakeMediaApi(),
    );

    final states = <List<ChatMessage>>[];
    final sub = service.streamMessages('chat-1').listen(states.add);

    await service.sendMessage(
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'Стабильное сообщение',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final messages = await service.streamMessages('chat-1').first;
    expect(messages, hasLength(1));
    expect(messages.single.text, 'Стабильное сообщение');
    expect(messages.single.clientMessageId, isNotNull);
    expect(
      states.where((items) => items.length > 1),
      isEmpty,
    );
    await sub.cancel();
  });

  test(
      'optimistic message plus REST plus socket echo stays one visible message',
      () async {
    final socket = _FakeChatSocketService();
    final api = _FakeChatsApi();
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final states = <List<ChatMessage>>[];
    final sub = service.streamMessages('chat-1').listen(
          (items) => states.add(List<ChatMessage>.from(items)),
        );

    await service.sendMessage(
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'Без дубля',
    );
    final sentClientMessageId = api.lastClientMessageId!;
    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'message': <String, dynamic>{
          'id': 'server-message-1',
          'chatId': 'chat-1',
          'senderId': 'user-1',
          'text': 'Без дубля',
          'clientMessageId': sentClientMessageId,
          'status': 'sent',
          'createdAt': DateTime.now().toIso8601String(),
        },
      },
    );
    socket.emitEvent(
      'message.sent',
      <String, dynamic>{
        'chat': _chatMap(),
        'message': <String, dynamic>{
          'id': 'server-message-1',
          'chatId': 'chat-1',
          'senderId': 'user-1',
          'text': 'Без дубля',
          'clientMessageId': sentClientMessageId,
          'status': 'sent',
          'createdAt': DateTime.now().toIso8601String(),
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final messages = await service.streamMessages('chat-1').first;
    expect(messages.where((item) => item.text == 'Без дубля'), hasLength(1));
    expect(states.where((items) => items.length > 1), isEmpty);
    await sub.cancel();
  });

  test('sendMessage prepares socket connection and chat join before REST send',
      () async {
    final socket = _FakeChatSocketService();
    final api = _FakeChatsApi();
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    await service.sendMessage(
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'Первый вход',
    );

    expect(socket.connectCalls, greaterThanOrEqualTo(1));
    expect(socket.joinedChats, contains('chat-1'));
    expect(api.sendMessageCalls, 1);
    final messages = await service.streamMessages('chat-1').first;
    expect(messages.single.status, 'sent');
  });

  test('Android socket connecting send waits and sends one message', () async {
    final socket = _FakeChatSocketService(connectCompleter: Completer<void>());
    final api = _FakeChatsApi();
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final send = service.sendMessage(
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'После connect',
    );
    await Future<void>.delayed(Duration.zero);

    expect(api.sendMessageCalls, 0);
    socket.completeConnect();
    await send;

    expect(api.sendMessageCalls, 1);
    final messages = await service.streamMessages('chat-1').first;
    expect(
        messages.where((item) => item.text == 'После connect'), hasLength(1));
    expect(messages.single.status, 'sent');
  });

  test('Android first REST send error retries safely with one message',
      () async {
    final api = _FakeChatsApi(
      sendMessageErrors: <Object>[const ApiException('Socket route warming')],
    );
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    await service.sendMessage(
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'Один tap',
    );

    final messages = await service.streamMessages('chat-1').first;
    expect(api.sendMessageCalls, 2);
    expect(messages.where((item) => item.text == 'Один tap'), hasLength(1));
    expect(messages.single.status, 'sent');
  });

  test('Android resume first send works without manual retry', () async {
    final socket = _FakeChatSocketService(reconnecting: true);
    final api = _FakeChatsApi();
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    await service.handleAppResumed('user-1');
    await service.sendMessage(
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'После resume',
    );

    expect(socket.forceReconnectCalls, greaterThanOrEqualTo(1));
    expect(api.sendMessageCalls, 1);
    final messages = await service.streamMessages('chat-1').first;
    expect(messages.where((item) => item.text == 'После resume'), hasLength(1));
    expect(messages.single.status, 'sent');
  });

  test('resume send waits for disconnected socket recovery and stays single',
      () async {
    final socket = _FakeChatSocketService(
      forceReconnectCompleter: Completer<void>(),
    );
    final api = _FakeChatsApi();
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final sub = service.streamMessages('chat-1').listen((_) {});
    service.setForegroundChat('chat-1');
    await Future<void>.delayed(Duration.zero);
    socket.connected = false;

    final resume = service.handleAppResumed('user-1');
    await Future<void>.delayed(Duration.zero);
    final send = service.sendMessage(
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'Первый tap после resume',
    );
    await Future<void>.delayed(Duration.zero);

    expect(api.sendMessageCalls, 0);
    socket.completeForceReconnect();
    await Future.wait(<Future<void>>[resume, send]);

    final sentClientMessageId = api.lastClientMessageId!;
    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'message': <String, dynamic>{
          'id': 'server-message-1',
          'chatId': 'chat-1',
          'senderId': 'user-1',
          'text': 'Первый tap после resume',
          'clientMessageId': sentClientMessageId,
          'status': 'sent',
          'createdAt': DateTime.now().toIso8601String(),
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final messages = await service.streamMessages('chat-1').first;
    expect(api.sendMessageCalls, 1);
    expect(messages.where((item) => item.text == 'Первый tap после resume'),
        hasLength(1));
    expect(messages.single.status, 'sent');
    await sub.cancel();
  });

  test('pending image message is merged with server message without duplicate',
      () async {
    final mediaApi = _FakeMediaApi();
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: _FakeChatsApi(),
      mediaApi: mediaApi,
    );
    final file = File('${Directory.systemTemp.path}/atta-chat-image.jpg');
    final image = img.Image(width: 400, height: 400);
    img.fill(image, color: img.ColorRgb8(100, 120, 140));
    await file.writeAsBytes(img.encodeJpg(image, quality: 90));

    final states = <List<ChatMessage>>[];
    final sub = service.streamMessages('chat-1').listen(states.add);
    await service.sendImage(
      chatId: 'chat-1',
      senderId: 'user-1',
      file: file,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final messages = await service.streamMessages('chat-1').first;
    expect(messages, hasLength(1));
    expect(messages.single.clientMessageId, isNotNull);
    expect(messages.single.hasImage, isTrue);
    expect(
      states.where((items) => items.length > 1),
      isEmpty,
    );
    await sub.cancel();
    await file.delete();
  });

  test('repeated text send while request is in flight creates one request',
      () async {
    final api = _FakeChatsApi(
      sendMessageDelay: const Duration(milliseconds: 40),
    );
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    await Future.wait([
      service.sendMessage(
        chatId: 'chat-1',
        senderId: 'user-1',
        text: 'Один раз',
      ),
      service.sendMessage(
        chatId: 'chat-1',
        senderId: 'user-1',
        text: 'Один раз',
      ),
      service.sendMessage(
        chatId: 'chat-1',
        senderId: 'user-1',
        text: 'Один раз',
      ),
    ]);

    expect(api.sendMessageCalls, 1);
    final messages = await service.streamMessages('chat-1').first;
    expect(messages.where((item) => item.text == 'Один раз'), hasLength(1));
  });

  test('sending text does not blink previous text messages', () async {
    final socket = _FakeChatSocketService();
    final service = ChatService(
      socketService: socket,
      api: _FakeChatsApi(),
      mediaApi: _FakeMediaApi(),
    );
    final states = <List<ChatMessage>>[];
    final sub = service.streamMessages('chat-1').listen(
          (items) => states.add(List<ChatMessage>.from(items)),
        );

    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'chat': _chatMap(),
        'message': <String, dynamic>{
          'id': 'old-text-1',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'text': 'Старый текст',
          'createdAt': '2026-06-25T10:00:00.000Z',
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await service.sendMessage(
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'Новое сообщение',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final meaningfulStates = states.where((items) => items.isNotEmpty).toList();
    expect(
      meaningfulStates.every(
        (items) => items.any((message) => message.id == 'old-text-1'),
      ),
      isTrue,
    );
    final firstExpandedIndex =
        meaningfulStates.indexWhere((items) => items.length >= 2);
    expect(
      firstExpandedIndex,
      greaterThanOrEqualTo(0),
    );
    expect(
      meaningfulStates
          .skip(firstExpandedIndex)
          .every((items) => items.length >= 2),
      isTrue,
    );
    await sub.cancel();
  });

  test('sending text does not blink previous image messages', () async {
    final socket = _FakeChatSocketService();
    final service = ChatService(
      socketService: socket,
      api: _FakeChatsApi(),
      mediaApi: _FakeMediaApi(),
    );
    final states = <List<ChatMessage>>[];
    final sub = service.streamMessages('chat-1').listen(
          (items) => states.add(List<ChatMessage>.from(items)),
        );

    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'chat': _chatMap(),
        'message': <String, dynamic>{
          'id': 'old-image-1',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'type': 'image',
          'imageUrl': 'https://cdn.example.com/old.jpg',
          'createdAt': '2026-06-25T10:00:00.000Z',
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await service.sendMessage(
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'Новое сообщение',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final meaningfulStates = states.where((items) => items.isNotEmpty).toList();
    expect(
      meaningfulStates.every(
        (items) => items.any((message) => message.id == 'old-image-1'),
      ),
      isTrue,
    );
    final firstExpandedIndex =
        meaningfulStates.indexWhere((items) => items.length >= 2);
    expect(
      firstExpandedIndex,
      greaterThanOrEqualTo(0),
    );
    expect(
      meaningfulStates
          .skip(firstExpandedIndex)
          .every((items) => items.length >= 2),
      isTrue,
    );
    await sub.cancel();
  });

  test('delivered read update does not blink old messages', () async {
    final socket = _FakeChatSocketService();
    final service = ChatService(
      socketService: socket,
      api: _FakeChatsApi(),
      mediaApi: _FakeMediaApi(),
    );
    final states = <List<ChatMessage>>[];
    final sub = service.streamMessages('chat-1').listen(
          (items) => states.add(List<ChatMessage>.from(items)),
        );

    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'chat': _chatMap(),
        'message': <String, dynamic>{
          'id': 'old-1',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'text': 'Первое',
          'createdAt': '2026-06-25T10:00:00.000Z',
        },
      },
    );
    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'chat': _chatMap(),
        'message': <String, dynamic>{
          'id': 'old-2',
          'chatId': 'chat-1',
          'senderId': 'user-1',
          'text': 'Второе',
          'createdAt': '2026-06-25T10:01:00.000Z',
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    socket.emitEvent(
      'message.read',
      <String, dynamic>{
        'message': <String, dynamic>{
          'id': 'old-2',
          'chatId': 'chat-1',
          'senderId': 'user-1',
          'status': 'read',
          'readAt': '2026-06-25T10:02:00.000Z',
          'createdAt': '2026-06-25T10:01:00.000Z',
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final meaningfulStates = states.where((items) => items.isNotEmpty).toList();
    expect(
      meaningfulStates.skip(2).every((items) => items.length == 2),
      isTrue,
    );
    expect(
      meaningfulStates.last
          .firstWhere((message) => message.id == 'old-2')
          .status,
      'read',
    );
    expect(
      meaningfulStates.last.any((message) => message.id == 'old-1'),
      isTrue,
    );
    await sub.cancel();
  });

  test('socket message.new does not recreate all previous bubbles', () async {
    final socket = _FakeChatSocketService();
    final service = ChatService(
      socketService: socket,
      api: _FakeChatsApi(),
      mediaApi: _FakeMediaApi(),
    );
    final states = <List<ChatMessage>>[];
    final sub = service.streamMessages('chat-1').listen(
          (items) => states.add(List<ChatMessage>.from(items)),
        );

    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'chat': _chatMap(),
        'message': <String, dynamic>{
          'id': 'old-1',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'text': 'Первое',
          'createdAt': '2026-06-25T10:00:00.000Z',
        },
      },
    );
    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'chat': _chatMap(),
        'message': <String, dynamic>{
          'id': 'old-2',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'text': 'Второе',
          'createdAt': '2026-06-25T10:01:00.000Z',
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'chat': _chatMap(),
        'message': <String, dynamic>{
          'id': 'new-3',
          'chatId': 'chat-1',
          'senderId': 'user-2',
          'text': 'Третье',
          'createdAt': '2026-06-25T10:02:00.000Z',
        },
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final meaningfulStates = states.where((items) => items.isNotEmpty).toList();
    expect(
      meaningfulStates.map((items) => items.length).toList(),
      containsAllInOrder(<int>[1, 2, 3]),
    );
    expect(
      meaningfulStates.last.map((message) => message.id),
      containsAll(<String>['old-1', 'old-2', 'new-3']),
    );
    expect(
      meaningfulStates.skip(2).every((items) => items.length >= 2),
      isTrue,
    );
    await sub.cancel();
  });

  test('socket chat update without message payload refreshes messages',
      () async {
    final socket = _FakeChatSocketService();
    final api = _FakeChatsApi();
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final sub = service.streamMessages('chat-1').listen((_) {});
    socket.emitEvent(
      'message.new',
      <String, dynamic>{
        'chat': _chatMap(id: 'chat-1', lastMessage: 'Догрузи меня'),
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(api.listMessagesCalls, contains('chat-1'));
    await sub.cancel();
  });

  test('chat.updated with newer preview refreshes active chat history',
      () async {
    final socket = _FakeChatSocketService();
    final api = _FakeChatsApi(
      listMessageItems: <Map<String, dynamic>>[
        _messageMap(
          id: 'preview-history-1',
          chatId: 'chat-preview',
          text: 'Preview уже показал',
        ),
      ],
    );
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final sub = service.streamMessages('chat-preview').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    api.listMessagesCalls.clear();

    socket.emitEvent(
      'chat.updated',
      <String, dynamic>{
        'chat': _chatMap(
          id: 'chat-preview',
          lastMessage: 'Preview уже показал',
          lastMessageAt: DateTime.utc(2026, 7, 2, 12).toIso8601String(),
        ),
      },
    );

    final messages = await service.streamMessages('chat-preview').firstWhere(
        (items) => items.any((item) => item.id == 'preview-history-1'));

    expect(api.listMessagesCalls, contains('chat-preview'));
    expect(messages.single.text, 'Preview уже показал');
    await sub.cancel();
  });

  test('chat list sorted by lastMessageAt desc, not updatedAt desc', () async {
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: _FakeChatsApi(
        chats: <Map<String, dynamic>>[
          _chatMap(
            id: 'old-chat',
            lastMessageAt: '2026-06-19T09:00:00.000Z',
            updatedAt: '2026-06-19T12:00:00.000Z',
          ),
          _chatMap(
            id: 'new-chat',
            lastMessageAt: '2026-06-19T11:00:00.000Z',
            updatedAt: '2026-06-19T11:00:00.000Z',
          ),
        ],
      ),
      mediaApi: _FakeMediaApi(),
    );

    final chats = await service.streamMyChats('user-1').firstWhere(
          (items) => items.length == 2,
        );

    expect(chats.map((item) => item.id).toList(), ['new-chat', 'old-chat']);
  });

  test('empty chats appear below chats with messages', () async {
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: _FakeChatsApi(
        chats: <Map<String, dynamic>>[
          _chatMap(
            id: 'empty-chat',
            lastMessage: '',
            lastMessageAt: null,
            createdAt: '2026-06-19T12:00:00.000Z',
            updatedAt: '2026-06-19T13:00:00.000Z',
          ),
          _chatMap(
            id: 'filled-chat',
            lastMessage: 'Привет',
            lastMessageAt: '2026-06-19T11:00:00.000Z',
            createdAt: '2026-06-19T10:00:00.000Z',
            updatedAt: '2026-06-19T11:00:00.000Z',
          ),
        ],
      ),
      mediaApi: _FakeMediaApi(),
    );

    final chats = await service.streamMyChats('user-1').firstWhere(
          (items) => items.length == 2,
        );

    expect(
        chats.map((item) => item.id).toList(), ['filled-chat', 'empty-chat']);
  });

  test('resume on home refreshes inbox without markRead', () async {
    final socket = _FakeChatSocketService();
    final api = _FakeChatsApi(
      chats: <Map<String, dynamic>>[
        _chatMap(unreadCount: 2),
      ],
    );
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    await service.handleAppResumed('user-1');

    expect(api.listChatsCalls, greaterThanOrEqualTo(1));
    expect(api.markChatReadCalls, isEmpty);
    expect(socket.forceReconnectCalls, 1);
  });

  test('resume inside active chat rejoins, refreshes and marks only that chat',
      () async {
    final socket = _FakeChatSocketService();
    final api = _FakeChatsApi(
      chats: <Map<String, dynamic>>[
        _chatMap(id: 'chat-a', unreadCount: 1),
      ],
    );
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final sub = service.streamMessages('chat-a').listen((_) {});
    service.setForegroundChat('chat-a');

    await service.handleAppResumed('user-1');

    expect(socket.joinedChats, contains('chat-a'));
    expect(api.listMessagesCalls.where((id) => id == 'chat-a').length, 2);
    expect(api.markChatReadCalls.where((id) => id != 'chat-a'), isEmpty);
    await sub.cancel();
  });

  test('repeated resume is throttled and does not duplicate refreshes',
      () async {
    final socket = _FakeChatSocketService();
    final api = _FakeChatsApi(
      chats: <Map<String, dynamic>>[
        _chatMap(id: 'chat-a', unreadCount: 1),
      ],
    );
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final sub = service.streamMessages('chat-a').listen((_) {});
    service.setForegroundChat('chat-a');

    await service.handleAppResumed('user-1');
    await service.handleAppResumed('user-1');
    await service.handleAppResumed('user-1');

    expect(api.listChatsCalls, 1);
    expect(api.listMessagesCalls.where((id) => id == 'chat-a').length, 2);
    expect(api.markChatReadCalls.where((id) => id != 'chat-a'), isEmpty);
    await sub.cancel();
  });

  test('Android sends while iPhone background then iPhone resume shows message',
      () async {
    final api = _FakeChatsApi(
      chats: <Map<String, dynamic>>[
        _chatMap(
          id: 'chat-cross-device',
          lastMessage: 'Android -> iPhone',
          unreadCount: 1,
        ),
      ],
      listMessageItems: <Map<String, dynamic>>[
        _messageMap(
          id: 'android-to-iphone-1',
          chatId: 'chat-cross-device',
          senderId: 'android-user',
          text: 'Android -> iPhone',
        ),
      ],
      unreadTotal: 1,
    );
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final sub = service.streamMessages('chat-cross-device').listen((_) {});
    await service.handleAppResumed('iphone-user');

    final messages = await service
        .streamMessages('chat-cross-device')
        .firstWhere(
            (items) => items.any((item) => item.id == 'android-to-iphone-1'));

    expect(api.listChatsCalls, greaterThanOrEqualTo(1));
    expect(api.listMessagesCalls, contains('chat-cross-device'));
    expect(messages.single.text, 'Android -> iPhone');
    await sub.cancel();
  });

  test(
      'iPhone sends while Android background then Android resume shows message',
      () async {
    final api = _FakeChatsApi(
      chats: <Map<String, dynamic>>[
        _chatMap(
          id: 'chat-cross-device',
          lastMessage: 'iPhone -> Android',
          unreadCount: 1,
        ),
      ],
      listMessageItems: <Map<String, dynamic>>[
        _messageMap(
          id: 'iphone-to-android-1',
          chatId: 'chat-cross-device',
          senderId: 'iphone-user',
          text: 'iPhone -> Android',
        ),
      ],
      unreadTotal: 1,
    );
    final socket = _FakeChatSocketService()..connected = true;
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final sub = service.streamMessages('chat-cross-device').listen((_) {});
    await service.handleAppResumed('android-user');

    final messages = await service
        .streamMessages('chat-cross-device')
        .firstWhere(
            (items) => items.any((item) => item.id == 'iphone-to-android-1'));

    expect(socket.forceReconnectCalls, 1);
    expect(messages.single.text, 'iPhone -> Android');
    await sub.cancel();
  });

  test('multiple offline messages keep unread count aligned with history',
      () async {
    final api = _FakeChatsApi(
      chats: <Map<String, dynamic>>[
        _chatMap(
          id: 'chat-offline',
          lastMessage: 'Третье offline',
          unreadCount: 3,
        ),
      ],
      listMessageItems: <Map<String, dynamic>>[
        _messageMap(
            id: 'offline-1', chatId: 'chat-offline', text: 'Первое offline'),
        _messageMap(
            id: 'offline-2', chatId: 'chat-offline', text: 'Второе offline'),
        _messageMap(
            id: 'offline-3', chatId: 'chat-offline', text: 'Третье offline'),
      ],
      unreadTotal: 3,
    );
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
      mediaApi: _FakeMediaApi(),
    );
    final unreadValues = <int>[];
    final unreadSub =
        service.streamUnreadTotal('user-1').listen(unreadValues.add);
    final messageSub = service.streamMessages('chat-offline').listen((_) {});

    await service.handleAppResumed('user-1');
    final messages = await service
        .streamMessages('chat-offline')
        .firstWhere((items) => items.length == 3);

    expect(unreadValues, contains(3));
    expect(messages, hasLength(3));
    await unreadSub.cancel();
    await messageSub.cancel();
  });

  test('cold start keeps unread preview and history consistent', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'atta.chat.cache.v1.user-1': jsonEncode(<String, dynamic>{
        'updatedAt': DateTime.utc(2026, 7, 1, 10).toIso8601String(),
        'chats': <Map<String, dynamic>>[
          _chatMap(
            id: 'chat-cold',
            lastMessage: 'Старый preview',
            unreadCount: 1,
          ),
        ],
        'messagesByChat': <String, dynamic>{
          'chat-cold': <Map<String, dynamic>>[
            _messageMap(id: 'old-cold', chatId: 'chat-cold', text: 'Старое'),
          ],
        },
      }),
    });
    final api = _FakeChatsApi(
      chats: <Map<String, dynamic>>[
        _chatMap(
          id: 'chat-cold',
          lastMessage: 'Новое после cold start',
          unreadCount: 2,
        ),
      ],
      listMessageItems: <Map<String, dynamic>>[
        _messageMap(id: 'cold-1', chatId: 'chat-cold', text: 'Первое новое'),
        _messageMap(
          id: 'cold-2',
          chatId: 'chat-cold',
          text: 'Новое после cold start',
        ),
      ],
      unreadTotal: 2,
    );
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final chats = await service.streamMyChats('user-1').firstWhere(
          (items) => items.any(
            (chat) =>
                chat.id == 'chat-cold' &&
                chat.lastMessage == 'Новое после cold start',
          ),
        );
    final messages = await service
        .streamMessages('chat-cold')
        .firstWhere((items) => items.any((item) => item.id == 'cold-2'));

    expect(chats.single.lastMessage, 'Новое после cold start');
    expect(chats.single.unreadFor('user-1'), 2);
    expect(
        messages.map((item) => item.text), contains(chats.single.lastMessage));
  });

  test('false connected socket is recreated before resume recovery', () async {
    final socket = _FakeChatSocketService()..connected = true;
    final api = _FakeChatsApi(
      chats: <Map<String, dynamic>>[
        _chatMap(id: 'chat-false-connected', lastMessage: 'После recovery'),
      ],
      listMessageItems: <Map<String, dynamic>>[
        _messageMap(
          id: 'false-connected-1',
          chatId: 'chat-false-connected',
          text: 'После recovery',
        ),
      ],
    );
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final sub = service.streamMessages('chat-false-connected').listen((_) {});
    await service.handleAppResumed('user-1');

    expect(socket.forceReconnectCalls, 1);
    expect(socket.joinedChats, contains('chat-false-connected'));
    expect(api.listMessagesCalls, contains('chat-false-connected'));
    await sub.cancel();
  });

  test('chat preview unread and message list do not diverge after recovery',
      () async {
    final api = _FakeChatsApi(
      chats: <Map<String, dynamic>>[
        _chatMap(
          id: 'chat-consistent',
          lastMessage: 'Финальное сообщение',
          unreadCount: 4,
        ),
      ],
      listMessageItems: <Map<String, dynamic>>[
        _messageMap(id: 'consistent-1', chatId: 'chat-consistent', text: '1'),
        _messageMap(id: 'consistent-2', chatId: 'chat-consistent', text: '2'),
        _messageMap(id: 'consistent-3', chatId: 'chat-consistent', text: '3'),
        _messageMap(
          id: 'consistent-4',
          chatId: 'chat-consistent',
          text: 'Финальное сообщение',
        ),
      ],
      unreadTotal: 4,
    );
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
      mediaApi: _FakeMediaApi(),
    );
    final unreadValues = <int>[];
    final unreadSub =
        service.streamUnreadTotal('user-1').listen(unreadValues.add);

    await service.handleAppResumed('user-1');
    final chats = await service.streamMyChats('user-1').firstWhere(
          (items) => items.any((chat) => chat.id == 'chat-consistent'),
        );
    final messages = await service
        .streamMessages('chat-consistent')
        .firstWhere((items) => items.length == 4);

    expect(unreadValues, contains(4));
    expect(chats.single.unreadFor('user-1'), 4);
    expect(
        messages.map((item) => item.text), contains(chats.single.lastMessage));
    await unreadSub.cancel();
  });

  test('opening chat multiple times does not spam ensureReady', () async {
    final socket = _FakeChatSocketService();
    final api = _FakeChatsApi(
      chats: <Map<String, dynamic>>[
        _chatMap(id: 'chat-a', unreadCount: 1),
      ],
    );
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final inboxSub = service.streamMyChats('user-1').listen((_) {});
    final firstChatSub = service.streamMessages('chat-a').listen((_) {});
    final secondChatSub = service.streamMessages('chat-a').listen((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(socket.connectCalls, 1);

    await inboxSub.cancel();
    await firstChatSub.cancel();
    await secondChatSub.cancel();
  });

  test('markChatsDelivered does not load messages for every inbox chat',
      () async {
    final socket = _FakeChatSocketService();
    final api = _FakeChatsApi(
      chats: <Map<String, dynamic>>[
        _chatMap(id: 'chat-a', unreadCount: 1),
        _chatMap(id: 'chat-b', unreadCount: 1),
      ],
    );
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    await service.refreshInbox('user-1');
    await service.markChatsDelivered(
      chatIds: const <String>['chat-a', 'chat-b'],
      uid: 'user-1',
    );

    expect(api.listMessagesCalls, isEmpty);
  });

  test('refreshInbox does not wait for socket connect before loading chats',
      () async {
    final socket = _FakeChatSocketService(hangConnect: true);
    final api = _FakeChatsApi(
      chats: <Map<String, dynamic>>[
        _chatMap(id: 'chat-a', unreadCount: 1),
      ],
    );
    final service = ChatService(
      socketService: socket,
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    await service.refreshInbox('user-1');

    expect(api.listChatsCalls, 1);
    expect(socket.connectCalls, 1);
  });

  test('refreshInbox timeout is swallowed and keeps cached chats', () async {
    final api = _FakeChatsApi(
      chats: <Map<String, dynamic>>[
        _chatMap(id: 'chat-cached', unreadCount: 2),
      ],
    );
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    await service.refreshInbox('user-1');
    api.listChatsError = TimeoutException('Future not completed');

    await service.refreshInbox('user-1');

    expect(service.lastChatsLoadError, isA<TimeoutException>());
    final chats = await service.streamMyChats('user-1').first;
    expect(chats.single.id, 'chat-cached');
  });

  test('chat cache restores last text conversation when network is unavailable',
      () async {
    final firstService = ChatService(
      socketService: _FakeChatSocketService(),
      api: _FakeChatsApi(
        chats: <Map<String, dynamic>>[
          _chatMap(id: 'chat-cached', lastMessage: 'Кэшированный текст'),
        ],
      ),
      mediaApi: _FakeMediaApi(),
    );

    await firstService.refreshInbox('user-1');
    await firstService.sendMessage(
      chatId: 'chat-cached',
      senderId: 'user-1',
      text: 'Останусь офлайн',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final secondService = ChatService(
      socketService: _FakeChatSocketService(),
      api: _FakeChatsApi(
        listMessagesError: const ApiException('Нет сети'),
      )..listChatsError = const ApiException('Нет сети'),
      mediaApi: _FakeMediaApi(),
    );

    final chats = await secondService.streamMyChats('user-1').firstWhere(
          (items) => items.isNotEmpty,
        );
    final messages =
        await secondService.streamMessages('chat-cached').firstWhere(
              (items) => items.isNotEmpty,
            );

    expect(chats.single.id, 'chat-cached');
    expect(messages.single.text, 'Останусь офлайн');
    expect(messages.single.hasImage, isFalse);
  });

  test('old cached message list does not block REST refresh on chat open',
      () async {
    final cachedAt = DateTime.utc(2026, 7, 1, 10).toIso8601String();
    final freshAt = DateTime.utc(2026, 7, 1, 11).toIso8601String();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'atta.chat.cache.v1.user-1': jsonEncode(<String, dynamic>{
        'updatedAt': cachedAt,
        'chats': <Map<String, dynamic>>[
          _chatMap(
            id: 'chat-cross-platform',
            lastMessage: 'Новое с другого телефона',
            lastMessageAt: freshAt,
            unreadCount: 1,
          ),
        ],
        'messagesByChat': <String, dynamic>{
          'chat-cross-platform': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'old-message',
              'chatId': 'chat-cross-platform',
              'senderId': 'user-2',
              'text': 'Старое из cache',
              'type': 'text',
              'status': 'read',
              'createdAt': cachedAt,
            },
          ],
        },
      }),
    });
    final api = _FakeChatsApi(
      chats: <Map<String, dynamic>>[
        _chatMap(
          id: 'chat-cross-platform',
          lastMessage: 'Новое с другого телефона',
          lastMessageAt: freshAt,
          unreadCount: 1,
        ),
      ],
      listMessageItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'new-message',
          'chatId': 'chat-cross-platform',
          'senderId': 'user-2',
          'text': 'Новое с другого телефона',
          'status': 'sent',
          'createdAt': freshAt,
        },
      ],
    );
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    final preview = await service.streamMyChats('user-1').firstWhere(
          (items) => items.isNotEmpty,
        );
    final messages = await service
        .streamMessages('chat-cross-platform')
        .firstWhere((items) => items.any((item) => item.id == 'new-message'));

    expect(preview.single.lastMessage, 'Новое с другого телефона');
    expect(api.listMessagesCalls, contains('chat-cross-platform'));
    expect(messages.map((item) => item.id), contains('old-message'));
    expect(messages.map((item) => item.id), contains('new-message'));
    expect(messages.where((item) => item.id == 'new-message'), hasLength(1));
  });

  test('markChatRead before REST messages finishes keeps incoming message',
      () async {
    final api = _FakeChatsApi(
      listMessagesDelay: const Duration(milliseconds: 30),
      chats: <Map<String, dynamic>>[
        _chatMap(id: 'chat-race', lastMessage: 'Не терять', unreadCount: 1),
      ],
      listMessageItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'race-message',
          'chatId': 'chat-race',
          'senderId': 'user-2',
          'text': 'Не терять',
          'status': 'sent',
          'createdAt': DateTime.utc(2026, 7, 1, 12).toIso8601String(),
        },
      ],
    );
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    await service.refreshInbox('user-1');
    final sub = service.streamMessages('chat-race').listen((_) {});
    await service.markChatRead(chatId: 'chat-race', uid: 'user-1');
    final messages = await service
        .streamMessages('chat-race')
        .firstWhere((items) => items.any((item) => item.id == 'race-message'));

    expect(api.markChatReadCalls, ['chat-race']);
    expect(messages.where((item) => item.id == 'race-message'), hasLength(1));
    await sub.cancel();
  });

  test('foreground push syncs REST messages before marking chat read',
      () async {
    final api = _FakeChatsApi(
      listMessageItems: <Map<String, dynamic>>[
        _messageMap(
          id: 'push-open-1',
          chatId: 'chat-push',
          text: 'Открыто из push',
        ),
      ],
    );
    final service = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
      mediaApi: _FakeMediaApi(),
    );

    service.setForegroundChat('chat-push');
    service.ingestMessageNotification(
      currentUserId: 'user-1',
      notification: <String, dynamic>{
        'chatId': 'chat-push',
        'type': 'chat_message',
      },
    );

    final messages = await service
        .streamMessages('chat-push')
        .firstWhere((items) => items.any((item) => item.id == 'push-open-1'));

    expect(messages.single.text, 'Открыто из push');
    expect(
        api.operationLog,
        containsAllInOrder(<String>[
          'listMessages:chat-push',
          'markChatRead:chat-push',
        ]));
  });
}

Map<String, dynamic> _chatMap({
  String id = 'chat-1',
  String lastMessage = 'Привет',
  String? lastMessageAt,
  String? createdAt,
  String? updatedAt,
  int unreadCount = 0,
}) =>
    <String, dynamic>{
      'id': id,
      'listingId': 'listing-1',
      'buyerId': 'user-1',
      'sellerId': 'user-2',
      'lastMessage': lastMessage,
      'lastMessageAt': lastMessageAt,
      'createdAt': createdAt ?? DateTime.now().toIso8601String(),
      'updatedAt': updatedAt ?? DateTime.now().toIso8601String(),
      'unreadCount': unreadCount,
      'buyerPreview': <String, dynamic>{'displayName': 'Buyer'},
      'sellerPreview': <String, dynamic>{'displayName': 'Seller'},
      'listingPreview': <String, dynamic>{'title': 'Listing'},
      'unread_for_buyer': unreadCount,
      'unread_for_seller': 0,
    };

Map<String, dynamic> _messageMap({
  required String id,
  required String chatId,
  String senderId = 'user-2',
  required String text,
  String status = 'sent',
  DateTime? createdAt,
}) =>
    <String, dynamic>{
      'id': id,
      'chatId': chatId,
      'senderId': senderId,
      'text': text,
      'status': status,
      'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
    };

class _FakeChatSocketService extends ChatSocketService {
  _FakeChatSocketService({
    this.hangConnect = false,
    this.connectCompleter,
    this.forceReconnectCompleter,
    this.reconnecting = false,
  });

  final StreamController<ChatSocketEvent> _eventsController =
      StreamController<ChatSocketEvent>.broadcast();
  final List<String> deliveredIds = <String>[];
  final List<String> readIds = <String>[];
  final List<String> joinedChats = <String>[];
  final bool hangConnect;
  final Completer<void>? connectCompleter;
  final Completer<void>? forceReconnectCompleter;
  bool reconnecting;
  bool forceReconnectInFlight = false;
  int connectCalls = 0;
  int reconnectCalls = 0;
  int forceReconnectCalls = 0;
  bool connected = false;

  @override
  Stream<ChatSocketEvent> get events => _eventsController.stream;

  @override
  Future<void> connect({String reason = 'unspecified'}) async {
    if (connected) {
      return;
    }
    connectCalls += 1;
    if (hangConnect) {
      return Completer<void>().future;
    }
    if (connectCompleter != null && !connectCompleter!.isCompleted) {
      await connectCompleter!.future;
      connected = true;
      reconnecting = false;
      return;
    }
    if (forceReconnectInFlight &&
        forceReconnectCompleter != null &&
        !forceReconnectCompleter!.isCompleted) {
      await forceReconnectCompleter!.future;
      connected = true;
      reconnecting = false;
      return;
    }
    connected = true;
    reconnecting = false;
  }

  @override
  Future<void> reconnect({String reason = 'manual'}) async {
    reconnectCalls += 1;
    connected = true;
    reconnecting = false;
  }

  @override
  Future<void> forceReconnect({String reason = 'manual'}) async {
    forceReconnectCalls += 1;
    if (forceReconnectCompleter != null &&
        !forceReconnectCompleter!.isCompleted) {
      forceReconnectInFlight = true;
      await forceReconnectCompleter!.future;
    }
    forceReconnectInFlight = false;
    connected = true;
    reconnecting = false;
  }

  @override
  Future<void> recoverAfterResume({String reason = 'resume'}) async {
    await forceReconnect(reason: reason);
  }

  @override
  Future<void> joinChat(String chatId, {String reason = 'chat.join'}) async {
    joinedChats.add(chatId);
  }

  @override
  bool get isConnected => connected;

  @override
  bool get isConnecting =>
      forceReconnectInFlight ||
      connectCompleter != null && !connectCompleter!.isCompleted;

  @override
  bool get isReconnecting => reconnecting;

  @override
  void leaveChat(String chatId) {}

  @override
  void sendDelivered(String messageId) {
    deliveredIds.add(messageId);
  }

  @override
  void sendRead(String messageId) {
    readIds.add(messageId);
  }

  void emitEvent(String name, Map<String, dynamic> payload) {
    _eventsController.add(ChatSocketEvent(name, payload));
  }

  void completeConnect() {
    connectCompleter?.complete();
  }

  void completeForceReconnect() {
    forceReconnectCompleter?.complete();
  }
}

class _FakeChatsApi extends ChatsApi {
  _FakeChatsApi({
    this.sendMessageError,
    List<Object>? sendMessageErrors,
    this.listMessagesError,
    this.chats = const <Map<String, dynamic>>[],
    this.listMessageItems = const <Map<String, dynamic>>[],
    this.listMessagesDelay = Duration.zero,
    this.sendMessageDelay = Duration.zero,
    this.unreadTotal,
  })  : sendMessageErrors = List<Object>.from(sendMessageErrors ?? const []),
        super(ApiClient(tokenStorage: TokenStorage()));

  Object? sendMessageError;
  final List<Object> sendMessageErrors;
  Object? listChatsError;
  final Object? listMessagesError;
  final List<Map<String, dynamic>> chats;
  final List<Map<String, dynamic>> listMessageItems;
  final Duration listMessagesDelay;
  final Duration sendMessageDelay;
  final int? unreadTotal;
  final List<String> getChatCalls = <String>[];
  final List<String> listMessagesCalls = <String>[];
  final List<String> markChatReadCalls = <String>[];
  final List<String> operationLog = <String>[];
  int listChatsCalls = 0;
  int sendMessageCalls = 0;
  String? lastClientMessageId;

  @override
  Future<Map<String, dynamic>> listChats() async {
    listChatsCalls += 1;
    if (listChatsError != null) {
      throw listChatsError!;
    }
    return <String, dynamic>{
      'items': chats,
      if (unreadTotal != null) 'unreadTotal': unreadTotal,
    };
  }

  @override
  Future<Map<String, dynamic>> listMessages(String chatId) async {
    listMessagesCalls.add(chatId);
    operationLog.add('listMessages:$chatId');
    if (listMessagesDelay > Duration.zero) {
      await Future<void>.delayed(listMessagesDelay);
    }
    if (listMessagesError != null) {
      throw listMessagesError!;
    }
    return <String, dynamic>{
      'chat': _chatMap(id: chatId),
      'items': listMessageItems,
    };
  }

  @override
  Future<Map<String, dynamic>> getChat(String chatId) async {
    getChatCalls.add(chatId);
    return <String, dynamic>{
      'chat': _chatMap(),
    };
  }

  @override
  Future<Map<String, dynamic>> markChatRead(String chatId) async {
    markChatReadCalls.add(chatId);
    operationLog.add('markChatRead:$chatId');
    return <String, dynamic>{
      'chat': _chatMap(id: chatId, unreadCount: 0),
      'messageIds': const <String>[],
    };
  }

  @override
  Future<Map<String, dynamic>> sendMessage({
    required String chatId,
    required String text,
    String? clientMessageId,
  }) async {
    sendMessageCalls += 1;
    lastClientMessageId = clientMessageId;
    if (sendMessageDelay > Duration.zero) {
      await Future<void>.delayed(sendMessageDelay);
    }
    if (sendMessageErrors.isNotEmpty) {
      throw sendMessageErrors.removeAt(0);
    }
    if (sendMessageError != null) {
      throw sendMessageError!;
    }
    return <String, dynamic>{
      'chat': _chatMap(id: chatId, lastMessage: text),
      'message': <String, dynamic>{
        'id': 'server-message-1',
        'chatId': chatId,
        'senderId': 'user-1',
        'text': text,
        'clientMessageId': clientMessageId,
        'status': 'sent',
        'createdAt': DateTime.now().toIso8601String(),
      },
    };
  }
}

class _FakeMediaApi extends MediaApi {
  _FakeMediaApi() : super(ApiClient(tokenStorage: TokenStorage()));

  int uploadCalls = 0;
  int lastUploadBytes = 0;

  @override
  Future<Map<String, dynamic>> uploadChatImage({
    required String chatId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    uploadCalls += 1;
    lastUploadBytes = bytes.length;
    return <String, dynamic>{
      'chat': _chatMap(),
      'message': <String, dynamic>{
        'id': 'server-image-1',
        'chatId': chatId,
        'senderId': 'user-1',
        'type': 'image',
        'imageUrl': 'https://cdn.example.com/final.jpg',
        'status': 'sent',
        'createdAt': DateTime.now().toIso8601String(),
      },
    };
  }
}
