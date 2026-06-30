import 'package:atta/src/features/auth/login_screen.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/backend_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'timeweb login flow does not require legacy SDK initialization',
    (tester) async {
      final auth = _FakeAuthService();

      await tester.pumpWidget(
        Provider<AuthService>.value(
          value: auth,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      expect(find.text('Добро пожаловать'), findsOneWidget);
      expect(find.text('Продолжить'), findsOneWidget);
    },
  );

  testWidgets(
    'existing phone calls check-registration and opens password screen',
    (tester) async {
      final auth = _FakeAuthService(
        registeredPhones: <String>{'79281234567'},
      );

      await tester.pumpWidget(
        Provider<AuthService>.value(
          value: auth,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Номер телефона').first,
        '928 123 45 67',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
      await tester.pumpAndSettle();

      expect(auth.checkedPhones, <String>['79281234567']);
      expect(auth.startedVerificationPhones, isEmpty);
      expect(auth.loginPhoneCalls, 0);
      expect(find.widgetWithText(TextField, 'Пароль'), findsOneWidget);
      expect(find.text('Войти'), findsOneWidget);
    },
  );

  testWidgets(
    'login-phone sends phone and password without phone start',
    (tester) async {
      final auth = _FakeAuthService(
        registeredPhones: <String>{'79281234567'},
      );

      await tester.pumpWidget(
        Provider<AuthService>.value(
          value: auth,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Номер телефона').first,
        '928 123 45 67',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Пароль'),
        'secret123',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle();

      expect(auth.startedVerificationPhones, isEmpty);
      expect(auth.loginPhoneCalls, 1);
      expect(auth.lastLoginPhone, '79281234567');
      expect(auth.lastLoginPassword, 'secret123');
    },
  );

  testWidgets(
    'login-phone is not submitted without password',
    (tester) async {
      final auth = _FakeAuthService(
        registeredPhones: <String>{'79281234567'},
      );

      await tester.pumpWidget(
        Provider<AuthService>.value(
          value: auth,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Номер телефона').first,
        '928 123 45 67',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.widgetWithText(
        FilledButton,
        'Войти',
      ));
      expect(button.onPressed, isNull);
      expect(auth.loginPhoneCalls, 0);
    },
  );

  testWidgets(
    'login-phone button stays disabled until password has 8 chars',
    (tester) async {
      final auth = _FakeAuthService(
        registeredPhones: <String>{'79281234567'},
      );

      await tester.pumpWidget(
        Provider<AuthService>.value(
          value: auth,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Номер телефона').first,
        '928 123 45 67',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Пароль'),
        'secret7',
      );
      await tester.pump();

      var button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Войти'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Пароль должен быть не короче 8 символов'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Пароль'),
        'secret78',
      );
      await tester.pump();

      button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Войти'),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets(
    'login-phone 400 shows russian error',
    (tester) async {
      final auth = _FakeAuthService(
        registeredPhones: <String>{'79281234567'},
        signInError: const ApiException(
          'Bad request',
          statusCode: 400,
          code: 'INVALID_PHONE_OR_PASSWORD',
        ),
      );

      await tester.pumpWidget(
        Provider<AuthService>.value(
          value: auth,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Номер телефона').first,
        '928 123 45 67',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Пароль'),
        'secret123',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Неверный номер телефона или пароль'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'unknown phone shows no account message and does not start verification',
    (tester) async {
      final auth = _FakeAuthService();

      await tester.pumpWidget(
        Provider<AuthService>.value(
          value: auth,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Номер телефона').first,
        '928 123 45 67',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('На этом номере аккаунта нет'), findsOneWidget);
      expect(auth.startedVerificationPhones, isEmpty);
      expect(auth.loginPhoneCalls, 0);
    },
  );

  testWidgets(
    'registration flow calls phone start verification',
    (tester) async {
      final auth = _FakeAuthService();

      await tester.pumpWidget(
        Provider<AuthService>.value(
          value: auth,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      await tester.tap(find.text('Нет аккаунта? Создать аккаунт'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Имя пользователя'),
        'Иван',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Пароль'),
        'secret123',
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Номер телефона'),
        '928 123 45 67',
      );
      await tester.pump();
      await tester
          .tap(find.widgetWithText(FilledButton, 'Подтвердить номер телефона'));
      await tester.pumpAndSettle();

      expect(auth.checkedPhones, contains('79281234567'));
      expect(auth.startedVerificationPhones, <String>['79281234567']);
      expect(find.text('Подтвердите номер'), findsOneWidget);
    },
  );
}

class _FakeAuthService extends AuthService {
  _FakeAuthService({
    Set<String>? registeredPhones,
    this.signInError,
  }) : _registeredPhones = registeredPhones ?? <String>{};

  final Set<String> _registeredPhones;
  final Object? signInError;
  final List<String> checkedPhones = <String>[];
  final List<String> startedVerificationPhones = <String>[];
  int loginPhoneCalls = 0;
  String? lastLoginPhone;
  String? lastLoginPassword;

  @override
  bool get useTimewebBackend => true;

  @override
  Future<bool> isPhoneRegistered({required String phone}) async {
    checkedPhones.add(phone);
    return _registeredPhones.contains(phone);
  }

  @override
  Future<PhoneVerificationStartResult> startPhoneVerification({
    required String phone,
    required String purpose,
  }) async {
    startedVerificationPhones.add(phone);
    return const PhoneVerificationStartResult(
      verificationId: 'verification-1',
      callToPhone: '+7 999 111-22-33',
    );
  }

  @override
  Future<void> signInWithPhone({
    required String phone,
    required String password,
    String verificationCheckId = '',
  }) async {
    if (signInError != null) {
      throw signInError!;
    }
    loginPhoneCalls += 1;
    lastLoginPhone = phone;
    lastLoginPassword = password;
  }
}
