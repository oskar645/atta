import 'package:flutter/material.dart';

import 'package:atta/src/services/admin_service.dart';

class AdminAppDownloadsSummary extends StatefulWidget {
  const AdminAppDownloadsSummary({
    super.key,
    required this.adminService,
    this.refreshToken = 0,
  });

  final AdminService adminService;
  final int refreshToken;

  @override
  State<AdminAppDownloadsSummary> createState() =>
      _AdminAppDownloadsSummaryState();
}

class _AdminAppDownloadsSummaryState extends State<AdminAppDownloadsSummary> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.adminService.appDownloads();
  }

  @override
  void didUpdateWidget(covariant AdminAppDownloadsSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.adminService != widget.adminService) {
      _future = widget.adminService.appDownloads(forceRefresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('admin-app-downloads-block'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.download_outlined),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Загрузки приложений',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                Tooltip(
                  message:
                      'Apple и Google используют немного разные правила подсчёта установок.',
                  child: Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 84,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (!snapshot.hasData) {
                  return const Text(
                    'Статистика магазинов временно недоступна. Остальные данные Dashboard работают.',
                  );
                }
                final ios = Map<String, dynamic>.from(
                    snapshot.data!['ios'] as Map? ?? const {});
                final android = Map<String, dynamic>.from(
                    snapshot.data!['android'] as Map? ?? const {});
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = [
                      _PlatformSummaryCard(
                        key: const ValueKey('app-downloads-ios'),
                        title: 'iOS',
                        icon: Icons.apple,
                        data: ios,
                      ),
                      _PlatformSummaryCard(
                        key: const ValueKey('app-downloads-android'),
                        title: 'Android',
                        icon: Icons.android,
                        data: android,
                      ),
                    ];
                    if (constraints.maxWidth >= 560) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: 10),
                          Expanded(child: cards[1]),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        cards[0],
                        const SizedBox(height: 10),
                        cards[1],
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformSummaryCard extends StatelessWidget {
  const _PlatformSummaryCard({
    super.key,
    required this.title,
    required this.icon,
    required this.data,
  });

  final String title;
  final IconData icon;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final today = data['today'] as num?;
    final last7Days = data['last7Days'] as num?;
    final allTime = data['allTime'] as num?;
    final value = today ?? last7Days ?? allTime;
    final label = today != null
        ? 'Сегодня'
        : last7Days != null
            ? 'Последние 7 дней'
            : allTime != null
                ? 'За всё время'
                : null;
    final status = data['status']?.toString();
    final message = status == 'notConfigured'
        ? 'Требуется настройка источника'
        : status == 'noData'
            ? 'Данные ещё не получены'
            : 'Данные за сегодня ещё не получены';
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AdminAppDownloadsDetailScreen(
              title: title,
              data: data,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      value == null
                          ? message
                          : '$label: ${_formatNumber(value)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (data['lastUpdatedAt'] != null)
                      Text(
                        'Обновлено: ${_formatDateTime(data['lastUpdatedAt'])}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminAppDownloadsDetailScreen extends StatelessWidget {
  const AdminAppDownloadsDetailScreen({
    super.key,
    required this.title,
    required this.data,
  });

  final String title;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Сегодня', _periodValue(data['today'], today: true)),
      ('Вчера', _periodValue(data['yesterday'])),
      ('За 7 дней', _periodValue(data['last7Days'])),
      ('За 30 дней', _periodValue(data['last30Days'])),
      ('За всё время', _periodValue(data['allTime'])),
    ];
    return Scaffold(
      appBar: AppBar(title: Text('Загрузки — $title')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (var index = 0; index < rows.length; index++) ...[
                    _DetailRow(label: rows[index].$1, value: rows[index].$2),
                    if (index != rows.length - 1) const Divider(height: 24),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Последнее обновление: ${_formatDateTime(data['lastUpdatedAt'])}',
            key: const ValueKey('app-downloads-last-updated'),
          ),
          const SizedBox(height: 6),
          if (data['latestReportDate'] != null)
            Text('Последний отчёт магазина: ${data['latestReportDate']}'),
          const SizedBox(height: 6),
          Text(
              'Метрика: ${data['metricLabel'] ?? 'официальный отчёт магазина'}'),
          const SizedBox(height: 6),
          Text('Часовой пояс отчёта: ${data['timeZone'] ?? '—'}'),
          const SizedBox(height: 12),
          Text(
            'Apple и Google используют немного разные правила подсчёта установок.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

String _periodValue(dynamic value, {bool today = false}) {
  if (value is num) return _formatNumber(value);
  return today ? 'Данные за сегодня ещё не получены' : 'Нет данных';
}

String _formatNumber(num value) {
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(' ');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

String _formatDateTime(dynamic raw) {
  final value = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (value == null) return 'ещё не обновлялось';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year} '
      '${two(value.hour)}:${two(value.minute)}';
}
