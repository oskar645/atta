import 'dart:convert';

import 'package:atta/src/services/auth/auth_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const String _accessTokenKey = 'timeweb_access_token';
  static const String _refreshTokenKey = 'timeweb_refresh_token';
  static const String _currentUserKey = 'timeweb_current_user';

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required AuthUser currentUser,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // TODO: move tokens to flutter_secure_storage before production release.
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    await prefs.setString(
      _currentUserKey,
      jsonEncode(currentUser.toJson()),
    );
  }

  Future<String?> readAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  Future<String?> readRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
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
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_currentUserKey);
  }
}
