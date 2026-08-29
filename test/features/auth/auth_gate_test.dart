import 'dart:async';

import 'package:atta/src/features/auth/auth_gate.dart';
import 'package:atta/src/features/auth/login_screen.dart';
import 'package:atta/src/services/auth_service.dart';
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
        child: const MaterialApp(
          home: AuthGate(
            bootstrapTimeout: Duration(milliseconds: 1),
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

  testWidgets('unauthenticated fallback opens registration mode first',
      (tester) async {
    final auth = _FakeAuthService();

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
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Регистрация'), findsOneWidget);
    expect(find.text('Уже есть аккаунт? Войти'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-phone-field')), findsNothing);
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
    await tester.tap(find.text('Уже есть аккаунт? Войти'));
    await tester.pumpAndSettle();

    expect(find.text('Вход'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-phone-field')), findsOneWidget);
  });
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
