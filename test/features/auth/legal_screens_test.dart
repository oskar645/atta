import 'package:atta/src/features/auth/legal_texts.dart';
import 'package:atta/src/features/auth/login_screen.dart';
import 'package:atta/src/features/auth/privacy_screen.dart';
import 'package:atta/src/features/auth/terms_screen.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/backend_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('user agreement opens as before from registration flow',
      (tester) async {
    final launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;

    await tester.pumpWidget(_buildApp());

    await tester.tap(find.text('Нет аккаунта? Создать аккаунт'));
    await tester.pumpAndSettle();
    await _tapSpanText(tester, 'Пользовательское соглашение');
    await tester.pumpAndSettle();

    expect(find.byType(TermsScreen), findsOneWidget);
    expect(find.text('Пользовательское соглашение'), findsWidgets);
    expect(find.textContaining('ПОЛЬЗОВАТЕЛЬСКОЕ СОГЛАШЕНИЕ ATTA'),
        findsOneWidget);
    expect(launcher.launchCalls, 0);
  });

  testWidgets('privacy policy opens as before from registration flow',
      (tester) async {
    final launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;

    await tester.pumpWidget(_buildApp());

    await tester.tap(find.text('Нет аккаунта? Создать аккаунт'));
    await tester.pumpAndSettle();
    await _tapSpanText(
      tester,
      'Политикой конфиденциальности',
    );
    await tester.pumpAndSettle();

    expect(find.byType(PrivacyScreen), findsOneWidget);
    expect(find.text('Политика конфиденциальности'), findsWidgets);
    expect(
      find.textContaining(
        'ПОЛИТИКА КОНФИДЕНЦИАЛЬНОСТИ\nИ ОБРАБОТКИ ПЕРСОНАЛЬНЫХ ДАННЫХ ATTA',
      ),
      findsOneWidget,
    );
    expect(launcher.launchCalls, 0);
  });

  test('terms text includes moderation and user responsibility sections', () {
    expect(attaTermsText, contains('8. МОДЕРАЦИЯ'));
    expect(attaTermsText, contains('7. ЗАПРЕЩЁННЫЕ МАТЕРИАЛЫ И ДЕЙСТВИЯ'));
    expect(attaTermsText, contains('10. ОТЗЫВЫ И ЖАЛОБЫ'));
    expect(attaTermsText, contains('4. БЕЗОПАСНОСТЬ АККАУНТА'));
    expect(attaTermsText, contains('13. ВНУТРЕННИЙ БАЛАНС И БОНУСЫ'));
  });

  test('privacy text includes data and communications sections', () {
    expect(attaPrivacyText, contains('3. КАТЕГОРИИ ДАННЫХ'));
    expect(attaPrivacyText, contains('5. ПУБЛИЧНЫЕ ДАННЫЕ'));
    expect(attaPrivacyText, contains('7. СООБЩЕНИЯ И ПОДДЕРЖКА'));
    expect(attaPrivacyText, contains('8. МОДЕРАЦИЯ'));
    expect(attaPrivacyText, contains('14. ПРАВА ПОЛЬЗОВАТЕЛЯ'));
  });

  testWidgets('registration has two required consent checkboxes',
      (tester) async {
    await tester.pumpWidget(_buildApp());

    await tester.tap(find.text('Нет аккаунта? Создать аккаунт'));
    await tester.pumpAndSettle();

    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsNWidgets(2));
    expect(find.textContaining('рекламные и маркетинговые сообщения'),
        findsNothing);

    Checkbox checkbox = tester.widget<Checkbox>(checkboxes.at(0));
    expect(checkbox.value, isFalse);

    await tester.tap(checkboxes.at(0));
    await tester.pumpAndSettle();

    checkbox = tester.widget<Checkbox>(checkboxes.at(0));
    expect(checkbox.value, isTrue);

    final personalData = tester.widget<Checkbox>(checkboxes.at(1));
    expect(personalData.value, isFalse);
  });
}

Widget _buildApp() {
  return Provider<AuthService>.value(
    value: _FakeAuthService(),
    child: const MaterialApp(home: LoginScreen()),
  );
}

Future<void> _tapSpanText(WidgetTester tester, String text) async {
  final richTexts = tester.widgetList<RichText>(find.byType(RichText));
  for (final richText in richTexts) {
    final recognizer = _findTapRecognizer(richText.text, text);
    if (recognizer != null) {
      recognizer.onTap?.call();
      return;
    }
  }
  fail('Не найден tappable span с текстом: $text');
}

TapGestureRecognizer? _findTapRecognizer(InlineSpan span, String text) {
  if (span is TextSpan) {
    if ((span.text ?? '').trim() == text &&
        span.recognizer is TapGestureRecognizer) {
      return span.recognizer as TapGestureRecognizer;
    }
    final children = span.children ?? const <InlineSpan>[];
    for (final child in children) {
      final recognizer = _findTapRecognizer(child, text);
      if (recognizer != null) return recognizer;
    }
  }
  return null;
}

class _FakeAuthService extends AuthService {
  @override
  bool get useTimewebBackend => true;

  @override
  Future<bool> isPhoneRegistered({required String phone}) async {
    return false;
  }

  @override
  Future<PhoneVerificationStartResult> startPhoneVerification({
    required String phone,
    required String purpose,
  }) async {
    return const PhoneVerificationStartResult(
      verificationId: 'verification-1',
      callToPhone: '+7 999 111-22-33',
    );
  }
}

class _FakeUrlLauncher extends UrlLauncherPlatform {
  int launchCalls = 0;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchCalls += 1;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
