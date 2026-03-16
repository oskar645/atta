import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chestore2/src/features/admin/admin_reports_screen.dart';
import 'package:chestore2/src/features/admin/admin_ads_tab.dart';
import 'admin_support_screen.dart';
import 'package:chestore2/src/services/admin_service.dart';
import 'package:chestore2/src/services/auth_service.dart';
import 'package:chestore2/src/services/notifications_service.dart';
import 'package:chestore2/src/utils/app_snackbar.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  Widget _tabWithAlert(String text, bool hasAlert) {
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
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
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
    _tab = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.read<AdminService>();
    final me = context.read<AuthService>().currentUser;
    final uid = me?.uid ?? '';
    if (uid.isEmpty) {
      return const Scaffold(body: Center(child: Text('Нужно войти')));
    }

    return StreamBuilder<bool>(
      stream: admin.streamIsAdmin(uid),
      initialData: false,
      builder: (context, adminSnap) {
        if (adminSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
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

        return Scaffold(
          appBar: AppBar(
            title: const Text('Админ-Панель'),
            bottom: TabBar(
              controller: _tab,
              isScrollable: true,
              tabs: [
                _tabWithAlert('Дашборд', false),
                StreamBuilder<int>(
                  stream: admin.streamPendingModerationCount(),
                  builder: (context, snap) =>
                      _tabWithAlert('Модерация', (snap.data ?? 0) > 0),
                ),
                StreamBuilder<int>(
                  stream: admin.streamUnreadSupportForAdminCount(),
                  builder: (context, snap) =>
                      _tabWithAlert('Поддержка', (snap.data ?? 0) > 0),
                ),
                StreamBuilder<int>(
                  stream: admin.streamOpenReportsCount(),
                  builder: (context, snap) =>
                      _tabWithAlert('Жалобы', (snap.data ?? 0) > 0),
                ),
                _tabWithAlert('Реклама', false),
                _tabWithAlert('Уведомления', false),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tab,
            children: const [
              _DashboardTab(),
              _ModerationTab(),
              AdminSupportTab(),
              AdminReportsScreen(),
              AdminAdsTab(),
              AdminNotificationsTab(),
            ],
          ),
        );
      },
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
    final client = Supabase.instance.client;

    try {
      // максимально совместимый вариант: просто вытягиваем id и считаем длину
      // (не идеально по скорости, но точно без ошибок компиляции)
      var q = client.from(table).select('id');

      if (eqFilters != null) {
        for (final e in eqFilters.entries) {
          q = q.eq(e.key, e.value);
        }
      }

      final res = await q;
      return (res as List).length;
    } catch (e) {
      debugPrint('Count error [$table]: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> _daily() async {
    final client = Supabase.instance.client;
    try {
      final res = await client
          .from('admin_dashboard_daily')
          .select('day, listings_new, tickets_new, reports_new')
          .order('day', ascending: true);

      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('Daily stats error: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<int> _onlineUsers() async {
    final client = Supabase.instance.client;
    final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
    try {
      final res = await client
          .from('user_presence')
          .select('user_id, is_online, last_seen');

      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows.where((r) {
        if (r['is_online'] != true) return false;
        final lastSeen = DateTime.tryParse((r['last_seen'] ?? '').toString())?.toUtc();
        if (lastSeen == null) return false;
        return lastSeen.isAfter(cutoff);
      }).length;
    } catch (e) {
      debugPrint('Online count error: $e');
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        Future.wait([
          _count('users'),
          _count('listings'),
          _count('listings', eqFilters: {'status': 'pending'}),
          _count('support_tickets'),
          _count('reports', eqFilters: {'status': 'open'}),
          _onlineUsers(),
        ]),
        _daily(),
      ]),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final counts = snap.data![0] as List<int>;
        final daily = snap.data![1] as List<Map<String, dynamic>>;

        final users = counts[0];
        final listings = counts[1];
        final pending = counts[2];
        final tickets = counts[3];
        final reports = counts[4];
        final online = counts[5];

        // серии для графика
        final listingsSeries =
            daily.map((e) => (e['listings_new'] ?? 0) as int).toList();
        final ticketsSeries =
            daily.map((e) => (e['tickets_new'] ?? 0) as int).toList();
        final reportsSeries =
            daily.map((e) => (e['reports_new'] ?? 0) as int).toList();

        Widget card(String title, String value, IconData icon) {
          return Card(
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
                      'Нет данных (проверь view admin_dashboard_daily)',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    )
                  else
                    MiniLineChart(values: values),
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
class _ModerationTab extends StatelessWidget {
  const _ModerationTab();

  Stream<List<Map<String, dynamic>>> _getPendingListings() {
    return Supabase.instance.client
        .from('listings')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .map((data) => List<Map<String, dynamic>>.from(data));
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

        final docs = snap.data!;
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
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminListingReviewScreen(
                      listingId: id,
                      listingData: data,
                    ),
                  ),
                );
              },
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 64,
                          height: 64,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: photos.isNotEmpty
                              ? Image.network(photos.first, fit: BoxFit.cover)
                              : const Icon(Icons.photo),
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
  static const List<_ModerationRejectReason> _rejectReasons = [
    _ModerationRejectReason(
      label: 'Мат / оскорбления',
      rejectionReason: 'Нецензурная лексика или оскорбления в тексте объявления.',
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
          'Товар или услуга не подходит для размещения на площадке CheStore.',
      notificationBody:
          'Ваше объявление отклонено: эта категория товара/услуги не размещается на CheStore.',
    ),
    _ModerationRejectReason(
      label: 'Запрещённый товар',
      rejectionReason: 'Запрещённый к продаже товар.',
      notificationBody:
          'Ваше объявление отклонено: товар запрещён к размещению правилами CheStore.',
    ),
  ];

  static const List<_ModerationDeleteReason> _deleteReasons = [
    _ModerationDeleteReason(
      label: 'Запрещенный товар',
      message:
          'Ваше объявление удалено модератором: товар не разрешен правилами CheStore.',
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

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.from('listings').update({
        'status': 'approved',
        'rejection_reason': null,
      }).eq('id', widget.listingId);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Ошибка одобрения: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final notifications = context.read<NotificationsService>();
    final selected = await _askRejectReason();
    if (selected == null) return;

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.from('listings').update({
        'status': 'rejected',
        'rejection_reason': selected.rejectionReason,
      }).eq('id', widget.listingId);

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
      Navigator.pop(context);
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
    final notifications = context.read<NotificationsService>();
    final selected = await _askDeleteReason();
    if (selected == null) return;

    setState(() => _busy = true);
    try {
      final body = selected.comment == null
          ? selected.reason.message
          : '${selected.reason.message}\n\nКомментарий модератора: ${selected.comment}';
      await Supabase.instance.client.from('listings').update({
        'status': 'deleted',
        'rejection_reason': body,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.listingId);

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
      Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    final d = widget.listingData;

    final title = (d['title'] ?? '').toString();
    final price = (d['price'] ?? 0).toString();
    final city = (d['city'] ?? '').toString();
    final category = (d['category'] ?? '').toString();
    final desc = (d['description'] ?? '').toString();
    final phone = (d['phone'] ?? '').toString();
    final ownerId = (d['owner_id'] ?? '').toString();

    final raw = d['photo_urls'] ?? [];
    final images =
        (raw is List) ? raw.map((e) => e.toString()).toList() : <String>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Проверка объявления')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (images.isNotEmpty)
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(images[i], width: 300, fit: BoxFit.cover),
                ),
              ),
            )
          else
            Container(
              height: 160,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: const Icon(Icons.photo, size: 44),
            ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text('Цена: $price • Город: $city • Категория: $category'),
          const SizedBox(height: 10),
          Text(desc.isEmpty ? 'Описание отсутствует' : desc),
          const SizedBox(height: 10),
          Text('Телефон: $phone'),
          const SizedBox(height: 8),
          Text(
            'owner_id: $ownerId',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
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
        ],
      ),
    );
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
  final _userIdCtrl = TextEditingController();

  bool _sendingGlobal = false;
  bool _sendingPersonal = false;

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
          'Скоро выйдет обновление CheStore: улучшим стабильность и добавим новые возможности. Спасибо, что пользуетесь приложением!',
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
    _userIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendGlobal() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      showAppSnack(context, 'Заполните заголовок и текст', isError: true);
      return;
    }

    final service = context.read<NotificationsService>();
    setState(() => _sendingGlobal = true);
    try {
      await service.sendGlobal(title: title, body: body);
      if (!mounted) return;
      showAppSnack(context, 'Общее уведомление отправлено');
      _titleCtrl.clear();
      _bodyCtrl.clear();
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
    if (userId.isEmpty || title.isEmpty || body.isEmpty) {
      showAppSnack(context, 'Укажи user_id, заголовок и текст', isError: true);
      return;
    }

    final service = context.read<NotificationsService>();
    setState(() => _sendingPersonal = true);
    try {
      await service.sendPersonal(
        userId: userId,
        title: title,
        body: body,
      );
      if (!mounted) return;
      showAppSnack(context, 'Личное уведомление отправлено');
      _userIdCtrl.clear();
      _titleCtrl.clear();
      _bodyCtrl.clear();
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


