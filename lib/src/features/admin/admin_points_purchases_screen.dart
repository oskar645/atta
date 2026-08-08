import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class AdminPointsPurchasesScreen extends StatefulWidget {
  const AdminPointsPurchasesScreen({super.key});

  @override
  State<AdminPointsPurchasesScreen> createState() =>
      _AdminPointsPurchasesScreenState();
}

class _AdminPointsPurchasesScreenState
    extends State<AdminPointsPurchasesScreen> {
  static const int _pageLimit = 30;

  final TextEditingController _searchController = TextEditingController();
  String _period = 'month';
  DateTimeRange? _customRange;
  Map<String, dynamic> _summary = const <String, dynamic>{};
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  String? _nextCursor;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTimeRange _effectiveRange() {
    final now = DateTime.now();
    switch (_period) {
      case 'day':
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: now,
        );
      case 'week':
        return DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );
      case '30days':
        return DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );
      case 'custom':
        return _customRange ??
            DateTimeRange(
              start: now.subtract(const Duration(days: 7)),
              end: now,
            );
      case 'month':
      default:
        return DateTimeRange(
          start: DateTime(now.year, now.month),
          end: now,
        );
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _nextCursor = null;
      });
    } else if (_nextCursor == null || _loadingMore) {
      return;
    } else {
      setState(() => _loadingMore = true);
    }

    final admin = context.read<AdminService>();
    final range = _effectiveRange();
    final search = _searchController.text.trim();
    try {
      final summaryFuture = reset
          ? admin.pointsPurchasesSummary(
              from: range.start.toUtc().toIso8601String(),
              to: range.end.toUtc().toIso8601String(),
              search: search,
              forceRefresh: true,
            )
          : Future<Map<String, dynamic>>.value(_summary);
      final listFuture = admin.pointsPurchases(
        from: range.start.toUtc().toIso8601String(),
        to: range.end.toUtc().toIso8601String(),
        search: search,
        limit: _pageLimit,
        cursor: reset ? null : _nextCursor,
        forceRefresh: true,
      );
      final results = await Future.wait([summaryFuture, listFuture]);
      final listResponse = results[1];
      final nextItems = _extractItems(listResponse);
      if (!mounted) return;
      setState(() {
        _summary = Map<String, dynamic>.from(results[0]);
        _items = reset
            ? nextItems
            : <Map<String, dynamic>>[
                ..._items,
                ...nextItems.where(
                  (item) => !_items.any(
                    (existing) =>
                        (existing['paymentId'] ?? '').toString() ==
                        (item['paymentId'] ?? '').toString(),
                  ),
                ),
              ];
        _nextCursor = (listResponse['nextCursor'] ?? '').toString().trim();
        if (_nextCursor!.isEmpty) _nextCursor = null;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> _refresh() => _load(reset: true);

  void _runSearch() {
    _load(reset: true);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
    );
    if (picked == null) return;
    setState(() {
      _period = 'custom';
      _customRange = DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        ),
      );
    });
    _load(reset: true);
  }

  void _setPeriod(String period) {
    if (period == 'custom') {
      _pickCustomRange();
      return;
    }
    if (_period == period) return;
    setState(() => _period = period);
    _load(reset: true);
  }

  Future<void> _copyUserId(String userId) async {
    final value = userId.trim();
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    showAppSnack(context, 'ID скопирован');
  }

  Future<void> _openUser(Map<String, dynamic> item) async {
    final userId = (item['userId'] ?? '').toString().trim();
    if (userId.isEmpty) return;
    try {
      final response = await context.read<AdminService>().userById(userId);
      final details = response['user'] is Map
          ? Map<String, dynamic>.from(response['user'] as Map)
          : item;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SellerPublicProfileScreen(
            sellerId: userId,
            initialSellerName:
                (details['display_name'] ?? details['displayName'] ??
                        details['name'] ??
                        item['displayName'] ??
                        'Пользователь')
                    .toString(),
            initialSellerAvatar:
                (details['avatar_url'] ?? details['avatarUrl'] ?? '').toString(),
            initialSellerPhone:
                (details['phone'] ?? item['phone'] ?? '').toString(),
            initialStatusLabel:
                (details['status'] ?? 'Активен').toString(),
            initialIsAdmin:
                details['is_admin'] == true || details['isAdmin'] == true,
            showAdminFields: true,
            titleText: 'Профиль пользователя',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnack(
        context,
        'Не удалось открыть профиль пользователя: $error',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Покупки баллов')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'day', label: Text('Сегодня')),
                ButtonSegment(value: 'week', label: Text('7 дней')),
                ButtonSegment(value: 'month', label: Text('Этот месяц')),
                ButtonSegment(value: '30days', label: Text('30 дней')),
                ButtonSegment(value: 'custom', label: Text('Период')),
              ],
              selected: {_period},
              onSelectionChanged: (value) => _setPeriod(value.first),
            ),
            if (_period == 'custom' && _customRange != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickCustomRange,
                icon: const Icon(Icons.date_range),
                label: Text(
                  '${_formatDate(_customRange!.start)} - ${_formatDate(_customRange!.end)}',
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                labelText: 'Поиск по телефону, имени, нику, userId',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Найти',
                  onPressed: _runSearch,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _items.isEmpty)
              _StateView(
                message: 'Не удалось загрузить покупки.\n$_error',
                onRetry: _refresh,
              )
            else ...[
              _SummaryGrid(summary: _summary),
              const SizedBox(height: 12),
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Покупки не найдены')),
                )
              else
                ..._items.map(
                  (item) => _PurchaseTile(
                    item: item,
                    onTap: () => _openUser(item),
                    onCopyUserId: () =>
                        _copyUserId((item['userId'] ?? '').toString()),
                  ),
                ),
              if (_nextCursor != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: OutlinedButton(
                    onPressed:
                        _loadingMore ? null : () => _load(reset: false),
                    child: _loadingMore
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Загрузить ещё'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _SummaryCard(
          title: 'Получено денег',
          value: '${_formatMoney(summary['totalAmountRub'])} ₽',
        ),
        _SummaryCard(
          title: 'Начислено баллов',
          value: _formatInt(summary['totalPoints']),
        ),
        _SummaryCard(
          title: 'Покупок',
          value: _formatInt(summary['purchasesCount']),
        ),
        _SummaryCard(
          title: 'Покупателей',
          value: _formatInt(summary['uniqueBuyersCount']),
        ),
      ],
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
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({
    required this.item,
    required this.onTap,
    required this.onCopyUserId,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onCopyUserId;

  @override
  Widget build(BuildContext context) {
    final name = (item['displayName'] ?? 'Пользователь').toString();
    final username = (item['username'] ?? '').toString().trim();
    final phone = (item['phone'] ?? '').toString().trim();
    final paymentId = (item['paymentId'] ?? '').toString().trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(child: Icon(Icons.person)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (username.isNotEmpty) Text('@$username'),
                        if (phone.isNotEmpty) Text(phone),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onCopyUserId,
                    tooltip: 'Скопировать userId',
                    icon: const Icon(Icons.copy),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('${_formatMoney(item['amountRub'])} ₽')),
                  Chip(label: Text('${_formatInt(item['points'])} баллов')),
                  const Chip(label: Text('Оплачено')),
                ],
              ),
              const SizedBox(height: 8),
              Text('Дата: ${_formatDateTime(item['createdAt'])}'),
              if (paymentId.isNotEmpty)
                Text(
                  'paymentId: $paymentId',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateView extends StatelessWidget {
  const _StateView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}

String _formatInt(Object? value) {
  final number = value is num ? value : num.tryParse((value ?? '0').toString());
  return (number ?? 0).round().toString();
}

String _formatMoney(Object? value) {
  final number = value is num ? value : num.tryParse((value ?? '0').toString());
  final amount = number ?? 0;
  if (amount == amount.roundToDouble()) return amount.round().toString();
  return amount.toStringAsFixed(2);
}

String _formatDateTime(Object? value) {
  final date = DateTime.tryParse((value ?? '').toString())?.toLocal();
  if (date == null) return '-';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day.$month.${date.year} $hour:$minute';
}
