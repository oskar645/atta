import 'package:atta/src/features/auth/email_passwordless_screen.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('new email follows email, six-digit code, name and consent flow',
      (tester) async {
    final auth = _EmailAuthService();
    await tester.pumpWidget(
      Provider<AuthService>.value(
        value: auth,
        child: const MaterialApp(home: EmailPasswordlessScreen()),
      ),
    );

    final start = find.byKey(const ValueKey('email-passwordless-start'));
    expect(find.text('Войти по почте'), findsOneWidget);
    expect(
      find.text(
        'Укажите адрес электронной почты, пришлём код для входа.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.text(
              'Укажите адрес электронной почты, пришлём код для входа.',
            ),
          )
          .textAlign,
      TextAlign.center,
    );
    expect(find.byIcon(Icons.mail_outline_rounded), findsNothing);
    expect(tester.widget<FilledButton>(start).onPressed, isNull);

    final emailField = tester.widget<TextField>(
      find.byKey(const ValueKey('email-passwordless-email')),
    );
    expect(emailField.keyboardType, TextInputType.emailAddress);

    await tester.tap(
      find.byKey(const ValueKey('email-passwordless-email')),
    );
    await tester.pump();
    final editable = find.descendant(
      of: find.byKey(const ValueKey('email-passwordless-email')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, true);
    await tester.tap(find.text('Войти по почте'));
    await tester.pump();
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, false);

    await tester.enterText(
      find.byKey(const ValueKey('email-passwordless-email')),
      'member@example.com',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('email-passwordless-start')));
    await tester.pump();

    expect(auth.startedEmail, 'member@example.com');
    expect(find.text('Введите код из письма'), findsOneWidget);
    expect(find.text('Код отправлен на m***@example.com'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('email-passwordless-code')),
      '123456',
    );
    await tester.pump();

    expect(auth.checkedChallenge, 'challenge-1');
    expect(auth.checkedCode, '123456');
    expect(find.text('Как вас зовут?'), findsOneWidget);

    final nameField = tester.widget<TextField>(
      find.byKey(const ValueKey('email-passwordless-name')),
    );
    expect(nameField.keyboardType, TextInputType.name);
    expect(nameField.textCapitalization, TextCapitalization.words);

    await tester.enterText(
      find.byKey(const ValueKey('email-passwordless-name')),
      'ATTA User',
    );
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('email-passwordless-complete')),
    );
    await tester.pump();

    expect(auth.completedToken, 'registration-token');
    expect(auth.completedName, 'ATTA User');
    expect(auth.completedLegal, true);
    expect(auth.completedPersonalData, true);
    expect(auth.isAuthenticated, true);
  });

  testWidgets('existing verified email signs in without asking for a name',
      (tester) async {
    final auth = _EmailAuthService(existingAccount: true);
    await tester.pumpWidget(
      Provider<AuthService>.value(
        value: auth,
        child: const MaterialApp(home: EmailPasswordlessScreen()),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('email-passwordless-email')),
      'member@example.com',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('email-passwordless-start')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('email-passwordless-code')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('email-passwordless-code')),
      '123456',
    );
    await tester.pumpAndSettle();

    expect(auth.currentUser?.uid, 'email-user');
    expect(find.byKey(const ValueKey('email-passwordless-name')), findsNothing);
    expect(auth.completedToken, isNull);
  });
}

class _EmailAuthService extends AuthService {
  _EmailAuthService({this.existingAccount = false});

  final bool existingAccount;
  String? startedEmail;
  String? checkedChallenge;
  String? checkedCode;
  String? completedToken;
  String? completedName;
  bool? completedLegal;
  bool? completedPersonalData;
  AuthUser? _user;

  @override
  AuthUser? get currentUser => _user;

  @override
  bool get isAuthenticated => _user != null;

  @override
  Future<Map<String, dynamic>> startEmailPasswordless(String email) async {
    startedEmail = email;
    return {
      'challengeId': 'challenge-1',
      'maskedEmail': 'm***@example.com',
      'resendAfter': 60,
    };
  }

  @override
  Future<Map<String, dynamic>> checkEmailPasswordless({
    required String challengeId,
    required String code,
    required bool Function() isActive,
  }) async {
    checkedChallenge = challengeId;
    checkedCode = code;
    if (existingAccount) {
      _user = const AuthUser(
        uid: 'email-user',
        email: 'member@example.com',
        emailVerified: true,
        displayName: 'Existing User',
      );
      return {
        'auth': {
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
        },
      };
    }
    return {
      'status': 'registration_required',
      'registrationToken': 'registration-token',
    };
  }

  @override
  Future<void> completeEmailPasswordless({
    required String registrationToken,
    required String displayName,
    required bool acceptedLegal,
    required bool acceptedPersonalData,
    required bool Function() isActive,
  }) async {
    completedToken = registrationToken;
    completedName = displayName;
    completedLegal = acceptedLegal;
    completedPersonalData = acceptedPersonalData;
    _user = const AuthUser(
      uid: 'email-user',
      email: 'member@example.com',
      emailVerified: true,
      displayName: 'ATTA User',
    );
  }
}
