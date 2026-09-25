import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:atta/src/services/usage_analytics_service.dart';

class AdminUsageAnalytics extends StatefulWidget {
  const AdminUsageAnalytics({super.key, this.load});
  final Future<Map<String, dynamic>> Function()? load;
  @override
  State<AdminUsageAnalytics> createState() => _AdminUsageAnalyticsState();
}

class _AdminUsageAnalyticsState extends State<AdminUsageAnalytics>
    with WidgetsBindingObserver {
  static const _periods = {
    'today': 'Сегодня',
    'yesterday': 'Вчера',
    'week': '7 дней',
    'month': 'Месяц',
    'all': 'Всё время',
  };
  static const _blocks = [
    _AnalyticsBlock(
        'Гости',
        Icons.people_outline,
        'guests',
        {'guests': 'Уникальных гостей'},
        'Уникальные гости за выбранный период. Данные — с начала сбора.'),
    _AnalyticsBlock(
        'Открытия объявлений',
        Icons.visibility_outlined,
        'totalOpens',
        {
          'guestOpens': 'Гости',
          'registeredOpens': 'Зарегистрированные',
          'totalOpens': 'Всего'
        },
        'Открытия гостями и зарегистрированными пользователями. Данные — с начала сбора.'),
    _AnalyticsBlock(
        'Сообщения',
        Icons.chat_bubble_outline,
        'messages',
        {'messages': 'Сообщений', 'activeChats': 'Активных диалогов'},
        'Сообщения из доступной истории чатов. Активный диалог — диалог с сообщениями за выбранный период.'),
  ];
  String _period = 'today';
  _AnalyticsBlock? _selected;
  Map<String, dynamic>? _data;
  bool _loading = false;
  bool _failed = false;
  bool _dirty = false;
  Timer? _debounce;
  Timer? _poll;
  StreamSubscription<ChatSocketEvent>? _events;
  StreamSubscription<bool>? _connection;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _reload());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_events != null) return;
    final socket = Provider.of<ChatSocketService?>(context, listen: false);
    if (socket == null) return;
    socket.subscribeAnalytics();
    _events = socket.events.listen((event) {
      if (event.name == 'analytics_updated') _invalidate();
    });
    _connection = socket.connectionChanges.listen((connected) {
      if (connected) {
        socket.subscribeAnalytics();
        _invalidate();
      }
    });
  }

  void _invalidate() {
    // Coalesce bursts without starving refresh during continuous activity.
    _debounce ??= Timer(const Duration(milliseconds: 1200), () {
      _debounce = null;
      _reload();
    });
  }

  Future<void> _reload() async {
    if (_loading) {
      _dirty = true;
      return;
    }
    setState(() => _loading = true);
    try {
      final data =
          await (widget.load ?? UsageAnalyticsService.instance.dashboard)();
      if (mounted) {
        setState(() {
          _data = data;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
      if (_dirty && mounted) {
        _dirty = false;
        _invalidate();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _poll?.cancel();
    _events?.cancel();
    _connection?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final periods = _data?['periods'] as Map?;
    final values = periods?[_period] as Map?;
    final theme = Theme.of(context);
    final selected = _selected;
    String value(String key) => '${values?[key] ?? '—'}';
    bool isEmpty(_AnalyticsBlock block) =>
        values != null && block.metrics.keys.every((key) => values[key] == 0);

    Widget summary(_AnalyticsBlock block) => Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('analytics-${block.primaryMetric}'),
            onTap: () => setState(() => _selected = block),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(block.icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      block.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value(block.primaryMetric),
                        maxLines: 1,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Активность приложения', style: theme.textTheme.titleLarge),
            IconButton(
                tooltip: 'Обновить аналитику',
                onPressed: _loading ? null : _reload,
                icon: const Icon(Icons.refresh)),
          ]),
      if (selected != null) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _selected = null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Все показатели'),
          ),
        ),
        Text(selected.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
      ],
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final period in _periods.entries)
          ChoiceChip(
              label: Text(period.value),
              selected: _period == period.key,
              onSelected: (_) => setState(() => _period = period.key)),
      ]),
      const SizedBox(height: 12),
      if (_loading) ...[
        const LinearProgressIndicator(semanticsLabel: 'Загрузка аналитики'),
        const SizedBox(height: 12),
      ],
      if (_failed)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_data == null
                ? 'Не удалось загрузить аналитику.'
                : 'Не удалось обновить аналитику. Показаны последние загруженные данные.'),
            TextButton.icon(
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ]),
        ),
      if (selected == null)
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 3
              : constraints.maxWidth >= 600
                  ? 2
                  : 1;
          final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final block in _blocks)
              SizedBox(width: width, child: summary(block)),
          ]);
        })
      else
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(selected.description, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  for (final metric in selected.metrics.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          Text(metric.value,
                              style: theme.textTheme.titleMedium),
                          Text(value(metric.key),
                              style: theme.textTheme.headlineSmall),
                        ],
                      ),
                    ),
                  if (isEmpty(selected)) ...[
                    const SizedBox(height: 12),
                    const Text('За выбранный период активности пока нет.'),
                  ],
                ]),
          ),
        ),
      const SizedBox(height: 12),
    ]);
  }
}

class _AnalyticsBlock {
  const _AnalyticsBlock(this.title, this.icon, this.primaryMetric, this.metrics,
      this.description);

  final String title;
  final IconData icon;
  final String primaryMetric;
  final Map<String, String> metrics;
  final String description;
}
