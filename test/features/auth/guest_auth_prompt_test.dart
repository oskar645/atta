import 'dart:async';

import 'package:atta/src/features/auth/account_recovery_screen.dart';
import 'package:atta/src/features/auth/guest_auth_prompt.dart';
import 'package:atta/src/features/auth/legal_document_screen.dart';
import 'package:atta/src/features/auth/public_support_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> mountAndOpen(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(const MaterialApp(home: _PromptHost()));
    await tester.tap(find.text('Открыть вход'));
    await tester.pumpAndSettle();
  }

  testWidgets('mobile guest auth is compact and closes', (tester) async {
    const screenSize = Size(390, 844);
    await mountAndOpen(tester, size: screenSize);

    final bottomSheet = find.byType(BottomSheet);
    expect(bottomSheet, findsOneWidget);
    expect(
      tester.getSize(bottomSheet).height,
      lessThan(screenSize.height * 0.75),
    );
    expect(
      tester.getBottomLeft(bottomSheet).dy,
      closeTo(screenSize.height, 0.1),
    );
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(
      find.text('Войдите, чтобы пользоваться всеми возможностями ATTA'),
      findsOneWidget,
    );
    expect(find.text('Войти по звонку'), findsOneWidget);
    expect(find.text('Бесплатный звонок вместо SMS'), findsOneWidget);
    expect(find.text('Войти по почте'), findsOneWidget);
    expect(find.text('Пришлём код на электронную почту'), findsOneWidget);
    expect(find.text('Нет доступа к номеру?'), findsOneWidget);
    expect(find.text('Нужна помощь?'), findsOneWidget);
    final legalNotice = tester.widget<RichText>(
      find.byKey(const ValueKey('guest-auth-legal-notice')),
    );
    expect(
      legalNotice.text.toPlainText(),
      'Авторизуясь на сайте, Вы принимаете условия '
      'пользовательского соглашения и политики конфиденциальности',
    );
    expect(legalNotice.textAlign, TextAlign.center);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('guest-auth-legal-notice')))
          .width,
      greaterThanOrEqualTo(screenSize.width - 40),
    );
    expect(find.byKey(const ValueKey('guest_auth_sheet')), findsOneWidget);
    expect(find.text('App Store'), findsNothing);
    expect(find.text('Google Play'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('small mobile sheet scrolls without overflow', (tester) async {
    const screenSize = Size(320, 480);
    await mountAndOpen(tester, size: screenSize);

    final bottomSheet = find.byType(BottomSheet);
    expect(tester.getSize(bottomSheet).height, lessThan(screenSize.height));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byKey(const ValueKey('guest_auth_sheet')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('guest-auth-legal-notice')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('help, recovery and legal links keep their existing routes',
      (tester) async {
    await mountAndOpen(tester);

    await tester.tap(
      find.byKey(const ValueKey('guest-auth-account-recovery')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AccountRecoveryScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('guest-auth-public-support')));
    await tester.pumpAndSettle();
    expect(find.byType(PublicSupportScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    final legalNotice = tester.widget<RichText>(
      find.byKey(const ValueKey('guest-auth-legal-notice')),
    );
    final legalSpans = (legalNotice.text as TextSpan).children!;
    final termsSpan = legalSpans
        .whereType<TextSpan>()
        .singleWhere((span) => span.text == 'пользовательского соглашения');
    final privacySpan = legalSpans
        .whereType<TextSpan>()
        .singleWhere((span) => span.text == 'политики конфиденциальности');

    (termsSpan.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();
    expect(
      tester.widget<LegalDocumentScreen>(find.byType(LegalDocumentScreen)).kind,
      LegalDocumentKind.terms,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    (privacySpan.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();
    expect(
      tester.widget<LegalDocumentScreen>(find.byType(LegalDocumentScreen)).kind,
      LegalDocumentKind.privacy,
    );
  });
}

class _PromptHost extends StatelessWidget {
  const _PromptHost();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => unawaited(promptGuestAuth(context)),
            child: const Text('Открыть вход'),
          ),
        ),
      );
}
