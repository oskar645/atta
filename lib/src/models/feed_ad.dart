import 'package:uuid/uuid.dart';

class FeedAd {
  final String id;
  final String title;
  final String imageUrl;
  final String targetUrl;
  final bool isActive;
  final int durationDays;
  final String placement;
  final DateTime createdAt;
  final DateTime? activatedAt;
  final DateTime? expiresAt;
  final DateTime? updatedAt;
  final int impressionCount;
  final int clickCount;

  const FeedAd({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.targetUrl,
    required this.isActive,
    required this.durationDays,
    required this.placement,
    required this.createdAt,
    required this.activatedAt,
    required this.expiresAt,
    required this.updatedAt,
    required this.impressionCount,
    required this.clickCount,
  });

  bool get hasLink => targetUrl.trim().isNotEmpty;

  bool get isExpired {
    final exp = expiresAt;
    if (exp == null) return false;
    return exp.isBefore(DateTime.now().toUtc());
  }

  bool get isVisibleNow => isActive && !isExpired;

  String get displayTitle => title.trim().isEmpty ? 'Реклама' : title.trim();

  double get ctrPercent =>
      impressionCount <= 0 ? 0 : (clickCount * 100) / impressionCount;

  FeedAd copyWith({
    String? id,
    String? title,
    String? imageUrl,
    String? targetUrl,
    bool? isActive,
    int? durationDays,
    String? placement,
    DateTime? createdAt,
    DateTime? activatedAt,
    DateTime? expiresAt,
    DateTime? updatedAt,
    int? impressionCount,
    int? clickCount,
  }) {
    return FeedAd(
      id: id ?? this.id,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      targetUrl: targetUrl ?? this.targetUrl,
      isActive: isActive ?? this.isActive,
      durationDays: durationDays ?? this.durationDays,
      placement: placement ?? this.placement,
      createdAt: createdAt ?? this.createdAt,
      activatedAt: activatedAt ?? this.activatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      updatedAt: updatedAt ?? this.updatedAt,
      impressionCount: impressionCount ?? this.impressionCount,
      clickCount: clickCount ?? this.clickCount,
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value)?.toUtc() ?? DateTime.now().toUtc();
    }
    return DateTime.now().toUtc();
  }

  static DateTime? _parseNullableDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
  }

  factory FeedAd.createDraft({
    required String title,
    required String imageUrl,
    required String targetUrl,
    required int durationDays,
    String placement = 'home',
  }) {
    final now = DateTime.now().toUtc();
    return FeedAd(
      id: const Uuid().v4(),
      title: title.trim(),
      imageUrl: imageUrl.trim(),
      targetUrl: targetUrl.trim(),
      isActive: false,
      durationDays: durationDays,
      placement: placement,
      createdAt: now,
      activatedAt: null,
      expiresAt: null,
      updatedAt: now,
      impressionCount: 0,
      clickCount: 0,
    );
  }

  factory FeedAd.fromMap(Map<String, dynamic> row) {
    return FeedAd(
      id: (row['id'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      imageUrl: (row['image_url'] ?? '').toString(),
      targetUrl: (row['target_url'] ?? '').toString(),
      isActive: row['is_active'] == true,
      durationDays:
          (row['duration_days'] is num) ? (row['duration_days'] as num).toInt() : 0,
      placement: (row['placement'] ?? 'home').toString(),
      createdAt: _parseDate(row['created_at']),
      activatedAt: _parseNullableDate(row['activated_at']),
      expiresAt: _parseNullableDate(row['expires_at']),
      updatedAt: _parseNullableDate(row['updated_at']),
      impressionCount: (row['impression_count'] is num)
          ? (row['impression_count'] as num).toInt()
          : 0,
      clickCount:
          (row['click_count'] is num) ? (row['click_count'] as num).toInt() : 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title.trim(),
      'image_url': imageUrl.trim(),
      'target_url': targetUrl.trim(),
      'is_active': isActive,
      'duration_days': durationDays,
      'placement': placement.trim(),
      'created_at': createdAt.toIso8601String(),
      'activated_at': activatedAt?.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'impression_count': impressionCount,
      'click_count': clickCount,
    };
  }
}
