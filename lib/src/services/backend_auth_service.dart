import 'dart:async';

import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/auth_api.dart';
import 'package:atta/src/services/api/users_api.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/utils/media_url.dart';
import 'package:flutter/foundation.dart';

class PhoneVerificationStartResult {
  final String verificationId;
  final String callToPhone;
  final String callToPhonePretty;
  final String expiresAt;

  const PhoneVerificationStartResult({
    required this.verificationId,
    this.callToPhone = '',
    this.callToPhonePretty = '',
    this.expiresAt = '',
  });

  bool get hasCallToPhone => callToPhone.trim().isNotEmpty;
}

class PhoneVerificationCheckResult {
  final String status;
  final String message;

  const PhoneVerificationCheckResult({
    required this.status,
    required this.message,
  });

  bool get isConfirmed => status == 'confirmed';
  bool get isPending => status == 'pending';
  bool get isExpired => status == 'expired';
}

class BackendAuthService {
  BackendAuthService({
    required AuthApi authApi,
    required UsersApi usersApi,
    required TokenStorage tokenStorage,
  })  : _authApi = authApi,
        _usersApi = usersApi,
        _tokenStorage = tokenStorage;

  final AuthApi _authApi;
  final UsersApi _usersApi;
  final TokenStorage _tokenStorage;
  final StreamController<AuthSessionEvent> _events =
      StreamController<AuthSessionEvent>.broadcast();

  Future<void>? _initialization;
  AuthUser? _currentUser;

  Stream<AuthSessionEvent> get onAuthStateChange => _events.stream;
  AuthUser? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  Future<void> ensureInitialized() {
    return _initialization ??= _restoreSession().catchError((error) {
      _initialization = null;
      throw error;
    });
  }

  Future<void> _restoreSession() async {
    _currentUser = await _tokenStorage.readCurrentUser();
    if (_currentUser == null) {
      return;
    }

    try {
      await me();
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        final refreshed = await _tryRefreshSession();
        if (!refreshed) {
          throw const ApiException(
            'Войдите снова',
            statusCode: 401,
            code: 'session_expired',
          );
        }
        return;
      }
      if (error.isServerUnavailable ||
          error.isNetworkError ||
          error.isTimeout) {
        _debugAuthLog(
          'Auth restore skipped remote profile refresh, using cached session'
          ' status=${error.statusCode} code=${error.code}',
        );
        return;
      }
      rethrow;
    }
  }

  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _authApi.login(email: email, password: password);
    await _consumeAuthPayload(response);
    return me();
  }

  Future<AuthUser> signUp({
    required String email,
    required String password,
    String? displayName,
    String? phone,
  }) async {
    final response = await _authApi.signup(
      email: email,
      password: password,
      displayName: displayName,
      phone: phone,
    );
    await _consumeAuthPayload(response);
    return me();
  }

  Future<AuthUser> me() async {
    late final Map<String, dynamic> response;
    try {
      response = await _authApi.me();
    } on ApiException catch (error) {
      if (!error.isNotFound) rethrow;
      response = await _usersApi.me();
    }
    final rawUser = (response['user'] ?? response) as Map;
    final user = _mergeUser(
      _currentUser,
      _parseUser(rawUser),
      preferServerAdmin: _hasExplicitAdminFlag(rawUser, response),
    );
    _currentUser = user;

    final accessToken = await _tokenStorage.readAccessToken();
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (accessToken != null && refreshToken != null) {
      await _tokenStorage.saveSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        currentUser: user,
      );
    }

    return user;
  }

  Future<void> signOut() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _authApi.logout(refreshToken: refreshToken);
      }
    } finally {
      await _clearSession();
    }
  }

  Future<void> deleteAccount() async {
    await _authApi.deleteAccount();
    await _clearSession();
  }

  Future<void> updateProfile({
    String? displayName,
    String? photoUrl,
  }) async {
    final response = await _usersApi.updateMe({
      if (displayName != null && displayName.trim().isNotEmpty)
        'display_name': displayName.trim(),
      if (photoUrl != null && photoUrl.trim().isNotEmpty)
        'avatar_url': photoUrl.trim(),
      if (photoUrl != null && photoUrl.trim().isNotEmpty)
        'photo_url': photoUrl.trim(),
    });

    final user = _parseUser((response['user'] ?? response) as Map);
    await _replaceCurrentUser(user);
  }

  Future<PhoneVerificationStartResult> startPhoneVerification({
    required String phone,
    required String purpose,
  }) async {
    final response = await _authApi.startPhoneVerification(
      phone: phone,
      purpose: purpose,
    );

    return PhoneVerificationStartResult(
      verificationId: (response['verificationId'] ??
              response['verificationCheckId'] ??
              response['checkId'] ??
              response['check_id'] ??
              '')
          .toString(),
      callToPhone: (response['callToPhone'] ??
              response['callPhone'] ??
              response['phoneToCall'] ??
              response['call_phone'] ??
              response['call_to_phone'] ??
              '')
          .toString(),
      callToPhonePretty: (response['callToPhonePretty'] ??
              response['callPhonePretty'] ??
              response['call_phone_pretty'] ??
              response['call_to_phone_pretty'] ??
              response['callToPhone'] ??
              response['callPhone'] ??
              response['phoneToCall'] ??
              response['call_phone'] ??
              response['call_to_phone'] ??
              '')
          .toString(),
      expiresAt: (response['expiresAt'] ?? '').toString(),
    );
  }

  Future<PhoneVerificationCheckResult> checkPhoneVerification({
    required String phone,
    required String verificationId,
    required String purpose,
  }) async {
    final response = await _authApi.checkPhoneVerification(
      phone: phone,
      verificationId: verificationId,
      purpose: purpose,
    );

    return PhoneVerificationCheckResult(
      status: (response['status'] ?? '').toString(),
      message: (response['message'] ?? '').toString(),
    );
  }

  Future<bool> isPhoneRegistered({
    required String phone,
  }) async {
    final response = await _authApi.checkPhoneRegistration(phone: phone);
    return response['exists'] == true;
  }

  Future<void> signInWithPhone({
    required String phone,
    required String password,
    String verificationCheckId = '',
  }) async {
    _debugAuthLog('Auth phone login request -> /auth/login-phone',
        phone: phone);
    final response = await _authApi.loginPhone(
      phone: phone,
      password: password,
      verificationCheckId: verificationCheckId,
    );
    await _consumeAuthPayload(response);
    await me();
    _debugAuthLog('Auth phone login success -> /auth/login-phone',
        phone: phone);
  }

  Future<void> signUpWithVerifiedPhone({
    required String phone,
    required String password,
    required String displayName,
    required String verificationCheckId,
  }) async {
    _debugAuthLog('Auth phone signup request -> /auth/signup-phone',
        phone: phone);
    final response = await _authApi.signupPhone(
      phone: phone,
      password: password,
      displayName: displayName,
      verificationCheckId: verificationCheckId,
    );
    await _consumeAuthPayload(response);
    await me();
    _debugAuthLog('Auth phone signup success -> /auth/signup-phone',
        phone: phone);
  }

  Future<void> resetPasswordWithVerifiedPhone({
    required String phone,
    required String newPassword,
    required String verificationCheckId,
  }) async {
    _debugAuthLog('Auth phone reset request -> /auth/reset-password-phone',
        phone: phone);
    await _authApi.resetPasswordPhone(
      phone: phone,
      newPassword: newPassword,
      verificationCheckId: verificationCheckId,
    );
    _debugAuthLog('Auth phone reset success -> /auth/reset-password-phone',
        phone: phone);
  }

  Future<void> linkEmailToCurrentUser({
    required String email,
  }) async {
    throw const ApiException(
      'Привязка email через Timeweb backend пока не поддерживается.',
    );
  }

  String userMessageForError(Object error, {bool isSignIn = false}) {
    if (error is ApiException) {
      final raw = error.message.toLowerCase();
      switch (error.code) {
        case 'PHONE_REQUIRED':
          return 'Введите номер телефона';
        case 'PASSWORD_REQUIRED':
          return 'Введите пароль';
        case 'PASSWORD_TOO_SHORT':
          return 'Пароль должен быть не короче 8 символов';
        case 'INVALID_PHONE_OR_PASSWORD':
          return 'Неверный номер телефона или пароль';
        case 'USER_NOT_FOUND':
          return 'На этом номере аккаунта нет';
        case 'ACCOUNT_DISABLED':
          return 'Аккаунт временно недоступен';
      }
      if (error.isNetworkError || error.isTimeout) {
        return 'Не удалось подключиться к серверу. Проверьте интернет.';
      }
      if (error.code == 'SMS_RU_CALLCHECK_FAILED' ||
          error.code == 'SMS_RU_CALL_PHONE_MISSING' ||
          error.code == 'SMS_RU_CALLCHECK_DISABLED' ||
          error.code == 'SMS_RU_API_ID_MISSING' ||
          error.code == 'SMS_RU_UNREACHABLE' ||
          error.code == 'SMS_RU_INVALID_RESPONSE' ||
          error.code == 'SMS_RU_HTTP_ERROR') {
        return 'Подтверждение телефона временно недоступно. Попробуйте позже.';
      }
      if (error.isUnauthorized) {
        return isSignIn
            ? 'Неверный номер телефона или пароль'
            : 'Доступ запрещен';
      }
      if (error.isNotFound) {
        return 'На этом номере аккаунта нет';
      }
      if (raw.contains('user already exists')) {
        return isSignIn
            ? 'Неверный номер телефона или пароль.'
            : 'Пользователь уже существует.';
      }
      if (raw.contains('invalid login credentials')) {
        return 'Неверный номер телефона или пароль';
      }
      if (raw.contains('expired')) {
        return 'Подтверждение номера истекло. Запросите новое.';
      }
      if (raw.contains('at least 8 characters') ||
          raw.contains('не короче 8 символов')) {
        return 'Пароль должен быть не короче 8 символов';
      }
      if (raw.contains('invalid password') ||
          raw.contains('wrong password') ||
          raw.contains('invalid credentials') ||
          raw.contains('invalid login credentials')) {
        return isSignIn
            ? 'Неверный номер телефона или пароль'
            : 'Неверный номер телефона или пароль';
      }
      return 'Попробуйте позже';
    }
    return 'Попробуйте позже';
  }

  Future<bool> _tryRefreshSession() async {
    return refreshSession();
  }

  Future<bool> refreshSession() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _clearSession();
      return false;
    }
    try {
      final response = await _authApi.refresh(refreshToken: refreshToken);
      await _consumeAuthPayload(response);
      try {
        await me();
      } on ApiException catch (error) {
        if (error.isUnauthorized) {
          await _clearSession();
          return false;
        }
        if (error.isNetworkError || error.isTimeout || error.isServerUnavailable) {
          return true;
        }
        rethrow;
      }
      return true;
    } on ApiException catch (_) {
      await _clearSession();
      return false;
    }
  }

  Future<void> expireSession() async {
    await _clearSession();
  }

  Future<AuthUser> _consumeAuthPayload(Map<String, dynamic> response) async {
    final auth =
        Map<String, dynamic>.from((response['auth'] ?? const {}) as Map);
    final rawUser = (response['user'] ?? response) as Map;
    final user = _mergeUser(
      _currentUser,
      _parseUser(rawUser),
      preferServerAdmin: _hasExplicitAdminFlag(rawUser, response),
    );
    final accessToken = (auth['access_token'] ??
            response['access_token'] ??
            response['accessToken'] ??
            response['token'])
        .toString();
    final refreshToken = (auth['refresh_token'] ??
            response['refresh_token'] ??
            response['refreshToken'])
        .toString();

    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw const ApiException('Backend не вернул access/refresh token.');
    }

    await _tokenStorage.saveSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      currentUser: user,
    );

    _currentUser = user;
    _events.add(const AuthSessionEvent(type: AuthSessionEventType.signedIn));
    return user;
  }

  AuthUser _parseUser(Map<dynamic, dynamic> raw) {
    String? pick(dynamic value) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty) return null;
      return text;
    }

    return AuthUser(
      uid: pick(raw['id']) ?? '',
      email: pick(raw['email']),
      displayName: pick(raw['display_name']) ??
          pick(raw['displayName']) ??
          pick(raw['name']),
      phone: pick(raw['phone']) ??
          pick(raw['normalized_phone']) ??
          pick(raw['normalizedPhone']),
      phoneVerified: raw['phoneVerified'] == true ||
          raw['phone_verified'] == true ||
          raw['isPhoneVerified'] == true,
      photoUrl: _cacheBustedAvatarUrl(
        _normalizeAvatarUrl(
          pick(raw['avatar_url']) ??
              pick(raw['avatarUrl']) ??
              pick(raw['photo_url']) ??
              pick(raw['photoUrl']),
        ),
        pick(raw['avatar_updated_at']) ??
            pick(raw['updated_at']) ??
            pick(raw['updatedAt']),
      ),
      isAdmin: raw['isAdmin'] == true ||
          raw['is_admin'] == true ||
          raw['role'] == 'admin',
    );
  }

  String? _normalizeAvatarUrl(String? url) {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return resolvePublicMediaUrl(trimmed, categoryHint: 'avatars').trim();
  }

  Future<void> _replaceCurrentUser(AuthUser user) async {
    final accessToken = await _tokenStorage.readAccessToken();
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (accessToken == null || refreshToken == null) {
      _currentUser = user;
      return;
    }

    _currentUser = _mergeUser(_currentUser, user);
    await _tokenStorage.saveSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      currentUser: _currentUser!,
    );
    _events.add(const AuthSessionEvent(type: AuthSessionEventType.userUpdated));
  }

  AuthUser _mergeUser(
    AuthUser? previous,
    AuthUser next, {
    bool preferServerAdmin = false,
  }) {
    if (previous == null) return next;
    final sameUser = previous.uid.isEmpty ||
        next.uid.isEmpty ||
        previous.uid == next.uid;
    return AuthUser(
      uid: next.uid.isNotEmpty ? next.uid : previous.uid,
      email: _pickPreferred(next.email, previous.email),
      displayName: _pickPreferred(next.displayName, previous.displayName),
      phone: _pickPreferred(next.phone, previous.phone),
      phoneVerified: next.phoneVerified || previous.phoneVerified,
      photoUrl: _pickPreferred(next.photoUrl, previous.photoUrl),
      isAdmin: preferServerAdmin
          ? next.isAdmin
          : sameUser
              ? (next.isAdmin || previous.isAdmin)
              : next.isAdmin,
    );
  }

  bool _hasExplicitAdminFlag(
    Map<dynamic, dynamic> rawUser,
    Map<String, dynamic> response,
  ) {
    return rawUser.containsKey('isAdmin') ||
        rawUser.containsKey('is_admin') ||
        rawUser.containsKey('role') ||
        response.containsKey('isAdmin') ||
        response.containsKey('is_admin') ||
        response.containsKey('role');
  }

  String? _pickPreferred(String? primary, String? fallback) {
    final value = primary?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
    final backup = fallback?.trim();
    if (backup != null && backup.isNotEmpty) {
      return backup;
    }
    return null;
  }

  String? _cacheBustedAvatarUrl(String? url, String? version) {
    final trimmedUrl = url?.trim();
    if (trimmedUrl == null || trimmedUrl.isEmpty) return null;
    final trimmedVersion = version?.trim();
    if (trimmedVersion == null ||
        trimmedVersion.isEmpty ||
        trimmedUrl.contains('v=')) {
      return trimmedUrl;
    }
    final separator = trimmedUrl.contains('?') ? '&' : '?';
    return '$trimmedUrl$separator'
        'v=${Uri.encodeQueryComponent(trimmedVersion)}';
  }

  Future<void> _clearSession() async {
    _currentUser = null;
    await _tokenStorage.clear();
    _events.add(const AuthSessionEvent(type: AuthSessionEventType.signedOut));
  }

  void _debugAuthLog(String message, {String? phone}) {
    if (!kDebugMode) return;
    final suffix = phone == null ? '' : ' phone=${_maskPhone(phone)}';
    debugPrint('$message$suffix');
  }

  String _maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return '***';
    final tail = digits.substring(digits.length - 4);
    return '***$tail';
  }
}
