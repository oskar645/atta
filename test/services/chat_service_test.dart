import 'dart:async';
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
    expect(socket.reconnectCalls, 1);
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
    expect(api.listMessagesCalls, ['chat-a']);
    expect(api.markChatReadCalls, ['chat-a']);
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
    expect(api.listMessagesCalls.where((id) => id == 'chat-a').length, 1);
    expect(api.markChatReadCalls.where((id) => id == 'chat-a').length, 1);
    await sub.cancel();
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

class _FakeChatSocketService extends ChatSocketService {
  _FakeChatSocketService({this.hangConnect = false});

  final StreamController<ChatSocketEvent> _eventsController =
      StreamController<ChatSocketEvent>.broadcast();
  final List<String> deliveredIds = <String>[];
  final List<String> readIds = <String>[];
  final List<String> joinedChats = <String>[];
  final bool hangConnect;
  int connectCalls = 0;
  int reconnectCalls = 0;
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
    connected = true;
  }

  @override
  Future<void> reconnect({String reason = 'manual'}) async {
    reconnectCalls += 1;
    connected = true;
  }

  @override
  Future<void> joinChat(String chatId, {String reason = 'chat.join'}) async {
    joinedChats.add(chatId);
  }

  @override
  bool get isConnected => connected;

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
}

class _FakeChatsApi extends ChatsApi {
  _FakeChatsApi({
    this.sendMessageError,
    this.listChatsError,
    this.listMessagesError,
    this.chats = const <Map<String, dynamic>>[],
    this.sendMessageDelay = Duration.zero,
  }) : super(ApiClient(tokenStorage: TokenStorage()));

  final Object? sendMessageError;
  Object? listChatsError;
  final Object? listMessagesError;
  final List<Map<String, dynamic>> chats;
  final Duration sendMessageDelay;
  final List<String> getChatCalls = <String>[];
  final List<String> listMessagesCalls = <String>[];
  final List<String> markChatReadCalls = <String>[];
  int listChatsCalls = 0;
  int sendMessageCalls = 0;
  String? lastClientMessageId;

  @override
  Future<Map<String, dynamic>> listChats() async {
    listChatsCalls += 1;
    if (listChatsError != null) {
      throw listChatsError!;
    }
    return <String, dynamic>{'items': chats};
  }

  @override
  Future<Map<String, dynamic>> listMessages(String chatId) async {
    listMessagesCalls.add(chatId);
    if (listMessagesError != null) {
      throw listMessagesError!;
    }
    return <String, dynamic>{
      'chat': _chatMap(),
      'items': <Map<String, dynamic>>[],
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
    if (sendMessageError != null) {
      throw sendMessageError!;
    }
    return <String, dynamic>{
      'chat': _chatMap(),
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
