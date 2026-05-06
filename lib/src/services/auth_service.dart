import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:atta/src/services/network_resilience.dart';

/// Адаптер под проект:
/// Supabase auth: user.id
/// Проект: uid
class AuthUser {
  final String uid;
  final String? email;

  /// Может быть в metadata, но UI мы будем брать из таблицы users
  final String? displayName;

  /// Может быть в metadata (avatar_url / photo_url / picture)
  final String? photoUrl;

  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
  });
}

class AuthService {
  final SupabaseClient _db = Supabase.instance.client;

  Stream<AuthState> get onAuthStateChange => _db.auth.onAuthStateChange;

  AuthUser? get currentUser {
    final u = _db.auth.currentUser;
    if (u == null) return null;

    final meta = u.userMetadata;

    String? pick(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    final displayName = pick(
      meta?['display_name'] ??
          meta?['displayName'] ??
          meta?['name'] ??
          meta?['full_name'] ??
          meta?['username'],
    );

    final photoUrl = pick(
      meta?['avatar_url'] ??
          meta?['photo_url'] ??
          meta?['photoUrl'] ??
          meta?['picture'],
    );

    return AuthUser(
      uid: u.id,
      email: u.email,
      displayName: displayName,
      photoUrl: photoUrl,
    );
  }

  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    final res = await NetworkResilience.run(
      () => _db.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      ),
      timeout: const Duration(seconds: 12),
      retries: 1,
    );

    final u = res.user;
    if (u == null) {
      throw Exception(
        'Не удалось войти. Пользователь не получен.',
      );
    }
    return currentUser ?? AuthUser(uid: u.id, email: u.email);
  }

  Future<AuthUser> signUp({
    required String email,
    required String password,
    String? displayName,
    String? phone,
  }) async {
    final res = await NetworkResilience.run(
      () => _db.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          if (displayName != null && displayName.trim().isNotEmpty)
            'display_name': displayName.trim(),
          if (displayName != null && displayName.trim().isNotEmpty)
            'name': displayName.trim(),
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
      ),
      timeout: const Duration(seconds: 12),
      retries: 0,
    );

    final u = res.user;
    if (u == null) {
      throw Exception(
        'Не удалось зарегистрироваться. Пользователь не получен.',
      );
    }
    return AuthUser(uid: u.id, email: u.email);
  }

  Future<void> signOut() async {
    await NetworkResilience.run(
      () => _db.auth.signOut(),
      timeout: const Duration(seconds: 8),
      retries: 0,
    );
  }

  /// Обновить metadata в Auth (не таблицу users!)
  Future<void> updateAuthMetadata({
    String? displayName,
    String? photoUrl,
  }) async {
    final data = <String, dynamic>{};

    if (displayName != null && displayName.trim().isNotEmpty) {
      data['display_name'] = displayName.trim();
      data['name'] = displayName.trim();
    }
    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      data['avatar_url'] = photoUrl.trim();
    }

    if (data.isEmpty) return;

    await NetworkResilience.run(
      () => _db.auth.updateUser(UserAttributes(data: data)),
      timeout: const Duration(seconds: 12),
      retries: 0,
    );
  }

  /// ВАЖНО: алиас под твой UI-код (ProfileScreen вызывает updateProfile)
  Future<void> updateProfile({
    String? displayName,
    String? photoUrl,
  }) async {
    await updateAuthMetadata(displayName: displayName, photoUrl: photoUrl);
  }
}
