import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/features/admin/admin_support_message_dialog.dart';
import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:atta/src/widgets/remote_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  static const int _pageLimit = 50;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;
  Future<Map<String, dynamic>>? _registrationStatsFuture;
  bool _busy = false;
  bool _showRegistrationStats = false;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  String? _nextCursor;
  bool _hasMore = true;
  bool _loadingMore = false;
  Object? _loadMoreError;
  int? _selectedStatsYear;
  int _requestSerial = 0;

  static const Set<String> _protectedAdminPhones = <String>{
    '79288888645',
    '79306939954',
  };

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
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load({
    bool forceRefresh = false,
    String? cursor,
    bool append = false,
    int? serial,
  }) async {
    final requestSerial = serial ?? ++_requestSerial;
    final response = await context.read<AdminService>().users(
          forceRefresh: forceRefresh,
          limit: _pageLimit,
          cursor: cursor,
          search: _searchController.text.trim(),
        );
    if (requestSerial != _requestSerial) {
      return _items;
    }
    final raw = response['items'];
    final items = raw is! List
        ? const <Map<String, dynamic>>[]
        : raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
    final nextCursor = (response['nextCursor'] ?? '').toString().trim();
    final hasMore = response['hasMore'] == true || nextCursor.isNotEmpty;
    if (mounted) {
      setState(() {
        _items = append ? _appendDeduped(_items, items) : items;
        _nextCursor = nextCursor.isEmpty ? null : nextCursor;
        _hasMore = hasMore;
        _loadingMore = false;
        _loadMoreError = null;
      });
    } else {
      _items = append ? _appendDeduped(_items, items) : items;
      _nextCursor = nextCursor.isEmpty ? null : nextCursor;
      _hasMore = hasMore;
      _loadingMore = false;
    }
    return _items;
  }

  Future<void> _refresh() async {
    final serial = ++_requestSerial;
    setState(() {
      _nextCursor = null;
      _hasMore = true;
      _loadingMore = false;
      _loadMoreError = null;
    });
    final next = _load(forceRefresh: true, serial: serial);
    setState(() {
      _future = next;
    });
    await next;
  }

  void _runSearch() {
    final serial = ++_requestSerial;
    setState(() {
      _items = const <Map<String, dynamic>>[];
      _nextCursor = null;
      _hasMore = true;
      _loadingMore = false;
      _loadMoreError = null;
      _future = _load(forceRefresh: true, serial: serial);
    });
  }

  void _showUsersTab() {
    if (!_showRegistrationStats) return;
    setState(() => _showRegistrationStats = false);
  }

  void _showRegistrationsTab() {
    if (_showRegistrationStats) return;
    setState(() {
      _showRegistrationStats = true;
      _registrationStatsFuture ??= _loadRegistrationStats();
    });
  }

  Future<Map<String, dynamic>> _loadRegistrationStats({
    bool forceRefresh = false,
    int? year,
  }) {
    final statsYear = year ?? _selectedStatsYear;
    return context.read<AdminService>().userRegistrationStats(
          year: statsYear,
          forceRefresh: forceRefresh,
        );
  }

  Future<void> _reloadRegistrationStats({
    bool forceRefresh = false,
    int? year,
  }) async {
    final next = _loadRegistrationStats(forceRefresh: forceRefresh, year: year);
    setState(() {
      _registrationStatsFuture = next;
    });
    await next;
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients ||
        !_hasMore ||
        _loadingMore ||
        _busy ||
        _nextCursor == null) {
      return;
    }
    final position = _scrollController.position;
    if (position.extentAfter > 700) return;
    _loadMore();
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore || !_hasMore) return;
    final serial = _requestSerial;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      await _load(cursor: cursor, append: true, serial: serial);
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = error;
      });
    }
  }

  List<Map<String, dynamic>> _appendDeduped(
    List<Map<String, dynamic>> current,
    List<Map<String, dynamic>> next,
  ) {
    final seen = current.map((item) => _value(item, const ['id'])).toSet();
    return <Map<String, dynamic>>[
      ...current,
      ...next.where((item) => seen.add(_value(item, const ['id']))),
    ];
  }

  Future<void> _deleteUser(Map<String, dynamic> item) async {
    final userId = (item['id'] ?? '').toString();
    final currentUserId = context.read<AuthService>().currentUser?.uid ?? '';
    final isSelf = userId == currentUserId;
    final phone = _value(item, const ['phone']);
    final isProtectedAdmin = _protectedAdminPhones.contains(phone);

    if (isProtectedAdmin) {
      showAppSnack(
        context,
        'Этот администратор защищён от удаления',
        isError: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title:
                Text(isSelf ? 'Удалить самого себя?' : 'Удалить пользователя?'),
            content: Text(
              isSelf
                  ? 'Это ваш аккаунт администратора. Такое удаление опасно и будет заблокировано сервером.'
                  : 'Профиль будет деактивирован, а его объявления станут скрыты.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    if (!mounted) return;

    final adminService = context.read<AdminService>();
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await adminService.deleteUser(userId);
      if (!mounted) return;
      if (response['deleted'] == true) {
        setState(() {
          _items = _items
              .where((candidate) =>
                  (candidate['id'] ?? '').toString().trim() != userId)
              .toList(growable: false);
          _future = Future<List<Map<String, dynamic>>>.value(_items);
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Пользователь удалён')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              (response['message'] ?? 'Не удалось удалить пользователя')
                  .toString(),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка удаления пользователя: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _value(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _avatarUrl(Map<String, dynamic> item) {
    return _value(
      item,
      const ['avatar_url', 'avatarUrl', 'photo_url', 'photoUrl'],
    );
  }

  bool _isProtectedAdmin(Map<String, dynamic> item) {
    return _protectedAdminPhones.contains(_value(item, const ['phone']));
  }

  String _supportHandle(Map<String, dynamic> item) {
    final nickname = _value(
      item,
      const ['nickname', 'username', 'user_name', 'display_name'],
    );
    if (nickname.isNotEmpty) return '@$nickname';
    return _maskedPhone(_value(item, const ['phone']));
  }

  String _maskedPhone(String rawPhone) {
    final digits = normalizeRuPhoneForApi(rawPhone);
    if (digits.length < 5) return '';
    return '+${digits.substring(0, 1)} *** *** ${digits.substring(digits.length - 4)}';
  }

  Future<void> _writeSupportMessage(Map<String, dynamic> item) async {
    final userId = _value(item, const ['id']);
    if (userId.isEmpty || _busy) return;
    final result = await showAdminSupportMessageDialog(
      context: context,
      userId: userId,
      userName: _value(item, const ['display_name', 'name', 'email', 'phone']),
      userHandle: _supportHandle(item),
    );
    if (!mounted || result == null) return;
    showAppSnack(context, 'Сообщение отправлено');
  }

  String _statusLabel(Map<String, dynamic> item) {
    if ((item['deleted_at'] ?? '').toString().trim().isNotEmpty) {
      return 'Удалён';
    }
    final status = (item['status'] ?? '').toString().trim().toLowerCase();
    switch (status) {
      case 'blocked':
        return 'Заблокирован';
      case 'inactive':
        return 'Неактивен';
      default:
        return 'Активен';
    }
  }

  Future<void> _openUser(Map<String, dynamic> item) async {
    final userId = _value(item, const ['id']);
    if (userId.isEmpty) return;

    try {
      final response = await context.read<AdminService>().userById(userId);
      final raw = response['user'];
      final details = raw is Map
          ? raw.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SellerPublicProfileScreen(
            sellerId: userId,
            initialSellerName: _value(
              details.isEmpty ? item : details,
              const ['display_name', 'name', 'email', 'phone'],
            ),
            initialSellerAvatar: _avatarUrl(details.isEmpty ? item : details),
            initialSellerPhone:
                _value(details.isEmpty ? item : details, const ['phone']),
            initialStatusLabel: _statusLabel(details.isEmpty ? item : details),
            initialIsAdmin:
                (details['is_admin'] == true || details['isAdmin'] == true) ||
                    item['is_admin'] == true ||
                    item['isAdmin'] == true,
            showAdminFields: true,
            titleText: 'Профиль пользователя',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnack(
        context,
        'Не удалось открыть профиль пользователя: $e',
        isError: true,
      );
    }
  }

  Future<void> _copyUserId(String userId) async {
    final value = userId.trim();
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    showAppSnack(context, 'ID скопирован');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Пользователи')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Пользователи'),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Регистрации'),
                ),
              ],
              selected: <bool>{_showRegistrationStats},
              onSelectionChanged: (selection) {
                final showStats = selection.first;
                if (showStats) {
                  _showRegistrationsTab();
                } else {
                  _showUsersTab();
                }
              },
            ),
          ),
          if (!_showRegistrationStats)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  labelText: 'Поиск по имени, телефону, userId',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Найти',
                    onPressed: _runSearch,
                  ),
                ),
              ),
            ),
          Expanded(
            child: _showRegistrationStats
                ? _RegistrationStatsView(
                    future: _registrationStatsFuture ??=
                        _loadRegistrationStats(),
                    selectedYear: _selectedStatsYear,
                    onRefresh: () => _reloadRegistrationStats(
                      forceRefresh: true,
                    ),
                    onYearChanged: (year) {
                      setState(() => _selectedStatsYear = year);
                      return _reloadRegistrationStats(
                        forceRefresh: true,
                        year: year,
                      );
                    },
                  )
                : FutureBuilder<List<Map<String, dynamic>>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError && _items.isEmpty) {
                        return _AdminStateView(
                          message:
                              'Не удалось загрузить пользователей.\n${snap.error}',
                          onRetry: _refresh,
                        );
                      }

                      final items = _items.isNotEmpty
                          ? _items
                          : (snap.data ?? const <Map<String, dynamic>>[]);
                      if (items.isEmpty) {
                        return _AdminStateView(
                          message: 'Пользователи пока не получены из Timeweb.',
                          onRetry: _refresh,
                          showButton: false,
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: items.length + 1,
                          itemBuilder: (context, index) {
                            if (index == items.length) {
                              if (_loadingMore) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }
                              if (_loadMoreError != null) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: Text(
                                      'Не удалось догрузить: $_loadMoreError',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox(height: 12);
                            }
                            final item = items[index];
                            final name = _value(
                              item,
                              const ['display_name', 'name', 'email', 'phone'],
                            );
                            final isAdmin = item['is_admin'] == true ||
                                item['isAdmin'] == true;
                            final isProtectedAdmin = _isProtectedAdmin(item);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _busy ? null : () => _openUser(item),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          RemoteAvatar(
                                            imageUrl: _avatarUrl(item),
                                            fallbackText: name.isEmpty
                                                ? 'Пользователь'
                                                : name,
                                            radius: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  name.isEmpty
                                                      ? 'Пользователь'
                                                      : name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _statusLabel(item),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .outline,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.chevron_right),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Телефон: ${formatRussianPhone(_value(item, const [
                                              'phone'
                                            ]))}',
                                      ),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'User ID: ${_value(item, const [
                                                    'id'
                                                  ])}',
                                            ),
                                          ),
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            tooltip: 'Скопировать ID',
                                            onPressed: _busy
                                                ? null
                                                : () => _copyUserId(
                                                      _value(
                                                          item, const ['id']),
                                                    ),
                                            icon: const Icon(Icons.copy,
                                                size: 18),
                                          ),
                                        ],
                                      ),
                                      Text(
                                          'Дата регистрации: ${_value(item, const [
                                            'created_at'
                                          ])}'),
                                      Text('Last seen: ${_value(item, const [
                                            'last_seen',
                                            'last_login_at'
                                          ])}'),
                                      Text('Admin: ${isAdmin ? 'да' : 'нет'}'),
                                      if (isProtectedAdmin)
                                        const Text('Защита: включена'),
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          alignment: WrapAlignment.end,
                                          children: [
                                            FilledButton.tonalIcon(
                                              onPressed: _busy
                                                  ? null
                                                  : () => _writeSupportMessage(
                                                      item),
                                              icon: const Icon(
                                                  Icons.support_agent),
                                              label: const Text('Написать'),
                                            ),
                                            OutlinedButton(
                                              onPressed:
                                                  _busy || isProtectedAdmin
                                                      ? null
                                                      : () => _deleteUser(item),
                                              child: Text(
                                                isProtectedAdmin
                                                    ? 'Защищён'
                                                    : 'Удалить',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RegistrationStatsView extends StatelessWidget {
  const _RegistrationStatsView({
    required this.future,
    required this.selectedYear,
    required this.onRefresh,
    required this.onYearChanged,
  });

  final Future<Map<String, dynamic>> future;
  final int? selectedYear;
  final Future<void> Function() onRefresh;
  final Future<void> Function(int year) onYearChanged;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _AdminStateView(
            message: 'Не удалось загрузить регистрации.\n${snapshot.error}',
            onRetry: onRefresh,
          );
        }

        final data = snapshot.data ?? const <String, dynamic>{};
        final years = _intList(data['available_years']);
        final year = _intValue(data['year']) ??
            selectedYear ??
            (years.isNotEmpty ? years.last : DateTime.now().year);
        final months = _monthRows(data['months']);
        final totalUsers = _intValue(data['total_users']) ?? 0;
        final currentMonthCount = _intValue(data['current_month_count']) ?? 0;

        if (totalUsers == 0 && months.isEmpty) {
          return _AdminStateView(
            message: 'Регистраций пока нет.',
            onRetry: onRefresh,
            showButton: false,
          );
        }

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Регистрации',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (years.isNotEmpty)
                    DropdownButton<int>(
                      value: years.contains(year) ? year : years.last,
                      items: years
                          .map(
                            (value) => DropdownMenuItem<int>(
                              value: value,
                              child: Text('$value'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          onYearChanged(value);
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _StatsMetricRow(
                label: 'Всего пользователей',
                value: totalUsers,
              ),
              _StatsMetricRow(
                label: 'За этот месяц',
                value: currentMonthCount,
              ),
              const SizedBox(height: 12),
              if (months.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('За выбранный год регистраций нет.'),
                )
              else
                ...months.map(
                  (row) => _StatsMetricRow(
                    label: _monthName(row.month),
                    value: row.count,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString());
  }

  static List<int> _intList(Object? value) {
    if (value is! List) return const <int>[];
    return value.map(_intValue).whereType<int>().toList(growable: false);
  }

  static List<_MonthRegistrationRow> _monthRows(Object? value) {
    if (value is! List) return const <_MonthRegistrationRow>[];
    return value.whereType<Map>().map((raw) {
      return _MonthRegistrationRow(
        month: _intValue(raw['month']) ?? 0,
        count: _intValue(raw['count']) ?? 0,
      );
    }).where((row) {
      return row.month >= 1 && row.month <= 12;
    }).toList(growable: false);
  }

  static String _monthName(int month) {
    const names = <int, String>{
      1: 'Январь',
      2: 'Февраль',
      3: 'Март',
      4: 'Апрель',
      5: 'Май',
      6: 'Июнь',
      7: 'Июль',
      8: 'Август',
      9: 'Сентябрь',
      10: 'Октябрь',
      11: 'Ноябрь',
      12: 'Декабрь',
    };
    return names[month] ?? '$month';
  }
}

class _MonthRegistrationRow {
  const _MonthRegistrationRow({
    required this.month,
    required this.count,
  });

  final int month;
  final int count;
}

class _StatsMetricRow extends StatelessWidget {
  const _StatsMetricRow({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(label, style: textTheme.bodyLarge)),
          Text(
            '$value',
            style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _AdminStateView extends StatelessWidget {
  const _AdminStateView({
    required this.message,
    required this.onRetry,
    this.showButton = true,
  });

  final String message;
  final Future<void> Function() onRetry;
  final bool showButton;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (showButton) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Повторить'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
