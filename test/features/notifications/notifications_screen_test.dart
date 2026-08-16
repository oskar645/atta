import 'dart:async';

import 'package:atta/src/features/notifications/notifications_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  tearDown(() {
    debugNotificationUrlOpener = null;
  });

  test('notification action label matches supported domains', () {
    expect(
      notificationActionLabelForUrl('https://instagram.com/atta'),
      'Открыть в Instagram',
    );
    expect(
      notificationActionLabelForUrl('https://t.me/atta_app'),
      'Открыть в Telegram',
    );
    expect(
      notificationActionLabelForUrl('https://wa.me/79990000000'),
      'Открыть в WhatsApp',
    );
    expect(
      notificationActionLabelForUrl('https://atta.example.com/news'),
      'Открыть ссылку',
    );
  });

  testWidgets('old notification without payload renders without crash',
      (tester) async {
    final notifications = _FakeNotificationsService(
      globalItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'global-1',
          'scope': 'global',
          'title': 'Старая запись',
          'body': 'Только текст',
          'type': 'general',
          'created_at': '2026-07-03T12:00:00.000Z',
        },
      ],
    );

    await tester.pumpWidget(_buildApp(notifications));
    await tester.pumpAndSettle();

    expect(find.text('Старая запись'), findsOneWidget);
    expect(find.text('Только текст'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('action button is hidden when actionUrl is empty',
      (tester) async {
    final notifications = _FakeNotificationsService(
      globalItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'global-1',
          'scope': 'global',
          'title': 'Новость',
          'body': 'Текст',
          'type': 'general',
          'created_at': '2026-07-03T12:00:00.000Z',
          'payload': <String, dynamic>{
            'description': 'Подробности',
          },
        },
      ],
    );

    await tester.pumpWidget(_buildApp(notifications));
    await tester.pumpAndSettle();

    expect(find.text('Открыть ссылку'), findsNothing);
    expect(find.text('Открыть в Telegram'), findsNothing);
  });

  testWidgets('action button opens url only once per tap burst',
      (tester) async {
    final notifications = _FakeNotificationsService(
      globalItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'global-1',
          'scope': 'global',
          'title': 'Новость',
          'body': 'Текст',
          'type': 'general',
          'created_at': '2026-07-03T12:00:00.000Z',
          'payload': <String, dynamic>{
            'actionUrl': 'https://t.me/atta_app',
          },
        },
      ],
    );
    var openCount = 0;
    final completer = Completer<bool>();
    debugNotificationUrlOpener = (_) {
      openCount += 1;
      return completer.future;
    };

    await tester.pumpWidget(_buildApp(notifications));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Открыть в Telegram'));
    await tester.pump();
    await tester.tap(find.text('Открыть в Telegram'));
    await tester.pump();

    expect(openCount, 1);

    completer.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('personal unread dot is visible for unread personal notification',
      (tester) async {
    final notifications = _FakeNotificationsService(
      globalItems: const <Map<String, dynamic>>[],
      personalItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'personal-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Ответ поддержки',
          'body': 'Мы ответили на ваш вопрос',
          'type': 'support',
          'created_at': '2026-07-03T12:00:00.000Z',
          'is_read': false,
        },
      ],
    );

    await tester.pumpWidget(_buildApp(notifications));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('personal_tab_unread_dot')),
      findsOneWidget,
    );
    expect(notifications.markAllSeenCalls, 0);
  });

  testWidgets('personal unread dot remains until personal tab is opened',
      (tester) async {
    final notifications = _FakeNotificationsService(
      globalItems: const <Map<String, dynamic>>[],
      personalItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'personal-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Ответ поддержки',
          'body': 'Мы ответили на ваш вопрос',
          'type': 'support',
          'created_at': '2026-07-03T12:00:00.000Z',
          'is_read': false,
        },
      ],
    );

    await tester.pumpWidget(_buildApp(notifications));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('personal_tab_unread_dot')),
      findsOneWidget,
    );
    expect(notifications.markAllSeenCalls, 0);
  });

  testWidgets('personal unread dot is hidden for general-only notification',
      (tester) async {
    final notifications = _FakeNotificationsService(
      globalItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'global-1',
          'scope': 'global',
          'title': 'Общая новость',
          'body': 'Текст',
          'type': 'general',
          'created_at': '2026-07-03T12:00:00.000Z',
          'is_read': false,
        },
      ],
    );

    await tester.pumpWidget(_buildApp(notifications));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('personal_tab_unread_dot')),
      findsNothing,
    );
  });

  testWidgets('personal unread dot clears after personal tab is seen',
      (tester) async {
    final notifications = _FakeNotificationsService(
      globalItems: const <Map<String, dynamic>>[],
      personalItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'personal-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Личное сообщение',
          'body': 'Текст',
          'type': 'generic',
          'created_at': '2026-07-03T12:00:00.000Z',
          'is_read': false,
        },
      ],
    );

    await tester.pumpWidget(_buildApp(notifications));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('personal_tab_unread_dot')),
      findsOneWidget,
    );

    await tester.tap(find.text('Личные'));
    await tester.pumpAndSettle();

    expect(notifications.markAllSeenCalls, 1);
    expect(
      find.byKey(const ValueKey('personal_tab_unread_dot')),
      findsNothing,
    );
  });

  testWidgets(
      'personal unread dot clears after delayed seen-all retry succeeds',
      (tester) async {
    final notifications = _FakeNotificationsService(
      globalItems: const <Map<String, dynamic>>[],
      personalItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'personal-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Личное сообщение',
          'body': 'Текст',
          'type': 'generic',
          'created_at': '2026-07-03T12:00:00.000Z',
          'is_read': false,
        },
      ],
    )..markAllSeenCompleter = Completer<void>();

    await tester.pumpWidget(_buildApp(notifications));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Личные'));
    await tester.pump();

    expect(notifications.markAllSeenCalls, 1);
    expect(
      find.byKey(const ValueKey('personal_tab_unread_dot')),
      findsOneWidget,
    );

    notifications.markAllSeenCompleter!.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('personal_tab_unread_dot')),
      findsNothing,
    );
  });

  testWidgets('personal unread dot stays while other personal unread remains',
      (tester) async {
    final notifications = _FakeNotificationsService(
      globalItems: const <Map<String, dynamic>>[],
      personalItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'personal-1',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Личное 1',
          'body': 'Текст',
          'type': 'generic',
          'created_at': '2026-07-03T12:00:00.000Z',
          'is_read': false,
        },
        <String, dynamic>{
          'id': 'personal-2',
          'scope': 'personal',
          'user_id': 'user-1',
          'title': 'Личное 2',
          'body': 'Текст',
          'type': 'generic',
          'created_at': '2026-07-03T12:01:00.000Z',
          'is_read': false,
        },
      ],
      unreadPersonalAfterMarkAllSeen: 1,
    );

    await tester.pumpWidget(_buildApp(notifications));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Личные'));
    await tester.pumpAndSettle();

    expect(notifications.markAllSeenCalls, 1);
    expect(
      find.byKey(const ValueKey('personal_tab_unread_dot')),
      findsOneWidget,
    );
  });

  testWidgets('notifications screen does not subscribe to bell badge count',
      (tester) async {
    final notifications = _FakeNotificationsService(
      globalItems: const <Map<String, dynamic>>[],
      personalItems: const <Map<String, dynamic>>[],
    );

    await tester.pumpWidget(_buildApp(notifications));
    await tester.pumpAndSettle();

    expect(notifications.bellBadgeStreamListenCount, 0);
  });
}

Widget _buildApp(_FakeNotificationsService notifications) {
  return MultiProvider(
    providers: [
      Provider<AuthService>.value(value: _FakeAuthService()),
      Provider<AdminService>.value(value: _FakeAdminService()),
      Provider<NotificationsService>.value(value: notifications),
    ],
    child: const MaterialApp(home: NotificationsScreen()),
  );
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'user-1');
}

class _FakeAdminService extends AdminService {
  @override
  Stream<bool> streamIsAdmin(String uid) => Stream<bool>.value(false);
}

class _FakeNotificationsService extends NotificationsService {
  _FakeNotificationsService({
    required this.globalItems,
    List<Map<String, dynamic>>? personalItems,
    this.unreadPersonalAfterMarkAllSeen = 0,
  }) : personalItems = personalItems ?? <Map<String, dynamic>>[];

  final List<Map<String, dynamic>> globalItems;
  final List<Map<String, dynamic>> personalItems;
  final int unreadPersonalAfterMarkAllSeen;
  final StreamController<void> _personalUpdates =
      StreamController<void>.broadcast();
  int markAllSeenCalls = 0;
  int bellBadgeStreamListenCount = 0;
  Completer<void>? markAllSeenCompleter;

  @override
  Stream<List<Map<String, dynamic>>> streamGlobal() =>
      Stream<List<Map<String, dynamic>>>.value(globalItems);

  @override
  Stream<List<Map<String, dynamic>>> streamPersonal(String userId) =>
      Stream<List<Map<String, dynamic>>>.multi((controller) {
        void emit() {
          controller.add(List<Map<String, dynamic>>.from(personalItems));
        }

        emit();
        final sub = _personalUpdates.stream.listen((_) => emit());
        controller.onCancel = sub.cancel;
      });

  @override
  Stream<int> streamUnreadGlobalCount(String userId) => Stream<int>.value(0);

  @override
  Stream<int> streamUnreadBadgeCount(String userId) =>
      Stream<int>.multi((controller) {
        bellBadgeStreamListenCount += 1;
        controller.add(0);
      });

  @override
  Stream<int> streamUnreadPersonalCount(String userId) =>
      Stream<int>.multi((controller) {
        void emit() {
          controller.add(
            personalItems.where((row) => row['is_read'] != true).length,
          );
        }

        emit();
        final sub = _personalUpdates.stream.listen((_) => emit());
        controller.onCancel = sub.cancel;
      });

  @override
  List<Map<String, dynamic>> peekGlobal() => globalItems;

  @override
  List<Map<String, dynamic>> peekPersonal(String userId) =>
      List<Map<String, dynamic>>.from(personalItems);

  @override
  Future<void> preload(String userId) async {}

  @override
  Future<void> markAllSeen(String userId) async {
    markAllSeenCalls += 1;
    if (markAllSeenCompleter != null) {
      await markAllSeenCompleter!.future;
      markAllSeenCompleter = null;
    }
    var unreadLeft = unreadPersonalAfterMarkAllSeen;
    for (final row in personalItems.reversed) {
      if (unreadLeft > 0) {
        row['is_read'] = false;
        unreadLeft -= 1;
        continue;
      }
      row['is_read'] = true;
    }
    _personalUpdates.add(null);
  }
}
