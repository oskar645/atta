import 'dart:async';

import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/notification_navigation_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/support_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NotificationNavigationService.debugResetState();
  });

  test('actionTypeForNotification prefers payload actionType', () {
    final actionType = NotificationNavigationService.actionTypeForNotification(
      <String, dynamic>{
        'type': 'generic',
        'payload': <String, dynamic>{
          'actionType': 'review_new',
        },
      },
    );

    expect(actionType, 'review_new');
  });

  test('payloadForNotification returns normalized map', () {
    final payload = NotificationNavigationService.payloadForNotification(
      <String, dynamic>{
        'payload': <Object, Object>{
          'ticketId': 'ticket-1',
          'reportId': 'report-1',
        },
      },
    );

    expect(payload['ticketId'], 'ticket-1');
    expect(payload['reportId'], 'report-1');
  });

  test('support_message payload opens support navigation', () {
    final notification = <String, dynamic>{
      'type': 'support',
      'payload': <String, dynamic>{
        'type': 'support_message',
        'ticketId': 'ticket-1',
      },
    };

    expect(
      NotificationNavigationService.actionTypeForNotification(notification),
      'support_message',
    );
    expect(
      NotificationNavigationService.shouldNavigateForNotification(notification),
      true,
    );
  });

  test('general notification does not require navigation', () {
    final shouldNavigate =
        NotificationNavigationService.shouldNavigateForNotification(
      <String, dynamic>{
        'type': 'general',
        'scope': 'global',
        'payload': const <String, dynamic>{},
      },
    );

    expect(shouldNavigate, false);
  });

  test('unknown notification without payload does not require navigation', () {
    final shouldNavigate =
        NotificationNavigationService.shouldNavigateForNotification(
      <String, dynamic>{
        'type': 'something_new',
        'scope': 'global',
      },
    );

    expect(shouldNavigate, false);
  });

  testWidgets(
      'general notification tap only marks read and does not push route',
      (tester) async {
    final notifications = _FakeNotificationsService();
    final observer = _TestNavigatorObserver();
    final context = await _pumpHarness(
      tester,
      notifications: notifications,
      observer: observer,
    );

    await NotificationNavigationService.handleNotificationTap(
      context,
      <String, dynamic>{
        'id': 'global-1',
        'type': 'general',
        'scope': 'global',
        'is_read': false,
      },
    );
    await tester.pumpAndSettle();

    expect(notifications.markAllSeenCalls, 1);
    expect(notifications.markPersonalReadCalls, 0);
    expect(observer.pushCount, 0);
  });

  testWidgets('support reply opens support screen only once on rapid tap',
      (tester) async {
    final notifications = _FakeNotificationsService();
    var supportOpenCount = 0;
    NotificationNavigationService.debugOpenSupportOverride =
        (_, __) async => supportOpenCount += 1;
    final context = await _pumpHarness(
      tester,
      notifications: notifications,
    );

    unawaited(
      NotificationNavigationService.handleNotificationTap(
        context,
        _supportNotification(),
      ),
    );
    unawaited(
      NotificationNavigationService.handleNotificationTap(
        context,
        _supportNotification(),
      ),
    );
    await tester.pumpAndSettle();

    expect(notifications.markPersonalReadCalls, 1);
    expect(supportOpenCount, 1);
  });

  testWidgets('pending notification action after auth executes once',
      (tester) async {
    final unauthContext = await _pumpHarness(
      tester,
      auth: _FakeAuthService(isAuthenticatedValue: false),
    );

    await NotificationNavigationService.handleNotificationTap(
      unauthContext,
      _supportNotification(),
    );
    await tester.pumpAndSettle();
    NotificationNavigationService.debugResetState();

    var supportOpenCount = 0;
    NotificationNavigationService.debugOpenSupportOverride =
        (_, __) async => supportOpenCount += 1;
    final notifications = _FakeNotificationsService();
    final authContext = await _pumpHarness(
      tester,
      notifications: notifications,
    );

    await NotificationNavigationService.consumePendingIfPossible(authContext);
    await NotificationNavigationService.consumePendingIfPossible(authContext);
    await tester.pumpAndSettle();

    expect(supportOpenCount, 1);
    expect(notifications.markPersonalReadCalls, 1);
  });

  testWidgets('admin report notification does not open admin screen for user',
      (tester) async {
    var adminOpenCount = 0;
    NotificationNavigationService.debugOpenAdminReportsOverride =
        (_, __) async => adminOpenCount += 1;
    final context = await _pumpHarness(
      tester,
      admin: _FakeAdminService(isAdmin: false),
    );

    await NotificationNavigationService.handleNotificationTap(
      context,
      <String, dynamic>{
        'id': 'report-notif-1',
        'type': 'generic',
        'scope': 'personal',
        'payload': <String, dynamic>{
          'actionType': 'admin_report_new',
          'reportId': 'report-1',
        },
      },
    );
    await tester.pumpAndSettle();

    expect(adminOpenCount, 0);
  });

  test(
      'moderation notification with approved status resolves to listing action',
      () {
    final actionType = NotificationNavigationService.actionTypeForNotification(
      <String, dynamic>{
        'type': 'moderation',
        'payload': <String, dynamic>{
          'listingId': 'listing-1',
          'status': 'approved',
        },
      },
    );

    expect(actionType, 'listing_approved');
  });

  testWidgets('listing approved notification opens my listings once',
      (tester) async {
    final notifications = _FakeNotificationsService();
    var listingsOpenCount = 0;
    NotificationNavigationService.debugOpenListingsOverride =
        (_, __) async => listingsOpenCount += 1;
    final context = await _pumpHarness(
      tester,
      notifications: notifications,
    );

    unawaited(
      NotificationNavigationService.handleNotificationTap(
        context,
        <String, dynamic>{
          'id': 'listing-notif-1',
          'type': 'moderation',
          'scope': 'personal',
          'is_read': false,
          'payload': <String, dynamic>{
            'listingId': 'listing-1',
            'status': 'approved',
          },
        },
      ),
    );
    unawaited(
      NotificationNavigationService.handleNotificationTap(
        context,
        <String, dynamic>{
          'id': 'listing-notif-1',
          'type': 'moderation',
          'scope': 'personal',
          'is_read': false,
          'payload': <String, dynamic>{
            'listingId': 'listing-1',
            'status': 'approved',
          },
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(notifications.markPersonalReadCalls, 1);
    expect(listingsOpenCount, 1);
  });
}

Future<BuildContext> _pumpHarness(
  WidgetTester tester, {
  _FakeAuthService? auth,
  _FakeNotificationsService? notifications,
  _FakeSupportService? support,
  _FakeReviewsService? reviews,
  _FakeAdminService? admin,
  _TestNavigatorObserver? observer,
}) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AuthService>.value(
          value: auth ?? _FakeAuthService(),
        ),
        Provider<NotificationsService>.value(
          value: notifications ?? _FakeNotificationsService(),
        ),
        Provider<SupportService>.value(
          value: support ?? _FakeSupportService(),
        ),
        Provider<ReviewsService>.value(
          value: reviews ?? _FakeReviewsService(),
        ),
        Provider<AdminService>.value(
          value: admin ?? _FakeAdminService(isAdmin: false),
        ),
      ],
      child: MaterialApp(
        navigatorObservers: [
          if (observer != null) observer,
        ],
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return capturedContext;
}

Map<String, dynamic> _supportNotification() => <String, dynamic>{
      'id': 'notif-1',
      'type': 'support',
      'scope': 'personal',
      'is_read': false,
      'payload': <String, dynamic>{
        'actionType': 'support_reply',
        'ticketId': 'ticket-1',
      },
    };

class _FakeAuthService extends AuthService {
  _FakeAuthService({
    this.isAuthenticatedValue = true,
  });

  final bool isAuthenticatedValue;

  @override
  bool get isAuthenticated => isAuthenticatedValue;

  @override
  AuthUser? get currentUser => const AuthUser(uid: 'user-1');
}

class _FakeNotificationsService extends NotificationsService {
  int markAllSeenCalls = 0;
  int markPersonalReadCalls = 0;

  @override
  Future<void> markAllSeen(String userId) async {
    markAllSeenCalls += 1;
  }

  @override
  Future<void> markPersonalReadById(String notificationId) async {
    markPersonalReadCalls += 1;
  }
}

class _FakeSupportService extends SupportService {
  final List<String> refreshMessagesCalls = <String>[];

  @override
  Future<List<Map<String, dynamic>>> refreshMessages(String ticketId) async {
    refreshMessagesCalls.add(ticketId);
    return const <Map<String, dynamic>>[];
  }
}

class _FakeReviewsService extends ReviewsService {
  @override
  Future<List<Map<String, dynamic>>> refreshSellerReviews(
      String sellerId) async {
    return <Map<String, dynamic>>[
      <String, dynamic>{'id': 'review-1'},
    ];
  }
}

class _FakeAdminService extends AdminService {
  _FakeAdminService({
    required this.isAdmin,
  });

  final bool isAdmin;

  @override
  Stream<bool> streamIsAdmin(String uid) => Stream<bool>.value(isAdmin);
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
