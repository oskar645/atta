import 'dart:async';

import 'package:atta/src/features/home/main_shell.dart';
import 'package:atta/src/features/home/home_screen.dart';
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

  testWidgets('bottom navigation uses a white background in light theme',
      (tester) async {
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
            pageBuilder: (index, controller) =>
                Text('page:$index', textDirection: TextDirection.ltr),
          ),
        ),
      ),
    );
    await tester.pump();

    final navigationTheme = tester.widget<NavigationBarTheme>(
      find.byType(NavigationBarTheme),
    );
    expect(navigationTheme.data.backgroundColor, Colors.white);
    expect(navigationTheme.data.height, 64);
    expect(navigationTheme.data.indicatorColor, Colors.transparent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected bottom navigation icon scales without moving layout',
      (tester) async {
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
            pageBuilder: (index, controller) =>
                Text('page:$index', textDirection: TextDirection.ltr),
          ),
        ),
      ),
    );
    await tester.pump();

    List<AnimatedScale> scalesFor(IconData icon) => tester
        .widgetList<AnimatedScale>(find.byType(AnimatedScale))
        .where((scale) =>
            scale.child is Icon && (scale.child as Icon).icon == icon)
        .toList();

    expect(scalesFor(Icons.search), isNotEmpty);
    expect(
        scalesFor(Icons.search).every((scale) => scale.scale == 1.15), isTrue);
    expect(
      scalesFor(Icons.search).every(
        (scale) =>
            scale.duration == const Duration(milliseconds: 220) &&
            scale.curve == Curves.easeOutCubic,
      ),
      isTrue,
    );
    expect(scalesFor(Icons.favorite_border).single.scale, 1);
    final searchCenterBefore =
        tester.getCenter(find.byIcon(Icons.search).first);
    final favoriteCenterBefore =
        tester.getCenter(find.byIcon(Icons.favorite_border));

    await tester.tap(find.text('Избранное'));
    await tester.pump();

    expect(scalesFor(Icons.search).every((scale) => scale.scale == 1), isTrue);
    expect(scalesFor(Icons.favorite).single.scale, 1.15);
    expect(
        tester.getCenter(find.byIcon(Icons.search).first), searchCenterBefore);
    expect(tester.getCenter(find.byIcon(Icons.favorite)), favoriteCenterBefore);

    await tester.pump(const Duration(milliseconds: 220));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'search tab preserves feed position when reselected from another tab',
      (tester) async {
    var scrollToTopCalls = 0;

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
              if (index == 0) {
                return _HomeTabProbe(
                  controller: controller,
                  onScrollToTop: () => scrollToTopCalls++,
                );
              }
              return Text('page:$index', textDirection: TextDirection.ltr);
            },
          ),
        ),
      ),
    );

    await tester.pump();

    await tester.tap(find.text('Избранное'));
    await tester.pump();
    await tester.tap(find.text('Поиск'));
    await tester.pump();

    expect(scrollToTopCalls, 0);

    await tester.tap(find.text('Поиск'));
    await tester.pump();

    expect(scrollToTopCalls, 1);
  });
}

class _HomeTabProbe extends StatefulWidget {
  const _HomeTabProbe({
    required this.controller,
    required this.onScrollToTop,
  });

  final HomeTabController controller;
  final VoidCallback onScrollToTop;

  @override
  State<_HomeTabProbe> createState() => _HomeTabProbeState();
}

class _HomeTabProbeState extends State<_HomeTabProbe> {
  @override
  void initState() {
    super.initState();
    widget.controller.attach(scrollToTop: widget.onScrollToTop);
  }

  @override
  void didUpdateWidget(covariant _HomeTabProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.onScrollToTop != widget.onScrollToTop) {
      oldWidget.controller.detach();
      widget.controller.attach(scrollToTop: widget.onScrollToTop);
    }
  }

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Text('page:0', textDirection: TextDirection.ltr);
  }
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
