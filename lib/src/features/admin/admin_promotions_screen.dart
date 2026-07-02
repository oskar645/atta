import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminPromotionsScreen extends StatefulWidget {
  const AdminPromotionsScreen({super.key});

  @override
  State<AdminPromotionsScreen> createState() => _AdminPromotionsScreenState();
}

class _AdminPromotionsScreenState extends State<AdminPromotionsScreen> {
  String _filter = 'all';
  late Future<_AdminPromotionsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_AdminPromotionsData> _load() async {
    final admin = context.read<AdminService>();
    final itemsResponse = await admin.promotions(
      status: _statusForFilter(_filter),
      type: _typeForFilter(_filter),
    );
    final summaryResponse = await admin.promotionsSummary();
    final itemsRaw = itemsResponse['items'];
    return _AdminPromotionsData(
      items: itemsRaw is List
          ? itemsRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
          : const <Map<String, dynamic>>[],
      summary: Map<String, dynamic>.from(summaryResponse),
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _setFilter(String value) async {
    setState(() {
      _filter = value;
      _future = _load();
    });
  }

  String? _statusForFilter(String value) {
    switch (value) {
      case 'active':
        return 'active';
      case 'expired':
        return 'expired';
      default:
        return null;
    }
  }

  String? _typeForFilter(String value) {
    switch (value) {
      case 'showcase':
      case 'bump':
      case 'vip':
      case 'turbo':
        return value;
      default:
        return null;
    }
  }

  String _timeLeft(Map<String, dynamic> item) {
    final seconds = item['timeRemainingSeconds'];
    final value = seconds is num ? seconds.toInt() : 0;
    if (value <= 0) return 'Истекло';
    final hours = value ~/ 3600;
    if (hours > 0) return '$hours ч';
    final minutes = value ~/ 60;
    return '$minutes мин';
  }

  Future<void> _cancelPromotion(String promotionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Отменить продвижение?'),
        content: const Text(
          'Объявление больше не будет выделяться этим способом.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Назад'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Отменить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await context.read<AdminService>().cancelPromotion(promotionId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Продвижение отменено')),
    );
    await _refresh();
  }

  Future<void> _showUserInfo(Map<String, dynamic> item) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (item['userName'] ?? 'Пользователь').toString(),
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('User ID: ${(item['userId'] ?? '').toString()}'),
              Text(
                'Телефон: ${formatRussianPhone((item['userPhone'] ?? '').toString())}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Продвижения')),
      body: FutureBuilder<_AdminPromotionsData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _AdminPanelStateView(
              message: 'Не удалось загрузить продвижения.\n${snap.error}',
              onRetry: _refresh,
            );
          }

          final data = snap.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  'Платежи пока не подключены. Сейчас учитываются только бонусы.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _AdminFilterChip(
                      label: 'Все',
                      value: 'all',
                      current: _filter,
                      onSelected: _setFilter,
                    ),
                    _AdminFilterChip(
                      label: 'Активные',
                      value: 'active',
                      current: _filter,
                      onSelected: _setFilter,
                    ),
                    _AdminFilterChip(
                      label: 'Витрина',
                      value: 'showcase',
                      current: _filter,
                      onSelected: _setFilter,
                    ),
                    _AdminFilterChip(
                      label: 'Поднятие',
                      value: 'bump',
                      current: _filter,
                      onSelected: _setFilter,
                    ),
                    _AdminFilterChip(
                      label: 'VIP',
                      value: 'vip',
                      current: _filter,
                      onSelected: _setFilter,
                    ),
                    _AdminFilterChip(
                      label: 'Истёкшие',
                      value: 'expired',
                      current: _filter,
                      onSelected: _setFilter,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _SummaryCard(
                      title: 'Витрина',
                      value: '${data.summary['activeShowcaseCount'] ?? 0}',
                    ),
                    _SummaryCard(
                      title: 'Поднятие',
                      value: '${data.summary['activeBumpCount'] ?? 0}',
                    ),
                    _SummaryCard(
                      title: 'VIP',
                      value: '${data.summary['activeVipCount'] ?? 0}',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...data.items.map(
                  (item) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (item['listingTitle'] ?? 'Объявление').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Тип: ${_promotionTypeLabel((item['type'] ?? '').toString())}',
                          ),
                          Text(
                              'Пользователь: ${(item['userName'] ?? '').toString()}'),
                          Text(
                            'Цена: ${formatPrice((item['listingPrice'] as num?)?.toInt() ?? 0)} ₽',
                          ),
                          Text(
                              'Бонусы: ${(item['costBonus'] ?? 0).toString()}'),
                          Text('Осталось: ${_timeLeft(item)}'),
                          Text(
                              'Показы: ${(item['impressionsCount'] ?? 0).toString()}'),
                          Text(
                              'Клики: ${(item['clicksCount'] ?? 0).toString()}'),
                          Text('Статус: ${(item['status'] ?? '').toString()}'),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () {
                                  final listingId =
                                      (item['listingId'] ?? '').toString();
                                  if (listingId.isEmpty) return;
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ListingDetailScreen(
                                        listingId: listingId,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('Открыть объявление'),
                              ),
                              OutlinedButton(
                                onPressed: () => _showUserInfo(item),
                                child: const Text('Открыть пользователя'),
                              ),
                              if ((item['status'] ?? '').toString() == 'active')
                                FilledButton.tonal(
                                  onPressed: () => _cancelPromotion(
                                    (item['promotionId'] ?? '').toString(),
                                  ),
                                  child: const Text('Отключить'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (data.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Продвижений пока нет')),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _promotionTypeLabel(String value) {
  switch (value) {
    case 'showcase':
      return 'Витрина';
    case 'bump':
      return 'Поднятие';
    case 'vip':
      return 'VIP';
    case 'turbo':
      return 'Турбо';
    default:
      return value;
  }
}

class _AdminPromotionsData {
  const _AdminPromotionsData({
    required this.items,
    required this.summary,
  });

  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> summary;
}

class _AdminFilterChip extends StatelessWidget {
  const _AdminFilterChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onSelected,
  });

  final String label;
  final String value;
  final String current;
  final Future<void> Function(String value) onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: value == current,
      onSelected: (_) => onSelected(value),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminPanelStateView extends StatelessWidget {
  const _AdminPanelStateView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
