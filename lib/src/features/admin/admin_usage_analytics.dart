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
    'month': 'Этот месяц',
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
  Map<String, dynamic>? _data;
  bool _loading = false;
  bool _failed = false;
  bool _automaticRefreshPaused = false;
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
    _poll = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _reload(automatic: true),
    );
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
      _reload(automatic: true);
    });
  }

  Future<void> _reload({bool automatic = false}) async {
    if (automatic && _automaticRefreshPaused) return;
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
          _automaticRefreshPaused = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _automaticRefreshPaused = true;
        });
      }
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
    if (state == AppLifecycleState.resumed) _reload(automatic: true);
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
    // Dashboard previews deliberately use one stable period. Detailed screens
    // own their period selection and never mutate this summary.
    final values = periods?['today'] as Map?;
    final theme = Theme.of(context);
    String value(String key) => '${values?[key] ?? '—'}';

    void openDetails(_AnalyticsBlock block) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _AnalyticsDetailsScreen(
            block: block,
            periods: periods,
          ),
        ),
      );
    }

    Widget summary(_AnalyticsBlock block) => Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('analytics-${block.primaryMetric}'),
            onTap: () => openDetails(block),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(block.icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      block.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _data == null && _loading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  semanticsLabel: 'Загрузка аналитики',
                                ),
                              )
                            : Text(
                                value(block.primaryMetric),
                                maxLines: 1,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_failed)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_data == null
                ? 'Не удалось загрузить аналитику.'
                : 'Не удалось обновить аналитику. Показаны последние загруженные данные.'),
            TextButton.icon(
              onPressed: _loading ? null : () => _reload(),
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ]),
        ),
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
      }),
      const SizedBox(height: 12),
    ]);
  }
}

class _AnalyticsDetailsScreen extends StatefulWidget {
  const _AnalyticsDetailsScreen({
    required this.block,
    required this.periods,
  });

  final _AnalyticsBlock block;
  final Map? periods;

  @override
  State<_AnalyticsDetailsScreen> createState() =>
      _AnalyticsDetailsScreenState();
}

class _AnalyticsDetailsScreenState extends State<_AnalyticsDetailsScreen> {
  late String _period;

  @override
  void initState() {
    super.initState();
    _period = 'today';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = widget.periods?[_period] as Map?;
    final isEmpty = values != null &&
        widget.block.metrics.keys.every((key) => values[key] == 0);

    return Scaffold(
      appBar: AppBar(title: Text(widget.block.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final period in _AdminUsageAnalyticsState._periods.entries)
              ChoiceChip(
                label: Text(period.value),
                selected: _period == period.key,
                onSelected: (_) {
                  setState(() => _period = period.key);
                },
              ),
          ]),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.block.description,
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  for (final metric in widget.block.metrics.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(metric.value,
                                style: theme.textTheme.titleMedium),
                          ),
                          const SizedBox(width: 16),
                          Text('${values?[metric.key] ?? '—'}',
                              style: theme.textTheme.headlineSmall),
                        ],
                      ),
                    ),
                  if (isEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('За выбранный период активности пока нет.'),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
