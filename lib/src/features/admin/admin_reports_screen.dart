import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/reports_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

class AdminReportsScreen extends StatelessWidget {
  const AdminReportsScreen({super.key});

  static const List<_DecisionTemplate> _noViolationTemplates = [
    _DecisionTemplate(
      label: 'Нарушений не найдено',
      title: 'Проверка жалобы завершена',
      body: 'Мы проверили объявление. Нарушений правил не обнаружено.',
    ),
  ];

  static const List<_DecisionTemplate> _warnTemplates = [
    _DecisionTemplate(
      label: 'Неполная информация',
      title: '⚠️ Предупреждение по объявлению',
      body:
          'По вашему объявлению вынесено предупреждение: добавьте корректные данные и исправьте описание.',
    ),
    _DecisionTemplate(
      label: 'Подозрительный контент',
      title: '⚠️ Предупреждение по объявлению',
      body:
          'По вашему объявлению вынесено предупреждение: обнаружены признаки нарушения правил размещения.',
    ),
    _DecisionTemplate(
      label: 'Неподходящая категория',
      title: '⚠️ Предупреждение по объявлению',
      body:
          'По вашему объявлению вынесено предупреждение: выбрана неверная категория. Исправьте, пожалуйста.',
    ),
  ];

  static const List<_DecisionTemplate> _removeTemplates = [
    _DecisionTemplate(
      label: 'Запрещенный товар',
      title: '🚫 Объявление удалено',
      body: 'Ваше объявление удалено: размещение такого товара запрещено правилами.',
    ),
    _DecisionTemplate(
      label: 'Мошенничество/фейк',
      title: '🚫 Объявление удалено',
      body:
          'Ваше объявление удалено: выявлены признаки мошенничества или недостоверной информации.',
    ),
    _DecisionTemplate(
      label: 'Спам/дубликат',
      title: '🚫 Объявление удалено',
      body: 'Ваше объявление удалено: обнаружен спам или дублирование.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    timeago.setLocaleMessages('ru', timeago.RuMessages());

    final reports = context.read<ReportsService>();
    final me = context.read<AuthService>().currentUser!;

    return Scaffold(
      appBar: AppBar(title: const Text('Жалобы')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: reports.streamOpenReports(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Ошибка: ${snap.error}'));
          }

          final docs = snap.data ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Открытых жалоб пока нет'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final x = docs[i];
              final reportId = x['id'].toString();
              final listingId = (x['listing_id'] ?? '').toString();
              final ownerUid = (x['listing_owner_id'] ?? '').toString();
              final reporterId = (x['reporter_id'] ?? '').toString();
              final reason = (x['reason'] ?? '').toString();
              final comment = (x['comment'] ?? '').toString();

              final createdRaw = x['created_at'];
              DateTime? createdAt;
              if (createdRaw is DateTime) createdAt = createdRaw;
              if (createdRaw is String) createdAt = DateTime.tryParse(createdRaw);

              Future<void> doDecision({
                required String decision,
                required bool deleteListing,
                required List<_DecisionTemplate> templates,
              }) async {
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

                  String? notifyError;
                  if (options.sendNotification && ownerUid.isNotEmpty) {
                    final messageBody = options.adminComment == null
                        ? options.template.body
                        : '${options.template.body}\n\nКомментарий администратора: ${options.adminComment}';

                    try {
                      await reports.notifyOwnerPersonal(
                        ownerUid: ownerUid,
                        title: options.template.title,
                        body: messageBody,
                      );
                    } catch (e) {
                      notifyError = e.toString();
                      try {
                        await reports.notifyOwnerViaSupport(
                          ownerUid: ownerUid,
                          ownerName: 'Пользователь',
                          messageFromAdmin:
                              '${options.template.title}\n$messageBody',
                        );
                        notifyError = null;
                      } catch (e2) {
                        notifyError = e2.toString();
                      }
                    }
                  }

                  if (!context.mounted) return;
                  if (notifyError == null) {
                    showAppSnack(context, 'Жалоба обработана');
                  } else {
                    showAppSnack(
                      context,
                      'Жалоба обработана, но уведомление не отправлено: $notifyError',
                      isError: true,
                    );
                  }
                } catch (e) {
                  if (!context.mounted) return;
                  showAppSnack(context, 'Ошибка: $e', isError: true);
                }
              }

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reason.isEmpty ? 'Жалоба без причины' : reason,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      createdAt == null
                          ? 'Время: ...'
                          : 'Время: ${timeago.format(createdAt, locale: 'ru')}',
                    ),
                    const SizedBox(height: 8),
                    Text('Объявление: ${listingId.isEmpty ? 'не указано' : listingId}'),
                    Text('Владелец: ${ownerUid.isEmpty ? 'не указан' : ownerUid}'),
                    Text('Кто пожаловался: ${reporterId.isEmpty ? 'не указан' : reporterId}'),
                    if (comment.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Комментарий: $comment'),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: listingId.isEmpty
                              ? null
                              : () {
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
                          onPressed: ownerUid.isEmpty
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => SellerPublicProfileScreen(
                                        sellerId: ownerUid,
                                      ),
                                    ),
                                  );
                                },
                          child: const Text('Открыть профиль'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => doDecision(
                            decision: 'no_violation',
                            deleteListing: false,
                            templates: _noViolationTemplates,
                          ),
                          child: const Text('Нарушений нет'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => doDecision(
                            decision: 'warned',
                            deleteListing: false,
                            templates: _warnTemplates,
                          ),
                          child: const Text('Предупредить'),
                        ),
                        FilledButton(
                          onPressed: listingId.isEmpty
                              ? null
                              : () => doDecision(
                                    decision: 'removed',
                                    deleteListing: true,
                                    templates: _removeTemplates,
                                  ),
                          child: const Text('Удалить объявление'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<_DecisionOptions?> _askDecisionOptions(
    BuildContext context, {
    required String title,
    required List<_DecisionTemplate> templates,
  }) async {
    final commentCtrl = TextEditingController();
    var selected = 0;
    var sendNotification = true;

    final result = await showDialog<_DecisionOptions>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Выберите причину/шаблон уведомления:'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (int i = 0; i < templates.length; i++)
                            ChoiceChip(
                              label: Text(templates[i].label),
                              selected: selected == i,
                              onSelected: (_) => setState(() => selected = i),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: sendNotification,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Отправить уведомление пользователю'),
                        onChanged: (v) {
                          setState(() => sendNotification = v ?? true);
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: commentCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Комментарий администратора (необязательно)',
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
                      _DecisionOptions(
                        template: templates[selected],
                        sendNotification: sendNotification,
                        adminComment: c.isEmpty ? null : c,
                      ),
                    );
                  },
                  child: const Text('Применить'),
                ),
              ],
            );
          },
        );
      },
    );

    commentCtrl.dispose();
    return result;
  }
}

class _DecisionTemplate {
  final String label;
  final String title;
  final String body;

  const _DecisionTemplate({
    required this.label,
    required this.title,
    required this.body,
  });
}

class _DecisionOptions {
  final _DecisionTemplate template;
  final bool sendNotification;
  final String? adminComment;

  const _DecisionOptions({
    required this.template,
    required this.sendNotification,
    required this.adminComment,
  });
}
