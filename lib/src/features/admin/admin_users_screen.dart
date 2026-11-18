import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/features/admin/admin_support_message_dialog.dart';
import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:atta/src/widgets/remote_avatar.dart';
import 'package:atta/src/widgets/atta_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:atta/src/theme/soft_shadows.dart';
import 'package:atta/src/widgets/standard_search_surface.dart';
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
  DateTimeRange? _selectedRegistrationRange;
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
    final range = _selectedRegistrationRange;
    return context.read<AdminService>().userRegistrationStats(
          year: statsYear,
          from: range == null ? null : _apiDate(range.start),
          to: range == null ? null : _apiDate(range.end),
          forceRefresh: forceRefresh,
        );
  }

  static String _apiDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

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

  bool _phoneVerified(Map<String, dynamic> item) =>
      item['phone_verified'] == true ||
      item['phoneVerified'] == true ||
      item['isPhoneVerified'] == true;

  bool _emailVerified(Map<String, dynamic> item) =>
      item['email_verified'] == true ||
      item['emailVerified'] == true ||
      _value(item, const ['email_verified_at', 'emailVerifiedAt']).isNotEmpty;

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

  String _registrationDate(Map<String, dynamic> item) {
    final raw = _value(item, const ['created_at', 'createdAt']);
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return 'Дата не указана';
    final moscow = parsed.toUtc().add(const Duration(hours: 3));
    return '${moscow.day.toString().padLeft(2, '0')}.'
        '${moscow.month.toString().padLeft(2, '0')}.${moscow.year} · '
        '${moscow.hour.toString().padLeft(2, '0')}:'
        '${moscow.minute.toString().padLeft(2, '0')}';
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
            initialSellerEmail:
                _value(details.isEmpty ? item : details, const ['email']),
            initialPhoneVerified:
                _phoneVerified(details.isEmpty ? item : details),
            initialEmailVerified:
                _emailVerified(details.isEmpty ? item : details),
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
              child: StandardSearchSurface(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _runSearch(),
                  decoration: InputDecoration(
                    labelText: 'Поиск по имени, телефону, Email, userId',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'Найти',
                      onPressed: _runSearch,
                    ),
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
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
                    selectedRange: _selectedRegistrationRange,
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
                    onRangeChanged: (range) {
                      setState(() => _selectedRegistrationRange = range);
                      return _reloadRegistrationStats(forceRefresh: true);
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

                      return AttaRefreshIndicator(
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
                              margin: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _busy ? null : () => _openUser(item),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    8,
                                    8,
                                  ),
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
                                            radius: 18,
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
                                          TextButton.icon(
                                            key: ValueKey(
                                              'copy-user-id-${_value(item, const [
                                                    'id'
                                                  ])}',
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : () => _copyUserId(
                                                      _value(
                                                          item, const ['id']),
                                                    ),
                                            style: TextButton.styleFrom(
                                              minimumSize: const Size(0, 30),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                              ),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            icon: const Icon(
                                              Icons.copy_outlined,
                                              size: 14,
                                            ),
                                            label: const Text(
                                              'ID',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _UserContactsInfo(
                                              phone:
                                                  _value(item, const ['phone']),
                                              email:
                                                  _value(item, const ['email']),
                                              phoneVerified:
                                                  _phoneVerified(item),
                                              emailVerified:
                                                  _emailVerified(item),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: _UserCompactInfo(
                                              icon: Icons.event_outlined,
                                              text: _registrationDate(item),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          if (isAdmin) const _UserAdminBadge(),
                                          const Spacer(),
                                          IconButton(
                                            tooltip: 'Написать пользователю',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: _busy
                                                ? null
                                                : () =>
                                                    _writeSupportMessage(item),
                                            icon: const Icon(
                                              Icons.chat_bubble_outline,
                                              size: 19,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: isProtectedAdmin
                                                ? 'Администратор защищён'
                                                : 'Удалить пользователя',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: _busy || isProtectedAdmin
                                                ? null
                                                : () => _deleteUser(item),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 19,
                                            ),
                                          ),
                                        ],
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

class _UserCompactInfo extends StatelessWidget {
  const _UserCompactInfo({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF667085)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text.isEmpty ? 'Не указано' : text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF475467),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

class _UserContactsInfo extends StatelessWidget {
  const _UserContactsInfo({
    required this.phone,
    required this.email,
    required this.phoneVerified,
    required this.emailVerified,
  });

  final String phone;
  final String email;
  final bool phoneVerified;
  final bool emailVerified;

  @override
  Widget build(BuildContext context) {
    final contacts = <Widget>[
      if (phone.trim().isNotEmpty)
        _UserContactLine(
          icon: Icons.phone_outlined,
          text: formatRussianPhone(phone),
          verified: phoneVerified,
        ),
      if (email.trim().isNotEmpty)
        _UserContactLine(
          icon: Icons.email_outlined,
          text: email.trim(),
          verified: emailVerified,
        ),
    ];
    if (contacts.isEmpty) {
      return const _UserContactLine(
        icon: Icons.contact_phone_outlined,
        text: 'Не указано',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < contacts.length; index++) ...[
          if (index > 0) const SizedBox(height: 3),
          contacts[index],
        ],
      ],
    );
  }
}

class _UserContactLine extends StatelessWidget {
  const _UserContactLine({
    required this.icon,
    required this.text,
    this.verified,
  });

  final IconData icon;
  final String text;
  final bool? verified;

  @override
  Widget build(BuildContext context) {
    final isVerified = verified == true;
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF667085)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF475467),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        if (verified != null) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: isVerified ? 'Подтверждён' : 'Не подтверждён',
            child: Icon(
              isVerified ? Icons.verified_rounded : Icons.error_outline_rounded,
              key: ValueKey(
                '${isVerified ? 'verified' : 'unverified'}-${icon.codePoint}-$text',
              ),
              size: 14,
              color: isVerified
                  ? const Color(0xFF12B76A)
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ],
    );
  }
}

class _UserAdminBadge extends StatelessWidget {
  const _UserAdminBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'Администратор',
          style: TextStyle(
            color: Color(0xFF175CD3),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _RegistrationStatsView extends StatefulWidget {
  const _RegistrationStatsView({
    required this.future,
    required this.selectedYear,
    required this.selectedRange,
    required this.onRefresh,
    required this.onYearChanged,
    required this.onRangeChanged,
  });

  final Future<Map<String, dynamic>> future;
  final int? selectedYear;
  final DateTimeRange? selectedRange;
  final Future<void> Function() onRefresh;
  final Future<void> Function(int year) onYearChanged;
  final Future<void> Function(DateTimeRange? range) onRangeChanged;

  @override
  State<_RegistrationStatsView> createState() => _RegistrationStatsViewState();
}

class _RegistrationStatsViewState extends State<_RegistrationStatsView> {
  int? _selectedMonth;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: widget.future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _AdminStateView(
            message: 'Не удалось загрузить регистрации.\n${snapshot.error}',
            onRetry: widget.onRefresh,
          );
        }

        final data = snapshot.data ?? const <String, dynamic>{};
        final years = _intList(data['available_years']);
        final moscowNow = _moscowNow();
        final year = _intValue(data['year']) ??
            widget.selectedYear ??
            (years.isNotEmpty ? years.last : moscowNow.year);
        final months = _completeMonthRows(_monthRows(data['months']));
        final totalUsers = _intValue(data['total_users']) ?? 0;
        final todayCount =
            _intValue(data['todayCount'] ?? data['today_count']) ?? 0;
        final yesterdayCount = _intValue(data['yesterday_count']) ?? 0;
        final last7DaysCount = _intValue(data['last_7_days_count']) ?? 0;
        final currentMonthCount = _intValue(data['current_month_count']) ?? 0;
        final phoneRegistrationCount =
            _intValue(data['phone_registration_count']) ?? 0;
        final emailRegistrationCount =
            _intValue(data['email_registration_count']) ?? 0;
        final unknownRegistrationCount =
            _intValue(data['unknown_registration_count']) ?? 0;
        final selectedYearCount = months.fold<int>(
          0,
          (total, row) => total + row.count,
        );
        final customRange = data['custom_range'];
        final customRangeCount =
            customRange is Map ? _intValue(customRange['count']) : null;

        final currentMonth = year == moscowNow.year ? moscowNow.month : 0;
        final selectedMonth =
            _selectedMonth ?? (currentMonth == 0 ? 1 : currentMonth);
        final selectedRow = months.firstWhere(
          (row) => row.month == selectedMonth,
          orElse: () => months.first,
        );
        final compareText = _comparisonText(months, selectedRow.month);

        return AttaRefreshIndicator(
          onRefresh: widget.onRefresh,
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
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE6EAF0)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            key: const ValueKey('registration-year-selector'),
                            value: years.contains(year) ? year : years.last,
                            borderRadius: BorderRadius.circular(8),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
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
                                widget.onYearChanged(value);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _RegistrationSummaryCards(
                totalUsers: totalUsers,
                todayCount: todayCount,
                yesterdayCount: yesterdayCount,
                last7DaysCount: last7DaysCount,
                currentMonthCount: currentMonthCount,
                selectedYear: year,
                selectedYearCount: selectedYearCount,
                phoneRegistrationCount: phoneRegistrationCount,
                emailRegistrationCount: emailRegistrationCount,
                unknownRegistrationCount: unknownRegistrationCount,
              ),
              const SizedBox(height: 12),
              _RegistrationRangeSelector(
                range: widget.selectedRange,
                count: customRangeCount,
                onChanged: widget.onRangeChanged,
              ),
              const SizedBox(height: 18),
              _RegistrationYearChart(
                months: months,
                currentMonth: currentMonth,
                selectedMonth: selectedRow.month,
                onMonthSelected: (month) {
                  setState(() => _selectedMonth = month);
                },
              ),
              const SizedBox(height: 14),
              Text(
                '${_monthName(selectedRow.month)} — ${selectedRow.count} '
                '${_registrationsWord(selectedRow.count)}',
                key: const ValueKey('registration-selected-month-summary'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                compareText,
                key: const ValueKey('registration-month-comparison'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF667085),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }

  static DateTime _moscowNow() {
    return DateTime.now().toUtc().add(const Duration(hours: 3));
  }

  static List<_MonthRegistrationRow> _completeMonthRows(
    List<_MonthRegistrationRow> source,
  ) {
    final byMonth = <int, int>{
      for (final row in source) row.month: row.count,
    };
    return List<_MonthRegistrationRow>.generate(
      12,
      (index) => _MonthRegistrationRow(
        month: index + 1,
        count: byMonth[index + 1] ?? 0,
      ),
      growable: false,
    );
  }

  static String _comparisonText(List<_MonthRegistrationRow> months, int month) {
    if (month <= 1) {
      return 'Нет данных для сравнения с предыдущим месяцем';
    }
    final current = months.firstWhere((row) => row.month == month).count;
    final previous = months.firstWhere((row) => row.month == month - 1).count;
    if (previous == 0) {
      return 'В предыдущем месяце регистраций не было';
    }
    final diff = ((current - previous) / previous * 100).round();
    if (diff == 0) {
      return 'Без изменений к ${_monthDativeName(month - 1)}';
    }
    final sign = diff > 0 ? '+' : '−';
    return '$sign${diff.abs()}% к ${_monthDativeName(month - 1)}';
  }

  static String _registrationsWord(int value) {
    final mod10 = value % 10;
    final mod100 = value % 100;
    if (mod10 == 1 && mod100 != 11) return 'регистрация';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'регистрации';
    }
    return 'регистраций';
  }

  static String _monthDativeName(int month) {
    const names = <int, String>{
      1: 'январю',
      2: 'февралю',
      3: 'марту',
      4: 'апрелю',
      5: 'маю',
      6: 'июню',
      7: 'июлю',
      8: 'августу',
      9: 'сентябрю',
      10: 'октябрю',
      11: 'ноябрю',
      12: 'декабрю',
    };
    return names[month] ?? 'прошлому месяцу';
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

  static String _monthShortName(int month) {
    const names = <int, String>{
      1: 'Янв',
      2: 'Фев',
      3: 'Мар',
      4: 'Апр',
      5: 'Май',
      6: 'Июн',
      7: 'Июл',
      8: 'Авг',
      9: 'Сен',
      10: 'Окт',
      11: 'Ноя',
      12: 'Дек',
    };
    return names[month] ?? '$month';
  }
}

class _RegistrationSummaryCards extends StatelessWidget {
  const _RegistrationSummaryCards({
    required this.totalUsers,
    required this.todayCount,
    required this.yesterdayCount,
    required this.last7DaysCount,
    required this.currentMonthCount,
    required this.selectedYear,
    required this.selectedYearCount,
    required this.phoneRegistrationCount,
    required this.emailRegistrationCount,
    required this.unknownRegistrationCount,
  });

  final int totalUsers;
  final int todayCount;
  final int yesterdayCount;
  final int last7DaysCount;
  final int currentMonthCount;
  final int selectedYear;
  final int selectedYearCount;
  final int phoneRegistrationCount;
  final int emailRegistrationCount;
  final int unknownRegistrationCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 560;
        const spacing = 8.0;
        final columns = isCompact ? 2 : 3;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            _RegistrationSummaryCard(
              key: const ValueKey('registration-total-users-card'),
              width: cardWidth,
              label: 'Всего',
              value: '$totalUsers',
            ),
            _RegistrationSummaryCard(
              key: const ValueKey('registration-phone-card'),
              width: cardWidth,
              label: 'По телефону',
              value: '$phoneRegistrationCount',
            ),
            _RegistrationSummaryCard(
              key: const ValueKey('registration-email-card'),
              width: cardWidth,
              label: 'По Email',
              value: '$emailRegistrationCount',
            ),
            if (unknownRegistrationCount > 0)
              _RegistrationSummaryCard(
                key: const ValueKey('registration-unknown-card'),
                width: cardWidth,
                label: 'Не определено',
                value: '$unknownRegistrationCount',
              ),
            _RegistrationSummaryCard(
              key: const ValueKey('registration-today-card'),
              width: cardWidth,
              label: 'Сегодня',
              value: '$todayCount',
            ),
            _RegistrationSummaryCard(
              key: const ValueKey('registration-yesterday-card'),
              width: cardWidth,
              label: 'Вчера',
              value: '$yesterdayCount',
            ),
            _RegistrationSummaryCard(
              key: const ValueKey('registration-last-7-days-card'),
              width: cardWidth,
              label: 'За 7 дней',
              value: '$last7DaysCount',
            ),
            _RegistrationSummaryCard(
              key: const ValueKey('registration-current-month-card'),
              width: cardWidth,
              label: 'В этом месяце',
              value: '$currentMonthCount',
            ),
            _RegistrationSummaryCard(
              key: const ValueKey('registration-selected-year-card'),
              width: cardWidth,
              label: 'За $selectedYear',
              value: '$selectedYearCount',
            ),
          ],
        );
      },
    );
  }
}

class _RegistrationRangeSelector extends StatelessWidget {
  const _RegistrationRangeSelector({
    required this.range,
    required this.count,
    required this.onChanged,
  });

  final DateTimeRange? range;
  final int? count;
  final Future<void> Function(DateTimeRange? range) onChanged;

  static String _dateLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year}';

  Future<void> _selectRange(BuildContext context) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: range,
      helpText: 'Регистрации за период',
      cancelText: 'Отмена',
      confirmText: 'Показать',
      saveText: 'Показать',
    );
    if (selected != null) await onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final selectedRange = range;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE3E8EF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.date_range_outlined, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedRange == null
                        ? 'Выбрать период'
                        : '${_dateLabel(selectedRange.start)} — '
                            '${_dateLabel(selectedRange.end)}',
                    key: const ValueKey('registration-custom-range-label'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    selectedRange == null
                        ? 'Посмотреть регистрации с даты по дату'
                        : '${count ?? 0} ${_RegistrationStatsViewState._registrationsWord(count ?? 0)}',
                    key: const ValueKey('registration-custom-range-count'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF667085),
                        ),
                  ),
                ],
              ),
            ),
            if (selectedRange != null)
              IconButton(
                key: const ValueKey('registration-custom-range-clear'),
                tooltip: 'Сбросить период',
                visualDensity: VisualDensity.compact,
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close, size: 18),
              ),
            TextButton(
              key: const ValueKey('registration-custom-range-button'),
              onPressed: () => _selectRange(context),
              child: Text(selectedRange == null ? 'Выбрать' : 'Изменить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegistrationSummaryCard extends StatelessWidget {
  const _RegistrationSummaryCard({
    super.key,
    required this.width,
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: 94,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.outlineVariant),
          boxShadow: attaSoftCardShadows(context),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF667085),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: textTheme.titleLarge?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegistrationYearChart extends StatelessWidget {
  const _RegistrationYearChart({
    required this.months,
    required this.currentMonth,
    required this.selectedMonth,
    required this.onMonthSelected,
  });

  final List<_MonthRegistrationRow> months;
  final int currentMonth;
  final int selectedMonth;
  final ValueChanged<int> onMonthSelected;

  @override
  Widget build(BuildContext context) {
    final maxCount = months.fold<int>(
      0,
      (max, row) => row.count > max ? row.count : max,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8ECF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Динамика за год',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 168,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: months.map((row) {
                  final isCurrent = row.month == currentMonth;
                  final isSelected = row.month == selectedMonth;
                  return Expanded(
                    child: _RegistrationMonthBar(
                      key: ValueKey('registration-month-bar-${row.month}'),
                      row: row,
                      maxCount: maxCount,
                      isCurrent: isCurrent,
                      isSelected: isSelected,
                      onTap: () => onMonthSelected(row.month),
                    ),
                  );
                }).toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegistrationMonthBar extends StatelessWidget {
  const _RegistrationMonthBar({
    super.key,
    required this.row,
    required this.maxCount,
    required this.isCurrent,
    required this.isSelected,
    required this.onTap,
  });

  final _MonthRegistrationRow row;
  final int maxCount;
  final bool isCurrent;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final normalized = maxCount == 0 ? 0.0 : row.count / maxCount;
    final barHeight = row.count == 0 ? 5.0 : 18.0 + normalized * 86.0;
    final barColor = isCurrent
        ? const Color(0xFF0B6BFF)
        : isSelected
            ? const Color(0xFF98A2B3)
            : const Color(0xFFD9DEE7);
    final labelColor = isCurrent || isSelected
        ? const Color(0xFF101828)
        : const Color(0xFF667085);

    return Semantics(
      button: true,
      label:
          '${_RegistrationStatsViewState._monthName(row.month)}: ${row.count}',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: 24,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${row.count}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF667085),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: isSelected ? 15 : 12,
                height: barHeight,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _RegistrationStatsViewState._monthShortName(row.month),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: labelColor,
                        fontWeight: isCurrent || isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
