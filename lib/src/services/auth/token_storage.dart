import 'dart:convert';

import 'package:atta/src/services/auth/auth_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  TokenStorage({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _accessTokenKey = 'timeweb_access_token';
  static const String _refreshTokenKey = 'timeweb_refresh_token';
  static const String _currentUserKey = 'timeweb_current_user';

  final FlutterSecureStorage _secureStorage;
  Future<void>? _migrationInFlight;

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required AuthUser currentUser,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await _secureStorage.write(key: _accessTokenKey, value: accessToken);
    await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.setString(
      _currentUserKey,
      jsonEncode(currentUser.toJson()),
    );
  }

  Future<String?> readAccessToken() async {
    await _migrateLegacyTokensIfNeeded();
    return _secureStorage.read(key: _accessTokenKey);
  }

  Future<String?> readRefreshToken() async {
    await _migrateLegacyTokensIfNeeded();
    return _secureStorage.read(key: _refreshTokenKey);
  }

  Future<AuthUser?> readCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_currentUserKey);
    if (raw == null || raw.trim().isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;

    return AuthUser.fromJson(decoded);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_currentUserKey);
  }

  Future<void> _migrateLegacyTokensIfNeeded() {
    final existing = _migrationInFlight;
    if (existing != null) {
      return existing;
    }
    final future = _migrateLegacyTokens();
    _migrationInFlight = future;
    return future.whenComplete(() {
      if (identical(_migrationInFlight, future)) {
        _migrationInFlight = null;
      }
    });
  }

  Future<void> _migrateLegacyTokens() async {
    final secureAccessToken = await _secureStorage.read(key: _accessTokenKey);
    final secureRefreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (_hasValue(secureAccessToken) && _hasValue(secureRefreshToken)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final legacyAccessToken = prefs.getString(_accessTokenKey);
    final legacyRefreshToken = prefs.getString(_refreshTokenKey);
    if (!_hasValue(legacyAccessToken) || !_hasValue(legacyRefreshToken)) {
      return;
    }

    await _secureStorage.write(
      key: _accessTokenKey,
      value: secureAccessToken ?? legacyAccessToken,
    );
    await _secureStorage.write(
      key: _refreshTokenKey,
      value: secureRefreshToken ?? legacyRefreshToken,
    );

    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  bool _hasValue(String? value) => value != null && value.trim().isNotEmpty;
}
