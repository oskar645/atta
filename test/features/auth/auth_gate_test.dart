import 'dart:async';

import 'package:atta/src/features/auth/auth_gate.dart';
import 'package:atta/src/features/auth/login_screen.dart';
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

  testWidgets('/auth/me is not retriggered by build loop in AuthGate',
      (tester) async {
    final auth = _FakeAuthService();

    await tester.pumpWidget(
      Provider<AuthService>.value(
        value: auth,
        child: MaterialApp(
          home: AuthGate(
            bootstrapTimeout: const Duration(milliseconds: 1),
            unauthenticatedBuilder: (_) => const Scaffold(
              body: Text('GUEST_HOME'),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(auth.ensureInitializedCalls, 1);
  });

  testWidgets('bootstrap timeout stops spinner and shows retry message',
      (tester) async {
    final auth = _HangingAuthService();

    await tester.pumpWidget(
      Provider<AuthService>.value(
        value: auth,
        child: const MaterialApp(
          home: AuthGate(
            bootstrapTimeout: Duration(milliseconds: 1),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('Проверьте интернет-соединение и попробуйте снова.'),
      findsOneWidget,
    );
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('startup uses one logo loading state before auth is ready',
      (tester) async {
    final auth = _HangingAuthService();

    await tester.pumpWidget(
      Provider<AuthService>.value(
        value: auth,
        child: const MaterialApp(
          home: AuthGate(
            bootstrapTimeout: Duration(milliseconds: 1),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byKey(const ValueKey('atta_startup_logo')), findsOneWidget);
    expect(find.byKey(const ValueKey('atta_startup_spinner')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 2));
  });

  testWidgets(
      'startup shows cached authenticated UI without waiting for auth init',
      (tester) async {
    final auth = _AuthenticatedHangingAuthService();

    await tester.pumpWidget(
      Provider<AuthService>.value(
        value: auth,
        child: MaterialApp(
          home: AuthGate(
            bootstrapTimeout: const Duration(milliseconds: 1),
            authenticatedBuilder: (_) => const Scaffold(
              body: Text('AUTH_HOME'),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2));

    expect(find.text('AUTH_HOME'), findsOneWidget);
    expect(find.byKey(const ValueKey('atta_startup_logo')), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('unauthenticated fallback opens guest MainShell', (tester) async {
    final auth = _FakeAuthService();

    await tester.pumpWidget(
      _withMainShellProviders(
        auth: auth,
        child: MaterialApp(
          home: AuthGate(
            bootstrapTimeout: const Duration(milliseconds: 1),
            unauthenticatedBuilder: (_) => MainShell(
              guestMode: true,
              pageBuilder: (index, controller) => Text('page:$index'),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final shell = tester.widget<MainShell>(find.byType(MainShell));
    expect(shell.guestMode, isTrue);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byKey(const ValueKey('login-phone-field')), findsNothing);
  });

  testWidgets(
      'authenticated profile logout confirm opens guest home immediately',
      (tester) async {
    final auth = _MutableAuthService(
      const AuthUser(uid: 'user-1', displayName: 'Old User'),
    );
    final shellController = MainShellController(initialIndex: 4);

    await tester.pumpWidget(
      _withMainShellProviders(
        auth: auth,
        shellController: shellController,
        child: MaterialApp(
          home: AuthGate(
            bootstrapTimeout: const Duration(milliseconds: 1),
            authenticatedBuilder: (_) => MainShell(
              pageBuilder: (index, controller) {
                if (index == 4) {
                  return _LogoutProfileProbe(auth: auth);
                }
                return Text('auth-page:$index');
              },
            ),
            unauthenticatedBuilder: (_) => MainShell(
              key: const ValueKey('guest-main-shell'),
              guestMode: true,
              pageBuilder: (index, controller) => Text('guest-page:$index'),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Old User'), findsOneWidget);

    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    expect(find.text('Выйти из аккаунта?'), findsOneWidget);

    await tester.tap(find.text('Да'));
    await tester.pump();
    await tester.pump();

    expect(auth.signOutCalls, 1);
    expect(shellController.selectedIndex, 0);
    expect(find.text('guest-page:0'), findsOneWidget);
    expect(find.text('Old User'), findsNothing);
  });

  testWidgets('default LoginScreen opens login mode', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );

    expect(find.text('Вход'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-phone-field')), findsOneWidget);
    expect(find.text('Нет аккаунта? Создать аккаунт'), findsOneWidget);
  });

  testWidgets('registration mode can switch back to login', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(initialIsLogin: false),
      ),
    );

    expect(find.text('Регистрация'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();

    expect(find.text('Вход'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-phone-field')), findsOneWidget);
  });
}

Widget _withMainShellProviders({
  required AuthService auth,
  MainShellController? shellController,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      Provider<AuthService>.value(value: auth),
      Provider<ChatService>.value(value: _FakeChatService()),
      Provider<AdminService>.value(value: _FakeAdminService()),
      Provider<NotificationsService>.value(
        value: _FakeNotificationsService(),
      ),
      Provider<PresenceService>.value(value: _FakePresenceService()),
      ChangeNotifierProvider<MainShellController>.value(
        value: shellController ?? MainShellController(),
      ),
    ],
    child: child,
  );
}

class _LogoutProfileProbe extends StatelessWidget {
  const _LogoutProfileProbe({required this.auth});

  final AuthService auth;

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Old User'),
          FilledButton(
            onPressed: () => _confirmLogout(context),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}

class _FakeAuthService extends AuthService {
  int ensureInitializedCalls = 0;
  final StreamController<AuthSessionEvent> _authEvents =
      StreamController<AuthSessionEvent>.broadcast();

  @override
  Stream<AuthSessionEvent> get onAuthStateChange => _authEvents.stream;

  @override
  bool get isAuthenticated => false;

  @override
  AuthUser? get currentUser => null;

  @override
  Future<void> ensureInitialized() async {
    ensureInitializedCalls += 1;
  }
}

class _MutableAuthService extends _FakeAuthService {
  _MutableAuthService(this._user);

  AuthUser? _user;
  int signOutCalls = 0;

  @override
  bool get isAuthenticated => _user != null;

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    _user = null;
    _authEvents.add(
      const AuthSessionEvent(type: AuthSessionEventType.signedOut),
    );
  }
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

class _HangingAuthService extends AuthService {
  @override
  bool get isAuthenticated => false;

  @override
  Future<void> ensureInitialized() {
    return Completer<void>().future;
  }
}

class _AuthenticatedHangingAuthService extends _HangingAuthService {
  @override
  bool get isAuthenticated => true;

  @override
  AuthUser? get currentUser => const AuthUser(uid: 'user-1');
}
