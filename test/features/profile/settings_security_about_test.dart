import 'package:atta/src/features/auth/legal_document_screen.dart';
import 'package:atta/src/features/profile/about_app_screen.dart';
import 'package:atta/src/features/profile/security_screen.dart';
import 'package:atta/src/features/profile/settings_screen.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/backend_auth_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('settings keeps profile save and opens incomplete security',
      (tester) async {
    await tester.pumpWidget(_settingsApp());
    await tester.pumpAndSettle();

    expect(find.text('Сохранить'), findsOneWidget);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Сменить пароль'), findsNothing);
    expect(find.text('Правовая информация'), findsNothing);
    expect(find.text('Новое объявление'), findsNothing);

    await tester.tap(find.text('Безопасность'));
    await tester.pumpAndSettle();

    expect(find.byType(SecurityScreen), findsOneWidget);
    expect(find.text('+7 999 123 45 67'), findsOneWidget);
    expect(find.text('Подтверждён ✓'), findsOneWidget);
    expect(find.text('Не добавлен'), findsOneWidget);
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
    expect(find.text('Email для восстановления доступа подключён'),
        findsOneWidget);
  });

  testWidgets('settings asks to confirm an unverified recovery email',
      (tester) async {
    await tester.pumpWidget(_settingsApp(
      email: 'pending@gmail.com',
      emailVerified: false,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Подтвердите email для восстановления доступа'),
        findsOneWidget);
  });

  testWidgets('settings saves name without phone', (tester) async {
    final auth = _FakeAuthService();
    final profile = _FakeProfileService();
    await tester.pumpWidget(_settingsApp(auth: auth, profile: profile));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Телефон'), findsNothing);
    var saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-name')),
    );
    expect(saveButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Новое имя');
    await tester.pump();
    saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-name')),
    );
    expect(saveButton.onPressed, isNotNull);

    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(profile.lastUpdate, {
      'display_name': 'Новое имя',
      'name': 'Новое имя',
    });
    saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-name')),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('settings keeps changed name enabled after save error',
      (tester) async {
    final profile = _FakeProfileService(updateError: Exception('offline'));
    await tester.pumpWidget(_settingsApp(profile: profile));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Новое имя');
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('Ошибка:'), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-name')),
    );
    expect(saveButton.onPressed, isNotNull);
  });

  testWidgets('settings stays usable with a long name on a small screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_settingsApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Очень длинное имя пользователя для проверки маленького экрана',
    );
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final buttonSize = tester.getSize(
      find.byKey(const ValueKey('save-name')),
    );
    expect(buttonSize.height, 42);
    expect(buttonSize.width, lessThan(288));
  });

  testWidgets('phone changes through CallCheck and refreshes security',
      (tester) async {
    final auth = _FakeAuthService();
    final profile = _FakeProfileService();
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AuthService>.value(value: auth),
        Provider<ProfileService>.value(value: profile),
      ],
      child: const MaterialApp(home: SecurityScreen()),
    ));

    await tester.tap(find.byKey(const ValueKey('change-phone')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('new-phone')), '988 765-43-21');
    await tester.tap(find.byKey(const ValueKey('start-phone-change')));
    await tester.pumpAndSettle();

    expect(auth.startedPurpose, 'change_phone');
    expect(auth.startedPhone, '79887654321');
    await tester.tap(find.byKey(const ValueKey('check-phone-change')));
    await tester.pumpAndSettle();

    expect(profile.lastUpdate, {
      'phone': '79887654321',
      'verificationCheckId': 'change-check-1',
    });
    expect(auth.checkedPurpose, 'change_phone');
    expect(find.byType(SecurityScreen), findsOneWidget);
    expect(find.text('+7 988 765 43 21'), findsOneWidget);
  });

  testWidgets('occupied phone has a clear error and keeps old phone',
      (tester) async {
    final auth = _FakeAuthService();
    final profile = _FakeProfileService(
      updateError: const ApiException(
        'Phone already exists',
        code: 'PHONE_ALREADY_IN_USE',
      ),
    );
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AuthService>.value(value: auth),
        Provider<ProfileService>.value(value: profile),
      ],
      child: const MaterialApp(home: ChangePhoneScreen()),
    ));

    await tester.enterText(
        find.byKey(const ValueKey('new-phone')), '988 765-43-21');
    await tester.tap(find.byKey(const ValueKey('start-phone-change')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('check-phone-change')));
    await tester.pumpAndSettle();

    expect(find.text('Этот номер уже привязан к другому аккаунту.'),
        findsOneWidget);
    expect(auth.phone, '+79991234567');
  });

  testWidgets('phone verification network error is understandable',
      (tester) async {
    final auth = _FakeAuthService(
      startError: const ApiException('offline', code: 'network'),
    );
    await tester.pumpWidget(Provider<AuthService>.value(
      value: auth,
      child: const MaterialApp(home: ChangePhoneScreen()),
    ));

    await tester.enterText(
        find.byKey(const ValueKey('new-phone')), '988 765-43-21');
    await tester.tap(find.byKey(const ValueKey('start-phone-change')));
    await tester.pumpAndSettle();

    expect(find.text('Не удалось подключиться к серверу. Проверьте интернет.'),
        findsOneWidget);
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

Widget _settingsApp({
  String? email,
  bool emailVerified = false,
  _FakeAuthService? auth,
  _FakeProfileService? profile,
}) {
  return MultiProvider(
    providers: [
      Provider<AuthService>.value(
          value: auth ??
              _FakeAuthService(
                email: email,
                emailVerified: emailVerified,
              )),
      Provider<ProfileService>.value(value: profile ?? _FakeProfileService()),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

class _FakeAuthService extends AuthService {
  _FakeAuthService({
    this.email,
    this.emailVerified = false,
    this.startError,
  });

  final String? email;
  final bool emailVerified;
  final Object? startError;
  int recoveryStarts = 0;
  String phone = '+79991234567';
  String? startedPhone;
  String? startedPurpose;
  String? checkedPurpose;

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
  Future<void> updateAuthMetadata(
      {String? displayName, String? photoUrl}) async {}

  @override
  Future<PhoneVerificationStartResult> startPhoneVerification({
    required String phone,
    required String purpose,
  }) async {
    if (startError != null) throw startError!;
    startedPhone = phone;
    startedPurpose = purpose;
    return const PhoneVerificationStartResult(
      verificationId: 'change-check-1',
      callToPhone: '78005553535',
      callToPhonePretty: '+7 800 555-35-35',
    );
  }

  @override
  Future<PhoneVerificationCheckResult> checkPhoneVerification({
    required String phone,
    required String verificationId,
    required String purpose,
  }) async {
    checkedPurpose = purpose;
    return const PhoneVerificationCheckResult(
      status: 'confirmed',
      message: '',
    );
  }

  @override
  Future<AuthUser?> syncCurrentUserFromProfile(
    String uid,
    Map<String, dynamic> profile,
  ) async {
    phone = profile['phone']?.toString() ?? phone;
    return currentUser;
  }

  @override
  AuthUser? get currentUser => AuthUser(
        uid: 'user-1',
        displayName: 'ATTA User',
        phone: phone,
        phoneVerified: true,
        email: email,
        emailVerified: emailVerified,
      );

  @override
  Future<bool> getMarketingConsent() async => false;
}

class _FakeProfileService extends ProfileService {
  _FakeProfileService({this.updateError});

  final Object? updateError;
  Map<String, dynamic>? lastUpdate;

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

  @override
  Future<Map<String, dynamic>> updateProfile(
    String uid,
    Map<String, dynamic> data,
  ) async {
    if (updateError != null) throw updateError!;
    lastUpdate = Map<String, dynamic>.from(data);
    return {
      'id': uid,
      'display_name': 'ATTA User',
      'phone': data['phone'] ?? '+79991234567',
      'phone_verified': true,
    };
  }
}
