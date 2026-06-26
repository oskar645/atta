class ActivePromotion {
  final String id;
  final String type;
  final String title;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String status;
  final int costBonus;
  final int impressionsCount;
  final int clicksCount;

  const ActivePromotion({
    required this.id,
    required this.type,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.costBonus,
    this.impressionsCount = 0,
    this.clicksCount = 0,
  });

  bool get isActive => status == 'active';

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  factory ActivePromotion.fromMap(Map<String, dynamic> map) {
    return ActivePromotion(
      id: (map['id'] ?? '').toString(),
      type: (map['type'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      startsAt: _parseDate(map['startsAt'] ?? map['starts_at']),
      endsAt: _parseDate(map['endsAt'] ?? map['ends_at']),
      status: (map['status'] ?? '').toString(),
      costBonus: (map['costBonus'] ?? map['cost_bonus'] ?? 0) is num
          ? ((map['costBonus'] ?? map['cost_bonus'] ?? 0) as num).toInt()
          : 0,
      impressionsCount: (map['impressionsCount'] ??
              map['impressions_count'] ??
              0) is num
          ? ((map['impressionsCount'] ?? map['impressions_count'] ?? 0) as num)
              .toInt()
          : 0,
      clicksCount: (map['clicksCount'] ?? map['clicks_count'] ?? 0) is num
          ? ((map['clicksCount'] ?? map['clicks_count'] ?? 0) as num).toInt()
          : 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'title': title,
        'startsAt': startsAt?.toIso8601String(),
        'endsAt': endsAt?.toIso8601String(),
        'status': status,
        'costBonus': costBonus,
        'impressionsCount': impressionsCount,
        'clicksCount': clicksCount,
      };
}
