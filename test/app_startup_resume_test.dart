import 'dart:async';

import 'package:atta/src/app.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/api/notifications_api.dart';
import 'package:atta/src/services/app_badge_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:atta/src/services/deep_link_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/push_notification_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/support_service.dart';
import 'package:atta/src/services/wallet_service.dart';
import 'package:atta/src/models/wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDeepLinkListingScreenBuilder = null;
  });

  tearDown(() {
    debugDeepLinkListingScreenBuilder = null;
  });

  testWidgets(
    'startup without new deep link does not reopen stale pending listing',
    (tester) async {
      final deepLinks = _FakeDeepLinkService()
        ..pendingListingId = 'listing-stale';
      final listings = _FakeListingsService();
      final auth = _FakeAuthService(
        currentUser: const AuthUser(uid: 'user-1'),
      );

      await tester.pumpWidget(
        _buildTestApp(
          auth: auth,
          deepLinks: deepLinks,
          listings: listings,
        ),
      );

      auth.emitSignedIn();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(listings.getListingByIdCalls, isEmpty);
      expect(deepLinks.pendingListingId, 'listing-stale');
    },
  );

  testWidgets(
    'pending deep link from current runtime opens after login and clears pending id',
    (tester) async {
      final deepLinks = _FakeDeepLinkService();
      final listings = _FakeListingsService();
      final auth = _FakeAuthService();
      final observer = _TestNavigatorObserver();
      debugDeepLinkListingScreenBuilder =
          (listingId) => Text('listing:$listingId');

      await tester.pumpWidget(
        _buildTestApp(
          auth: auth,
          deepLinks: deepLinks,
          listings: listings,
          navigatorObserver: observer,
        ),
      );

      deepLinks.emitListing('listing-42');
      await tester.pump();
      expect(deepLinks.pendingListingId, 'listing-42');
      expect(listings.getListingByIdCalls, isEmpty);

      auth.setSignedInUser(const AuthUser(uid: 'user-1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(listings.getListingByIdCalls, ['listing-42']);
      expect(deepLinks.clearedListingIds, ['listing-42']);
      expect(observer.pushCount, 1);
    },
  );

  testWidgets('same listing deep link is deduplicated while app is active',
      (tester) async {
    final deepLinks = _FakeDeepLinkService();
    final listings = _FakeListingsService();
    final auth = _FakeAuthService(
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final observer = _TestNavigatorObserver();
    debugDeepLinkListingScreenBuilder =
        (listingId) => Text('listing:$listingId');

    await tester.pumpWidget(
      _buildTestApp(
        auth: auth,
        deepLinks: deepLinks,
        listings: listings,
        navigatorObserver: observer,
      ),
    );

    deepLinks.emitListing('listing-42');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    deepLinks.emitListing('listing-42');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      listings.getListingByIdCalls.where((id) => id == 'listing-42').length,
      1,
    );
    expect(observer.pushCount, 1);
  });

  testWidgets(
    'same listing deep link does not push a second screen while it is already open',
    (tester) async {
      final deepLinks = _FakeDeepLinkService();
      final listings = _FakeListingsService();
      final auth = _FakeAuthService(
        currentUser: const AuthUser(uid: 'user-1'),
      );
      final observer = _TestNavigatorObserver();
      debugDeepLinkListingScreenBuilder =
          (listingId) => Text('listing:$listingId');

      await tester.pumpWidget(
        _buildTestApp(
          auth: auth,
          deepLinks: deepLinks,
          listings: listings,
          navigatorObserver: observer,
        ),
      );

      deepLinks.emitListing('listing-42');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(seconds: 3));

      deepLinks.emitListing('listing-42');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        listings.getListingByIdCalls.where((id) => id == 'listing-42').length,
        1,
      );
      expect(observer.pushCount, 1);
    },
  );

  testWidgets('rapid resume is debounced to one restore cycle', (tester) async {
    final auth = _FakeAuthService(
      currentUser: const AuthUser(uid: 'user-1'),
    )..restoreCompleter = Completer<AuthUser?>();
    final chats = _FakeChatService();
    final notifications = _FakeNotificationsService();
    final admin = _FakeAdminService();
    final presence = _FakePresenceService();

    await tester.pumpWidget(
      _buildTestApp(
        auth: auth,
        chats: chats,
        notifications: notifications,
        admin: admin,
        presence: presence,
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(auth.restoreCalls, 1);
    expect(chats.handleResumeCalls, 0);
    expect(notifications.refreshCalls, 0);

    auth.restoreCompleter!.complete(const AuthUser(uid: 'user-1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(chats.handleResumeCalls, 1);
    expect(notifications.refreshCalls, 1);
    expect(presence.recoverAfterResumeCalls, 1);
    expect(admin.refreshCalls, 0);
  });

  testWidgets('resume recovers presence before chat refresh', (tester) async {
    final order = <String>[];
    final auth = _FakeAuthService(
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final presence = _FakePresenceService(callOrder: order)
      ..recoverAfterResumeCompleter = Completer<void>();
    final chats = _FakeChatService(callOrder: order);

    await tester.pumpWidget(
      _buildTestApp(
        auth: auth,
        presence: presence,
        chats: chats,
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(order, <String>['presence.resume']);
    expect(chats.handleResumeCalls, 0);

    presence.recoverAfterResumeCompleter!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(order, <String>['presence.resume', 'chat.resume']);
    expect(chats.handleResumeCalls, 1);
  });

  testWidgets('hidden paused resumed runs realtime recovery once',
      (tester) async {
    final auth = _FakeAuthService(
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final presence = _FakePresenceService();
    final chats = _FakeChatService();

    await tester.pumpWidget(
      _buildTestApp(
        auth: auth,
        presence: presence,
        chats: chats,
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(auth.restoreCalls, 1);
    expect(presence.recoverAfterResumeCalls, 1);
    expect(chats.handleResumeCalls, 1);
  });
}

Widget _buildTestApp({
  _FakeAuthService? auth,
  _FakeDeepLinkService? deepLinks,
  _FakeListingsService? listings,
  _FakeChatService? chats,
  _FakeNotificationsService? notifications,
  _FakeAdminService? admin,
  _FakePresenceService? presence,
  NavigatorObserver? navigatorObserver,
}) {
  return MultiProvider(
    providers: [
      Provider<AuthService>.value(value: auth ?? _FakeAuthService()),
      Provider<DeepLinkService>.value(
        value: deepLinks ?? _FakeDeepLinkService(),
      ),
      Provider<ListingsService>.value(
          value: listings ?? _FakeListingsService()),
      Provider<FollowService>.value(value: FollowService()),
      Provider<FavoritesService>.value(value: FavoritesService()),
      ChangeNotifierProvider<ListingHistoryService>.value(
        value: _FakeListingHistoryService(),
      ),
      Provider<ProfileService>.value(value: ProfileService()),
      Provider<WalletService>.value(value: _FakeWalletService()),
      Provider<ChatSocketService>.value(value: ChatSocketService()),
      Provider<ChatService>.value(value: chats ?? _FakeChatService()),
      Provider<ReviewsService>.value(value: ReviewsService()),
      Provider<SupportService>.value(value: _FakeSupportService()),
      Provider<AdminService>.value(value: admin ?? _FakeAdminService()),
      Provider<PresenceService>.value(
          value: presence ?? _FakePresenceService()),
      Provider<AppBadgeService>.value(value: _FakeAppBadgeService()),
      Provider<NotificationsService>.value(
        value: notifications ?? _FakeNotificationsService(),
      ),
      Provider<PushNotificationService>.value(
        value: _FakePushNotificationService(),
      ),
    ],
    child: MaterialApp(
      navigatorKey: attaNavigatorKey,
      navigatorObservers: [
        if (navigatorObserver != null) navigatorObserver,
      ],
      home: const SessionPresenceBinder(
        child: Scaffold(body: Text('home')),
      ),
    ),
  );
}

class _FakeAuthService extends AuthService {
  _FakeAuthService({
    AuthUser? currentUser,
  }) : _currentUser = currentUser;

  final StreamController<AuthSessionEvent> _events =
      StreamController<AuthSessionEvent>.broadcast();
  AuthUser? _currentUser;
  int restoreCalls = 0;
  Completer<AuthUser?>? restoreCompleter;

  @override
  Stream<AuthSessionEvent> get onAuthStateChange => _events.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  bool get isAuthenticated => _currentUser != null;

  void emitSignedIn() {
    _events.add(const AuthSessionEvent(type: AuthSessionEventType.signedIn));
  }

  void setSignedInUser(AuthUser user) {
    _currentUser = user;
    emitSignedIn();
  }

  @override
  Future<AuthUser?> restoreSessionOnResume({bool force = false}) async {
    restoreCalls += 1;
    final completer = restoreCompleter;
    if (completer != null) {
      return completer.future;
    }
    return _currentUser;
  }
}

class _FakeDeepLinkService extends DeepLinkService {
  _FakeDeepLinkService();

  final StreamController<AttaDeepLink> _controller =
      StreamController<AttaDeepLink>.broadcast();
  final List<String> clearedListingIds = <String>[];
  String? pendingListingId;

  @override
  Stream<AttaDeepLink> get links => _controller.stream;

  @override
  Future<void> initialize() async {}

  void emitListing(String listingId) {
    _controller.add(
      AttaDeepLink.listing(
        uri: Uri.parse('https://attamarket.online/listing/$listingId'),
        listingId: listingId,
      ),
    );
  }

  @override
  Future<void> savePendingListingId(String listingId) async {
    pendingListingId = listingId;
  }

  @override
  Future<String?> readPendingListingId() async => pendingListingId;

  @override
  Future<void> clearPendingListingIdIfMatches(String listingId) async {
    if (pendingListingId == listingId) {
      clearedListingIds.add(listingId);
      pendingListingId = null;
    }
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

class _FakeListingsService extends ListingsService {
  final List<String> getListingByIdCalls = <String>[];

  @override
  Future<Listing?> getListingById(String id) async {
    getListingByIdCalls.add(id);
    return Listing.fromMap(<String, dynamic>{
      'id': id,
      'owner_id': 'user-2',
      'owner_email': 'seller@example.com',
      'owner_name': 'Seller',
      'title': 'Listing $id',
      'description': 'Description',
      'category': 'Электроника',
      'subcategory': 'Телефоны',
      'price': 1000,
      'phone': '+79990000000',
      'phone_hidden': false,
      'city': 'Москва',
      'location': <String, dynamic>{'locality': 'Москва'},
      'delivery': <String, dynamic>{'pickup': true},
      'photo_urls': const <String>[],
      'photo_items': const <Map<String, dynamic>>[],
      'car': null,
      'deal_type': null,
      'real_estate_type': null,
      'clothes_type': null,
      'view_count': 0,
      'favorite_count': 0,
      'status': 'approved',
      'rejection_reason': '',
      'published_at': '2026-07-08T10:00:00.000Z',
      'created_at': '2026-07-08T10:00:00.000Z',
      'updated_at': '2026-07-08T10:00:00.000Z',
      'can_promote': true,
    });
  }

  @override
  void resetSession() {}
}

class _FakeChatService extends ChatService {
  _FakeChatService({this.callOrder})
      : super(socketService: ChatSocketService());

  final List<String>? callOrder;
  int handleResumeCalls = 0;

  @override
  Stream<int> streamUnreadTotal(String uid) => Stream<int>.value(0);

  @override
  Future<void> handleAppResumed(
    String uid, {
    bool recoverSocket = true,
  }) async {
    handleResumeCalls += 1;
    callOrder?.add('chat.resume');
  }

  @override
  Future<void> resetSession() async {}
}

class _FakeNotificationsService extends NotificationsService {
  int refreshCalls = 0;

  @override
  void activateSession(String userId) {}

  @override
  void resetSession() {}

  @override
  Stream<int> streamUnreadBadgeCount(String userId) => Stream<int>.value(0);

  @override
  Future<void> refreshActiveSession({bool force = false}) async {
    refreshCalls += 1;
  }
}

class _FakeAdminService extends AdminService {
  int refreshCalls = 0;

  @override
  void activateSession() {}

  @override
  void bindAdminUser(String uid) {}

  @override
  void resetSession() {}

  @override
  Future<void> refreshAdminAttention({bool force = false}) async {
    refreshCalls += 1;
  }
}

class _FakeSupportService extends SupportService {
  @override
  void activateAdminSession({required bool isAdmin}) {}

  @override
  void resetSession() {}
}

class _FakePresenceService extends PresenceService {
  _FakePresenceService({this.callOrder})
      : super(socketService: ChatSocketService());

  final List<String>? callOrder;
  int recoverAfterResumeCalls = 0;
  Completer<void>? recoverAfterResumeCompleter;

  @override
  Future<void> setOnline({
    required String uid,
    required bool isOnline,
  }) async {}

  @override
  Future<void> recoverAfterResume(String uid) async {
    recoverAfterResumeCalls += 1;
    callOrder?.add('presence.resume');
    final completer = recoverAfterResumeCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Future<void> resetSession() async {}
}

class _FakeListingHistoryService extends ListingHistoryService {
  @override
  Future<void> activateSession() async {}

  @override
  Future<void> resetSession() async {}
}

class _FakeAppBadgeService extends AppBadgeService {
  @override
  Future<void> bindForUser({
    required String userId,
    required ChatService chatService,
    required NotificationsService notificationsService,
  }) async {}

  @override
  Future<void> clear() async {}
}

class _FakePushNotificationService extends PushNotificationService {
  @override
  Future<void> bindForUser({
    required NotificationsApi api,
    required String userId,
  }) async {}

  @override
  Future<void> unbind({NotificationsApi? api}) async {}

  @override
  Future<void> dispose() async {}
}

class _FakeWalletService extends WalletService {
  @override
  void activateSession(String uid) {}

  @override
  void resetSession() {}

  @override
  Future<Wallet?> maybeCheckAccrualOncePerSession() async => null;
}

class _TestNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      pushCount += 1;
    }
    super.didPush(route, previousRoute);
  }
}
