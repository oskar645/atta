class TopBanner {
  const TopBanner(
      {required this.id,
      required this.title,
      required this.imageUrl,
      required this.targetUrl,
      required this.enabled,
      required this.startAt,
      required this.endAt,
      required this.sortOrder,
      required this.status,
      required this.impressions,
      required this.clicks});
  final String id, title, imageUrl, targetUrl, status;
  final bool enabled;
  final DateTime startAt, endAt;
  final int sortOrder, impressions, clicks;
  bool get hasLink => targetUrl.trim().isNotEmpty;
  double get ctr => impressions == 0 ? 0 : clicks * 100 / impressions;
  factory TopBanner.fromMap(Map<String, dynamic> map) => TopBanner(
      id: '${map['id'] ?? ''}',
      title: '${map['title'] ?? ''}',
      imageUrl: '${map['image_url'] ?? ''}',
      targetUrl: '${map['target_url'] ?? ''}',
      enabled: map['enabled'] == true,
      startAt: DateTime.parse('${map['start_at']}').toUtc(),
      endAt: DateTime.parse('${map['end_at']}').toUtc(),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      status: '${map['status'] ?? 'paused'}',
      impressions: (map['impression_count'] as num?)?.toInt() ?? 0,
      clicks: (map['click_count'] as num?)?.toInt() ?? 0);
}
