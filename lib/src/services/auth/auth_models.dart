import 'package:atta/src/utils/media_url.dart';

class AuthUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String? phone;
  final bool phoneVerified;
  final String? photoUrl;
  final bool isAdmin;

  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.phone,
    this.phoneVerified = false,
    this.photoUrl,
    this.isAdmin = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'phone': phone,
      'phoneVerified': phoneVerified,
      'photoUrl': photoUrl,
      'isAdmin': isAdmin,
    };
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    String? pickText(List<String> keys) {
      for (final key in keys) {
        final value = json[key]?.toString().trim();
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
      return null;
    }

    return AuthUser(
      uid: pickText(const ['uid', 'id']) ?? '',
      email: pickText(const ['email']),
      displayName: pickText(const ['displayName', 'display_name', 'name']),
      phone: pickText(const ['phone', 'normalizedPhone', 'normalized_phone']),
      phoneVerified: json['phoneVerified'] == true ||
          json['phone_verified'] == true ||
          json['isPhoneVerified'] == true,
      photoUrl: () {
        final raw = pickText(const [
          'photoUrl',
          'photo_url',
          'avatarUrl',
          'avatar_url',
        ]);
        if (raw == null || raw.isEmpty) return null;
        return resolvePublicMediaUrl(raw, categoryHint: 'avatars').trim();
      }(),
      isAdmin: json['isAdmin'] == true ||
          json['is_admin'] == true ||
          json['role'] == 'admin',
    );
  }
}

enum AuthSessionEventType {
  signedIn,
  signedOut,
  userUpdated,
  passwordRecovery,
}

class AuthSessionEvent {
  final AuthSessionEventType type;

  const AuthSessionEvent({
    required this.type,
  });
}
