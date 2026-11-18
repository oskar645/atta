import 'dart:async';
import 'dart:math' as math;

import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/widgets/atta_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminServerStatusScreen extends StatefulWidget {
  const AdminServerStatusScreen({super.key});

  @override
  State<AdminServerStatusScreen> createState() =>
      _AdminServerStatusScreenState();
}

class _AdminServerStatusScreenState extends State<AdminServerStatusScreen> {
  Map<String, dynamic>? _data;
  Object? _error;
  Timer? _timer;
  bool _loading = true;
  final Map<String, List<double>> _history = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(
        const Duration(seconds: 15), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final next = await context.read<AdminService>().serverStatus();
      if (!mounted) return;
      _remember('cpu', _number(_map(next, 'cpu')['percent']));
      _remember('memory', _number(_map(next, 'memory')['percent']));
      _remember('disk', _number(_map(next, 'disk')['percent']));
      _remember('response', _number(_map(next, 'http')['averageResponseMs']));
      setState(() {
        _data = next;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _remember(String key, double value) {
    final values = _history.putIfAbsent(key, () => <double>[]);
    values.add(value);
    if (values.length > 24) values.removeAt(0);
  }

  static Map<String, dynamic> _map(Map<String, dynamic> source, String key) =>
      Map<String, dynamic>.from(source[key] as Map? ?? const {});

  static double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  String _bytes(dynamic value) {
    final bytes = _number(value);
    if (bytes <= 0) return 'Нет данных';
    const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
    var amount = bytes;
    var index = 0;
    while (amount >= 1024 && index < units.length - 1) {
      amount /= 1024;
      index++;
    }
    return '${amount.toStringAsFixed(index >= 3 ? 1 : 0)} ${units[index]}';
  }

  Color _levelColor(BuildContext context, double percent) {
    if (percent >= 90) return Colors.red;
    if (percent >= 75) return Colors.orange;
    return const Color(0xFF22A06B);
  }

  String _levelText(double percent) {
    if (percent >= 90) return 'Критическая нагрузка';
    if (percent >= 75) return 'Повышенная нагрузка';
    return 'Работает нормально';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Состояние сервера'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading && _data == null
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? _ErrorState(onRetry: _refresh)
              : AttaRefreshIndicator(
                  onRefresh: _refresh,
                  child: _content(context, _data!),
                ),
    );
  }

  Widget _content(BuildContext context, Map<String, dynamic> data) {
    final cpu = _map(data, 'cpu');
    final memory = _map(data, 'memory');
    final disk = _map(data, 'disk');
    final database = _map(data, 'database');
    final http = _map(data, 'http');
    final cpuPercent = _number(cpu['percent']);
    final memoryPercent = _number(memory['percent']);
    final diskPercent = _number(disk['percent']);
    final highest = math.max(cpuPercent, math.max(memoryPercent, diskPercent));
    final statusColor =
        database['ok'] == true ? _levelColor(context, highest) : Colors.red;
    final statusText =
        database['ok'] == true ? _levelText(highest) : 'База данных недоступна';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: statusColor.withValues(alpha: .28)),
          ),
          child: Row(children: [
            CircleAvatar(
              backgroundColor: statusColor,
              foregroundColor: Colors.white,
              child: Icon(database['ok'] == true
                  ? Icons.check
                  : Icons.warning_amber_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(statusText,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  const Text('Данные обновляются каждые 15 секунд',
                      style: TextStyle(fontSize: 12)),
                ])),
          ]),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          const Text('Не удалось обновить данные. Показаны последние значения.',
              style: TextStyle(color: Colors.orange, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        _MetricCard(
          title: 'Процессор',
          icon: Icons.memory,
          value: '${cpuPercent.toStringAsFixed(0)}%',
          detail: '${cpu['cores'] ?? 0} ядер • ${_levelText(cpuPercent)}',
          percent: cpuPercent,
          color: _levelColor(context, cpuPercent),
          points: _history['cpu'] ?? const [],
        ),
        _MetricCard(
          title: 'Оперативная память',
          icon: Icons.storage_rounded,
          value: '${memoryPercent.toStringAsFixed(0)}%',
          detail:
              '${_bytes(memory['usedBytes'])} из ${_bytes(memory['totalBytes'])} • приложение ${_bytes(memory['applicationBytes'])}',
          percent: memoryPercent,
          color: _levelColor(context, memoryPercent),
          points: _history['memory'] ?? const [],
        ),
        _MetricCard(
          title: 'Память сервера',
          icon: Icons.storage_outlined,
          value: disk['percent'] == null
              ? 'Нет данных'
              : '${diskPercent.toStringAsFixed(0)}%',
          detail: disk['totalBytes'] == null
              ? 'Сервер не передал данные о диске'
              : '${_bytes(disk['usedBytes'])} из ${_bytes(disk['totalBytes'])}',
          percent: diskPercent,
          color: _levelColor(context, diskPercent),
          points: _history['disk'] ?? const [],
        ),
        _InfoGrid(items: [
          _InfoItem('Скорость ответа', '${http['averageResponseMs'] ?? 0} мс',
              Icons.speed),
          _InfoItem('Запросов сейчас', '${http['requestsPerMinute'] ?? 0}/мин',
              Icons.sync_alt),
          _InfoItem('Ошибок сейчас', '${http['errorsPerMinute'] ?? 0}/мин',
              Icons.error_outline),
          _InfoItem(
              'База данных',
              database['ok'] == true ? 'Работает' : 'Ошибка',
              Icons.dns_outlined),
          _InfoItem('Ответ базы', '${database['responseMs'] ?? 0} мс',
              Icons.timer_outlined),
          _InfoItem(
              'Работает без перезапуска',
              _uptime(_number(data['uptimeSeconds']).round()),
              Icons.restart_alt),
        ]),
      ],
    );
  }

  String _uptime(int seconds) {
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    if (days > 0) return '$days д. $hours ч.';
    final minutes = (seconds % 3600) ~/ 60;
    return '$hours ч. $minutes мин.';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.title,
      required this.icon,
      required this.value,
      required this.detail,
      required this.percent,
      required this.color,
      required this.points});
  final String title, value, detail;
  final IconData icon;
  final double percent;
  final Color color;
  final List<double> points;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Expanded(
                        child: Text(title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800))),
                    Text(value,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: color))
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                          value: (percent / 100).clamp(0, 1),
                          minHeight: 6,
                          color: color,
                          backgroundColor: color.withValues(alpha: .12))),
                  const SizedBox(height: 5),
                  Text(detail,
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.outline)),
                ])),
            const SizedBox(width: 10),
            SizedBox(
                width: 58,
                height: 38,
                child: CustomPaint(painter: _SparklinePainter(points, color))),
          ]),
        ),
      );
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.points, this.color);
  final List<double> points;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final values = points.length < 2 ? <double>[...points, ...points] : points;
    if (values.isEmpty) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / math.max(1, values.length - 1);
      final y = size.height - (values[i].clamp(0, 100) / 100) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

class _InfoItem {
  const _InfoItem(this.title, this.value, this.icon);
  final String title, value;
  final IconData icon;
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.items});
  final List<_InfoItem> items;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items
                .map((item) => SizedBox(
                    width: width,
                    child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(item.icon, size: 20),
                                  const SizedBox(height: 10),
                                  Text(item.value,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16)),
                                  Text(item.title,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline))
                                ])))))
                .toList());
      });
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('Не удалось получить состояние сервера',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Повторить'))
          ])));
}
