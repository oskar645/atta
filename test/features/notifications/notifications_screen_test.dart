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
  });

  final List<Map<String, dynamic>> globalItems;

  @override
  Stream<List<Map<String, dynamic>>> streamGlobal() =>
      Stream<List<Map<String, dynamic>>>.value(globalItems);

  @override
  Stream<List<Map<String, dynamic>>> streamPersonal(String userId) =>
      Stream<List<Map<String, dynamic>>>.value(const <Map<String, dynamic>>[]);

  @override
  Stream<int> streamUnreadGlobalCount(String userId) => Stream<int>.value(0);

  @override
  Stream<int> streamUnreadPersonalCount(String userId) => Stream<int>.value(0);

  @override
  List<Map<String, dynamic>> peekGlobal() => globalItems;

  @override
  List<Map<String, dynamic>> peekPersonal(String userId) =>
      const <Map<String, dynamic>>[];

  @override
  Future<void> preload(String userId) async {}

  @override
  Future<void> markAllSeen(String userId) async {}
}
