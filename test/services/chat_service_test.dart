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
    expect(socket.readIds, contains('message-1'));
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

  test('resolveMessageImageUrl appends token for protected backend media', () async {
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
      'http://5.42.125.179/media/chats/file?key=chats%2Fchat-1%2Fphoto.jpg',
    );

    expect(
      resolved,
      'http://5.42.125.179/media/chats/file?key=chats%2Fchat-1%2Fphoto.jpg&token=access-token',
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
  _FakeChatSocketService();

  final StreamController<ChatSocketEvent> _eventsController =
      StreamController<ChatSocketEvent>.broadcast();
  final List<String> deliveredIds = <String>[];
  final List<String> readIds = <String>[];

  @override
  Stream<ChatSocketEvent> get events => _eventsController.stream;

  @override
  Future<void> connect() async {}

  @override
  Future<void> joinChat(String chatId) async {}

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
    this.chats = const <Map<String, dynamic>>[],
  }) : super(ApiClient(tokenStorage: TokenStorage()));

  final Object? sendMessageError;
  final List<Map<String, dynamic>> chats;
  final List<String> getChatCalls = <String>[];

  @override
  Future<Map<String, dynamic>> listChats() async {
    return <String, dynamic>{'items': chats};
  }

  @override
  Future<Map<String, dynamic>> listMessages(String chatId) async {
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
  Future<Map<String, dynamic>> sendMessage({
    required String chatId,
    required String text,
  }) async {
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
