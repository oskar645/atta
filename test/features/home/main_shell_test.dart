import 'dart:async';

import 'package:atta/src/features/home/main_shell.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/main_shell_controller.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('startup does not eagerly build private tabs', (tester) async {
    final buildCounts = <int, int>{};

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ChatService>.value(value: _FakeChatService()),
          Provider<AdminService>.value(value: _FakeAdminService()),
          Provider<NotificationsService>.value(
            value: _FakeNotificationsService(),
          ),
          Provider<PresenceService>.value(value: _FakePresenceService()),
          ChangeNotifierProvider<MainShellController>(
            create: (_) => MainShellController(),
          ),
        ],
        child: MaterialApp(
          home: MainShell(
            pageBuilder: (index, controller) {
              buildCounts[index] = (buildCounts[index] ?? 0) + 1;
              return Text('page:$index', textDirection: TextDirection.ltr);
            },
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('page:0'), findsOneWidget);
    expect(find.text('page:1'), findsNothing);
    expect(find.text('page:2'), findsNothing);
    expect(find.text('page:3'), findsNothing);
    expect(find.text('page:4'), findsNothing);
    expect(buildCounts, {0: 1});

    await tester.tap(find.text('Избранное'));
    await tester.pump();

    expect(find.text('page:1'), findsOneWidget);
    expect(buildCounts[1], 1);
    expect(buildCounts.containsKey(2), isFalse);
    expect(buildCounts.containsKey(3), isFalse);
    expect(buildCounts.containsKey(4), isFalse);
  });
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'user-1');

  @override
  bool get isAuthenticated => true;
}

class _FakeChatService extends ChatService {
  @override
  Stream<int> streamUnreadTotal(String uid) => Stream<int>.value(0);
}

class _FakeAdminService extends AdminService {
  @override
  Stream<bool> streamIsAdmin(String uid) => Stream<bool>.value(false);

  @override
  Stream<bool> streamNeedsAttention({bool refreshOnListen = false}) =>
      Stream<bool>.value(false);
}

class _FakeNotificationsService extends NotificationsService {
  @override
  Stream<int> streamUnreadSavedSearchCount(String userId) =>
      Stream<int>.value(0);
}

class _FakePresenceService extends PresenceService {
  @override
  Future<void> setOnline({
    required String uid,
    required bool isOnline,
  }) async {}

  @override
  Future<void> heartbeat(String uid) async {}
}
