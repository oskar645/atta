import 'dart:async';

import 'package:atta/src/features/auth/auth_gate.dart';
import 'package:atta/src/features/auth/passwordless_controller.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth/pending_passwordless_storage.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'passwordless_controller_test.dart' show FakePasswordlessAuth;

class RestartAuth extends FakePasswordlessAuth {
  RestartAuth() : super(now: DateTime.now);
  @override
  Future<void> ensureInitialized() async {}
  @override
  Stream<AuthSessionEvent> get onAuthStateChange => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final result in [
    'pending',
    'existing',
    'new',
    'name',
    'expired',
    'offline'
  ]) {
    test('cold restart restores $result using the same secure record', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime.now());
        final firstAuth = FakePasswordlessAuth(now: clock.now);
        final first = PasswordlessController(firstAuth, now: clock.now);
        unawaited(first.start('89281234567'));
        async.flushMicrotasks();
        if (result == 'name') {
          firstAuth.registrationRequired = true;
          async.elapse(PasswordlessController.pollInterval);
          expect(first.step, PasswordlessStep.name);
        }
        // Disposing the old process must not delete the durable record.
        first.dispose();
        if (result == 'expired') async.elapse(const Duration(minutes: 6));
        final auth = FakePasswordlessAuth(now: clock.now)
          ..status = result == 'existing' ? 'confirmed' : 'pending'
          ..registrationRequired = result == 'new';
        if (result == 'offline') {
          auth.checkError = const ApiException('offline', code: 'network');
        }
        final restored = PasswordlessController(auth, now: clock.now);
        unawaited(restored.restore());
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        expect(auth.phones, isEmpty);
        expect(restored.phone, '79281234567');
        expect(restored.callToPhone, '78005553535');
        expect(
            restored.step,
            switch (result) {
              'existing' => PasswordlessStep.signedIn,
              'new' || 'name' => PasswordlessStep.name,
              'expired' => PasswordlessStep.phone,
              _ => PasswordlessStep.call,
            });
        expect(
            auth.challenges,
            result == 'name' || result == 'expired'
                ? isEmpty
                : ['opaque-challenge']);
        if (result == 'offline') {
          auth.checkError = null;
          auth.registrationRequired = true;
          async.elapse(const Duration(seconds: 10));
          expect(restored.step, PasswordlessStep.name);
          expect(auth.challenges, ['opaque-challenge', 'opaque-challenge']);
        }
        if (restored.step == PasswordlessStep.name) {
          unawaited(restored.complete(
              displayName: 'Anna',
              acceptedLegal: true,
              acceptedPersonalData: true));
          async.flushMicrotasks();
          expect(auth.registrations.single['registrationToken'],
              'opaque-registration');
          expect(restored.step, PasswordlessStep.signedIn);
        }
        Map<String, dynamic>? saved;
        unawaited(
            PendingPasswordlessStorage().read().then((value) => saved = value));
        async.flushMicrotasks();
        expect(saved, result == 'pending' ? isNotNull : isNull);
        restored.dispose();
      });
    });
  }

  test('explicit change phone defeats a late response and clears restart state',
      () {
    fakeAsync((async) {
      final auth = FakePasswordlessAuth(now: DateTime.now);
      final flow = PasswordlessController(auth);
      unawaited(flow.start('89281234567'));
      async.flushMicrotasks();
      auth.pendingCheck = Completer<Map<String, dynamic>>();
      async.elapse(PasswordlessController.pollInterval);
      flow.changePhone();
      auth.pendingCheck!.complete({
        'status': 'registration_required',
        'registrationToken': 'late',
        'expiresAt':
            DateTime.now().add(const Duration(minutes: 2)).toIso8601String()
      });
      async.flushMicrotasks();
      flow.dispose();
      final restored = PasswordlessController(auth);
      unawaited(restored.restore());
      async.flushMicrotasks();
      expect(restored.step, PasswordlessStep.phone);
      expect(auth.phones, hasLength(1));
      restored.dispose();
    });
  });

  for (final registration in [false, true]) {
    test('killed awaiting check response replays registration=$registration',
        () {
      fakeAsync((async) {
        final firstAuth = FakePasswordlessAuth(now: DateTime.now);
        final first = PasswordlessController(firstAuth);
        unawaited(first.start('89281234567'));
        async.flushMicrotasks();
        firstAuth.pendingCheck = Completer<Map<String, dynamic>>();
        async.elapse(PasswordlessController.pollInterval);
        first.dispose();
        // The server has confirmed the call, but its response never reached
        // the old app. The new instance only has the original challenge.
        final auth = FakePasswordlessAuth(now: DateTime.now)
          ..registrationRequired = registration
          ..status = 'confirmed';
        final restored = PasswordlessController(auth);
        unawaited(restored.restore());
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        expect(auth.phones, isEmpty);
        expect(auth.challenges, ['opaque-challenge']);
        expect(restored.step,
            registration ? PasswordlessStep.name : PasswordlessStep.signedIn);
        firstAuth.pendingCheck!.complete({'status': 'pending'});
        async.flushMicrotasks();
        restored.dispose();
      });
    });
  }

  for (final authenticated in [false, true]) {
    testWidgets(
        'startup resumes pending only when authenticated=$authenticated',
        (tester) async {
      await PendingPasswordlessStorage().save({
        'challenge': 'opaque-challenge',
        'phone': '79281234567',
        'callToPhone': '78005553535',
        'registrationToken': 'opaque-registration',
        'expiresAt':
            DateTime.now().add(const Duration(minutes: 2)).toIso8601String(),
      });
      final auth = RestartAuth()..authenticated = authenticated;
      await tester.pumpWidget(Provider<AuthService>.value(
        value: auth,
        child: MaterialApp(
            home: AuthGate(
          authenticatedBuilder: (_) => const Scaffold(body: Text('ACCOUNT')),
          unauthenticatedBuilder: (_) => const Scaffold(body: Text('GUEST')),
        )),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Как вас зовут?'),
          authenticated ? findsNothing : findsOneWidget);
      expect(auth.phones, isEmpty);
      expect(auth.challenges, isEmpty);
      if (!authenticated) {
        await tester.tap(find.text('Изменить номер'));
        await tester.pumpAndSettle();
        expect(await PendingPasswordlessStorage().read(), isNull);
        expect(
            find.byKey(const ValueKey('passwordless-phone')), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
