import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:atta/src/widgets/atta_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminPromotionsScreen extends StatefulWidget {
  const AdminPromotionsScreen({super.key});

  @override
  State<AdminPromotionsScreen> createState() => _AdminPromotionsScreenState();
}

class _AdminPromotionsScreenState extends State<AdminPromotionsScreen> {
  static const int _pageLimit = 50;

  final ScrollController _scrollController = ScrollController();
  String _filter = 'all';
  late Future<_AdminPromotionsData> _future;
  _AdminPromotionsData _data = const _AdminPromotionsData(
    items: <Map<String, dynamic>>[],
    summary: <String, dynamic>{},
  );
  String? _nextCursor;
  bool _hasMore = true;
  bool _loadingMore = false;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    _future = _load();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  Future<_AdminPromotionsData> _load({
    String? cursor,
    bool append = false,
    int? serial,
  }) async {
    final requestSerial = serial ?? ++_requestSerial;
    final admin = context.read<AdminService>();
    final itemsResponse = await admin.promotions(
      status: _statusForFilter(_filter),
      type: _typeForFilter(_filter),
      limit: _pageLimit,
      cursor: cursor,
    );
    if (requestSerial != _requestSerial) return _data;
    final summaryResponse =
        append ? _data.summary : await admin.promotionsSummary();
    final itemsRaw = itemsResponse['items'];
    final nextItems = itemsRaw is List
        ? itemsRaw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final nextCursor = (itemsResponse['nextCursor'] ?? '').toString().trim();
    final data = _AdminPromotionsData(
      items: append ? _appendDeduped(_data.items, nextItems) : nextItems,
      summary: Map<String, dynamic>.from(summaryResponse),
    );
    if (mounted) {
      setState(() {
        _data = data;
        _nextCursor = nextCursor.isEmpty ? null : nextCursor;
        _hasMore = itemsResponse['hasMore'] == true || nextCursor.isNotEmpty;
        _loadingMore = false;
      });
    }
    return data;
  }

  Future<void> _refresh() async {
    final serial = ++_requestSerial;
    setState(() {
      _nextCursor = null;
      _hasMore = true;
      _loadingMore = false;
    });
    final next = _load(serial: serial);
    if (!mounted) return;
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _refreshAfterSuccessfulMutation({
    _AdminPromotionsData? fallbackData,
  }) async {
    try {
      final data = await _load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _future = Future<_AdminPromotionsData>.value(data);
      });
    } catch (_) {
      if (!mounted) return;
      if (fallbackData != null) {
        setState(() {
          _data = fallbackData;
          _future = Future<_AdminPromotionsData>.value(fallbackData);
        });
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Действие выполнено, но список не удалось обновить'),
        ),
      );
    }
  }

  Future<void> _setFilter(String value) async {
    final serial = ++_requestSerial;
    setState(() {
      _filter = value;
      _data = const _AdminPromotionsData(
        items: <Map<String, dynamic>>[],
        summary: <String, dynamic>{},
      );
      _nextCursor = null;
      _hasMore = true;
      _loadingMore = false;
      _future = _load(serial: serial);
    });
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients ||
        !_hasMore ||
        _loadingMore ||
        _nextCursor == null) {
      return;
    }
    if (_scrollController.position.extentAfter > 700) return;
    final cursor = _nextCursor;
    if (cursor == null) return;
    setState(() => _loadingMore = true);
    _load(cursor: cursor, append: true, serial: _requestSerial);
  }

  List<Map<String, dynamic>> _appendDeduped(
    List<Map<String, dynamic>> current,
    List<Map<String, dynamic>> next,
  ) {
    final seen =
        current.map((item) => (item['promotionId'] ?? '').toString()).toSet();
    return <Map<String, dynamic>>[
      ...current,
      ...next.where((item) => seen.add((item['promotionId'] ?? '').toString())),
    ];
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
    final admin = context.read<AdminService>();
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

    await admin.cancelPromotion(promotionId);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Продвижение отменено')),
    );
    await _refreshAfterSuccessfulMutation(
      fallbackData: _data.copyWith(
        items: _data.items
            .where(
                (item) => (item['promotionId'] ?? '').toString() != promotionId)
            .toList(growable: false),
      ),
    );
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
      appBar: AppBar(title: const Text('Продвижение')),
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
          _data = data;
          return AttaRefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _PromotionOverview(summary: data.summary),
                const SizedBox(height: 20),
                Text(
                  'Показать',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
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
                      label: 'Турбо',
                      value: 'turbo',
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
                const SizedBox(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        'Покупки продвижения',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    Text(
                      'Показано: ${data.items.length}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 8.0;
                    final width = (constraints.maxWidth - gap) / 2;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: data.items
                          .map(
                            (item) => SizedBox(
                              width: width,
                              child: _PromotionPurchaseCard(
                                key: ValueKey(
                                  'adminPromotionCard-${item['promotionId']}',
                                ),
                                item: item,
                                timeLeft: _timeLeft(item),
                                onOpenListing: () {
                                  final listingId =
                                      (item['listingId'] ?? '').toString();
                                  if (listingId.isEmpty) return;
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ListingDetailScreen(
                                        trackUsageAnalytics: false,
                                        listingId: listingId,
                                      ),
                                    ),
                                  );
                                },
                                onOpenUser: () => _showUserInfo(item),
                                onCancel: (item['status'] ?? '').toString() ==
                                        'active'
                                    ? () => _cancelPromotion(
                                          (item['promotionId'] ?? '')
                                              .toString(),
                                        )
                                    : null,
                              ),
                            ),
                          )
                          .toList(growable: false),
                    );
                  },
                ),
                if (data.items.isEmpty)
                  _EmptyPromotionsView(filtered: _filter != 'all'),
                if (_hasMore && !_loadingMore)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Center(
                      child: Text(
                        'Прокрутите ниже, чтобы загрузить ещё',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                if (_loadingMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
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

  _AdminPromotionsData copyWith({
    List<Map<String, dynamic>>? items,
    Map<String, dynamic>? summary,
  }) {
    return _AdminPromotionsData(
      items: items ?? this.items,
      summary: summary ?? this.summary,
    );
  }
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

class _PromotionOverview extends StatelessWidget {
  const _PromotionOverview({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final showcase = _intValue(summary['activeShowcaseCount']);
    final bump = _intValue(summary['activeBumpCount']);
    final vip = _intValue(summary['activeVipCount']);
    final turbo = _intValue(summary['activeTurboCount']);
    final activeTotal = showcase + bump + vip + turbo;

    return Container(
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.14),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.rocket_launch_rounded,
                  color: colors.onPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Обзор продвижения',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      'Сейчас активно: $activeTotal',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              final width = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _OverviewMetric(
                    width: width,
                    label: 'Витрина',
                    value: showcase,
                    icon: Icons.storefront_outlined,
                  ),
                  _OverviewMetric(
                    width: width,
                    label: 'Поднятие',
                    value: bump,
                    icon: Icons.vertical_align_top_rounded,
                  ),
                  _OverviewMetric(
                    width: width,
                    label: 'VIP',
                    value: vip,
                    icon: Icons.workspace_premium_outlined,
                  ),
                  _OverviewMetric(
                    width: width,
                    label: 'Турбо',
                    value: turbo,
                    icon: Icons.bolt_rounded,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: [
              _OverviewStat(
                label: 'Списано сегодня',
                value: '${_intValue(summary['totalBonusSpentToday'])} бонусов',
              ),
              _OverviewStat(
                label: 'Списано за месяц',
                value:
                    '${_intValue(summary['totalBonusSpentThisMonth'])} бонусов',
              ),
              _OverviewStat(
                label: 'Показы витрины',
                value: '${_intValue(summary['totalShowcaseImpressions'])}',
              ),
              _OverviewStat(
                label: 'Клики из витрины',
                value: '${_intValue(summary['totalShowcaseClicks'])}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Покупки продвижения сейчас оплачиваются бонусами.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  final double width;
  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PromotionPurchaseCard extends StatelessWidget {
  const _PromotionPurchaseCard({
    super.key,
    required this.item,
    required this.timeLeft,
    required this.onOpenListing,
    required this.onOpenUser,
    required this.onCancel,
  });

  final Map<String, dynamic> item;
  final String timeLeft;
  final VoidCallback onOpenListing;
  final VoidCallback onOpenUser;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final type = (item['type'] ?? '').toString();
    final status = (item['status'] ?? '').toString();
    final active = status == 'active';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenListing,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _promotionTypeIcon(type),
                      size: 17,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      (item['listingTitle'] ?? 'Объявление').toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        height: 1.15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: PopupMenuButton<String>(
                      key: ValueKey(
                        'adminPromotionActions-${item['promotionId']}',
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 19,
                      tooltip: 'Действия',
                      onSelected: (value) {
                        switch (value) {
                          case 'listing':
                            onOpenListing();
                            return;
                          case 'user':
                            onOpenUser();
                            return;
                          case 'cancel':
                            onCancel?.call();
                            return;
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'listing',
                          child: Text('Открыть объявление'),
                        ),
                        const PopupMenuItem(
                          value: 'user',
                          child: Text('Открыть пользователя'),
                        ),
                        if (onCancel != null)
                          const PopupMenuItem(
                            value: 'cancel',
                            child: Text('Отключить'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                (item['userName'] ?? 'Пользователь').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _promotionTypeLabel(type),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? colors.primary : colors.outline,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _promotionStatusLabel(status),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: active ? colors.primary : colors.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _CompactPromotionValue(
                      icon: Icons.stars_rounded,
                      value: '${_intValue(item['costBonus'])} б',
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _CompactPromotionValue(
                      icon: Icons.schedule_rounded,
                      value: timeLeft,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactPromotionValue extends StatelessWidget {
  const _CompactPromotionValue({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 13,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPromotionsView extends StatelessWidget {
  const _EmptyPromotionsView({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(
            Icons.rocket_launch_outlined,
            size: 42,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            filtered
                ? 'По этому фильтру покупок нет'
                : 'Покупок продвижения пока нет',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

int _intValue(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString()) ?? 0;
}

IconData _promotionTypeIcon(String type) {
  switch (type) {
    case 'showcase':
      return Icons.storefront_outlined;
    case 'bump':
      return Icons.vertical_align_top_rounded;
    case 'vip':
      return Icons.workspace_premium_outlined;
    case 'turbo':
      return Icons.bolt_rounded;
    default:
      return Icons.rocket_launch_outlined;
  }
}

String _promotionStatusLabel(String status) {
  switch (status) {
    case 'active':
      return 'Активно';
    case 'expired':
      return 'Завершено';
    case 'cancelled':
    case 'canceled':
      return 'Отключено';
    default:
      return status.isEmpty ? '—' : status;
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
