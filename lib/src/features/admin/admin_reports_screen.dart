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
  late final ReportsService _reports;
  late final Stream<List<Map<String, dynamic>>> _openReportsStream;
  late final Stream<List<Map<String, dynamic>>> _processedReportsStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _reports = context.read<ReportsService>();
    _openReportsStream = _reports.streamOpenReports();
    _processedReportsStream = _reports.streamProcessedReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    timeago.setLocaleMessages('ru', timeago.RuMessages());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Жалобы'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Новые'),
            Tab(text: 'Обработанные'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ReportsTab(
            stream: _openReportsStream,
            emptyText: 'Новых жалоб пока нет',
            initialReportId: widget.initialReportId,
            isProcessedTab: false,
          ),
          _ReportsTab(
            stream: _processedReportsStream,
            emptyText: 'Обработанных жалоб пока нет',
            initialReportId: widget.initialReportId,
            isProcessedTab: true,
          ),
        ],
      ),
    );
  }
}

class _ReportsTab extends StatefulWidget {
  const _ReportsTab({
    required this.stream,
    required this.emptyText,
    required this.initialReportId,
    required this.isProcessedTab,
  });

  final Stream<List<Map<String, dynamic>>> stream;
  final String emptyText;
  final String initialReportId;
  final bool isProcessedTab;

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  final ScrollController _scrollController = ScrollController();
  bool _loadingMore = false;
  Object? _loadMoreError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
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
    final reports = context.read<ReportsService>();
    if (!reports.canLoadMoreReports) return;
    _loadMore();
  }

  Future<void> _loadMore() async {
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      await context.read<ReportsService>().loadMoreReports();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadMoreError = error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.stream,
      initialData: context.read<ReportsService>().peekAllReports(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            (snap.data == null || snap.data!.isEmpty)) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Ошибка: ${snap.error}'));
        }

        final items =
            (snap.data ?? const <Map<String, dynamic>>[]).where((item) {
          final isOpen = ReportsService.isOpenStatusValue(
            (item['status'] ?? '').toString(),
          );
          return widget.isProcessedTab ? !isOpen : isOpen;
        }).toList(growable: false);
        if (items.isEmpty) {
          return Center(child: Text(widget.emptyText));
        }

        return RefreshIndicator(
          onRefresh: () async {
            await context.read<ReportsService>().refreshReports(force: true);
          },
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: items.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, index) {
              if (index == items.length) {
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
                if (_loadMoreError != null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
              return _ReportCard(
                report: items[index],
                highlight: widget.initialReportId.trim().isNotEmpty &&
                    (items[index]['id'] ?? '').toString().trim() ==
                        widget.initialReportId.trim(),
              );
            },
          ),
        );
      },
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
            builder: (_) => ListingDetailScreen(listingId: listingId),
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
              IconButton(
                tooltip: 'Убрать из списка',
                onPressed: () => _confirmHideReport(context),
                icon: const Icon(Icons.delete_outline, size: 20),
                visualDensity: VisualDensity.compact,
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
                  child: const Text('Пометить обработанной'),
                ),
                FilledButton(
                  onPressed: listingId.isEmpty
                      ? null
                      : () => _applyDecision(
                            context,
                            decision: 'removed',
                            deleteListing: true,
                            templates: AdminReportsScreen._removeTemplates,
                          ),
                  child: const Text('Удалить объявление'),
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
