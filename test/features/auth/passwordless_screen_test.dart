import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';

import 'package:atta/src/features/auth/guest_auth_prompt.dart';
import 'package:atta/src/features/auth/passwordless_screen.dart';
import 'package:atta/src/features/auth/terms_screen.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'passwordless_controller_test.dart' show FakePasswordlessAuth;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> mount(WidgetTester tester, FakePasswordlessAuth auth,
      {bool guest = false}) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(Provider<AuthService>.value(
      value: auth,
      child: MaterialApp(
          home: guest ? const _GuestAction() : const PasswordlessScreen()),
    ));
  }

  Future<void> start(WidgetTester tester) async {
    await tester.enterText(
        find.byKey(const ValueKey('passwordless-phone')), '9281234567');
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('Continue releases phone focus while start is pending',
      (tester) async {
    final auth = FakePasswordlessAuth(now: DateTime.now)
      ..pendingStart = Completer<Map<String, dynamic>>();
    await mount(tester, auth);
    await tester.enterText(find.byType(TextField), '9281234567');
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse);
    await dispose(tester);
    auth.pendingStart!.complete({});
    await tester.pump();
  });

  testWidgets('prefix stays visible and shares the phone baseline',
      (tester) async {
    await mount(tester, FakePasswordlessAuth(now: DateTime.now));
    final prefix = find.text('+7');
    expect(prefix, findsOneWidget);
    // Prefix must be painted even while the empty field is unfocused.
    expect(
        tester
            .widget<AnimatedOpacity>(find
                .ancestor(of: prefix, matching: find.byType(AnimatedOpacity))
                .first)
            .opacity,
        1);
    await tester.enterText(find.byType(TextField), '9281234567');
    await tester.pumpAndSettle();
    final prefixBox = tester.renderObject<RenderBox>(prefix);
    final editableBox =
        tester.renderObject<RenderBox>(find.byType(EditableText));
    final prefixBaseline = prefixBox
        .localToGlobal(Offset(
            0,
            prefixBox.getDryBaseline(BoxConstraints.tight(prefixBox.size),
                TextBaseline.alphabetic)!))
        .dy;
    final inputBaseline = editableBox
        .localToGlobal(Offset(
            0,
            editableBox.getDryBaseline(BoxConstraints.tight(editableBox.size),
                TextBaseline.alphabetic)!))
        .dy;
    expect(prefixBaseline, closeTo(inputBaseline, 0.1));
    expect(
        tester.getTopLeft(find.byType(EditableText)).dx -
            tester.getTopRight(prefix).dx,
        closeTo(8, 0.1));
    await tester.enterText(find.byType(TextField), '');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(prefix, findsOneWidget);
    await dispose(tester);
  });

  testWidgets('manual digits and deletion keep immutable country prefix',
      (tester) async {
    final auth = FakePasswordlessAuth(now: DateTime.now);
    await mount(tester, auth);
    await tester.showKeyboard(find.byType(TextField));
    for (final digit in '9281234567'.split('')) {
      final field = tester.widget<TextField>(find.byType(TextField));
      tester.testTextInput.enterText('${field.controller!.text}$digit');
      await tester.pump();
    }
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '928 123-45-67');
    tester.testTextInput.enterText('928 123-45-670');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '928 123-45-67');
    tester.testTextInput.enterText('');
    await tester.pump();
    expect(find.text('+7'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('cancel focused auth and reenter without restoring keyboard',
      (tester) async {
    final auth = FakePasswordlessAuth(now: DateTime.now)..status = 'confirmed';
    await mount(tester, auth, guest: true);
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('Закрытое действие'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.enterText(find.byType(TextField), '9281234567');
      await tester.pump();
      if (attempt == 0) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.text('Продолжить'));
        await tester.pump();
        expect(tester.testTextInput.isVisible, isFalse);
        await tester.pump(const Duration(seconds: 5));
      }
      await tester.pumpAndSettle();
      expect(find.byType(PasswordlessScreen), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
    }
    expect(find.text('Действие выполнено'), findsOneWidget);
  });

  for (final input in [
    '9281234567',
    '8 928 123-45-67',
    '7 928 123-45-67',
    '+7 928 123-45-67',
    '(928) 123-45-67'
  ]) {
    testWidgets('phone input $input normalizes behind visual +7',
        (tester) async {
      final auth = FakePasswordlessAuth(now: DateTime.now);
      await mount(tester, auth);
      await tester.enterText(find.byType(TextField), input);
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '928 123-45-67');
      expect(find.text('+7'), findsOneWidget);
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      expect(auth.phones, ['79281234567']);
      expect(find.text('Подтвердите номер'), findsOneWidget);
      expect(
          find.text('Позвоните с номера +7 928 123 45 67 на:'), findsOneWidget);
      expect(find.text('Пароль'), findsNothing);
      expect(find.text('5:00'), findsOneWidget);
      await dispose(tester);
    });
  }

  testWidgets(
      'guest sheet has one entry; successful login resumes original action',
      (tester) async {
    final auth = FakePasswordlessAuth(now: DateTime.now)..status = 'confirmed';
    await mount(tester, auth, guest: true);
    await tester.tap(find.text('Закрытое действие'));
    await tester.pumpAndSettle();
    expect(find.text('Создать аккаунт'), findsNothing);
    expect(find.text('Уже есть аккаунт? Войти'), findsNothing);
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    expect(find.byType(PasswordlessScreen), findsOneWidget);
    await start(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Действие выполнено'), findsOneWidget);
    expect(find.byType(PasswordlessScreen), findsNothing);
  });

  testWidgets('dismissed guest sheet leaves guest and original action intact',
      (tester) async {
    final auth = FakePasswordlessAuth(now: DateTime.now);
    await mount(tester, auth, guest: true);
    await tester.tap(find.text('Закрытое действие'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Гость'), findsOneWidget);
    expect(auth.phones, isEmpty);
  });

  testWidgets('change number and system back return to editable phone',
      (tester) async {
    final auth = FakePasswordlessAuth(now: DateTime.now);
    await mount(tester, auth);
    await start(tester);
    await tester.tap(find.text('Изменить номер'));
    await tester.pumpAndSettle();
    expect(find.text('Войдите по номеру телефона'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '928 123-45-67');
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Войдите по номеру телефона'), findsOneWidget);
    await dispose(tester);
  });

  for (final supported in [true, false]) {
    testWidgets(
        'dialer supported=$supported does not authenticate or fail; polling needs no resumed',
        (tester) async {
      final oldLauncher = UrlLauncherPlatform.instance;
      final launcher = _Launcher(supported: supported);
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = oldLauncher);
      final auth = FakePasswordlessAuth(now: DateTime.now);
      await mount(tester, auth);
      await start(tester);
      await tester.tap(find.text('Позвонить'));
      await tester.pumpAndSettle();
      expect(launcher.calls.first, 'tel:+78005553535');
      expect(auth.isAuthenticated, false);
      expect(find.text('Подтвердите номер'), findsOneWidget);
      expect(find.textContaining('ошибка'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(auth.challenges, ['opaque-challenge']);
      await dispose(tester);
    });
  }

  testWidgets('rapid dialer taps launch once', (tester) async {
    final oldLauncher = UrlLauncherPlatform.instance;
    final launcher = _Launcher(supported: true)..pending = Completer<bool>();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = oldLauncher);
    final auth = FakePasswordlessAuth(now: DateTime.now);
    await mount(tester, auth);
    await start(tester);
    await tester.tap(find.text('Позвонить'));
    await tester.tap(find.text('Позвонить'));
    expect(launcher.calls, hasLength(1));
    launcher.pending!.complete(true);
    await tester.pumpAndSettle();
    expect(auth.isAuthenticated, false);
    await dispose(tester);
  });

  testWidgets('new user sees only name and existing legal links and consents',
      (tester) async {
    final auth = FakePasswordlessAuth(now: DateTime.now)
      ..registrationRequired = true;
    await mount(tester, auth, guest: true);
    await tester.tap(find.text('Закрытое действие'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    await start(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Как вас зовут?'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Пароль'), findsNothing);
    expect(find.text('Email'), findsNothing);
    expect(find.byType(Checkbox), findsNWidgets(2));
    final span = tester
        .widgetList<RichText>(find.byType(RichText))
        .expand((w) => (w.text as TextSpan).children ?? <InlineSpan>[])
        .whereType<TextSpan>()
        .firstWhere((s) => s.text == 'Пользовательское соглашение');
    (span.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(TermsScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Анна');
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Готово'))
            .onPressed,
        isNull);
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(auth.isAuthenticated, true);
    expect(find.byType(PasswordlessScreen), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(auth.registrations.single['displayName'], 'Анна');
    await dispose(tester);
  });

  testWidgets('expired challenge has explicit retry and no automatic start',
      (tester) async {
    final auth = FakePasswordlessAuth(now: DateTime.now)..status = 'expired';
    await mount(tester, auth);
    await start(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Время подтверждения истекло'), findsOneWidget);
    expect(find.text('Попробовать снова'), findsOneWidget);
    expect(auth.phones, hasLength(1));
    await tester.tap(find.text('Попробовать снова'));
    await tester.pumpAndSettle();
    expect(auth.phones, hasLength(2));
    await dispose(tester);
  });
}

class _Launcher extends UrlLauncherPlatform {
  _Launcher({required this.supported});
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  final bool supported;
  final calls = <String>[];
  Completer<bool>? pending;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    calls.add(url);
    if (pending != null) return pending!.future;
    return supported;
  }
}

class _GuestAction extends StatefulWidget {
  const _GuestAction();
  @override
  State<_GuestAction> createState() => _GuestActionState();
}

class _GuestActionState extends State<_GuestAction> {
  bool completed = false;
  @override
  Widget build(BuildContext context) => Scaffold(
          body: Column(children: [
        Text(completed ? 'Действие выполнено' : 'Гость'),
        FilledButton(
            onPressed: () async {
              final authenticated = await promptGuestAuth(context);
              if (mounted) setState(() => completed = authenticated);
            },
            child: const Text('Закрытое действие')),
      ]));
}
