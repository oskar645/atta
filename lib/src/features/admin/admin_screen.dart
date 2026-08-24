import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/features/admin/admin_listings_screen.dart';
import 'package:atta/src/features/admin/admin_online_users_screen.dart';
import 'package:atta/src/features/admin/admin_points_purchases_screen.dart';
import 'package:atta/src/features/admin/admin_promotions_screen.dart';
import 'package:atta/src/features/admin/admin_reports_screen.dart';
import 'package:atta/src/features/admin/admin_today_visits_screen.dart';
import 'package:atta/src/features/admin/admin_users_screen.dart';
import 'package:atta/src/features/admin/admin_wallet_analytics_screen.dart';
import 'package:atta/src/features/admin/admin_ads_tab.dart';
import 'package:atta/src/features/admin/admin_blocks_screen.dart';
import 'admin_support_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/saved_search_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:atta/src/widgets/admin_copy_user_id_button.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:atta/src/widgets/skeletons.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({
    super.key,
    this.initialTabIndex = 0,
    this.initialReportId = '',
  });

  final int initialTabIndex;
  final String initialReportId;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  Stream<bool>? _isAdminStream;
  Stream<int>? _pendingModerationCountStream;
  Stream<int>? _unreadSupportCountStream;
  Stream<int>? _openReportsCountStream;
  String? _streamUid;
  bool _didMarkInitialSection = false;

  void _ensureAdminStreams(String uid) {
    if (_streamUid == uid &&
        _isAdminStream != null &&
        _pendingModerationCountStream != null &&
        _unreadSupportCountStream != null &&
        _openReportsCountStream != null) {
      return;
    }
    final admin = context.read<AdminService>();
    admin.bindAdminUser(uid);
    _streamUid = uid;
    _isAdminStream = admin.streamIsAdmin(uid);
    _pendingModerationCountStream = admin.streamPendingModerationCount();
    _unreadSupportCountStream = admin.streamUnreadSupportForAdminCount();
    _openReportsCountStream = admin.streamOpenReportsCount();
  }

  Widget _tabWithAlert(String text, int unreadCount) {
    final hasAlert = unreadCount > 0;
    return Tab(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text),
            if (hasAlert) ...[
              const SizedBox(width: 6),
              Container(
                key: ValueKey('admin-tab-badge:$text'),
                padding: EdgeInsets.symmetric(
                  horizontal: unreadCount > 9 ? 5 : 4,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 9,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 8),
    );
    _tab.addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tab.removeListener(_handleTabChanged);
    _tab.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tab.indexIsChanging) {
      return;
    }
    _markCurrentSectionSeen();
  }

  void _markCurrentSectionSeen() {
    final admin = context.read<AdminService>();
    switch (_tab.index) {
      case 1:
        unawaited(admin.markSectionSeen(AdminService.moderationSection));
        break;
      case 2:
        unawaited(admin.markSectionSeen(AdminService.supportSection));
        break;
      case 3:
        unawaited(admin.markSectionSeen(AdminService.reportsSection));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<AuthService>().currentUser;
    final uid = me?.uid ?? '';
    if (uid.isEmpty) {
      return const Scaffold(body: Center(child: Text('Нужно войти')));
    }
    _ensureAdminStreams(uid);

    return StreamBuilder<bool>(
      stream: _isAdminStream,
      initialData: false,
      builder: (context, adminSnap) {
        if (adminSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (adminSnap.hasError) {
          final error = adminSnap.error;
          final message =
              error is ApiException && error.message.trim().isNotEmpty
                  ? error.message.trim()
                  : 'Не удалось проверить права администратора';
          return Scaffold(
            appBar: AppBar(title: const Text('Админ-Панель')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (adminSnap.data != true) {
          return Scaffold(
            appBar: AppBar(title: const Text('Админ-Панель')),
            body: const Center(
              child: Text('Доступ запрещен: только для администраторов'),
            ),
          );
        }

        if (!_didMarkInitialSection) {
          _didMarkInitialSection = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _markCurrentSectionSeen();
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Админ-Панель'),
            bottom: TabBar(
              controller: _tab,
              isScrollable: true,
              tabs: [
                _tabWithAlert('Дашборд', 0),
                StreamBuilder<int>(
                  stream: _pendingModerationCountStream,
                  builder: (context, snap) =>
                      _tabWithAlert('Модерация', snap.data ?? 0),
                ),
                StreamBuilder<int>(
                  stream: _unreadSupportCountStream,
                  builder: (context, snap) =>
                      _tabWithAlert('Поддержка', snap.data ?? 0),
                ),
                StreamBuilder<int>(
                  stream: _openReportsCountStream,
                  builder: (context, snap) =>
                      _tabWithAlert('Жалобы', snap.data ?? 0),
                ),
                _tabWithAlert('Реклама', 0),
                _tabWithAlert('Продвижения', 0),
                _tabWithAlert('Бонусы', 0),
                _tabWithAlert('Блокировки', 0),
                _tabWithAlert('Уведомления', 0),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tab,
            children: [
              const _DashboardTab(),
              const _TimewebAdminListingsModerationTab(),
              const AdminSupportTab(),
              AdminReportsScreen(initialReportId: widget.initialReportId),
              const AdminAdsTab(),
              const AdminPromotionsScreen(),
              const AdminWalletAnalyticsScreen(),
              const AdminBlocksScreen(),
              const AdminNotificationsTab(),
            ],
          ),
        );
      },
    );
  }
}

class _TimewebAdminListingsModerationTab extends StatefulWidget {
  const _TimewebAdminListingsModerationTab();

  @override
  State<_TimewebAdminListingsModerationTab> createState() =>
      _TimewebAdminListingsModerationTabState();
}

class _TimewebAdminListingsModerationTabState
    extends State<_TimewebAdminListingsModerationTab> {
  String _status = 'pending';
  bool _busy = false;
  Future<List<Map<String, dynamic>>>? _future;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  String? _errorText;
  bool _loading = true;
  bool _loadedOnce = false;
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final admin = context.read<AdminService>();
    try {
      var items = await _fetchListings(admin, forceRefresh: true);
      if (_status == 'pending' && items.isEmpty) {
        final pendingCount =
            await admin.pendingModerationCount(forceRefresh: true);
        if (pendingCount > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          items = await _fetchListings(admin, forceRefresh: true);
        }
      }
      if (mounted) {
        setState(() {
          _items = items;
          _errorText = null;
          _loading = false;
          _loadedOnce = true;
        });
      }
      return items;
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorText = _friendlyAdminError(error);
          _loading = false;
          _loadedOnce = true;
        });
      }
      return List<Map<String, dynamic>>.from(_items);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchListings(
    AdminService admin, {
    required bool forceRefresh,
  }) async {
    final response = await admin.listings(
      status: _status,
      forceRefresh: forceRefresh,
    );
    final rawItems = response['items'];
    return rawItems is List
        ? rawItems
            .whereType<Map>()
            .map(
              (item) =>
                  item.map((key, value) => MapEntry(key.toString(), value)),
            )
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
  }

  String _friendlyAdminError(Object error) {
    if ('$error'.contains('admin_forbidden')) {
      return 'Нет доступа к модерации. Войдите снова.';
    }
    if ('$error'.contains('401')) {
      return 'Сессия истекла. Войдите снова.';
    }
    return 'Не удалось загрузить объявления. Повторите попытку.';
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _errorText = null;
      _loading = true;
      _future = _load();
    });
    await _future;
  }

  Future<void> _setStatus(String status) async {
    if (_status == status) return;
    setState(() {
      _status = status;
      _errorText = null;
      _loading = true;
      _future = _load();
    });
  }

  Future<void> _approve(Map<String, dynamic> item) async {
    final adminService = context.read<AdminService>();
    setState(() => _busy = true);
    try {
      final listingId = _id(item);
      await adminService.approveListing(listingId);
      _removeItemLocally(listingId);
      unawaited(adminService.dashboardStats(forceRefresh: true));
      if (!mounted) return;
      showAppSnack(context, 'Объявление одобрено');
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка одобрения: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(Map<String, dynamic> item) async {
    final adminService = context.read<AdminService>();
    final reason = await _askReason(
      title: 'Отклонить объявление',
      hint: 'Причина отклонения',
      confirmText: 'Отклонить',
    );
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      final listingId = _id(item);
      await adminService.rejectListing(
        listingId,
        reason: reason,
      );
      _removeItemLocally(listingId);
      unawaited(adminService.dashboardStats(forceRefresh: true));
      if (!mounted) return;
      showAppSnack(context, 'Объявление отклонено');
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка отклонения: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final adminService = context.read<AdminService>();
    final reason = await _askReason(
      title: 'Скрыть объявление',
      hint: 'Причина удаления/скрытия',
      confirmText: 'Скрыть',
    );
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      final listingId = _id(item);
      await adminService.deleteListing(
        listingId,
        reason: reason,
      );
      _removeItemLocally(listingId);
      unawaited(adminService.dashboardStats(forceRefresh: true));
      if (!mounted) return;
      showAppSnack(context, 'Объявление скрыто');
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка удаления: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason({
    required String title,
    required String hint,
    required String confirmText,
  }) async {
    var value = '';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          minLines: 2,
          maxLines: 4,
          onChanged: (next) => value = next,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, value.trim()),
            child: Text(confirmText),
          ),
        ],
      ),
    );

    final normalized = (result ?? '').trim();
    if (normalized.isEmpty) return null;
    return normalized;
  }

  String _id(Map<String, dynamic> item) => (item['id'] ?? '').toString();

  void _removeItemLocally(String listingId) {
    setState(() {
      _items = _items
          .where((item) => _id(item) != listingId)
          .toList(growable: false);
    });
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'На модерации';
      case 'approved':
        return 'Активно';
      case 'rejected':
        return 'Отклонено';
      case 'archived':
        return 'В архиве';
      case 'deleted':
        return 'Скрыто';
      case 'sold':
        return 'Продано';
      default:
        return status;
    }
  }

  String _createdAt(Map<String, dynamic> item) {
    final raw = (item['created_at'] ?? '').toString().trim();
    if (raw.isEmpty) return '';
    return raw.replaceFirst('T', ' ').split('.').first;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        final items = _loadedOnce
            ? _items
            : (snap.data ?? const <Map<String, dynamic>>[]);
        if (_loading && items.isEmpty) {
          return const _ModerationLoadingView();
        }
        if (_errorText != null && items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _errorText!,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _refresh,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('На модерации'),
                        selected: _status == 'pending',
                        onSelected: _busy ? null : (_) => _setStatus('pending'),
                      ),
                      ChoiceChip(
                        label: const Text('Все'),
                        selected: _status == 'all',
                        onSelected: _busy ? null : (_) => _setStatus('all'),
                      ),
                    ],
                  ),
                ),
                if (_loading && items.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      key: Key('admin_moderation_inline_spinner'),
                      strokeWidth: 2,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Text(
                    _status == 'pending'
                        ? 'Нет объявлений на модерации.'
                        : 'Список объявлений пока пуст.',
                  ),
                ),
              )
            else
              ...items.map(
                (item) {
                  final listingId = _id(item);
                  final rawPhotos =
                      item['photo_urls'] ?? item['photoUrls'] ?? [];
                  final photos = rawPhotos is List
                      ? rawPhotos
                          .map((entry) => entry.toString())
                          .toList(growable: false)
                      : const <String>[];
                  return Card(
                    key: ValueKey('admin-moderation-item:$listingId'),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final handled = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AdminListingReviewScreen(
                                    listingId: listingId,
                                    listingData: item,
                                  ),
                                ),
                              );
                              if (handled == true && mounted) {
                                _removeItemLocally(listingId);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 92,
                                    height: 72,
                                    child: MediaPreviewBox(
                                      imageUrl:
                                          photos.isNotEmpty ? photos.first : '',
                                      categoryHint: 'listings',
                                      borderRadius: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (item['title'] ?? 'Без названия')
                                              .toString(),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${(item['price'] ?? 0).toString()} ₽ • ${(item['city'] ?? '').toString()}',
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Категория: ${(item['category'] ?? '').toString()}',
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Владелец: ${(item['owner_name'] ?? '').toString()}',
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Статус: ${_statusLabel((item['status'] ?? '').toString())}',
                                        ),
                                        const SizedBox(height: 4),
                                        Text('Создано: ${_createdAt(item)}'),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Нажмите, чтобы открыть подробный просмотр',
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
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () async {
                                  final handled = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AdminListingReviewScreen(
                                        listingId: listingId,
                                        listingData: item,
                                      ),
                                    ),
                                  );
                                  if (handled == true && mounted) {
                                    _removeItemLocally(listingId);
                                  }
                                },
                                child: const Text('Открыть'),
                              ),
                              FilledButton(
                                onPressed: _busy ||
                                        (item['status'] ?? '').toString() ==
                                            'approved'
                                    ? null
                                    : () => _approve(item),
                                child: const Text('Одобрить'),
                              ),
                              FilledButton.tonal(
                                onPressed: _busy ||
                                        (item['status'] ?? '').toString() ==
                                            'rejected'
                                    ? null
                                    : () => _reject(item),
                                child: const Text('Отклонить'),
                              ),
                              OutlinedButton(
                                onPressed: _busy ? null : () => _delete(item),
                                child: const Text('Скрыть'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _ModerationLoadingView extends StatelessWidget {
  const _ModerationLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SkeletonBox(width: 132, height: 32, radius: 999),
            SkeletonBox(width: 72, height: 32, radius: 999),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < 4; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: 180, height: 16),
                SizedBox(height: 10),
                SkeletonLine(height: 12),
                SizedBox(height: 6),
                SkeletonLine(width: 160, height: 12),
                SizedBox(height: 6),
                SkeletonLine(width: 140, height: 12),
                SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: SkeletonBox(height: 36, radius: 10)),
                    SizedBox(width: 8),
                    Expanded(child: SkeletonBox(height: 36, radius: 10)),
                    SizedBox(width: 8),
                    Expanded(child: SkeletonBox(height: 36, radius: 10)),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ----------------
// 0) ДАШБОРД
// ----------------
class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  Future<int> _count(
    String table, {
    Map<String, dynamic>? eqFilters,
  }) async {
    return 0;
  }

  Future<List<Map<String, dynamic>>> _daily() async {
    return <Map<String, dynamic>>[];
  }

  Future<int> _soldThisMonth() async {
    return 0;
  }

  Future<int> _onlineUsers() async {
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (ApiConfig.useTimewebBackend) {
      debugPrint('Admin dashboard source: Timeweb');
      return FutureBuilder<Map<String, dynamic>>(
        future: context.read<AdminService>().dashboardStats(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final stats = Map<String, dynamic>.from(
              (snap.data!['stats'] as Map?) ?? const {});
          final dailyRoot = Map<String, dynamic>.from(
              (snap.data!['daily'] as Map?) ?? const {});
          final daily = ((dailyRoot['listings'] as List?) ?? const <dynamic>[])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          final listingsSeries = daily
              .map((e) => ((e['listings_new'] as num?) ?? 0).toInt())
              .toList();

          Widget card(
            String title,
            String value,
            IconData icon, {
            VoidCallback? onTap,
            String? subtitle,
          }) {
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(icon),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            if (subtitle != null && subtitle.trim().isNotEmpty)
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        value,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          Widget chartCard({
            required String title,
            required List<int> values,
          }) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (values.isEmpty)
                      Text(
                        'Нет данных',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      )
                    else
                      MiniLineChart(
                        values: values,
                        height: 140,
                      ),
                  ],
                ),
              ),
            );
          }

          int read(String key) {
            final value = stats[key];
            if (value is num) return value.toInt();
            return int.tryParse((value ?? '').toString()) ?? 0;
          }

          final pointsPurchasesMonth = Map<String, dynamic>.from(
            stats['pointsPurchasesMonth'] as Map? ?? const {},
          );
          int readPurchaseMetric(String key) {
            final value = pointsPurchasesMonth[key];
            if (value is num) return value.toInt();
            return int.tryParse((value ?? '').toString()) ?? 0;
          }

          String readPurchaseAmountRub() {
            final value = pointsPurchasesMonth['totalAmountRub'];
            final number =
                value is num ? value : num.tryParse((value ?? '0').toString());
            final amount = number ?? 0;
            if (amount == amount.roundToDouble()) {
              return amount.round().toString();
            }
            return amount.toStringAsFixed(2);
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              card(
                'Пользователей',
                '${read('users')}',
                Icons.people,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
                ),
              ),
              card(
                'Сейчас онлайн',
                '${read('onlineUsers')}',
                Icons.circle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminOnlineUsersScreen(),
                  ),
                ),
              ),
              card(
                'Сегодня заходили',
                '${read('todayVisits')}',
                Icons.groups,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminTodayVisitsScreen(),
                  ),
                ),
              ),
              card(
                'Объявлений всего',
                '${read('listings')}',
                Icons.list_alt,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminListingsScreen(),
                  ),
                ),
              ),
              card('Активных объявлений', '${read('activeListings')}',
                  Icons.campaign),
              card(
                'Продано',
                '${read('sold')}',
                Icons.sell,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const AdminListingsScreen(initialStatus: 'sold'),
                  ),
                ),
              ),
              card('Продажи за 30 дней', '${read('sales30d')}',
                  Icons.sell_outlined),
              card(
                'Потрачено баллов',
                '${read('spentPoints30d')}',
                Icons.stars_outlined,
                subtitle: 'за последние 30 дней',
              ),
              card(
                'Покупки баллов',
                '${readPurchaseAmountRub()} ₽',
                Icons.payments_outlined,
                subtitle:
                    '${readPurchaseMetric('totalPoints')} баллов • ${readPurchaseMetric('purchasesCount')} покупок',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminPointsPurchasesScreen(),
                  ),
                ),
              ),
              card(
                  'На модерации', '${read('pendingModeration')}', Icons.shield),
              card('Тикетов поддержки', '${read('supportTickets')}',
                  Icons.support_agent),
              card('Жалоб (open)', '${read('reportsOpen')}', Icons.report),
              card('Рекламы active', '${read('activeAds')}',
                  Icons.ad_units_outlined),
              const SizedBox(height: 8),
              chartCard(
                title: 'Новые объявления за 14 дней',
                values: listingsSeries,
              ),
            ],
          );
        },
      );
    }

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        Future.wait([
          _count('users'),
          _count('listings'),
          _count('listings', eqFilters: {'status': 'approved'}),
          _count('listings', eqFilters: {'status': 'pending'}),
          _count('listings', eqFilters: {'status': 'sold'}),
          _count('support_tickets'),
          _count('reports', eqFilters: {'status': 'open'}),
          _onlineUsers(),
        ]),
        _daily(),
        _soldThisMonth(),
      ]),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final counts = snap.data![0] as List<int>;
        final daily = snap.data![1] as List<Map<String, dynamic>>;
        final soldThisMonth = snap.data![2] as int;

        final users = counts[0];
        final listings = counts[1];
        final active = counts[2];
        final pending = counts[3];
        final sold = counts[4];
        final tickets = counts[5];
        final reports = counts[6];
        final online = counts[7];

        // серии для графика
        final listingsSeries =
            daily.map((e) => (e['listings_new'] ?? 0) as int).toList();
        final ticketsSeries =
            daily.map((e) => (e['tickets_new'] ?? 0) as int).toList();
        final reportsSeries =
            daily.map((e) => (e['reports_new'] ?? 0) as int).toList();

        Widget card(
          String title,
          String value,
          IconData icon, {
          VoidCallback? onTap,
        }) {
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(icon),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        Widget chartCard({
          required String title,
          required List<int> values,
          bool compact = false,
        }) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (values.isEmpty)
                    Text(
                      'Нет данных (проверь view admin_dashboard_daily)',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    )
                  else
                    MiniLineChart(
                      values: values,
                      height: compact ? 72 : 140,
                    ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            card('Пользователей', '$users', Icons.people),
            card('Сейчас онлайн', '$online', Icons.circle),
            card('Объявлений всего', '$listings', Icons.list_alt),
            card('Активных объявлений', '$active', Icons.campaign),
            card(
              'Продано',
              '$sold',
              Icons.sell,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const AdminListingsScreen(initialStatus: 'sold'),
                ),
              ),
            ),
            card('Продажи за 30 дней', '$soldThisMonth', Icons.sell_outlined),
            card(
              'Покупки баллов',
              'Открыть',
              Icons.payments_outlined,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdminPointsPurchasesScreen(),
                ),
              ),
            ),
            card('На модерации', '$pending', Icons.shield),
            card('Тикетов поддержки', '$tickets', Icons.support_agent),
            card('Жалоб (open)', '$reports', Icons.report),
            const SizedBox(height: 8),
            chartCard(
              title: 'Новые объявления за 14 дней',
              values: listingsSeries,
            ),
            chartCard(
              title: 'Новые тикеты поддержки за 14 дней',
              values: ticketsSeries,
            ),
            chartCard(
              title: 'Новые жалобы за 14 дней',
              values: reportsSeries,
            ),
          ],
        );
      },
    );
  }
}

// ----------------
// 1) МОДЕРАЦИЯ
// ----------------
class _ModerationTab extends StatefulWidget {
  const _ModerationTab();

  @override
  State<_ModerationTab> createState() => _ModerationTabState();
}

class _ModerationTabState extends State<_ModerationTab> {
  final Set<String> _handledIds = <String>{};
  Stream<List<Map<String, dynamic>>>? _pendingListingsStream;

  Stream<List<Map<String, dynamic>>> _getPendingListings() {
    return _pendingListingsStream ??=
        Stream<List<Map<String, dynamic>>>.fromFuture((() async {
      final response = await context.read<AdminService>().listings(
            status: 'pending',
            forceRefresh: true,
          );
      final raw = response['items'];
      if (raw is! List) return const <Map<String, dynamic>>[];
      return raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    })())
            .startWith(const <Map<String, dynamic>>[]);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getPendingListings(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Ошибка: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!
            .where((doc) => !_handledIds.contains((doc['id'] ?? '').toString()))
            .toList();
        if (docs.isEmpty) {
          return const Center(child: Text('Нет объявлений на модерации'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final data = docs[i];
            final id = (data['id'] ?? '').toString();

            final title = (data['title'] ?? '').toString();
            final price = (data['price'] ?? 0).toString();
            final city = (data['city'] ?? '').toString();
            final category = (data['category'] ?? '').toString();

            final raw = data['photo_urls'] ?? [];
            final photos = (raw is List)
                ? raw.map((e) => e.toString()).toList()
                : <String>[];

            return InkWell(
              key: ValueKey('admin-moderation-item:$id'),
              onTap: () async {
                final handled = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminListingReviewScreen(
                      listingId: id,
                      listingData: data,
                    ),
                  ),
                );
                if (handled == true && mounted) {
                  setState(() => _handledIds.add(id));
                }
              },
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: MediaPreviewBox(
                          imageUrl: photos.isNotEmpty ? photos.first : '',
                          categoryHint: 'listings',
                          width: 80,
                          height: 60,
                          borderRadius: 10,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text('Цена: $price • $city'),
                            const SizedBox(height: 4),
                            Text(
                              'Категория: $category',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Нажми, чтобы открыть и проверить полностью →',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.outline,
                                fontSize: 12,
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
        );
      },
    );
  }
}

class AdminListingReviewScreen extends StatefulWidget {
  final String listingId;
  final Map<String, dynamic> listingData;

  const AdminListingReviewScreen({
    super.key,
    required this.listingId,
    required this.listingData,
  });

  @override
  State<AdminListingReviewScreen> createState() =>
      _AdminListingReviewScreenState();
}

class _AdminListingReviewScreenState extends State<AdminListingReviewScreen> {
  bool _busy = false;
  int _photoIndex = 0;
  static const List<_ModerationRejectReason> _rejectReasons = [
    _ModerationRejectReason(
      label: 'Мат / оскорбления',
      rejectionReason:
          'Нецензурная лексика или оскорбления в тексте объявления.',
      notificationBody:
          'Ваше объявление отклонено: в тексте обнаружены мат или оскорбления.',
    ),
    _ModerationRejectReason(
      label: 'Спам / дубликат',
      rejectionReason: 'Спам или дублирующее объявление.',
      notificationBody:
          'Ваше объявление отклонено: обнаружен спам или дублирующая публикация.',
    ),
    _ModerationRejectReason(
      label: 'Фейк / обман',
      rejectionReason: 'Недостоверная информация (фейк/обман).',
      notificationBody:
          'Ваше объявление отклонено: информация в объявлении не подтверждается и выглядит недостоверной.',
    ),
    _ModerationRejectReason(
      label: 'Не по теме сайта',
      rejectionReason:
          'Товар или услуга не подходит для размещения на площадке ATTA.',
      notificationBody:
          'Ваше объявление отклонено: эта категория товара/услуги не размещается на ATTA.',
    ),
    _ModerationRejectReason(
      label: 'Запрещённый товар',
      rejectionReason: 'Запрещённый к продаже товар.',
      notificationBody:
          'Ваше объявление отклонено: товар запрещён к размещению правилами ATTA.',
    ),
  ];

  static const List<_ModerationDeleteReason> _deleteReasons = [
    _ModerationDeleteReason(
      label: 'Запрещенный товар',
      message:
          'Ваше объявление удалено модератором: товар не разрешен правилами ATTA.',
    ),
    _ModerationDeleteReason(
      label: 'Спам/дубликат',
      message:
          'Ваше объявление удалено модератором: обнаружен спам или дублирование.',
    ),
    _ModerationDeleteReason(
      label: 'Недостоверная информация',
      message:
          'Ваше объявление удалено модератором: обнаружена недостоверная информация.',
    ),
    _ModerationDeleteReason(
      label: 'Нарушение правил контента',
      message:
          'Ваше объявление удалено модератором: обнаружено нарушение правил публикации.',
    ),
  ];

  static const List<_BlockDurationOption> _blockDurations = [
    _BlockDurationOption(
      label: '1 день',
      value: 'one_day',
      summary: 'первое нарушение',
    ),
    _BlockDurationOption(
      label: '7 дней',
      value: '7_days',
      summary: 'повторное нарушение',
    ),
    _BlockDurationOption(
      label: '30 дней',
      value: '30_days',
      summary: 'следующее нарушение',
    ),
    _BlockDurationOption(
      label: 'До даты',
      value: 'custom',
      summary: 'ручной срок',
    ),
    _BlockDurationOption(
      label: 'Навсегда',
      value: 'permanent',
      summary: 'серьезное нарушение',
    ),
  ];

  Future<void> _approve() async {
    final adminService = context.read<AdminService>();
    final savedSearchService = context.read<SavedSearchService>();
    setState(() => _busy = true);
    try {
      await adminService.approveListing(widget.listingId);

      try {
        await savedSearchService.notifyMatchesForApprovedListing(
          widget.listingData,
        );
      } catch (e) {
        debugPrint('Ошибка уведомлений по сохраненным поискам: $e');
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Ошибка одобрения: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final adminService = context.read<AdminService>();
    final notifications = context.read<NotificationsService>();
    final selected = await _askRejectReason();
    if (selected == null) return;

    setState(() => _busy = true);
    try {
      await adminService.rejectListing(
        widget.listingId,
        reason: selected.rejectionReason,
        moderationNote: selected.rejectionReason,
      );

      String? notifyError;
      final ownerId = (widget.listingData['owner_id'] ?? '').toString();
      if (ownerId.trim().isNotEmpty) {
        try {
          await notifications.sendPersonal(
            userId: ownerId,
            title: '❌ Объявление отклонено',
            body: selected.notificationBody,
          );
        } catch (e) {
          notifyError = e.toString();
        }
      }

      if (!mounted) return;
      if (notifyError == null) {
        showAppSnack(context, 'Объявление отклонено, уведомление отправлено');
      } else {
        showAppSnack(
          context,
          'Объявление отклонено, но уведомление не отправлено: $notifyError',
          isError: true,
        );
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка отклонения: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_ModerationRejectReason?> _askRejectReason() async {
    var selected = 0;
    return showDialog<_ModerationRejectReason>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Причина отклонения'),
          content: SizedBox(
            width: 420,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < _rejectReasons.length; i++)
                  ChoiceChip(
                    label: Text(_rejectReasons[i].label),
                    selected: selected == i,
                    onSelected: (_) => setState(() => selected = i),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _rejectReasons[selected]),
              child: const Text('Отклонить и уведомить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final adminService = context.read<AdminService>();
    final notifications = context.read<NotificationsService>();
    final selected = await _askDeleteReason();
    if (selected == null) return;

    setState(() => _busy = true);
    try {
      final body = selected.comment == null
          ? selected.reason.message
          : '${selected.reason.message}\n\nКомментарий модератора: ${selected.comment}';
      await adminService.deleteListing(
        widget.listingId,
        reason: body,
        moderationNote: body,
      );

      String? notifyError;
      final ownerId = (widget.listingData['owner_id'] ?? '').toString();
      if (ownerId.trim().isNotEmpty) {
        try {
          await notifications.sendPersonal(
            userId: ownerId,
            title: '🚫 Объявление удалено',
            body: body,
          );
        } catch (e) {
          notifyError = e.toString();
        }
      }

      if (!mounted) return;
      if (notifyError == null) {
        showAppSnack(context, 'Объявление удалено, уведомление отправлено');
      } else {
        showAppSnack(
          context,
          'Объявление удалено, но уведомление не отправлено: $notifyError',
          isError: true,
        );
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка удаления: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_DeleteDecision?> _askDeleteReason() async {
    var selected = 0;
    final commentCtrl = TextEditingController();
    final res = await showDialog<_DeleteDecision>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Удалить объявление'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Выберите причину:'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int i = 0; i < _deleteReasons.length; i++)
                        ChoiceChip(
                          label: Text(_deleteReasons[i].label),
                          selected: selected == i,
                          onSelected: (_) => setState(() => selected = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: commentCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Комментарий модератора (необязательно)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final c = commentCtrl.text.trim();
                Navigator.pop(
                  ctx,
                  _DeleteDecision(
                    reason: _deleteReasons[selected],
                    comment: c.isEmpty ? null : c,
                  ),
                );
              },
              child: const Text('Удалить и уведомить'),
            ),
          ],
        ),
      ),
    );
    commentCtrl.dispose();
    return res;
  }

  Future<void> _blockUser() async {
    final adminService = context.read<AdminService>();
    final ownerId = (widget.listingData['owner_id'] ?? '').toString().trim();
    if (ownerId.isEmpty) {
      showAppSnack(context, 'Не найден пользователь объявления', isError: true);
      return;
    }

    final decision = await _askBlockDecision();
    if (decision == null) return;

    setState(() => _busy = true);
    try {
      await adminService.blockUser(
        ownerId,
        duration: decision.duration.value,
        reason: decision.reason,
        internalNote: decision.internalNote,
        listingId: widget.listingId,
        endsAt: decision.endsAt?.toIso8601String(),
        banPhoneIdentity: decision.banPhoneIdentity,
      );
      if (!mounted) return;
      showAppSnack(context, 'Пользователь заблокирован, объявление отклонено');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка блокировки: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_BlockDecision?> _askBlockDecision() async {
    var selected = 0;
    DateTime? customEndsAt;
    var banPhoneIdentity = false;
    var reason = '';
    var note = '';
    final ownerName = (widget.listingData['owner_name'] ??
            widget.listingData['ownerName'] ??
            '')
        .toString();
    final title = (widget.listingData['title'] ?? '').toString();

    final res = await showDialog<_BlockDecision>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final duration = _blockDurations[selected];
          final needsDate = duration.value == 'custom';
          final canSubmit =
              reason.trim().isNotEmpty && (!needsDate || customEndsAt != null);
          return AlertDialog(
            title: const Text('Заблокировать пользователя'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ownerName.trim().isNotEmpty)
                      _AdminInfoRow(label: 'Пользователь', value: ownerName),
                    _AdminInfoRow(label: 'Объявление', value: title),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (int i = 0; i < _blockDurations.length; i++)
                          ChoiceChip(
                            label: Text(_blockDurations[i].label),
                            selected: selected == i,
                            onSelected: (_) => setState(() => selected = i),
                          ),
                      ],
                    ),
                    if (needsDate) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            firstDate:
                                DateTime.now().add(const Duration(days: 1)),
                            lastDate:
                                DateTime.now().add(const Duration(days: 3650)),
                            initialDate: customEndsAt ??
                                DateTime.now().add(const Duration(days: 1)),
                          );
                          if (picked != null) {
                            if (!ctx.mounted) return;
                            setState(() => customEndsAt = picked);
                          }
                        },
                        icon: const Icon(Icons.event),
                        label: Text(
                          customEndsAt == null
                              ? 'Выбрать дату'
                              : _formatModerationDate(
                                  customEndsAt!.toIso8601String()),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (value) => setState(() => reason = value),
                      decoration: const InputDecoration(
                        labelText: 'Причина блокировки',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      minLines: 2,
                      maxLines: 3,
                      onChanged: (value) => note = value,
                      decoration: const InputDecoration(
                        labelText: 'Внутренний комментарий',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: banPhoneIdentity,
                      onChanged: duration.value == 'permanent'
                          ? (value) =>
                              setState(() => banPhoneIdentity = value ?? false)
                          : null,
                      title: const Text(
                          'Запретить повторную регистрацию по номеру'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    Text(
                      'Итог: объявление будет отклонено и скрыто из ленты, пользователь получит блокировку ${duration.label} (${duration.summary}).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: canSubmit
                    ? () => Navigator.pop(
                          ctx,
                          _BlockDecision(
                            duration: duration,
                            reason: reason.trim(),
                            internalNote:
                                note.trim().isEmpty ? null : note.trim(),
                            endsAt: customEndsAt,
                            banPhoneIdentity: banPhoneIdentity,
                          ),
                        )
                    : null,
                child: const Text('Заблокировать'),
              ),
            ],
          );
        },
      ),
    );
    return res;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.listingData;

    final title = (d['title'] ?? '').toString();
    final price = (d['price'] ?? 0).toString();
    final city = (d['city'] ?? '').toString();
    final category = (d['category'] ?? '').toString();
    final subcategory = (d['subcategory'] ?? '').toString();
    final desc = (d['description'] ?? '').toString();
    final phone = (d['phone'] ?? '').toString();
    final phoneDisplay = formatRussianPhone(phone);
    final ownerId = (d['owner_id'] ?? '').toString();
    final ownerName = (d['owner_name'] ?? d['ownerName'] ?? '').toString();
    final status = (d['status'] ?? '').toString();
    final createdAt = (d['created_at'] ?? '').toString();
    final moderationChanges = _moderationChangesByField(d);
    final moderationChangesByLabel = _moderationChangesByDisplayLabel(d);

    final raw = d['photo_urls'] ?? [];
    final images =
        (raw is List) ? raw.map((e) => e.toString()).toList() : <String>[];
    final extraFields = _moderationExtraFields(d);

    return Scaffold(
      appBar: AppBar(title: const Text('Проверка объявления')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (images.isNotEmpty)
            Column(
              children: [
                SizedBox(
                  height: 240,
                  child: PageView.builder(
                    itemCount: images.length,
                    onPageChanged: (value) {
                      if (!mounted) return;
                      setState(() => _photoIndex = value);
                    },
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: MediaPreviewBox(
                        imageUrl: images[i],
                        categoryHint: 'listings',
                        width: double.infinity,
                        height: 240,
                        borderRadius: 16,
                      ),
                    ),
                  ),
                ),
                if (moderationChanges.containsKey('photos')) ...[
                  const SizedBox(height: 8),
                  _ModerationChangedLine(
                    change: moderationChanges['photos']!,
                    photos: true,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Фото ${_photoIndex + 1} из ${images.length}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    ...List<Widget>.generate(
                      images.length,
                      (index) => Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == _photoIndex
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            Container(
              height: 180,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo, size: 44),
                  SizedBox(height: 8),
                  Text('Фотографии не добавлены'),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  if (moderationChanges.containsKey('title')) ...[
                    const SizedBox(height: 6),
                    _ModerationChangedLine(
                      change: moderationChanges['title']!,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _AdminInfoChip(
                        label: 'Цена',
                        value: '$price ₽',
                        change: moderationChanges['price'],
                        formatBefore: (value) =>
                            '${_formatModerationValue(value)} ₽',
                      ),
                      _AdminInfoChip(
                        label: 'Город',
                        value: city,
                        change: moderationChanges['city'],
                      ),
                      _AdminInfoChip(
                        label: 'Категория',
                        value: category,
                        change: moderationChanges['category'],
                      ),
                      if (subcategory.trim().isNotEmpty)
                        _AdminInfoChip(
                          label: 'Подкатегория',
                          value: subcategory,
                          change: moderationChanges['subcategory'],
                        ),
                      _AdminInfoChip(
                        label: 'Статус',
                        value: _moderationStatusLabel(status),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _AdminInfoSection(
            title: 'Описание',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc.isEmpty ? 'Описание отсутствует' : desc),
                if (moderationChanges.containsKey('description')) ...[
                  const SizedBox(height: 8),
                  _ModerationChangedLine(
                    change: moderationChanges['description']!,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          _AdminInfoSection(
            title: 'Продавец',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ownerName.trim().isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: _AdminInfoRow(label: 'Имя', value: ownerName),
                      ),
                      AdminCopyUserIdButton(userId: ownerId),
                    ],
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AdminCopyUserIdButton(userId: ownerId),
                  ),
                if (phone.trim().isNotEmpty)
                  _AdminInfoRow(label: 'Телефон', value: phoneDisplay),
                if (createdAt.trim().isNotEmpty)
                  _AdminInfoRow(
                      label: 'Создано',
                      value: _formatModerationDate(createdAt)),
              ],
            ),
          ),
          if (extraFields.isNotEmpty) ...[
            const SizedBox(height: 10),
            _AdminInfoSection(
              title: 'Дополнительные поля',
              child: Column(
                children: extraFields.entries
                    .map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _AdminInfoRow(
                          label: entry.key,
                          value: entry.value,
                          change: moderationChangesByLabel[entry.key],
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _approve,
                  child: Text(_busy ? '...' : 'Одобрить ✅'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _busy ? null : _reject,
                  child: Text(_busy ? '...' : 'Отклонить ❌'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            label: const Text('Удалить полностью'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _blockUser,
            icon: const Icon(Icons.lock),
            label: const Text('Заблокировать пользователя'),
          ),
        ],
      ),
    );
  }
}

class _AdminInfoSection extends StatelessWidget {
  const _AdminInfoSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _AdminInfoRow extends StatelessWidget {
  const _AdminInfoRow({
    required this.label,
    required this.value,
    this.change,
  });

  final String label;
  final String value;
  final _ModerationChange? change;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value.trim().isEmpty ? 'Не указано' : value,
              ),
              if (change != null) ...[
                const SizedBox(height: 4),
                _ModerationChangedLine(change: change!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminInfoChip extends StatelessWidget {
  const _AdminInfoChip({
    required this.label,
    required this.value,
    this.change,
    this.formatBefore,
  });

  final String label;
  final String value;
  final _ModerationChange? change;
  final String Function(dynamic value)? formatBefore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: value.trim().isEmpty ? 'Не указано' : value),
              ],
            ),
          ),
          if (change != null) ...[
            const SizedBox(height: 5),
            _ModerationChangedLine(
              change: change!,
              formatBefore: formatBefore,
            ),
          ],
        ],
      ),
    );
  }
}

class _ModerationChangedLine extends StatelessWidget {
  const _ModerationChangedLine({
    required this.change,
    this.photos = false,
    this.formatBefore,
  });

  final _ModerationChange change;
  final bool photos;
  final String Function(dynamic value)? formatBefore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final details = photos
        ? _formatPhotoChange(change)
        : 'Было: ${(formatBefore ?? _formatModerationValue)(change.before)}';
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.28)),
          ),
          child: Text(
            'Изменено',
            style: TextStyle(
              color: scheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          details,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ModerationChange {
  const _ModerationChange({
    required this.field,
    required this.label,
    this.before,
    this.after,
    this.added = const [],
    this.removed = const [],
  });

  final String field;
  final String label;
  final dynamic before;
  final dynamic after;
  final List<dynamic> added;
  final List<dynamic> removed;
}

Map<String, String> _moderationExtraFields(Map<String, dynamic> data) {
  const excludedKeys = <String>{
    'id',
    'title',
    'price',
    'city',
    'category',
    'subcategory',
    'description',
    'phone',
    'phone_hidden',
    'owner_id',
    'owner_name',
    'ownerName',
    'status',
    'created_at',
    'updated_at',
    'photo_urls',
    'photoUrls',
    'photo_items',
    'photoItems',
    'moderation_diff',
  };

  final fields = <String, String>{};
  for (final entry in data.entries) {
    if (excludedKeys.contains(entry.key)) continue;
    final normalized = _normalizeModerationFieldValue(entry.value);
    if (normalized == null || normalized.trim().isEmpty) continue;
    fields[_moderationFieldLabel(entry.key)] = normalized;
  }
  return fields;
}

Map<String, _ModerationChange> _moderationChangesByField(
  Map<String, dynamic> data,
) {
  final diff = data['moderation_diff'];
  if (diff is! Map) return const <String, _ModerationChange>{};
  final changed = diff['changed'];
  if (changed is! List) return const <String, _ModerationChange>{};

  final result = <String, _ModerationChange>{};
  for (final raw in changed) {
    if (raw is! Map) continue;
    final field = (raw['field'] ?? '').toString().trim();
    if (field.isEmpty) continue;
    result[field] = _ModerationChange(
      field: field,
      label: (raw['label'] ?? _moderationFieldLabel(field)).toString(),
      before: raw['before'],
      after: raw['after'],
      added: raw['added'] is List
          ? List<dynamic>.from(raw['added'] as List)
          : const [],
      removed: raw['removed'] is List
          ? List<dynamic>.from(raw['removed'] as List)
          : const [],
    );
  }
  return result;
}

Map<String, _ModerationChange> _moderationChangesByDisplayLabel(
  Map<String, dynamic> data,
) {
  final byField = _moderationChangesByField(data);
  return {
    for (final change in byField.values) change.label: change,
  };
}

String _moderationFieldLabel(String key) {
  const labels = <String, String>{
    'brand': 'Марка',
    'model': 'Модель',
    'condition': 'Состояние',
    'delivery': 'Доставка',
    'address': 'Адрес',
    'deal_type': 'Тип сделки',
    'real_estate_type': 'Вид товара',
    'clothes_type': 'Тип одежды',
    'clothes_size': 'Размер одежды',
    'auto_brand': 'Марка авто',
    'auto_model': 'Модель авто',
    'auto_condition': 'Состояние авто',
    'mileage': 'Пробег',
    'year': 'Год',
  };
  return labels[key] ?? key.replaceAll('_', ' ');
}

String? _normalizeModerationFieldValue(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value ? 'Да' : 'Нет';
  if (value is num) return value.toString();
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is List) {
    final items = value
        .map(_normalizeModerationFieldValue)
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
    return items.isEmpty ? null : items.join(', ');
  }
  if (value is Map) {
    final entries = value.entries
        .map((entry) {
          final normalized = _normalizeModerationFieldValue(entry.value);
          if (normalized == null || normalized.trim().isEmpty) {
            return null;
          }
          return '${_moderationFieldLabel(entry.key.toString())}: $normalized';
        })
        .whereType<String>()
        .toList(growable: false);
    return entries.isEmpty ? null : entries.join(' • ');
  }
  return value.toString();
}

String _formatModerationValue(dynamic value) {
  final normalized = _normalizeModerationFieldValue(value);
  return normalized == null || normalized.trim().isEmpty
      ? 'Не указано'
      : normalized;
}

String _formatPhotoChange(_ModerationChange change) {
  final added = change.added.length;
  final removed = change.removed.length;
  final parts = <String>[
    if (added > 0) 'Добавлено фото: $added',
    if (removed > 0) 'Удалено фото: $removed',
  ];
  if (parts.isEmpty) {
    parts.add('Изменён порядок фотографий');
  }
  return parts.join(' • ');
}

String _formatModerationDate(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final local = parsed.toLocal();
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final yyyy = local.year.toString();
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$dd.$mm.$yyyy, $hh:$min';
}

String _moderationStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'На модерации';
    case 'approved':
      return 'Активно';
    case 'rejected':
      return 'Отклонено';
    case 'archived':
      return 'В архиве';
    case 'deleted':
      return 'Скрыто';
    case 'sold':
      return 'Продано';
    default:
      return status.trim().isEmpty ? 'Не указан' : status;
  }
}

extension<T> on Stream<T> {
  Stream<T> startWith(T initial) async* {
    yield initial;
    yield* this;
  }
}

class _ModerationDeleteReason {
  final String label;
  final String message;
  const _ModerationDeleteReason({
    required this.label,
    required this.message,
  });
}

class _ModerationRejectReason {
  final String label;
  final String rejectionReason;
  final String notificationBody;
  const _ModerationRejectReason({
    required this.label,
    required this.rejectionReason,
    required this.notificationBody,
  });
}

class _BlockDurationOption {
  final String label;
  final String value;
  final String summary;

  const _BlockDurationOption({
    required this.label,
    required this.value,
    required this.summary,
  });
}

class _BlockDecision {
  final _BlockDurationOption duration;
  final String reason;
  final String? internalNote;
  final DateTime? endsAt;
  final bool banPhoneIdentity;

  const _BlockDecision({
    required this.duration,
    required this.reason,
    required this.internalNote,
    required this.endsAt,
    required this.banPhoneIdentity,
  });
}

class _DeleteDecision {
  final _ModerationDeleteReason reason;
  final String? comment;
  const _DeleteDecision({
    required this.reason,
    required this.comment,
  });
}

// ----------------
// ГРАФИК (без пакетов)
// ----------------
class MiniLineChart extends StatelessWidget {
  final List<int> values;
  final double height;

  const MiniLineChart({
    super.key,
    required this.values,
    this.height = 140,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _MiniLineChartPainter(
          values: values,
          lineColor: Theme.of(context).colorScheme.primary,
          gridColor: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class _MiniLineChartPainter extends CustomPainter {
  final List<int> values;
  final Color lineColor;
  final Color gridColor;

  _MiniLineChartPainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV).abs();
    final safeRange = range == 0 ? 1 : range;

    // grid
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // line
    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = size.width * (i / (values.length - 1));
      final normalized = (values[i] - minV) / safeRange;
      final y = size.height - (normalized * size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _MiniLineChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor;
  }
}

// ----------------
// 4) Вкладка "Уведомления"
// ----------------
class AdminNotificationsTab extends StatefulWidget {
  const AdminNotificationsTab({super.key});

  @override
  State<AdminNotificationsTab> createState() => _AdminNotificationsTabState();
}

class _AdminNotificationsTabState extends State<AdminNotificationsTab> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _actionUrlCtrl = TextEditingController();
  final _userIdCtrl = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _sendingGlobal = false;
  bool _sendingPersonal = false;
  bool _uploadingGlobalImage = false;
  String _globalImageUrl = '';
  XFile? _selectedGlobalImage;

  final List<Map<String, String>> _quickTemplates = const [
    {
      'label': 'Модерация',
      'body':
          'Мы получили ваш запрос и передали его на модерацию. Обычно проверка занимает от нескольких минут до нескольких часов.',
    },
    {
      'label': 'Жалоба',
      'body':
          'Мы приняли вашу жалобу в работу. Проверим объявление и сообщим о результате в ближайшее время.',
    },
    {
      'label': 'Обновление',
      'body':
          'Скоро выйдет обновление ATTA: улучшим стабильность и добавим новые возможности. Спасибо, что пользуетесь приложением!',
    },
    {
      'label': 'Поддержка',
      'body':
          'Ваше обращение получено. Специалист поддержки уже подключился и скоро ответит.',
    },
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _descriptionCtrl.dispose();
    _actionUrlCtrl.dispose();
    _userIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickGlobalImage() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 2200,
      maxHeight: 2200,
    );
    if (image == null || !mounted) return;
    setState(() {
      _selectedGlobalImage = image;
      _uploadingGlobalImage = true;
    });
    try {
      final url = await context
          .read<NotificationsService>()
          .uploadNotificationImage(File(image.path));
      if (!mounted) return;
      setState(() {
        _globalImageUrl = url;
      });
    } catch (error) {
      if (!mounted) return;
      showAppSnack(
        context,
        error is ApiException
            ? error.message
            : 'Не удалось загрузить фото для уведомления. Попробуйте другое фото.',
        isError: true,
      );
      setState(() {
        _selectedGlobalImage = null;
        _globalImageUrl = '';
      });
    } finally {
      if (mounted) {
        setState(() => _uploadingGlobalImage = false);
      }
    }
  }

  void _clearGlobalImage() {
    setState(() {
      _selectedGlobalImage = null;
      _globalImageUrl = '';
      _uploadingGlobalImage = false;
    });
  }

  String? _validateActionUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      return 'Укажите корректную ссылку.';
    }
    if (uri.scheme.toLowerCase() != 'https') {
      return 'Используйте ссылку формата https://';
    }
    return null;
  }

  Map<String, dynamic>? _buildNotificationPayload() {
    final description = _descriptionCtrl.text.trim();
    final actionUrl = _actionUrlCtrl.text.trim();
    final payload = <String, dynamic>{};
    if (_globalImageUrl.trim().isNotEmpty) {
      payload['imageUrl'] = _globalImageUrl.trim();
    }
    if (description.isNotEmpty) {
      payload['description'] = description;
    }
    if (actionUrl.isNotEmpty) {
      payload['actionUrl'] = actionUrl;
    }
    return payload.isEmpty ? null : payload;
  }

  bool _hasNotificationContent({
    required String title,
    required String body,
    required Map<String, dynamic>? payload,
  }) {
    final description = (payload?['description'] ?? '').toString().trim();
    final imageUrl = (payload?['imageUrl'] ?? '').toString().trim();
    return title.isNotEmpty ||
        body.isNotEmpty ||
        description.isNotEmpty ||
        imageUrl.isNotEmpty;
  }

  Future<void> _sendGlobal() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final payload = _buildNotificationPayload();
    if (!_hasNotificationContent(title: title, body: body, payload: payload)) {
      showAppSnack(
        context,
        'Добавьте текст, описание или фото.',
        isError: true,
      );
      return;
    }
    final actionUrlError = _validateActionUrl(_actionUrlCtrl.text);
    if (actionUrlError != null) {
      showAppSnack(context, actionUrlError, isError: true);
      return;
    }
    if (_uploadingGlobalImage) {
      showAppSnack(
        context,
        'Дождитесь завершения загрузки фото.',
        isError: true,
      );
      return;
    }

    final service = context.read<NotificationsService>();
    setState(() => _sendingGlobal = true);
    try {
      await service.sendGlobal(
        title: title.isEmpty ? null : title,
        body: body.isEmpty ? null : body,
        payload: payload,
      );
      if (!mounted) return;
      showAppSnack(context, 'Общее уведомление отправлено');
      _titleCtrl.clear();
      _bodyCtrl.clear();
      _descriptionCtrl.clear();
      _actionUrlCtrl.clear();
      _clearGlobalImage();
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sendingGlobal = false);
    }
  }

  Future<void> _sendPersonal() async {
    final userId = _userIdCtrl.text.trim();
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final payload = _buildNotificationPayload();
    if (userId.isEmpty) {
      showAppSnack(context, 'Укажите ID пользователя.', isError: true);
      return;
    }
    if (!_hasNotificationContent(title: title, body: body, payload: payload)) {
      showAppSnack(
        context,
        'Добавьте текст, описание или фото.',
        isError: true,
      );
      return;
    }
    final actionUrlError = _validateActionUrl(_actionUrlCtrl.text);
    if (actionUrlError != null) {
      showAppSnack(context, actionUrlError, isError: true);
      return;
    }
    if (_uploadingGlobalImage) {
      showAppSnack(
        context,
        'Дождитесь завершения загрузки фото.',
        isError: true,
      );
      return;
    }

    final service = context.read<NotificationsService>();
    setState(() => _sendingPersonal = true);
    try {
      await service.sendPersonal(
        userId: userId,
        title: title.isEmpty ? null : title,
        body: body.isEmpty ? null : body,
        payload: payload,
      );
      if (!mounted) return;
      showAppSnack(context, 'Личное уведомление отправлено');
      _userIdCtrl.clear();
      _titleCtrl.clear();
      _bodyCtrl.clear();
      _descriptionCtrl.clear();
      _actionUrlCtrl.clear();
      _clearGlobalImage();
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sendingPersonal = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset + 20),
      children: [
        const Text(
          'Уведомления',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(
            labelText: 'Заголовок',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bodyCtrl,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Текст уведомления',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionCtrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Описание',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _actionUrlCtrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Ссылка (необязательно)',
            hintText: 'https://example.com',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (_selectedGlobalImage != null || _globalImageUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: _globalImageUrl.isNotEmpty
                        ? MediaPreviewBox(
                            imageUrl: _globalImageUrl,
                            categoryHint: 'misc',
                            borderRadius: 0,
                          )
                        : Image.file(
                            File(_selectedGlobalImage!.path),
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: (_uploadingGlobalImage || _sendingGlobal)
                          ? null
                          : _clearGlobalImage,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ),
                if (_uploadingGlobalImage)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x55000000),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: (_uploadingGlobalImage || _sendingGlobal)
                ? null
                : _pickGlobalImage,
            icon: _uploadingGlobalImage
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_library_outlined),
            label: Text(
              _globalImageUrl.isNotEmpty ? 'Фото загружено' : 'Выбрать фото',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickTemplates.map((t) {
            return OutlinedButton(
              onPressed: () {
                setState(() {
                  _bodyCtrl.text = t['body'] ?? '';
                });
              },
              child: Text(t['label'] ?? 'Шаблон'),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        const Text(
          'ЛИЧНОЕ уведомление (по user_id)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Скопируй ID в профиле пользователя и вставь сюда. Администратор видит ID на публичном профиле пользователя.',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _userIdCtrl,
          decoration: const InputDecoration(
            labelText: 'ID пользователя',
            hintText: 'Например: 123e4567-e89b-12d3-a456-426614174000',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _sendingPersonal ? null : _sendPersonal,
          child: Text(
            _sendingPersonal ? 'Отправляем…' : 'Отправить ЛИЧНОЕ уведомление',
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        const Text(
          'ОБЩЕЕ уведомление (для всех)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 12),
          child: FilledButton.tonal(
            onPressed: _sendingGlobal ? null : _sendGlobal,
            child: Text(
              _sendingGlobal ? 'Отправляем…' : 'Отправить ОБЩЕЕ уведомление',
            ),
          ),
        ),
      ],
    );
  }
}
