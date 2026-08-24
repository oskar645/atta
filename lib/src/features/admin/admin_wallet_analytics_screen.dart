import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminWalletAnalyticsScreen extends StatefulWidget {
  const AdminWalletAnalyticsScreen({super.key});

  @override
  State<AdminWalletAnalyticsScreen> createState() =>
      _AdminWalletAnalyticsScreenState();
}

class _AdminWalletAnalyticsScreenState
    extends State<AdminWalletAnalyticsScreen> {
  static const int _pageLimit = 50;

  late Future<_AdminWalletAnalyticsData> _future;
  String _period = 'month';
  DateTimeRange? _customRange;
  final TextEditingController _searchController = TextEditingController();
  String? _walletsNextCursor;
  bool _walletsHasMore = true;
  bool _walletsLoadingMore = false;
  String? _transactionsNextCursor;
  bool _transactionsHasMore = true;
  bool _transactionsLoadingMore = false;
  String? _referralsNextCursor;
  bool _referralsHasMore = true;
  bool _referralsLoadingMore = false;
  int _requestSerial = 0;
  _AdminWalletAnalyticsData? _data;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_AdminWalletAnalyticsData> _load({
    bool forceRefresh = false,
    String? search,
    String? referralsCursor,
    bool appendReferrals = false,
    int? serial,
  }) async {
    final requestSerial = serial ?? ++_requestSerial;
    final admin = context.read<AdminService>();
    final referralSearch = (search ?? _searchController.text).trim();
    final from = _period == 'custom'
        ? _customRange?.start.toUtc().toIso8601String()
        : null;
    final to = _period == 'custom'
        ? _customRange?.end.toUtc().toIso8601String()
        : null;
    final walletsResponse = appendReferrals
        ? Future<Map<String, dynamic>>.value({'items': _data?.wallets ?? []})
        : admin.wallets(forceRefresh: forceRefresh, limit: _pageLimit);
    final transactionsResponse = appendReferrals
        ? Future<Map<String, dynamic>>.value(
            {'items': _data?.transactions ?? []},
          )
        : admin.walletTransactions(
            forceRefresh: forceRefresh,
            limit: _pageLimit,
          );
    final analyticsResponse = appendReferrals
        ? Future<Map<String, dynamic>>.value(_data?.analytics ?? {})
        : admin.bonusAnalytics(period: _period, forceRefresh: forceRefresh);
    final referralSummaryResponse = appendReferrals
        ? Future<Map<String, dynamic>>.value(_data?.referralSummary ?? {})
        : admin.referralSummary(
            period: _period,
            from: from,
            to: to,
            forceRefresh: forceRefresh,
          );
    final referralsResponse = await admin.referrals(
      period: _period,
      from: from,
      to: to,
      search: referralSearch,
      limit: _pageLimit,
      cursor: referralsCursor,
      forceRefresh: forceRefresh,
    );
    if (requestSerial != _requestSerial) {
      return _data ??
          const _AdminWalletAnalyticsData(
            wallets: <Map<String, dynamic>>[],
            transactions: <Map<String, dynamic>>[],
            analytics: <String, dynamic>{},
            referralSummary: <String, dynamic>{},
            referralUsers: <Map<String, dynamic>>[],
            referralSearch: '',
          );
    }
    final nextCursor =
        (referralsResponse['nextCursor'] ?? '').toString().trim();
    final nextReferralUsers = _extractItems(referralsResponse);
    final walletsResult = await walletsResponse;
    final transactionsResult = await transactionsResponse;
    final data = _AdminWalletAnalyticsData(
      wallets: _extractItems(walletsResult),
      transactions: _extractItems(transactionsResult),
      analytics: Map<String, dynamic>.from(await analyticsResponse),
      referralSummary: Map<String, dynamic>.from(await referralSummaryResponse),
      referralUsers: appendReferrals
          ? _appendReferralUsers(_data?.referralUsers ?? [], nextReferralUsers)
          : nextReferralUsers,
      referralSearch: referralSearch,
    );
    if (mounted) {
      setState(() {
        _data = data;
        if (!appendReferrals) {
          final walletsCursor =
              (walletsResult['nextCursor'] ?? '').toString().trim();
          _walletsNextCursor = walletsCursor.isEmpty ? null : walletsCursor;
          _walletsHasMore =
              walletsResult['hasMore'] == true || walletsCursor.isNotEmpty;
          final transactionsCursor =
              (transactionsResult['nextCursor'] ?? '').toString().trim();
          _transactionsNextCursor =
              transactionsCursor.isEmpty ? null : transactionsCursor;
          _transactionsHasMore = transactionsResult['hasMore'] == true ||
              transactionsCursor.isNotEmpty;
          _walletsLoadingMore = false;
          _transactionsLoadingMore = false;
        }
        _referralsNextCursor = nextCursor.isEmpty ? null : nextCursor;
        _referralsHasMore =
            referralsResponse['hasMore'] == true || nextCursor.isNotEmpty;
        _referralsLoadingMore = false;
      });
    }
    return data;
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> _refresh() async {
    final serial = ++_requestSerial;
    setState(() {
      _referralsNextCursor = null;
      _referralsHasMore = true;
      _referralsLoadingMore = false;
      _walletsNextCursor = null;
      _walletsHasMore = true;
      _walletsLoadingMore = false;
      _transactionsNextCursor = null;
      _transactionsHasMore = true;
      _transactionsLoadingMore = false;
    });
    final next = _load(forceRefresh: true, serial: serial);
    setState(() {
      _future = next;
    });
    await next;
  }

  void _setPeriod(String period) {
    if (_period == period) return;
    final serial = ++_requestSerial;
    setState(() {
      _period = period;
      _referralsNextCursor = null;
      _referralsHasMore = true;
      _referralsLoadingMore = false;
      _walletsNextCursor = null;
      _walletsHasMore = true;
      _walletsLoadingMore = false;
      _transactionsNextCursor = null;
      _transactionsHasMore = true;
      _transactionsLoadingMore = false;
      _future = _load(forceRefresh: true, serial: serial);
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = _customRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: initial,
    );
    if (picked == null) return;
    setState(() {
      _customRange = DateTimeRange(
        start: DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        ),
        end: DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        ),
      );
      _period = 'custom';
      _referralsNextCursor = null;
      _referralsHasMore = true;
      _referralsLoadingMore = false;
      _walletsNextCursor = null;
      _walletsHasMore = true;
      _walletsLoadingMore = false;
      _transactionsNextCursor = null;
      _transactionsHasMore = true;
      _transactionsLoadingMore = false;
      _future = _load(forceRefresh: true, serial: ++_requestSerial);
    });
  }

  void _runSearch() {
    final search = _searchController.text.trim();
    final serial = ++_requestSerial;
    setState(() {
      _referralsNextCursor = null;
      _referralsHasMore = true;
      _referralsLoadingMore = false;
      _walletsNextCursor = null;
      _walletsHasMore = true;
      _walletsLoadingMore = false;
      _transactionsNextCursor = null;
      _transactionsHasMore = true;
      _transactionsLoadingMore = false;
      _future = _load(forceRefresh: true, search: search, serial: serial);
    });
  }

  void _loadMoreReferrals() {
    final cursor = _referralsNextCursor;
    if (!_referralsHasMore || _referralsLoadingMore || cursor == null) return;
    setState(() => _referralsLoadingMore = true);
    _load(
      referralsCursor: cursor,
      appendReferrals: true,
      serial: _requestSerial,
    );
  }

  Future<void> _loadMoreWallets() async {
    final cursor = _walletsNextCursor;
    if (!_walletsHasMore ||
        _walletsLoadingMore ||
        cursor == null ||
        _data == null) {
      return;
    }
    setState(() => _walletsLoadingMore = true);
    try {
      final response = await context.read<AdminService>().wallets(
            limit: _pageLimit,
            cursor: cursor,
          );
      final nextItems = _extractItems(response);
      final nextCursor = (response['nextCursor'] ?? '').toString().trim();
      setState(() {
        _data = _data!.copyWith(
          wallets: _appendById(_data!.wallets, nextItems),
        );
        _walletsNextCursor = nextCursor.isEmpty ? null : nextCursor;
        _walletsHasMore = response['hasMore'] == true || nextCursor.isNotEmpty;
        _walletsLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _walletsLoadingMore = false);
    }
  }

  Future<void> _loadMoreTransactions() async {
    final cursor = _transactionsNextCursor;
    if (!_transactionsHasMore ||
        _transactionsLoadingMore ||
        cursor == null ||
        _data == null) {
      return;
    }
    setState(() => _transactionsLoadingMore = true);
    try {
      final response = await context.read<AdminService>().walletTransactions(
            limit: _pageLimit,
            cursor: cursor,
          );
      final nextItems = _extractItems(response);
      final nextCursor = (response['nextCursor'] ?? '').toString().trim();
      setState(() {
        _data = _data!.copyWith(
          transactions: _appendById(_data!.transactions, nextItems),
        );
        _transactionsNextCursor = nextCursor.isEmpty ? null : nextCursor;
        _transactionsHasMore =
            response['hasMore'] == true || nextCursor.isNotEmpty;
        _transactionsLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _transactionsLoadingMore = false);
    }
  }

  List<Map<String, dynamic>> _appendById(
    List<Map<String, dynamic>> current,
    List<Map<String, dynamic>> next,
  ) {
    String idOf(Map<String, dynamic> item) =>
        (item['id'] ?? item['walletId'] ?? item['transactionId'] ?? '')
            .toString();
    final seen = current.map(idOf).toSet();
    return <Map<String, dynamic>>[
      ...current,
      ...next.where((item) => seen.add(idOf(item))),
    ];
  }

  List<Map<String, dynamic>> _appendReferralUsers(
    List<Map<String, dynamic>> current,
    List<Map<String, dynamic>> next,
  ) {
    String idOf(Map<String, dynamic> item) {
      final inviter = Map<String, dynamic>.from(item['inviter'] as Map? ?? {});
      return (inviter['id'] ?? item['referralCode'] ?? '').toString();
    }

    final seen = current.map(idOf).toSet();
    return <Map<String, dynamic>>[
      ...current,
      ...next.where((item) => seen.add(idOf(item))),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Кошельки и бонусы'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Обзор'),
              Tab(text: 'Рефералы'),
            ],
          ),
        ),
        body: FutureBuilder<_AdminWalletAnalyticsData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _AdminWalletStateView(
                message:
                    'Не удалось загрузить бонусную активность.\n${snap.error}',
                onRetry: _refresh,
              );
            }

            final data = _data ?? snap.data!;
            return TabBarView(
              children: [
                _OverviewTab(
                  data: data,
                  onRefresh: _refresh,
                  canLoadMoreWallets:
                      _walletsHasMore && _walletsNextCursor != null,
                  walletsLoadingMore: _walletsLoadingMore,
                  onLoadMoreWallets: _loadMoreWallets,
                  canLoadMoreTransactions:
                      _transactionsHasMore && _transactionsNextCursor != null,
                  transactionsLoadingMore: _transactionsLoadingMore,
                  onLoadMoreTransactions: _loadMoreTransactions,
                ),
                _ReferralsTab(
                  data: data,
                  period: _period,
                  customRange: _customRange,
                  searchController: _searchController,
                  onPeriodChanged: _setPeriod,
                  onPickCustomRange: _pickCustomRange,
                  onSearch: _runSearch,
                  onRefresh: _refresh,
                  canLoadMore:
                      _referralsHasMore && _referralsNextCursor != null,
                  loadingMore: _referralsLoadingMore,
                  onLoadMore: _loadMoreReferrals,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.data,
    required this.onRefresh,
    required this.canLoadMoreWallets,
    required this.walletsLoadingMore,
    required this.onLoadMoreWallets,
    required this.canLoadMoreTransactions,
    required this.transactionsLoadingMore,
    required this.onLoadMoreTransactions,
  });

  final _AdminWalletAnalyticsData data;
  final Future<void> Function() onRefresh;
  final bool canLoadMoreWallets;
  final bool walletsLoadingMore;
  final VoidCallback onLoadMoreWallets;
  final bool canLoadMoreTransactions;
  final bool transactionsLoadingMore;
  final VoidCallback onLoadMoreTransactions;

  @override
  Widget build(BuildContext context) {
    final spentByReason = Map<String, dynamic>.from(
        data.analytics['spentByReason'] as Map? ?? {});
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Бонусная активность',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text(
            'Реальные платежи не подключены. Сейчас учитываются только бонусы.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _WalletSummaryCard(
                  title: 'Начислено',
                  value: '${data.analytics['totalBonusAccrued'] ?? 0}'),
              _WalletSummaryCard(
                  title: 'Списано',
                  value: '${data.analytics['totalBonusSpent'] ?? 0}'),
              _WalletSummaryCard(
                  title: 'Витрина',
                  value: '${spentByReason['promotion_showcase'] ?? 0}'),
              _WalletSummaryCard(
                  title: 'Поднятие',
                  value: '${spentByReason['promotion_bump'] ?? 0}'),
              _WalletSummaryCard(
                  title: 'VIP',
                  value: '${spentByReason['promotion_vip'] ?? 0}'),
              _WalletSummaryCard(
                  title: 'Турбо',
                  value: '${spentByReason['promotion_turbo'] ?? 0}'),
            ],
          ),
          const SizedBox(height: 16),
          Text('Кошельки', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...data.wallets.map(
            (wallet) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text((wallet['userName'] ?? 'Пользователь').toString()),
                subtitle: Text((wallet['userPhone'] ?? '').toString()),
                trailing: Text('${wallet['bonusBalance'] ?? 0}'),
              ),
            ),
          ),
          if (walletsLoadingMore)
            const _AdminLoadMoreSpinner()
          else if (canLoadMoreWallets)
            Center(
              child: TextButton.icon(
                onPressed: onLoadMoreWallets,
                icon: const Icon(Icons.expand_more),
                label: const Text('Показать ещё'),
              ),
            ),
          const SizedBox(height: 8),
          Text('Последние операции',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...data.transactions.map(
            (item) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text((item['reason'] ?? '').toString()),
                subtitle: Text((item['userName'] ?? '').toString()),
                trailing: Text(
                  '${item['amount'] ?? 0}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          if (transactionsLoadingMore)
            const _AdminLoadMoreSpinner()
          else if (canLoadMoreTransactions)
            Center(
              child: TextButton.icon(
                onPressed: onLoadMoreTransactions,
                icon: const Icon(Icons.expand_more),
                label: const Text('Показать ещё'),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminLoadMoreSpinner extends StatelessWidget {
  const _AdminLoadMoreSpinner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ReferralsTab extends StatelessWidget {
  const _ReferralsTab({
    required this.data,
    required this.period,
    required this.customRange,
    required this.searchController,
    required this.onPeriodChanged,
    required this.onPickCustomRange,
    required this.onSearch,
    required this.onRefresh,
    required this.canLoadMore,
    required this.loadingMore,
    required this.onLoadMore,
  });

  final _AdminWalletAnalyticsData data;
  final String period;
  final DateTimeRange? customRange;
  final TextEditingController searchController;
  final ValueChanged<String> onPeriodChanged;
  final VoidCallback onPickCustomRange;
  final VoidCallback onSearch;
  final Future<void> Function() onRefresh;
  final bool canLoadMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final summary = data.referralSummary;
    final hasSearch = data.referralSearch.trim().isNotEmpty;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          final metrics = notification.metrics;
          if (canLoadMore && !loadingMore && metrics.extentAfter < 700) {
            onLoadMore();
          }
          return false;
        },
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'day', label: Text('Сегодня')),
                ButtonSegment(value: 'week', label: Text('7 дней')),
                ButtonSegment(value: 'month', label: Text('Месяц')),
                ButtonSegment(value: 'custom', label: Text('Период')),
              ],
              selected: {period},
              onSelectionChanged: (value) {
                final next = value.first;
                if (next == 'custom') {
                  onPickCustomRange();
                } else {
                  onPeriodChanged(next);
                }
              },
            ),
            if (period == 'custom' && customRange != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onPickCustomRange,
                icon: const Icon(Icons.date_range),
                label: Text(
                  '${_formatDate(customRange!.start)} - ${_formatDate(customRange!.end)}',
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSearch(),
              decoration: InputDecoration(
                labelText: 'Поиск по имени, телефону, коду, userId',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Найти',
                  onPressed: onSearch,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _WalletSummaryCard(
                    title: 'Регистрации',
                    value: '${summary['newRegistrationsByInvite'] ?? 0}'),
                _WalletSummaryCard(
                    title: 'Бонусов',
                    value: '${summary['rewardedReferralBonuses'] ?? 0}'),
                _WalletSummaryCard(
                    title: 'Баллов',
                    value: '${summary['referralPointsAwarded'] ?? 0}'),
                _WalletSummaryCard(
                    title: 'Не завершено',
                    value: '${summary['unfinishedInvites'] ?? 0}'),
                _WalletSummaryCard(
                    title: 'Отказы',
                    value: '${summary['rewardFailures'] ?? 0}'),
                _WalletSummaryCard(
                    title: 'Куплено',
                    value: '${summary['pointsPurchased'] ?? 0}'),
                _WalletSummaryCard(
                    title: 'Потрачено',
                    value: '${summary['pointsSpent'] ?? 0}'),
                _WalletSummaryCard(
                    title: 'Ежедневные',
                    value: '${summary['dailyBonusesAwarded'] ?? 0}'),
              ],
            ),
            const SizedBox(height: 16),
            ...data.referralUsers.map((user) => _ReferralUserTile(item: user)),
            if (data.referralUsers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  hasSearch
                      ? 'Пользователь не найден'
                      : 'За выбранный период реферальных записей нет.',
                ),
              ),
            if (loadingMore)
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
      ),
    );
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _ReferralUserTile extends StatelessWidget {
  const _ReferralUserTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final inviter = Map<String, dynamic>.from(item['inviter'] as Map? ?? {});
    final nickname =
        (inviter['username'] ?? inviter['displayName'] ?? '').toString().trim();
    final invitations = (item['invitations'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundImage: (inviter['avatarUrl'] ?? '').toString().isNotEmpty
              ? NetworkImage(inviter['avatarUrl'].toString())
              : null,
          child: (inviter['avatarUrl'] ?? '').toString().isEmpty
              ? const Icon(Icons.person)
              : null,
        ),
        title: Text((inviter['name'] ?? 'Пользователь').toString()),
        subtitle: Text(
          'userId: ${inviter['id'] ?? ''}\n'
          '${nickname.isEmpty ? '' : 'ник: $nickname\n'}'
          'телефон: ${inviter['phone'] ?? '-'}\n'
          'referralCode: ${item['referralCode'] ?? ''}\n'
          '${item['inviteLink'] ?? ''}',
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text('${item['referralPoints'] ?? 0}'),
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('Аккаунт пригласившего'),
            subtitle: Text((inviter['id'] ?? '').toString()),
            onTap: () => _openAdminReferralUser(
              context,
              inviter,
              'Профиль пригласившего',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip('Открыли', item['openedCount']),
                _MetricChip('Зарегистр.', item['registeredCount']),
                _MetricChip('Начислено', item['rewardedCount']),
                _MetricChip('Баллы', item['referralPoints']),
                _MetricChip('Не заверш.', item['unfinishedCount']),
                _MetricChip('Отказы', item['rejectedCount']),
              ],
            ),
          ),
          ...invitations.map((invite) => _ReferralInviteTile(item: invite)),
        ],
      ),
    );
  }
}

class _ReferralInviteTile extends StatelessWidget {
  const _ReferralInviteTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final invited = Map<String, dynamic>.from(item['invited'] as Map? ?? {});
    final inviter = Map<String, dynamic>.from(item['inviter'] as Map? ?? {});
    final title = invited.isEmpty
        ? 'Регистрация не завершена'
        : (invited['name'] ?? 'Пользователь').toString();
    final reason = (item['failureText'] ?? '').toString();
    return ListTile(
      onTap: invited.isEmpty
          ? null
          : () => _openAdminReferralUser(
                context,
                invited,
                'Профиль приглашённого',
              ),
      title: Text(title),
      subtitle: Text(
        'Пригласил: ${inviter['name'] ?? ''}\n'
        'Открытие: ${item['openedAt'] ?? item['appOpenedAt'] ?? '-'}\n'
        'Регистрация завершена: ${item['registrationCompleted'] == true ? 'да' : 'нет'}; '
        'новый пользователь: ${item['isNewUser'] == true ? 'да' : 'нет'}; '
        'бонус: ${item['bonusAwarded'] == true ? 'да' : 'нет'}'
        '${reason.isNotEmpty ? '\n$reason' : ''}',
      ),
      trailing: Text('${item['rewardAmount'] ?? 0}'),
    );
  }
}

void _openAdminReferralUser(
  BuildContext context,
  Map<String, dynamic> user,
  String title,
) {
  final userId = (user['id'] ?? '').toString();
  if (userId.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => SellerPublicProfileScreen(
        sellerId: userId,
        initialSellerName: (user['name'] ?? 'Пользователь').toString(),
        initialSellerAvatar: (user['avatarUrl'] ?? '').toString(),
        initialSellerPhone: (user['phone'] ?? '').toString(),
        showAdminFields: true,
        titleText: title,
      ),
    ),
  );
}

class _MetricChip extends StatelessWidget {
  const _MetricChip(this.label, this.value);

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: ${value ?? 0}'));
  }
}

class _AdminWalletAnalyticsData {
  const _AdminWalletAnalyticsData({
    required this.wallets,
    required this.transactions,
    required this.analytics,
    required this.referralSummary,
    required this.referralUsers,
    required this.referralSearch,
  });

  final List<Map<String, dynamic>> wallets;
  final List<Map<String, dynamic>> transactions;
  final Map<String, dynamic> analytics;
  final Map<String, dynamic> referralSummary;
  final List<Map<String, dynamic>> referralUsers;
  final String referralSearch;

  _AdminWalletAnalyticsData copyWith({
    List<Map<String, dynamic>>? wallets,
    List<Map<String, dynamic>>? transactions,
  }) {
    return _AdminWalletAnalyticsData(
      wallets: wallets ?? this.wallets,
      transactions: transactions ?? this.transactions,
      analytics: analytics,
      referralSummary: referralSummary,
      referralUsers: referralUsers,
      referralSearch: referralSearch,
    );
  }
}

class _WalletSummaryCard extends StatelessWidget {
  const _WalletSummaryCard({
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
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminWalletStateView extends StatelessWidget {
  const _AdminWalletStateView({
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
