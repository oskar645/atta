import 'dart:async';

import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/reports_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({
    super.key,
    this.initialReportId = '',
  });

  final String initialReportId;

  static const List<_DecisionTemplate> _noViolationTemplates = [
    _DecisionTemplate(
      label: 'Нарушений не найдено',
      title: 'Проверка жалобы завершена',
      body: 'Мы проверили жалобу. Нарушений правил не обнаружено.',
    ),
  ];

  static const List<_DecisionTemplate> _warnTemplates = [
    _DecisionTemplate(
      label: 'Предупреждение',
      title: 'Предупреждение по жалобе',
      body:
          'Мы проверили ситуацию и направили пользователю предупреждение по жалобе.',
    ),
  ];

  static const List<_DecisionTemplate> _removeTemplates = [
    _DecisionTemplate(
      label: 'Удаление объявления',
      title: 'Объявление удалено',
      body: 'По результатам проверки объявление было удалено.',
    ),
  ];

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  String _reason = '';
  String _sort = 'newest';
  DateTimeRange? _dateRange;
  Map<String, int> _counts = const <String, int>{};

  static const _reasons = <String>[
    'Запрещённый товар',
    'Мошенничество',
    'Спам / реклама',
    'Оскорбления',
    'Фейк / обман',
    'Другое',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _scheduleSearch(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() {});
    });
  }

  void _updateCounts(Map<String, int> counts) {
    if (!mounted || counts.isEmpty) return;
    if (_counts.toString() == counts.toString()) return;
    setState(() => _counts = counts);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _dateRange,
    );
    if (picked != null && mounted) setState(() => _dateRange = picked);
  }

  String _tabLabel(String label, String key) {
    final count = _counts[key];
    return count == null ? label : '$label $count';
  }

  @override
  Widget build(BuildContext context) {
    timeago.setLocaleMessages('ru', timeago.RuMessages());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Жалобы'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: _tabLabel('Новые', 'open')),
            Tab(text: _tabLabel('На проверке', 'in_progress')),
            Tab(text: _tabLabel('Завершённые', 'completed')),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _search,
              onChanged: _scheduleSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Поиск по жалобам',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Очистить поиск',
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                isDense: true,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                DropdownButton<String>(
                  value: _reason,
                  underline: const SizedBox.shrink(),
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem(
                        value: '', child: Text('Все причины')),
                    ..._reasons.map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    ),
                  ],
                  onChanged: (value) => setState(() => _reason = value ?? ''),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label:
                      Text(_dateRange == null ? 'Любая дата' : 'Период выбран'),
                ),
                if (_dateRange != null)
                  IconButton(
                    tooltip: 'Сбросить дату',
                    onPressed: () => setState(() => _dateRange = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                const SizedBox(width: 4),
                DropdownButton<String>(
                  value: _sort,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                        value: 'newest', child: Text('Сначала новые')),
                    DropdownMenuItem(
                        value: 'oldest', child: Text('Сначала старые')),
                  ],
                  onChanged: (value) =>
                      setState(() => _sort = value ?? 'newest'),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ReportsTab(
                  status: 'open',
                  emptyText: 'Новых жалоб пока нет',
                  initialReportId: widget.initialReportId,
                  search: _search.text.trim(),
                  reason: _reason,
                  sort: _sort,
                  dateRange: _dateRange,
                  onCounts: _updateCounts,
                ),
                _ReportsTab(
                  status: 'in_progress',
                  emptyText: 'Жалоб на проверке пока нет',
                  initialReportId: widget.initialReportId,
                  search: _search.text.trim(),
                  reason: _reason,
                  sort: _sort,
                  dateRange: _dateRange,
                  onCounts: _updateCounts,
                ),
                _ReportsTab(
                  status: 'completed',
                  emptyText: 'Завершённых жалоб пока нет',
                  initialReportId: widget.initialReportId,
                  search: _search.text.trim(),
                  reason: _reason,
                  sort: _sort,
                  dateRange: _dateRange,
                  onCounts: _updateCounts,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsTab extends StatefulWidget {
  const _ReportsTab({
    required this.status,
    required this.emptyText,
    required this.initialReportId,
    required this.search,
    required this.reason,
    required this.sort,
    required this.dateRange,
    required this.onCounts,
  });

  final String status;
  final String emptyText;
  final String initialReportId;
  final String search;
  final String reason;
  final String sort;
  final DateTimeRange? dateRange;
  final ValueChanged<Map<String, int>> onCounts;

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _items = const [];
  String? _nextCursor;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    unawaited(_load(reset: true));
  }

  @override
  void didUpdateWidget(covariant _ReportsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search ||
        oldWidget.reason != widget.reason ||
        oldWidget.sort != widget.sort ||
        oldWidget.dateRange != widget.dateRange) {
      unawaited(_load(reset: true));
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients || _loadingMore) return;
    if (_scrollController.position.extentAfter > 700) return;
    if (!_hasMore) return;
    unawaited(_load(reset: false));
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loadingMore || !_hasMore)) return;
    final generation = reset ? ++_generation : _generation;
    setState(() {
      if (reset) _loading = true;
      _loadingMore = !reset;
      _error = null;
    });
    try {
      final page = await context.read<ReportsService>().queryAdminReports(
            status: widget.status,
            cursor: reset ? null : _nextCursor,
            search: widget.search,
            reason: widget.reason,
            sort: widget.sort,
            dateFrom: widget.dateRange?.start,
            dateTo: widget.dateRange == null
                ? null
                : DateTime(
                    widget.dateRange!.end.year,
                    widget.dateRange!.end.month,
                    widget.dateRange!.end.day,
                    23,
                    59,
                    59,
                    999,
                  ),
          );
      if (!mounted || generation != _generation) return;
      final seen = <String>{};
      final merged =
          reset ? page.items : <Map<String, dynamic>>[..._items, ...page.items];
      setState(() {
        _items = merged
            .where((item) => seen.add((item['id'] ?? '').toString()))
            .toList(growable: false);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
      widget.onCounts(page.counts);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _open(Map<String, dynamic> report) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Жалоба')),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _ReportCard(report: report, highlight: false),
            ],
          ),
        ),
      ),
    );
    if (mounted) await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return _ReportsError(error: _error!, onRetry: () => _load(reset: true));
    }
    if (_items.isEmpty) return Center(child: Text(widget.emptyText));
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        key: PageStorageKey('admin-reports-${widget.status}'),
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          if (index == _items.length) {
            if (_loadingMore) {
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
            if (_error != null) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: TextButton(
                    onPressed: () => _load(reset: false),
                    child: const Text(
                      'Не удалось догрузить. Нажмите, чтобы повторить.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            return const SizedBox(height: 12);
          }
          return _CompactReportCard(
            report: _items[index],
            highlight: widget.initialReportId.trim().isNotEmpty &&
                (_items[index]['id'] ?? '').toString().trim() ==
                    widget.initialReportId.trim(),
            onTap: () => _open(_items[index]),
          );
        },
      ),
    );
  }
}

class _ReportsError extends StatelessWidget {
  const _ReportsError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Не удалось загрузить жалобы.'),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
          ]),
        ),
      );
}

class _CompactReportCard extends StatelessWidget {
  const _CompactReportCard({
    required this.report,
    required this.highlight,
    required this.onTap,
  });
  final Map<String, dynamic> report;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reason = (report['reason'] ?? 'Причина не указана').toString();
    final title = (report['listing_title'] ?? '').toString().trim();
    final target = title.isEmpty
        ? (report['reported_user_name'] ?? 'Профиль пользователя').toString()
        : title;
    final status = (report['status'] ?? 'open').toString();
    final createdAt =
        DateTime.tryParse((report['created_at'] ?? '').toString());
    final statusLabel = switch (status) {
      'in_progress' => 'На проверке',
      'resolved' || 'rejected' => 'Завершена',
      _ => 'Новая',
    };
    return Card(
      elevation: 0,
      color: highlight ? Theme.of(context).colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(reason, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$target${createdAt == null ? '' : ' · ${timeago.format(createdAt, locale: 'ru')}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(statusLabel, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.highlight,
  });

  final Map<String, dynamic> report;
  final bool highlight;

  String _formatStatus(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'open':
      case 'new':
      case 'pending':
        return 'Новая';
      case 'in_progress':
        return 'В обработке';
      case 'resolved':
        return 'Обработана';
      case 'rejected':
        return 'Закрыта';
      default:
        return 'Новая';
    }
  }

  Future<void> _openReportedObject(BuildContext context) async {
    final listingId = (report['listing_id'] ?? '').toString().trim();
    final reportedUserId =
        (report['reported_user_id'] ?? report['listing_owner_id'] ?? '')
            .toString()
            .trim();
    if (listingId.isNotEmpty) {
      try {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ListingDetailScreen(
                trackUsageAnalytics: false, listingId: listingId),
          ),
        );
      } catch (_) {
        if (!context.mounted) return;
        showAppSnack(
          context,
          'Объявление не найдено или больше недоступно.',
          isError: true,
        );
      }
      return;
    }
    if (reportedUserId.isNotEmpty) {
      await _openUser(context, reportedUserId);
      return;
    }
    showAppSnack(
      context,
      'Объект жалобы больше недоступен.',
      isError: true,
    );
  }

  Future<void> _openUser(BuildContext context, String userId) async {
    if (userId.trim().isEmpty) return;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SellerPublicProfileScreen(
            sellerId: userId,
            showAdminFields: true,
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      showAppSnack(
        context,
        'Пользователь не найден или больше недоступен.',
        isError: true,
      );
    }
  }

  String _buildSupportContext({
    required bool forReportedUser,
    required bool hasListingTarget,
  }) {
    if (forReportedUser) {
      if (hasListingTarget) {
        return 'Здравствуйте. На ваше объявление поступила жалоба.\n\n'
            'Пожалуйста, проверьте объявление и убедитесь, что оно соответствует правилам ATTA: указана корректная информация, нет запрещённых товаров или услуг, спама или вводящих в заблуждение данных.\n\n'
            'Если нарушение подтвердится, объявление может быть отредактировано, снято с публикации или удалено.\n\n'
            'Если вы считаете, что жалоба ошибочная, ответьте в этом чате — мы проверим ситуацию.';
      }
      return 'Здравствуйте. На ваш профиль поступила жалоба.\n\n'
          'Пожалуйста, проверьте информацию в профиле и убедитесь, что она соответствует правилам ATTA и не вводит пользователей в заблуждение.\n\n'
          'Если вы считаете, что жалоба ошибочная, ответьте в этом чате — мы проверим ситуацию.';
    }
    return hasListingTarget
        ? 'Здравствуйте. Мы получили вашу жалобу на объявление и уже проверяем ситуацию.\n\nЕсли хотите дополнить информацию, ответьте в этом чате.'
        : 'Здравствуйте. Мы получили вашу жалобу на пользователя и уже проверяем ситуацию.\n\nЕсли хотите дополнить информацию, ответьте в этом чате.';
  }

  String _reportSubject({
    required bool forReportedUser,
    required bool hasListingTarget,
  }) {
    if (forReportedUser) {
      return hasListingTarget ? 'Жалоба на объявление' : 'Жалоба на профиль';
    }
    return 'Ответ по вашей жалобе';
  }

  Future<void> _confirmHideReport(BuildContext context) async {
    final reportId = (report['id'] ?? '').toString().trim();
    if (reportId.isEmpty) {
      showAppSnack(context, 'Не удалось определить жалобу.', isError: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Убрать жалобу из списка?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<ReportsService>().hideReport(reportId);
      if (!context.mounted) return;
      showAppSnack(context, 'Жалоба убрана из списка');
    } catch (error) {
      if (!context.mounted) return;
      showAppSnack(context, 'Не удалось убрать жалобу: $error', isError: true);
    }
  }

  Future<void> _startReview(BuildContext context) async {
    final reportId = (report['id'] ?? '').toString().trim();
    if (reportId.isEmpty) return;
    try {
      await context.read<ReportsService>().startReview(reportId);
      if (!context.mounted) return;
      showAppSnack(context, 'Жалоба взята на проверку');
      Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) return;
      showAppSnack(context, 'Не удалось начать проверку: $error',
          isError: true);
    }
  }

  Future<void> _contactUserViaSupport(
    BuildContext context, {
    required String userId,
    required String userName,
    required String subject,
    required String initialMessage,
  }) async {
    final draft = await _showSupportMessageComposer(
      context,
      initialMessage: initialMessage,
    );
    if (draft == null || !context.mounted) return;
    try {
      await context.read<ReportsService>().contactUserViaSupport(
            userId: userId,
            name: userName,
            subject: subject,
            message: draft,
          );
      if (!context.mounted) return;
      showAppSnack(context, 'Сообщение отправлено');
    } catch (error) {
      if (!context.mounted) return;
      showAppSnack(
        context,
        'Не удалось отправить сообщение. Попробуйте ещё раз.',
        isError: true,
      );
    }
  }

  Future<String?> _showSupportMessageComposer(
    BuildContext context, {
    required String initialMessage,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _SupportMessageComposerDialog(
        initialMessage: initialMessage,
      ),
    );
  }

  Future<void> _applyDecision(
    BuildContext context, {
    required String decision,
    required bool deleteListing,
    required List<_DecisionTemplate> templates,
  }) async {
    final me = context.read<AuthService>().currentUser!;
    final reports = context.read<ReportsService>();
    final listingId = (report['listing_id'] ?? '').toString().trim();
    final ownerUid =
        (report['listing_owner_id'] ?? report['reported_user_id'] ?? '')
            .toString()
            .trim();
    final reportId = (report['id'] ?? '').toString().trim();
    final options = await _askDecisionOptions(
      context,
      templates: templates,
      title: deleteListing ? 'Удаление объявления' : 'Решение по жалобе',
    );
    if (options == null) return;

    try {
      if (deleteListing && listingId.isNotEmpty) {
        final deleteReason = options.adminComment == null
            ? options.template.body
            : '${options.template.body}\n\nКомментарий администратора: ${options.adminComment}';
        await reports.deleteListingById(
          listingId,
          reason: deleteReason,
        );
      }

      await reports.closeReportDecision(
        reportId: reportId,
        adminUid: me.uid,
        decision: decision,
        adminComment: options.adminComment,
      );

      if (options.sendNotification && ownerUid.isNotEmpty) {
        final body = options.adminComment == null
            ? options.template.body
            : '${options.template.body}\n\nКомментарий администратора: ${options.adminComment}';
        await reports.notifyOwnerPersonal(
          ownerUid: ownerUid,
          title: options.template.title,
          body: body,
        );
      }

      if (!context.mounted) return;
      showAppSnack(context, 'Жалоба обработана');
      Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) return;
      showAppSnack(context, 'Ошибка: $error', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportId = (report['id'] ?? '').toString().trim();
    final listingId = (report['listing_id'] ?? '').toString().trim();
    final reporterId = (report['reporter_id'] ?? '').toString().trim();
    final reporterName =
        (report['reporter_name'] ?? 'Пользователь').toString().trim();
    final reportedUserId =
        (report['reported_user_id'] ?? report['listing_owner_id'] ?? '')
            .toString()
            .trim();
    final reportedUserName =
        (report['reported_user_name'] ?? 'Пользователь').toString().trim();
    final reason = (report['reason'] ?? '').toString().trim();
    final comment = (report['comment'] ?? '').toString().trim();
    final listingTitle = (report['listing_title'] ?? '').toString().trim();
    final listingPhotoUrl =
        (report['listing_photo_url'] ?? '').toString().trim();
    final listingSellerName =
        (report['listing_seller_name'] ?? '').toString().trim();
    final statusText = _formatStatus((report['status'] ?? '').toString());
    final rawStatus = (report['status'] ?? '').toString().trim().toLowerCase();
    final decision = (report['decision'] ?? '').toString().trim();
    final adminComment = (report['admin_comment'] ?? '').toString().trim();
    final handledByName = (report['handled_by_name'] ?? '').toString().trim();
    final handledAt =
        DateTime.tryParse((report['handled_at'] ?? '').toString());
    final createdAt =
        DateTime.tryParse((report['created_at'] ?? '').toString());
    final isOpen =
        ReportsService.isOpenStatusValue((report['status'] ?? '').toString());
    final hasListingTarget = listingId.isNotEmpty;
    final displayedReason = reason.isEmpty ? 'Причина не указана' : reason;
    final displayedReporterName =
        reporterName.isEmpty ? 'Пользователь' : reporterName;
    final displayedReportedUserName =
        reportedUserName.isEmpty ? 'Пользователь' : reportedUserName;
    final displayedListingTitle =
        listingTitle.isEmpty ? 'Объявление без названия' : listingTitle;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: highlight
            ? Theme.of(context).colorScheme.primaryContainer.withValues(
                  alpha: 0.32,
                )
            : null,
        border: Border.all(
          color: highlight
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: highlight ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hasListingTarget
                      ? 'Жалоба на объявление'
                      : 'Жалоба на пользователя',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: Text(
                  statusText,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'Дополнительные действия',
                onSelected: (value) {
                  if (value == 'hide') unawaited(_confirmHideReport(context));
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'hide',
                    child: Text('Убрать жалобу из списка'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            createdAt == null
                ? 'Дата: неизвестно'
                : 'Дата: ${timeago.format(createdAt, locale: 'ru')}',
          ),
          const SizedBox(height: 8),
          Text('Причина: $displayedReason'),
          const SizedBox(height: 4),
          Text('Кто пожаловался: $displayedReporterName'),
          Text('На кого пожаловались: $displayedReportedUserName'),
          if (hasListingTarget) ...[
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openReportedObject(context),
              child: Ink(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 52,
                        height: 52,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: listingPhotoUrl.isEmpty
                            ? const Icon(Icons.photo_outlined)
                            : Image.network(
                                listingPhotoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.photo_outlined),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayedListingTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (listingSellerName.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Продавец: $listingSellerName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            'Открыть объявление',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Комментарий: $comment'),
          ],
          if (decision.isNotEmpty ||
              adminComment.isNotEmpty ||
              handledByName.isNotEmpty ||
              handledAt != null) ...[
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('Обработка жалобы'),
              children: [
                if (decision.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Решение: ${_decisionLabel(decision)}'),
                  ),
                if (adminComment.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Комментарий администратора: $adminComment'),
                  ),
                if (handledByName.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Администратор: $handledByName'),
                  ),
                if (handledAt != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Обработано: ${timeago.format(handledAt, locale: 'ru')}',
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _openReportedObject(context),
                child: Text(
                  listingId.isNotEmpty
                      ? 'Открыть объявление'
                      : 'Открыть профиль',
                ),
              ),
              OutlinedButton(
                onPressed: reporterId.isEmpty
                    ? null
                    : () => _openUser(context, reporterId),
                child: const Text('Профиль автора жалобы'),
              ),
              OutlinedButton(
                onPressed: reportedUserId.isEmpty
                    ? null
                    : () => _openUser(context, reportedUserId),
                child: const Text('Профиль второй стороны'),
              ),
              OutlinedButton(
                onPressed: reporterId.isEmpty
                    ? null
                    : () => _contactUserViaSupport(
                          context,
                          userId: reporterId,
                          userName: displayedReporterName,
                          subject: _reportSubject(
                            forReportedUser: false,
                            hasListingTarget: hasListingTarget,
                          ),
                          initialMessage: _buildSupportContext(
                            forReportedUser: false,
                            hasListingTarget: hasListingTarget,
                          ),
                        ),
                child: const Text('Написать автору жалобы'),
              ),
              OutlinedButton(
                onPressed: reportedUserId.isEmpty
                    ? null
                    : () => _contactUserViaSupport(
                          context,
                          userId: reportedUserId,
                          userName: displayedReportedUserName,
                          subject: _reportSubject(
                            forReportedUser: true,
                            hasListingTarget: hasListingTarget,
                          ),
                          initialMessage: _buildSupportContext(
                            forReportedUser: true,
                            hasListingTarget: hasListingTarget,
                          ),
                        ),
                child: const Text('Отправить предупреждение'),
              ),
              if (rawStatus == 'open')
                FilledButton.tonalIcon(
                  onPressed: () => _startReview(context),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Начать проверку'),
                ),
              if (isOpen) ...[
                FilledButton.tonal(
                  onPressed: () => _applyDecision(
                    context,
                    decision: 'no_violation',
                    deleteListing: false,
                    templates: AdminReportsScreen._noViolationTemplates,
                  ),
                  child: const Text('Нарушений нет'),
                ),
                FilledButton.tonal(
                  onPressed: () => _applyDecision(
                    context,
                    decision: 'warned',
                    deleteListing: false,
                    templates: AdminReportsScreen._warnTemplates,
                  ),
                  child: const Text('Принять меры'),
                ),
                PopupMenuButton<String>(
                  enabled: listingId.isNotEmpty,
                  tooltip: 'Опасные действия',
                  onSelected: (value) {
                    if (value == 'delete_listing') {
                      unawaited(
                        _applyDecision(
                          context,
                          decision: 'removed',
                          deleteListing: true,
                          templates: AdminReportsScreen._removeTemplates,
                        ),
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'delete_listing',
                      child: Text('Удалить объявление'),
                    ),
                  ],
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.more_horiz),
                    label: const Text('Опасные действия'),
                  ),
                ),
              ] else
                OutlinedButton(
                  onPressed: () async {
                    try {
                      await context
                          .read<ReportsService>()
                          .reopenReport(reportId);
                      if (!context.mounted) return;
                      showAppSnack(context, 'Жалоба возвращена в новые');
                      Navigator.of(context).pop();
                    } catch (error) {
                      if (!context.mounted) return;
                      showAppSnack(context, 'Ошибка: $error', isError: true);
                    }
                  },
                  child: const Text('Вернуть в новые'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _decisionLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'no_violation':
      case 'rejected':
        return 'Нарушений не обнаружено';
      case 'warned':
        return 'Приняты меры: предупреждение';
      case 'removed':
        return 'Приняты меры: объявление удалено';
      case 'action_taken':
      case 'resolved':
        return 'Приняты меры';
      default:
        return value;
    }
  }

  Future<_DecisionOptions?> _askDecisionOptions(
    BuildContext context, {
    required String title,
    required List<_DecisionTemplate> templates,
  }) async {
    return showDialog<_DecisionOptions>(
      context: context,
      builder: (ctx) => _DecisionOptionsDialog(
        title: title,
        templates: templates,
      ),
    );
  }
}

class _SupportMessageComposerDialog extends StatefulWidget {
  const _SupportMessageComposerDialog({
    required this.initialMessage,
  });

  final String initialMessage;

  @override
  State<_SupportMessageComposerDialog> createState() =>
      _SupportMessageComposerDialogState();
}

class _SupportMessageComposerDialogState
    extends State<_SupportMessageComposerDialog> {
  late final TextEditingController _controller;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialMessage.trim());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Сообщение в поддержку'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              minLines: 6,
              maxLines: 12,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Введите сообщение',
                border: const OutlineInputBorder(),
                errorText: _validationError,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isEmpty) {
              setState(() {
                _validationError = 'Сообщение не может быть пустым.';
              });
              return;
            }
            Navigator.of(context).pop(value);
          },
          child: const Text('Отправить'),
        ),
      ],
    );
  }
}

class _DecisionOptionsDialog extends StatefulWidget {
  const _DecisionOptionsDialog({
    required this.title,
    required this.templates,
  });

  final String title;
  final List<_DecisionTemplate> templates;

  @override
  State<_DecisionOptionsDialog> createState() => _DecisionOptionsDialogState();
}

class _DecisionOptionsDialogState extends State<_DecisionOptionsDialog> {
  late final TextEditingController _commentCtrl;
  int _selected = 0;
  bool _sendNotification = true;

  @override
  void initState() {
    super.initState();
    _commentCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Выберите шаблон решения:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < widget.templates.length; i++)
                    ChoiceChip(
                      label: Text(widget.templates[i].label),
                      selected: _selected == i,
                      onSelected: (_) => setState(() => _selected = i),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _sendNotification,
                contentPadding: EdgeInsets.zero,
                title: const Text('Отправить уведомление'),
                onChanged: (value) {
                  setState(() => _sendNotification = value ?? true);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _commentCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Комментарий администратора',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final comment = _commentCtrl.text.trim();
            Navigator.pop(
              context,
              _DecisionOptions(
                template: widget.templates[_selected],
                sendNotification: _sendNotification,
                adminComment: comment.isEmpty ? null : comment,
              ),
            );
          },
          child: const Text('Применить'),
        ),
      ],
    );
  }
}

class _DecisionTemplate {
  const _DecisionTemplate({
    required this.label,
    required this.title,
    required this.body,
  });

  final String label;
  final String title;
  final String body;
}

class _DecisionOptions {
  const _DecisionOptions({
    required this.template,
    required this.sendNotification,
    required this.adminComment,
  });

  final _DecisionTemplate template;
  final bool sendNotification;
  final String? adminComment;
}
