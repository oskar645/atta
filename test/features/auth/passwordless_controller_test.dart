import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';

import 'package:atta/src/features/auth/passwordless_controller.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePasswordlessAuth extends AuthService {
  FakePasswordlessAuth({required this.now});
  final DateTime Function() now;
  final phones = <String>[];
  final challenges = <String>[];
  final registrations = <Map<String, dynamic>>[];
  bool authenticated = false;
  bool registrationRequired = false;
  Object? startError;
  Object? checkError;
  Object? completeError;
  String status = 'pending';
  num? retryAfterSeconds;
  Duration ttl = const Duration(minutes: 5);
  Completer<Map<String, dynamic>>? pendingCheck;
  Completer<Map<String, dynamic>>? pendingStart;
  bool Function()? lastIsActive;

  @override
  bool get isAuthenticated => authenticated;

  @override
  Future<Map<String, dynamic>> startPasswordless(
      {required String phone}) async {
    phones.add(phone);
    if (startError != null) throw startError!;
    if (pendingStart != null) return pendingStart!.future;
    return {
      'challenge': 'opaque-challenge',
      'callToPhone': '78005553535',
      'expiresAt': now().add(ttl).toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>> checkPasswordless({
    required String challenge,
    required bool Function() isActive,
  }) async {
    challenges.add(challenge);
    lastIsActive = isActive;
    if (checkError != null) throw checkError!;
    if (pendingCheck != null) return pendingCheck!.future;
    if (registrationRequired) {
      return {
        'status': 'registration_required',
        'registrationToken': 'opaque-registration',
        'expiresAt': now().add(const Duration(minutes: 2)).toIso8601String()
      };
    }
    if (status == 'confirmed' && isActive()) {
      authenticated = true;
      return {'auth': <String, dynamic>{}};
    }
    return {'status': status, 'retryAfterSeconds': retryAfterSeconds};
  }

  @override
  Future<void> completePasswordless({
    required String registrationToken,
    required String displayName,
    required bool acceptedLegal,
    required bool acceptedPersonalData,
    required bool Function() isActive,
  }) async {
    registrations.add({
      'registrationToken': registrationToken,
      'displayName': displayName,
      'acceptedLegal': acceptedLegal,
      'acceptedPersonalData': acceptedPersonalData
    });
    if (completeError != null) throw completeError!;
    if (isActive()) authenticated = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  void scenario(
      void Function(FakeAsync, FakePasswordlessAuth, PasswordlessController)
          run) {
    fakeAsync((async) {
      final clock = async.getClock(DateTime.utc(2026, 9, 21));
      final auth = FakePasswordlessAuth(now: clock.now);
      final flow = PasswordlessController(auth, now: clock.now);
      try {
        run(async, auth, flow);
      } finally {
        flow.dispose();
      }
    });
  }

  void start(FakeAsync async, PasswordlessController flow) {
    unawaited(flow.start('8 (928) 123-45-67'));
    async.flushMicrotasks();
  }

  test(
      'existing user: start and check reach normal signed in state without lifecycle events',
      () {
    scenario((async, auth, flow) {
      auth.status = 'confirmed';
      start(async, flow);
      expect(auth.phones, ['79281234567']);
      expect(flow.secondsLeft, 300);
      async.elapse(PasswordlessController.pollInterval);
      expect(flow.step, PasswordlessStep.signedIn);
      expect(auth.isAuthenticated, true);
      expect(auth.challenges, ['opaque-challenge']);
      async.elapse(const Duration(seconds: 30));
      expect(auth.challenges, hasLength(1));
    });
  });

  test(
      'new user: name and both consents required; complete retries the same token',
      () {
    scenario((async, auth, flow) {
      auth.registrationRequired = true;
      start(async, flow);
      async.elapse(PasswordlessController.pollInterval);
      expect(flow.step, PasswordlessStep.name);
      unawaited(flow.complete(
          displayName: 'Anna',
          acceptedLegal: true,
          acceptedPersonalData: false));
      async.flushMicrotasks();
      expect(auth.registrations, isEmpty);
      auth.completeError = const ApiException('lost response', code: 'network');
      unawaited(flow.complete(
          displayName: ' Anna ',
          acceptedLegal: true,
          acceptedPersonalData: true));
      async.flushMicrotasks();
      expect(flow.step, PasswordlessStep.name);
      auth.completeError = null;
      unawaited(flow.complete(
          displayName: ' Anna ',
          acceptedLegal: true,
          acceptedPersonalData: true));
      async.flushMicrotasks();
      expect(flow.step, PasswordlessStep.signedIn);
      expect(auth.registrations, hasLength(2));
      expect(auth.registrations[0], auth.registrations[1]);
      expect(auth.registrations.last['displayName'], 'Anna');
      expect(auth.phones, hasLength(1));
    });
  });

  for (final error in [
    const ApiException('offline', code: 'network'),
    const ApiException('timeout', code: 'timeout'),
    const ApiException('unavailable', statusCode: 503),
  ]) {
    test('temporary $error retries same challenge, never starts a replacement',
        () {
      scenario((async, auth, flow) {
        auth.checkError = error;
        start(async, flow);
        async.elapse(const Duration(seconds: 5));
        expect(flow.step, PasswordlessStep.call);
        auth.checkError = null;
        auth.status = 'confirmed';
        async.elapse(const Duration(seconds: 10));
        expect(auth.challenges, ['opaque-challenge', 'opaque-challenge']);
        expect(auth.phones, hasLength(1));
        expect(flow.step, PasswordlessStep.signedIn);
      });
    });
  }

  test('check honors Retry-After and resumes automatically', () {
    scenario((async, auth, flow) {
      auth.checkError = const ApiException('limited',
          statusCode: 429, retryAfter: Duration(seconds: 70));
      start(async, flow);
      async.elapse(const Duration(seconds: 5));
      auth.checkError = null;
      async.elapse(const Duration(seconds: 69));
      expect(auth.challenges, hasLength(1));
      async.elapse(const Duration(seconds: 1));
      expect(auth.challenges, hasLength(2));
    });
  });

  test(
      'successive pending responses honor each server delay on the same challenge',
      () {
    scenario((async, auth, flow) {
      auth.retryAfterSeconds = 12;
      start(async, flow);
      async.elapse(const Duration(seconds: 5));
      expect(auth.challenges, hasLength(1));
      async.elapse(const Duration(milliseconds: 11999));
      expect(auth.challenges, hasLength(1));
      auth.retryAfterSeconds = 8;
      async.elapse(const Duration(milliseconds: 1));
      expect(auth.challenges, hasLength(2));
      async.elapse(const Duration(milliseconds: 7999));
      expect(auth.challenges, hasLength(2));
      async.elapse(const Duration(milliseconds: 1));
      expect(auth.challenges, List.filled(3, 'opaque-challenge'));
      expect(auth.phones, hasLength(1));
    });
  });

  test('start honors rate limit, including after changing the phone', () {
    scenario((async, auth, flow) {
      auth.startError = const ApiException('limited', statusCode: 429);
      start(async, flow);
      flow.changePhone();
      start(async, flow);
      expect(auth.phones, hasLength(1));
      async.elapse(const Duration(seconds: 60));
      auth.startError = null;
      start(async, flow);
      expect(auth.phones, hasLength(2));
    });
  });

  test('polling never overlaps a slow request', () {
    scenario((async, auth, flow) {
      auth.pendingCheck = Completer<Map<String, dynamic>>();
      start(async, flow);
      async.elapse(const Duration(seconds: 50));
      expect(auth.challenges, hasLength(1));
      auth.pendingCheck!.complete({'status': 'pending'});
      async.flushMicrotasks();
      auth.pendingCheck = null;
      async.elapse(const Duration(seconds: 5));
      expect(auth.challenges, hasLength(2));
    });
  });

  test('repeated continue is ignored while start is in flight', () {
    scenario((async, auth, flow) {
      auth.pendingStart = Completer<Map<String, dynamic>>();
      start(async, flow);
      start(async, flow);
      expect(auth.phones, hasLength(1));
    });
  });

  test(
      'changing number invalidates a late check and preserves phone for correction',
      () {
    scenario((async, auth, flow) {
      auth.pendingCheck = Completer<Map<String, dynamic>>();
      start(async, flow);
      async.elapse(const Duration(seconds: 5));
      flow.changePhone();
      expect(auth.lastIsActive!(), false);
      auth.pendingCheck!.complete(
          {'status': 'registration_required', 'registrationToken': 'late'});
      async.flushMicrotasks();
      expect(flow.step, PasswordlessStep.phone);
      expect(flow.phone, '79281234567');
      async.elapse(const Duration(seconds: 30));
      expect(auth.challenges, hasLength(1));
    });
  });

  test('actual expiry stops checks and only explicit retry creates challenge',
      () {
    scenario((async, auth, flow) {
      auth.ttl = const Duration(seconds: 90);
      start(async, flow);
      async.elapse(const Duration(seconds: 89));
      expect(flow.step, PasswordlessStep.call);
      async.elapse(const Duration(seconds: 1));
      expect(flow.step, PasswordlessStep.expired);
      expect(flow.message, 'Время подтверждения истекло');
      expect(auth.phones, hasLength(1));
      start(async, flow);
      expect(auth.phones, hasLength(2));
    });
  });

  test('provider failed does not produce immediate dialer cancellation error',
      () {
    scenario((async, auth, flow) {
      auth.status = 'failed';
      start(async, flow);
      async.elapse(const Duration(seconds: 20));
      expect(flow.step, PasswordlessStep.call);
      expect(flow.message, isNull);
      expect(auth.phones, hasLength(1));
    });
  });

  for (final code in ['ACCOUNT_BLOCKED', 'PHONE_BLOCKED']) {
    test('$code stops polling with safe copy', () {
      scenario((async, auth, flow) {
        auth.checkError =
            ApiException('provider details', statusCode: 401, code: code);
        start(async, flow);
        async.elapse(const Duration(seconds: 30));
        expect(flow.step, PasswordlessStep.blocked);
        expect(flow.message, 'Доступ для этого номера ограничен');
        expect(auth.challenges, hasLength(1));
      });
    });
  }

  test('registration token expiry returns to explicit retry', () {
    scenario((async, auth, flow) {
      auth.registrationRequired = true;
      start(async, flow);
      async.elapse(const Duration(seconds: 125));
      expect(flow.step, PasswordlessStep.expired);
      expect(auth.registrations, isEmpty);
    });
  });
}
