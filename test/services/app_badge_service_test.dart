import 'dart:async';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/chats_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/app_badge_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('badge combines chat and notification unread and read clears both',
      () async {
    final chats = _UnreadChats();
    final notifications = _UnreadNotifications();
    final updates = <int>[];
    final badge = AppBadgeService(
        isSupported: () async => true,
        updateBadge: (n) async => updates.add(n));
    await badge.bindForUser(
        userId: 'A', chatService: chats, notificationsService: notifications);
    chats.counts.add(2);
    notifications.counts.add(3);
    await Future<void>.delayed(Duration.zero);
    expect(updates.last, 5);
    chats.counts.add(0);
    notifications.counts.add(1);
    await Future<void>.delayed(Duration.zero);
    expect(updates.last, 1);
    notifications.counts.add(0);
    await Future<void>.delayed(Duration.zero);
    expect(updates.last, 0);
    await badge.dispose();
  });

  test('old asynchronous native write cannot overwrite logout or B badge',
      () async {
    final chatsA = _UnreadChats(), chatsB = _UnreadChats();
    final notifications = _UnreadNotifications();
    final started = Completer<void>(), release = Completer<void>();
    final updates = <int>[];
    final badge = AppBadgeService(
        isSupported: () async => true,
        updateBadge: (n) async {
          if (n == 7) {
            started.complete();
            await release.future;
          }
          updates.add(n);
        });
    await badge.bindForUser(
        userId: 'A', chatService: chatsA, notificationsService: notifications);
    chatsA.counts.add(7);
    await started.future;
    final clearing = badge.clear();
    await badge.bindForUser(
        userId: 'B', chatService: chatsB, notificationsService: notifications);
    chatsA.counts.add(99);
    chatsB.counts.add(1);
    release.complete();
    await clearing;
    await Future<void>.delayed(Duration.zero);
    expect(updates.last, 1);
    expect(updates, isNot(contains(99)));
    await badge.clear();
    expect(updates.last, 0);
  });

  test('new messages set absolute unread badge without double increment',
      () async {
    final updates = <int>[];
    final socket = _FakeChatSocketService();
    final chats = ChatService(
      socketService: socket,
      api: _FakeChatsApi(),
    );
    final badge = AppBadgeService(
      isSupported: () async => true,
      updateBadge: (count) async => updates.add(count),
    );

    await badge.bindForUser(
      userId: 'user-1',
      chatService: chats,
      notificationsService: NotificationsService(),
    );
    socket.emitEvent('message.new', _messageEvent('m1', unreadTotal: 1));
    socket.emitEvent('message.new', _messageEvent('m2', unreadTotal: 2));
    socket.emitEvent(
      'unread.changed',
      <String, dynamic>{
        'chatId': 'chat-1',
        'unreadCount': 2,
        'unreadTotal': 2,
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(updates, containsAllInOrder(<int>[1, 2]));
    expect(updates, isNot(contains(3)));
    expect(updates.last, 2);
  });

  test('opening chat clears badge after mark read', () async {
    final updates = <int>[];
    final api = _FakeChatsApi();
    final chats = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
    );
    final badge = AppBadgeService(
      isSupported: () async => true,
      updateBadge: (count) async => updates.add(count),
    );

    await badge.bindForUser(
      userId: 'user-1',
      chatService: chats,
      notificationsService: NotificationsService(),
    );
    await chats.refreshInbox('user-1');
    await chats.markChatRead(chatId: 'chat-1', uid: 'user-1');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(api.markChatReadCalls, <String>['chat-1']);
    expect(updates.last, 0);
  });

  test('resume sync uses backend unread total', () async {
    final updates = <int>[];
    final api = _FakeChatsApi(initialUnreadTotal: 5);
    final chats = ChatService(
      socketService: _FakeChatSocketService(),
      api: api,
    );
    final badge = AppBadgeService(
      isSupported: () async => true,
      updateBadge: (count) async => updates.add(count),
    );

    await badge.bindForUser(
      userId: 'user-1',
      chatService: chats,
      notificationsService: NotificationsService(),
    );
    await chats.handleAppResumed('user-1');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(api.listChatsCalls, greaterThanOrEqualTo(1));
    expect(updates.last, 5);
  });

  test('logout clears badge', () async {
    final updates = <int>[];
    final badge = AppBadgeService(
      isSupported: () async => true,
      updateBadge: (count) async => updates.add(count),
    );

    await badge.clear();

    expect(updates, <int>[0]);
  });
}

Map<String, dynamic> _messageEvent(String id, {required int unreadTotal}) {
  return <String, dynamic>{
    'chat': _chatMap(unreadCount: unreadTotal),
    'message': <String, dynamic>{
      'id': id,
      'chatId': 'chat-1',
      'senderId': 'user-2',
      'text': 'Привет',
      'createdAt': DateTime.now().toIso8601String(),
    },
    'unreadTotal': unreadTotal,
  };
}

Map<String, dynamic> _chatMap({int unreadCount = 1}) {
  return <String, dynamic>{
    'id': 'chat-1',
    'listingId': 'listing-1',
    'buyerId': 'user-1',
    'sellerId': 'user-2',
    'lastMessage': 'Привет',
    'lastMessageAt': DateTime.now().toIso8601String(),
    'createdAt': DateTime.now().toIso8601String(),
    'updatedAt': DateTime.now().toIso8601String(),
    'unreadCount': unreadCount,
    'buyerPreview': <String, dynamic>{'displayName': 'Buyer'},
    'sellerPreview': <String, dynamic>{'displayName': 'Seller'},
    'listingPreview': <String, dynamic>{'title': 'Listing'},
    'unread_for_buyer': unreadCount,
    'unread_for_seller': 0,
  };
}

class _FakeChatSocketService extends ChatSocketService {
  final _events = StreamController<ChatSocketEvent>.broadcast();

  @override
  Stream<ChatSocketEvent> get events => _events.stream;

  @override
  Future<void> connect({String reason = 'unspecified'}) async {}

  @override
  Future<void> reconnect({String reason = 'manual'}) async {}

  @override
  bool get isConnected => true;

  @override
  void sendDelivered(String messageId) {}

  void emitEvent(String name, Map<String, dynamic> payload) {
    _events.add(ChatSocketEvent(name, payload));
  }
}

class _FakeChatsApi extends ChatsApi {
  _FakeChatsApi({this.initialUnreadTotal = 1})
      : super(ApiClient(tokenStorage: TokenStorage()));

  final int initialUnreadTotal;
  int listChatsCalls = 0;
  final List<String> markChatReadCalls = <String>[];

  @override
  Future<Map<String, dynamic>> listChats({int? limit, String? cursor}) async {
    listChatsCalls += 1;
    return <String, dynamic>{
      'items': <Map<String, dynamic>>[
        _chatMap(unreadCount: initialUnreadTotal),
      ],
      'unreadTotal': initialUnreadTotal,
    };
  }

  @override
  Future<Map<String, dynamic>> markChatRead(String chatId) async {
    markChatReadCalls.add(chatId);
    return <String, dynamic>{
      'chat': _chatMap(unreadCount: 0),
      'messageIds': const <String>[],
    };
  }
}

class _UnreadChats extends ChatService {
  final counts = StreamController<int>.broadcast();
  @override
  Stream<int> streamUnreadTotal(String uid) => counts.stream;
}

class _UnreadNotifications extends NotificationsService {
  final counts = StreamController<int>.broadcast();
  @override
  Stream<int> streamUnreadBadgeCount(String uid) => counts.stream;
}
