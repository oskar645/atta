import 'package:atta/src/features/auth/legal_document_screen.dart';
import 'package:atta/src/features/profile/about_app_screen.dart';
import 'package:atta/src/features/profile/security_screen.dart';
import 'package:atta/src/features/profile/settings_screen.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('settings keeps profile save and opens incomplete security',
      (tester) async {
    await tester.pumpWidget(_settingsApp());
    await tester.pumpAndSettle();

    expect(find.text('Сохранить изменения'), findsOneWidget);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Сменить пароль'), findsNothing);
    expect(find.text('Правовая информация'), findsNothing);
    expect(find.text('Новое объявление'), findsNothing);

    await tester.tap(find.text('Безопасность'));
    await tester.pumpAndSettle();

    expect(find.byType(SecurityScreen), findsOneWidget);
    expect(find.text('+7 *** *** ** 67'), findsOneWidget);
    expect(find.text('Подтверждён ✓'), findsOneWidget);
    expect(find.text('Не подключён'), findsOneWidget);
  });

  testWidgets('security only shows complete status for verified email',
      (tester) async {
    await tester.pumpWidget(
      Provider<AuthService>.value(
        value: _FakeAuthService(
          email: 'member@gmail.com',
          emailVerified: true,
        ),
        child: const MaterialApp(home: SecurityScreen()),
      ),
    );

    expect(find.text('m***@gmail.com'), findsOneWidget);
    expect(find.text('Подтверждён ✓'), findsNWidgets(2));
  });

  testWidgets(
      'settings security is green only when phone and email are verified',
      (tester) async {
    await tester.pumpWidget(_settingsApp(
      email: 'member@gmail.com',
      emailVerified: true,
    ));
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Безопасность'));
    expect(title.style?.color, Colors.green.shade700);
    expect(find.text('Телефон и резервный email подтверждены'), findsOneWidget);
  });

  testWidgets('first recovery-email start opens code entry and cooldown timer',
      (tester) async {
    final auth = _FakeAuthService();
    await tester.pumpWidget(Provider<AuthService>.value(
      value: auth,
      child: const MaterialApp(home: RecoveryEmailScreen()),
    ));

    await tester.enterText(find.byType(TextField), ' member@example.com ');
    await tester.tap(find.text('Получить код'));
    await tester.pump();

    expect(auth.recoveryStarts, 1);
    expect(find.byKey(const ValueKey('recovery-email-code')), findsOneWidget);
    expect(find.text('Отправить снова через 60 сек.'), findsOneWidget);

    await tester.tap(find.text('Отправить снова через 60 сек.'));
    await tester.pump();
    expect(auth.recoveryStarts, 1);
  });

  testWidgets('about app contains every existing legal document link',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutAppScreen()));

    const titles = [
      'Пользовательское соглашение',
      'Политика конфиденциальности',
      'Согласие на обработку персональных данных',
      'Маркетинговое согласие',
      'Согласие на распространение персональных данных',
    ];
    for (final title in titles) {
      await tester.scrollUntilVisible(find.text(title), 200);
      expect(find.text(title), findsOneWidget);
    }

    await tester.tap(find.text('Пользовательское соглашение'));
    await tester.pumpAndSettle();
    expect(find.byType(LegalDocumentScreen), findsOneWidget);
    expect(
      find.textContaining('ПОЛЬЗОВАТЕЛЬСКОЕ СОГЛАШЕНИЕ ATTA'),
      findsOneWidget,
    );
  });
}

Widget _settingsApp({String? email, bool emailVerified = false}) {
  return MultiProvider(
    providers: [
      Provider<AuthService>.value(
          value: _FakeAuthService(
        email: email,
        emailVerified: emailVerified,
      )),
      Provider<ProfileService>.value(value: _FakeProfileService()),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

class _FakeAuthService extends AuthService {
  _FakeAuthService({this.email, this.emailVerified = false});

  final String? email;
  final bool emailVerified;
  int recoveryStarts = 0;

  @override
  Future<Map<String, dynamic>> startRecoveryEmail(String email) async {
    recoveryStarts++;
    expect(email, ' member@example.com ');
    return {
      'challengeId': 'challenge-1',
      'maskedEmail': 'm***@example.com',
      'resendAfter': 60,
    };
  }

  @override
  AuthUser? get currentUser => AuthUser(
        uid: 'user-1',
        displayName: 'ATTA User',
        phone: '+79991234567',
        phoneVerified: true,
        email: email,
        emailVerified: emailVerified,
      );

  @override
  Future<bool> getMarketingConsent() async => false;
}

class _FakeProfileService extends ProfileService {
  @override
  Future<Map<String, dynamic>> getProfile(
    String uid, {
    bool forceRefresh = false,
  }) async {
    return {
      'display_name': 'ATTA User',
      'phone': '+79991234567',
    };
  }
}
