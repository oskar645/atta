import 'dart:async';

import 'package:atta/src/services/auth/pending_passwordless_storage.dart';

import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:flutter/foundation.dart';

enum PasswordlessStep { phone, call, name, expired, blocked, signedIn }

/// Owns one challenge. Dialer/lifecycle events deliberately do not drive auth.
class PasswordlessController extends ChangeNotifier {
  PasswordlessController(this._auth,
      {DateTime Function()? now, PendingPasswordlessStorage? storage})
      : _now = now ?? DateTime.now,
        _storage = storage ?? PendingPasswordlessStorage();

  final PendingPasswordlessStorage _storage;

  final AuthService _auth;
  final DateTime Function() _now;
  static const pollInterval = Duration(seconds: 5);
  PasswordlessStep step = PasswordlessStep.phone;
  String phone = '';
  String callToPhone = '';
  String? message;
  DateTime? expiresAt;
  bool busy = false;
  String _challenge = '';
  String _registrationToken = '';
  DateTime? _notBefore;
  Timer? _poll;
  Timer? _ticker;
  int _epoch = 0;
  bool _disposed = false;

  bool get coolingDown => _notBefore?.isAfter(_now()) ?? false;
  bool get canSubmit => !busy && !coolingDown;
  int get secondsLeft {
    final milliseconds = expiresAt?.difference(_now()).inMilliseconds ?? 0;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  bool _active(int epoch) => !_disposed && epoch == _epoch;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _tick() {
    if ((step == PasswordlessStep.call || step == PasswordlessStep.name) &&
        secondsLeft == 0) {
      _expire();
    }
    _changed();
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> start(String input) async {
    if (!canSubmit ||
        (step != PasswordlessStep.phone && step != PasswordlessStep.expired)) {
      return;
    }
    final normalized = normalizeRuPhoneForApi(input);
    if (normalized.isEmpty) {
      message = 'Введите номер телефона';
      _changed();
      return;
    }
    phone = normalized;
    busy = true;
    message = null;
    final epoch = ++_epoch;
    _poll?.cancel();
    _ensureTicker();
    _changed();
    try {
      final result = await _auth.startPasswordless(phone: phone);
      if (!_active(epoch)) return;
      _challenge = result['challenge']?.toString() ?? '';
      callToPhone = result['callToPhone']?.toString() ?? '';
      expiresAt = DateTime.tryParse(result['expiresAt']?.toString() ?? '');
      if (_challenge.isEmpty || callToPhone.isEmpty || expiresAt == null) {
        throw const FormatException('Invalid passwordless start response');
      }
      phone = result['phone']?.toString() ?? phone;
      _registrationToken = '';
      await _save();
      if (!_active(epoch)) return;
      step = PasswordlessStep.call;
      if (secondsLeft == 0) {
        _expire();
      } else {
        _schedule(pollInterval);
      }
    } catch (error) {
      if (_active(epoch)) _handleError(error);
    } finally {
      if (_active(epoch)) {
        busy = false;
        _changed();
      }
    }
  }

  Future<void> restore() async {
    if (busy || _auth.isAuthenticated) return;
    busy = true;
    final epoch = _epoch;
    _changed();
    try {
      final state = await _storage.read();
      if (!_active(epoch) || state == null || _auth.isAuthenticated) return;
      phone = state['phone'] as String;
      callToPhone = state['callToPhone'] as String;
      _challenge = state['challenge'] as String;
      _registrationToken = state['registrationToken'] as String? ?? '';
      expiresAt = DateTime.parse(state['expiresAt'] as String);
      if (secondsLeft == 0) {
        _expire();
        step = PasswordlessStep.phone;
        message = 'Время подтверждения истекло. Попробуйте снова';
      } else {
        step = _registrationToken.isEmpty
            ? PasswordlessStep.call
            : PasswordlessStep.name;
        _ensureTicker();
        _schedule(Duration.zero);
      }
    } catch (error) {
      if (_active(epoch)) _handleError(error);
    } finally {
      if (_active(epoch)) {
        busy = false;
        _changed();
      }
    }
  }

  Future<void> _save() => _storage.save({
        'challenge': _challenge,
        'phone': phone,
        'callToPhone': callToPhone,
        'expiresAt': expiresAt!.toIso8601String(),
        if (_registrationToken.isNotEmpty)
          'registrationToken': _registrationToken,
      });

  void _clearPending() {
    unawaited(_storage.clear().catchError((Object _) {
      if (!_disposed) {
        message = 'Не удалось очистить подтверждение. Попробуйте снова';
        _changed();
      }
    }));
  }

  void _schedule(Duration delay) {
    _poll?.cancel();
    if (_disposed || step != PasswordlessStep.call) return;
    _poll = Timer(delay, _check);
  }

  Future<void> _check() async {
    if (_disposed || step != PasswordlessStep.call || busy) return;
    if (secondsLeft == 0) {
      _expire();
      _changed();
      return;
    }
    if (coolingDown) {
      _schedule(_notBefore!.difference(_now()));
      return;
    }
    busy = true;
    final epoch = _epoch;
    var delay = pollInterval;
    try {
      final result = await _auth.checkPasswordless(
        challenge: _challenge,
        isActive: () => _active(epoch),
      );
      if (!_active(epoch)) return;
      if (result['auth'] is Map && _auth.isAuthenticated) {
        _clearPending();
        step = PasswordlessStep.signedIn;
        message = null;
      } else if (result['status'] == 'registration_required') {
        _registrationToken = result['registrationToken']?.toString() ?? '';
        expiresAt = DateTime.tryParse(result['expiresAt']?.toString() ?? '');
        if (_registrationToken.isEmpty || expiresAt == null) {
          throw const FormatException('Invalid registration response');
        }
        await _save();
        if (!_active(epoch)) return;
        step = PasswordlessStep.name;
        message = null;
        if (secondsLeft == 0) _expire();
      } else if (result['status'] == 'expired') {
        _expire();
      } else {
        // A failed provider check is not proof that the user's call was
        // cancelled. Keep the current challenge until its actual deadline.
        message = null;
        final seconds = num.tryParse('${result['retryAfterSeconds']}');
        if (seconds != null && seconds.isFinite && seconds > 0) {
          final requested = Duration(milliseconds: (seconds * 1000).ceil());
          if (requested > delay) delay = requested;
        }
        _notBefore = _now().add(delay);
      }
    } catch (error) {
      if (!_active(epoch)) return;
      _handleError(error);
      delay = coolingDown
          ? _notBefore!.difference(_now())
          : const Duration(seconds: 10);
    } finally {
      if (_active(epoch)) {
        busy = false;
        if (_active(epoch)) _schedule(delay);
        _changed();
      }
    }
  }

  Future<void> complete({
    required String displayName,
    required bool acceptedLegal,
    required bool acceptedPersonalData,
  }) async {
    if (!canSubmit || step != PasswordlessStep.name) return;
    if (secondsLeft == 0) {
      _expire();
      _changed();
      return;
    }
    if (displayName.trim().isEmpty || !acceptedLegal || !acceptedPersonalData) {
      return;
    }
    busy = true;
    message = null;
    final epoch = _epoch;
    _changed();
    try {
      await _auth.completePasswordless(
        registrationToken: _registrationToken,
        displayName: displayName.trim(),
        acceptedLegal: acceptedLegal,
        acceptedPersonalData: acceptedPersonalData,
        isActive: () => _active(epoch),
      );
      if (_active(epoch) && _auth.isAuthenticated) {
        _clearPending();
        step = PasswordlessStep.signedIn;
      }
    } catch (error) {
      if (_active(epoch)) _handleError(error);
    } finally {
      if (_active(epoch)) {
        busy = false;
        _changed();
      }
    }
  }

  void changePhone() {
    busy = false;
    _clearPending();
    ++_epoch;
    _poll?.cancel();
    _challenge = '';
    _registrationToken = '';
    expiresAt = null;
    message = null;
    step = PasswordlessStep.phone;
    _changed();
  }

  void _expire() {
    busy = false;
    ++_epoch;
    _clearPending();
    _poll?.cancel();
    step = PasswordlessStep.expired;
    message = 'Время подтверждения истекло';
  }

  void _handleError(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 403 ||
          error.code == 'ACCOUNT_BLOCKED' ||
          error.code == 'PHONE_BLOCKED') {
        _poll?.cancel();
        step = PasswordlessStep.blocked;
        message = 'Доступ для этого номера ограничен';
        return;
      }
      if (error.code == 'PASSWORDLESS_INVALID') {
        _expire();
        return;
      }
      if (error.statusCode == 429) {
        _notBefore =
            _now().add(error.retryAfter ?? const Duration(seconds: 60));
        message = 'Слишком много попыток. Подождите немного';
        return;
      }
      if (error.isNetworkError || error.isTimeout) {
        message = 'Проверьте подключение к интернету';
        return;
      }
    }
    message = 'Сервис временно недоступен. Попробуйте позже';
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    _poll?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
