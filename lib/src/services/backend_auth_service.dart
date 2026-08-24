import 'dart:async';
import 'dart:convert';

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
  Future<AuthUser>? _meInFlight;
  Future<bool>? _refreshInFlight;
  Future<AuthUser?>? _resumeRestoreInFlight;
  Future<void>? _privateAuthReadyInFlight;
  AuthUser? _currentUser;
  DateTime? _lastResumeRestoreAt;

  static const Duration _resumeRestoreCooldown = Duration(seconds: 5);

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

    _events.add(const AuthSessionEvent(type: AuthSessionEventType.signedIn));
    _primePrivateAuthReady();
  }

  void _primePrivateAuthReady() {
    if (_currentUser == null || _privateAuthReadyInFlight != null) {
      return;
    }
    late final Future<void> trackedFuture;
    trackedFuture = _ensurePrivateAuthReady().whenComplete(() {
      if (identical(_privateAuthReadyInFlight, trackedFuture)) {
        _privateAuthReadyInFlight = null;
      }
    });
    _privateAuthReadyInFlight = trackedFuture;
    unawaited(trackedFuture);
  }

  Future<void> awaitPrivateAuthReady() async {
    final future = _privateAuthReadyInFlight;
    if (future == null) {
      return;
    }
    try {
      // This is an auth-recovery limit, not an HTTP request timeout. It makes
      // a broken platform/storage future retryable instead of pinning every
      // private screen in a permanent loading state.
      await future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      if (identical(_privateAuthReadyInFlight, future)) {
        _privateAuthReadyInFlight = null;
      }
      throw const ApiException(
        'Восстановление авторизации заняло слишком много времени.',
        code: 'auth_recovery_timeout',
      );
    }
  }

  Future<void> _ensurePrivateAuthReady() async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (!_isJwtExpired(accessToken)) {
      final user = _currentUser;
      if (user != null) {
        _debugAuthLog('Auth ready user=${user.uid}');
      }
      return;
    }
    _debugAuthLog('Auth restore cached session');
    _debugAuthLog('Auth refresh start');
    final refreshed = await refreshSession();
    if (refreshed) {
      final user = _currentUser;
      _debugAuthLog('Auth refresh success');
      if (user != null) {
        _debugAuthLog('Auth ready user=${user.uid}');
      }
      return;
    }
    _debugAuthLog('Auth refresh failed');
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
    final existing = _meInFlight;
    if (existing != null) {
      return existing;
    }

    final future = _loadCurrentUser();
    _meInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_meInFlight, future)) {
        _meInFlight = null;
      }
    }
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

  Future<AuthUser?> syncCurrentUserFromProfile(
    String uid,
    Map<String, dynamic> profile,
  ) async {
    final current = _currentUser;
    final normalizedUid = uid.trim();
    if (current == null ||
        normalizedUid.isEmpty ||
        current.uid != normalizedUid) {
      return current;
    }

    final raw = <String, dynamic>{
      ...profile,
      'id': normalizedUid,
      if (!profile.containsKey('block_status') && current.blockStatus != null)
        'block_status': current.blockStatus!.toJson(),
    };
    await _replaceCurrentUser(_parseUser(raw));
    return _currentUser;
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
    unawaited(
      me().catchError((Object error, StackTrace stackTrace) {
        _debugAuthLog(
          'Auth phone login profile refresh deferred failure: $error',
          phone: phone,
        );
        throw error;
      }),
    );
    _debugAuthLog('Auth phone login success -> /auth/login-phone',
        phone: phone);
  }

  Future<void> signUpWithVerifiedPhone({
    required String phone,
    required String password,
    required String displayName,
    required String verificationCheckId,
    String referralCode = '',
    String referralId = '',
  }) async {
    _debugAuthLog('Auth phone signup request -> /auth/signup-phone',
        phone: phone);
    final response = await _authApi.signupPhone(
      phone: phone,
      password: password,
      displayName: displayName,
      verificationCheckId: verificationCheckId,
      referralCode: referralCode,
      referralId: referralId,
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

  Future<bool> refreshSession() async {
    final existing = _refreshInFlight;
    if (existing != null) {
      return existing;
    }

    final future = _refreshSessionInternal();
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<bool> _refreshSessionInternal() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _clearSession();
      return false;
    }
    try {
      final response = await _authApi.refresh(refreshToken: refreshToken);
      await _consumeAuthPayload(response);
      // Do not call `me()` here. During cold start this refresh is itself the
      // private-auth gate; `me()` is an authorized ApiClient request and would
      // wait for this very gate, creating a self-await deadlock. The refresh
      // payload is already persisted by _consumeAuthPayload, and profile data
      // is revalidated later by the normal foreground/profile refresh path.
      return true;
    } on ApiException catch (error) {
      if (error.isNetworkError ||
          error.isTimeout ||
          error.isServerUnavailable) {
        return _currentUser != null ||
            await _tokenStorage.readCurrentUser() != null;
      }
      await _clearSession();
      return false;
    }
  }

  Future<void> expireSession() async {
    await _clearSession();
  }

  Future<AuthUser?> revalidateCurrentUser() async {
    if (_currentUser == null) {
      return null;
    }
    return restoreSessionOnResume(force: true);
  }

  Future<AuthUser?> restoreSessionOnResume({bool force = false}) async {
    _currentUser ??= await _tokenStorage.readCurrentUser();
    if (_currentUser == null) {
      return null;
    }

    final existing = _resumeRestoreInFlight;
    if (existing != null) {
      return existing;
    }

    final now = DateTime.now();
    final lastRestoreAt = _lastResumeRestoreAt;
    if (!force &&
        lastRestoreAt != null &&
        now.difference(lastRestoreAt) < _resumeRestoreCooldown) {
      return _currentUser;
    }

    final future = _restoreSessionOnResumeInternal();
    _resumeRestoreInFlight = future;
    try {
      final user = await future;
      _lastResumeRestoreAt = DateTime.now();
      return user;
    } finally {
      if (identical(_resumeRestoreInFlight, future)) {
        _resumeRestoreInFlight = null;
      }
    }
  }

  Future<AuthUser?> _restoreSessionOnResumeInternal() async {
    try {
      return await me();
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        final refreshed = await refreshSession();
        if (!refreshed) {
          return _currentUser;
        }
        return _currentUser ?? await me();
      }
      if (error.isNetworkError ||
          error.isTimeout ||
          error.isServerUnavailable) {
        return _currentUser;
      }
      rethrow;
    }
  }

  Future<AuthUser> _consumeAuthPayload(Map<String, dynamic> response) async {
    final auth =
        Map<String, dynamic>.from((response['auth'] ?? const {}) as Map);
    final rawUser =
        Map<dynamic, dynamic>.from((response['user'] ?? response) as Map);
    if (response['block_status'] != null) {
      rawUser['block_status'] = response['block_status'];
    }
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

  bool _isJwtExpired(String? token) {
    final raw = token?.trim() ?? '';
    if (raw.isEmpty) {
      return true;
    }
    final parts = raw.split('.');
    if (parts.length < 2) {
      return false;
    }
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return false;
      }
      final expRaw = decoded['exp'];
      final expSeconds =
          expRaw is num ? expRaw.toInt() : int.tryParse('$expRaw');
      if (expSeconds == null) {
        return false;
      }
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      return expSeconds <= nowSeconds + 15;
    } catch (_) {
      return false;
    }
  }

  Future<AuthUser> _loadCurrentUser() async {
    late final Map<String, dynamic> response;
    try {
      response = await _authApi.me();
    } on ApiException catch (error) {
      if (!error.isNotFound) rethrow;
      response = await _usersApi.me();
    }
    final rawUser =
        Map<dynamic, dynamic>.from((response['user'] ?? response) as Map);
    if (response['block_status'] != null) {
      rawUser['block_status'] = response['block_status'];
    }
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
      referralCode: pick(raw['referralCode']) ?? pick(raw['referral_code']),
      blockStatus: raw['block_status'] is Map
          ? AuthBlockStatus.fromJson(raw['block_status'] as Map)
          : null,
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
    final sameUser =
        previous.uid.isEmpty || next.uid.isEmpty || previous.uid == next.uid;
    return AuthUser(
      uid: next.uid.isNotEmpty ? next.uid : previous.uid,
      email: _pickPreferred(next.email, previous.email),
      displayName: _pickPreferred(next.displayName, previous.displayName),
      phone: _pickPreferred(next.phone, previous.phone),
      phoneVerified: next.phoneVerified || previous.phoneVerified,
      photoUrl: _pickPreferred(next.photoUrl, previous.photoUrl),
      referralCode: _pickPreferred(next.referralCode, previous.referralCode),
      blockStatus: next.blockStatus,
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
    _lastResumeRestoreAt = null;
    _privateAuthReadyInFlight = null;
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
