import 'dart:async';

import 'package:atta/src/app.dart';
import 'package:atta/src/features/inbox/chat_screen.dart';
import 'package:atta/src/features/inbox/inbox_screen.dart';
import 'package:atta/src/models/chat.dart';
import 'package:atta/src/models/message.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/main_shell_controller.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/widgets/app_error_view.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
      'opening inbox list keeps unread chat unread and does not mark read',
      (tester) async {
    final chatService = _InboxFakeChatService(
      chats: <Chat>[
        _chatFixture(unreadForBuyer: 2),
      ],
    );

    await tester.pumpWidget(
      _buildInboxApp(
        chatService: chatService,
        child: const InboxScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    expect(chatService.markChatReadCalls, isEmpty);
  });

  testWidgets('opening concrete chat marks only that chat as read',
      (tester) async {
    final unreadChat = _chatFixture(id: 'chat-unread', unreadForBuyer: 1);
    final otherChat = _chatFixture(id: 'chat-other', unreadForBuyer: 3);
    final chatService = _InboxFakeChatService(
      chats: <Chat>[unreadChat, otherChat],
      chat: unreadChat,
      messages: <ChatMessage>[
        ChatMessage(
          id: 'incoming-1',
          chatId: unreadChat.id,
          senderId: 'user-2',
          text: 'Привет',
          createdAt: DateTime.parse('2026-06-30T10:00:00.000Z'),
        ),
      ],
    );

    await tester.pumpWidget(
      _buildInboxApp(
        chatService: chatService,
        child: const InboxScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Seller').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(chatService.markChatReadCalls, isNotEmpty);
    expect(
      chatService.markChatReadCalls.every((chatId) => chatId == 'chat-unread'),
      isTrue,
    );
    expect(chatService.markChatsDeliveredCalls, isNotEmpty);
  });

  testWidgets(
      'inbox shows separate chats for same seller with different listings',
      (tester) async {
    final chatService = _InboxFakeChatService(
      chats: <Chat>[
        _chatFixture(
          id: 'chat-bmw',
          listingId: 'listing-bmw',
          listingTitle: 'BMW',
          unreadForBuyer: 1,
        ),
        _chatFixture(
          id: 'chat-mercedes',
          listingId: 'listing-mercedes',
          listingTitle: 'Mercedes',
          unreadForBuyer: 2,
        ),
      ],
    );

    await tester.pumpWidget(
      _buildInboxApp(
        chatService: chatService,
        child: const InboxScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('BMW'), findsOneWidget);
    expect(find.textContaining('Mercedes'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-item:chat-bmw:listing-bmw')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-item:chat-mercedes:listing-mercedes')),
      findsOneWidget,
    );
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('pull to refresh updates inbox and does not call mark read',
      (tester) async {
    final chatService = _InboxFakeChatService(
      chats: <Chat>[
        _chatFixture(id: 'chat-1', unreadForBuyer: 1),
      ],
    );

    await tester.pumpWidget(
      _buildInboxApp(
        chatService: chatService,
        child: const InboxScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).first, const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(chatService.refreshInboxCalls, 2);
    expect(chatService.markChatReadCalls, isEmpty);
  });

  testWidgets(
      'inbox keeps cached chats visible when stream emits an error after load',
      (tester) async {
    final chatService = _InboxFakeChatService(
      chats: <Chat>[
        _chatFixture(id: 'chat-1', unreadForBuyer: 1),
      ],
    );

    await tester.pumpWidget(
      _buildInboxApp(
        chatService: chatService,
        child: const InboxScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Seller'), findsOneWidget);

    chatService.emitChatsError(Exception('network'));
    await tester.pump();

    expect(find.text('Seller'), findsOneWidget);
    expect(find.byType(AppErrorView), findsNothing);
  });

  testWidgets('inbox does not show empty state before first refresh completes',
      (tester) async {
    final refreshCompleter = Completer<void>();
    final chatService = _InboxFakeChatService(
      chats: const <Chat>[],
      refreshInboxCompleter: refreshCompleter,
    );

    await tester.pumpWidget(
      _buildInboxApp(
        chatService: chatService,
        child: const InboxScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('Пока нет сообщений'), findsNothing);
    expect(find.byType(SkeletonChatRow), findsWidgets);

    refreshCompleter.complete();
    await tester.pump();

    expect(find.text('Пока нет сообщений'), findsOneWidget);
  });

  testWidgets('inbox retry after timeout starts a new inbox request',
      (tester) async {
    final chatService = _RetryInboxFakeChatService();

    await tester.pumpWidget(
      _buildInboxApp(
        chatService: chatService,
        child: const InboxScreen(),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(AppErrorView), findsOneWidget);

    await tester.tap(find.text('Повторить').first);
    await tester.pumpAndSettle();

    expect(find.text('Seller'), findsOneWidget);
    expect(find.byType(AppErrorView), findsNothing);
    expect(chatService.refreshInboxCalls, 2);
  });

  testWidgets('chat screen shows messages with small avatars', (tester) async {
    final chatService = _InboxFakeChatService(
      chat: _chatFixture(),
      messages: <ChatMessage>[
        ChatMessage(
          id: 'out-1',
          chatId: 'chat-1',
          senderId: 'user-1',
          text: 'Моё сообщение',
          createdAt: DateTime.parse('2026-06-30T10:00:00.000Z'),
        ),
        ChatMessage(
          id: 'in-1',
          chatId: 'chat-1',
          senderId: 'user-2',
          text: 'Чужое сообщение',
          createdAt: DateTime.parse('2026-06-30T09:59:00.000Z'),
        ),
      ],
    );

    await tester.pumpWidget(
      _buildInboxApp(
        chatService: chatService,
        child: const ChatScreen(chatId: 'chat-1'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Моё сообщение'), findsOneWidget);
    expect(find.text('Чужое сообщение'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('avatar-mine-out-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('avatar-other-in-1')),
        findsOneWidget);
  });

  testWidgets('tap outside input closes keyboard', (tester) async {
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              AppKeyboardDismissOnTap(
                child: const SizedBox.expand(),
              ),
              TextField(focusNode: focusNode),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);

    await tester.tapAt(const Offset(300, 500));
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isFalse);
  });
}

Widget _buildInboxApp({
  required ChatService chatService,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      Provider<AuthService>.value(value: _FakeAuthService()),
      Provider<ChatService>.value(value: chatService),
      Provider<ProfileService>.value(value: _FakeProfileService()),
      Provider<PresenceService>.value(value: _FakePresenceService()),
      ChangeNotifierProvider(
        create: (_) => MainShellController(initialIndex: 3),
      ),
    ],
    child: MaterialApp(
      navigatorObservers: [attaRouteObserver],
      home: child,
    ),
  );
}

Chat _chatFixture({
  String id = 'chat-1',
  String listingId = 'listing-1',
  String listingTitle = 'Объявление',
  int unreadForBuyer = 0,
}) {
  final now = DateTime.parse('2026-06-30T10:00:00.000Z');
  return Chat(
    id: id,
    listingId: listingId,
    listingTitle: listingTitle,
    listingPhotoUrl: '',
    buyerId: 'user-1',
    sellerId: 'user-2',
    buyerName: 'Buyer',
    sellerName: 'Seller',
    buyerAvatar: '',
    sellerAvatar: '',
    lastMessage: 'Последнее сообщение',
    lastMessageAt: now,
    createdAt: now,
    updatedAt: now,
    unreadCount: unreadForBuyer,
    unreadForBuyer: unreadForBuyer,
    unreadForSeller: 0,
  );
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(
        uid: 'user-1',
        displayName: 'Current User',
        photoUrl: 'https://cdn.example.com/me.jpg',
      );
}

class _FakeProfileService extends ProfileService {
  @override
  Stream<Map<String, dynamic>> streamProfile(
    String uid, {
    Map<String, dynamic>? seed,
  }) async* {
    yield <String, dynamic>{
      ...?seed,
      'display_name': uid == 'user-2' ? 'Seller' : 'Current User',
      'avatar_url': uid == 'user-2'
          ? 'https://cdn.example.com/seller.jpg'
          : 'https://cdn.example.com/me.jpg',
    };
  }

  @override
  void seedProfile(String uid, Map<String, dynamic> row) {}
}

class _FakePresenceService extends PresenceService {
  @override
  bool? peekIsOnline(String uid) => false;

  @override
  Stream<bool> streamIsOnline(
    String uid, {
    Duration staleAfter = const Duration(minutes: 2),
  }) {
    return Stream<bool>.value(false);
  }
}

class _InboxFakeChatService extends ChatService {
  _InboxFakeChatService({
    List<Chat>? chats,
    Chat? chat,
    List<ChatMessage>? messages,
    Completer<void>? refreshInboxCompleter,
    Object? refreshInboxError,
  })  : _chats = chats ?? <Chat>[_chatFixture()],
        _chat = chat ?? _chatFixture(),
        _messages = messages ?? const <ChatMessage>[],
        _refreshInboxCompleter = refreshInboxCompleter,
        _refreshInboxError = refreshInboxError;

  final List<Chat> _chats;
  final Chat _chat;
  final List<ChatMessage> _messages;
  final Completer<void>? _refreshInboxCompleter;
  final Object? _refreshInboxError;
  final StreamController<List<Chat>> _myChatsController =
      StreamController<List<Chat>>.broadcast();
  final List<String> markChatReadCalls = <String>[];
  final List<List<String>> markChatsDeliveredCalls = <List<String>>[];
  int refreshInboxCalls = 0;

  @override
  Stream<List<Chat>> streamMyChats(String uid) =>
      Stream<List<Chat>>.multi((controller) {
        controller.add(_chats);
        final sub = _myChatsController.stream.listen(
          controller.add,
          onError: controller.addError,
        );
        controller.onCancel = () async {
          await sub.cancel();
        };
      }, isBroadcast: true);

  @override
  Stream<int> streamUnreadTotal(String uid) => Stream<int>.value(
        _chats.fold<int>(0, (sum, chat) => sum + chat.unreadFor(uid)),
      );

  @override
  Stream<Chat?> streamChat(String chatId) => Stream<Chat?>.value(_chat);

  @override
  Future<void> preloadChat(String chatId, {String? uid}) async {}

  @override
  Future<void> refreshInbox(String uid) async {
    refreshInboxCalls += 1;
    if (_refreshInboxError != null) {
      throw _refreshInboxError!;
    }
    final completer = _refreshInboxCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Stream<List<ChatMessage>> streamMessages(String chatId) =>
      Stream<List<ChatMessage>>.multi(
        (controller) {
          controller.add(_messages);
          controller.close();
        },
        isBroadcast: true,
      );

  @override
  Future<void> markChatRead({
    required String chatId,
    required String uid,
  }) async {
    markChatReadCalls.add(chatId);
  }

  @override
  Future<void> markChatsDelivered({
    required Iterable<String> chatIds,
    required String uid,
  }) async {
    markChatsDeliveredCalls.add(chatIds.toList());
  }

  @override
  void setForegroundChat(String? chatId) {}

  void emitChats(List<Chat> chats) {
    _myChatsController.add(chats);
  }

  void emitChatsError(Object error) {
    _myChatsController.addError(error);
  }
}

class _RetryInboxFakeChatService extends ChatService {
  final StreamController<List<Chat>> _myChatsController =
      StreamController<List<Chat>>.broadcast();
  int refreshInboxCalls = 0;
  Object? _lastError;

  @override
  Object? get lastChatsLoadError => _lastError;

  @override
  Stream<List<Chat>> streamMyChats(String uid) =>
      Stream<List<Chat>>.multi((controller) {
        controller.add(const <Chat>[]);
        final sub = _myChatsController.stream.listen(
          controller.add,
          onError: controller.addError,
        );
        controller.onCancel = () async {
          await sub.cancel();
        };
      }, isBroadcast: true);

  @override
  Future<void> refreshInbox(String uid) async {
    refreshInboxCalls += 1;
    if (refreshInboxCalls == 1) {
      _lastError = TimeoutException('Future not completed');
      return;
    }
    _lastError = null;
    _myChatsController.add(<Chat>[_chatFixture()]);
  }

  @override
  Future<void> markChatsDelivered({
    required Iterable<String> chatIds,
    required String uid,
  }) async {}
}
