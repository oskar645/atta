import 'package:atta/src/utils/media_url.dart';

class AuthBlockStatus {
  final String id;
  final String reason;
  final String status;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool permanent;

  const AuthBlockStatus({
    required this.id,
    required this.reason,
    required this.status,
    this.startsAt,
    this.endsAt,
    this.permanent = false,
  });

  bool get isActive => status.toLowerCase() == 'active';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reason': reason,
      'status': status,
      'starts_at': startsAt?.toIso8601String(),
      'ends_at': endsAt?.toIso8601String(),
      'permanent': permanent,
    };
  }

  factory AuthBlockStatus.fromJson(Map<dynamic, dynamic> json) {
    String pickText(List<String> keys) {
      for (final key in keys) {
        final value = json[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return '';
    }

    DateTime? pickDate(List<String> keys) {
      final raw = pickText(keys);
      return raw.isEmpty ? null : DateTime.tryParse(raw);
    }

    return AuthBlockStatus(
      id: pickText(const ['id', 'block_id', 'blockId']),
      reason: pickText(const ['reason']),
      status: pickText(const ['status']).isEmpty
          ? 'active'
          : pickText(const ['status']),
      startsAt: pickDate(const ['starts_at', 'startsAt']),
      endsAt: pickDate(const ['ends_at', 'endsAt']),
      permanent: json['permanent'] == true,
    );
  }
}

class AuthUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String? phone;
  final bool phoneVerified;
  final String? photoUrl;
  final String? referralCode;
  final bool isAdmin;
  final AuthBlockStatus? blockStatus;

  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.phone,
    this.phoneVerified = false,
    this.photoUrl,
    this.referralCode,
    this.isAdmin = false,
    this.blockStatus,
  });

  bool get isBlocked => blockStatus?.isActive == true;
  String? get blockId => blockStatus?.id;
  String? get blockReason => blockStatus?.reason;
  DateTime? get blockStartsAt => blockStatus?.startsAt;
  DateTime? get blockEndsAt => blockStatus?.endsAt;
  bool get blockPermanent => blockStatus?.permanent == true;

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'phone': phone,
      'phoneVerified': phoneVerified,
      'photoUrl': photoUrl,
      'referralCode': referralCode,
      'isAdmin': isAdmin,
      if (blockStatus != null) 'block_status': blockStatus!.toJson(),
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
      referralCode: pickText(const ['referralCode', 'referral_code']),
      isAdmin: json['isAdmin'] == true ||
          json['is_admin'] == true ||
          json['role'] == 'admin',
      blockStatus: json['block_status'] is Map
          ? AuthBlockStatus.fromJson(json['block_status'] as Map)
          : null,
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
