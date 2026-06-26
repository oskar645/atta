class PromotionPlan {
  final String type;
  final String title;
  final String description;
  final int costBonus;
  final int durationHours;

  const PromotionPlan({
    required this.type,
    required this.title,
    required this.description,
    required this.costBonus,
    required this.durationHours,
  });

  factory PromotionPlan.fromMap(Map<String, dynamic> map) {
    return PromotionPlan(
      type: (map['type'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      costBonus: (map['costBonus'] ?? map['cost_bonus'] ?? 0) is num
          ? ((map['costBonus'] ?? map['cost_bonus'] ?? 0) as num).toInt()
          : 0,
      durationHours: (map['durationHours'] ?? map['duration_hours'] ?? 0) is num
          ? ((map['durationHours'] ?? map['duration_hours'] ?? 0) as num)
              .toInt()
          : 0,
    );
  }
}
