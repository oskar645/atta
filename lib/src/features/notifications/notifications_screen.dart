import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    timeago.setLocaleMessages('ru', timeago.RuMessages());

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final me = context.read<AuthService>().currentUser;
      if (me == null) return;
      await context.read<NotificationsService>().markAllSeen(me.uid);
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteNotification({
    required NotificationsService notifications,
    required String id,
    required String title,
  }) async {
    if (id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить уведомление?'),
        content: Text(
          title.trim().isEmpty
              ? 'Уведомление исчезнет у всех, кому оно было доступно.'
              : '«$title» исчезнет у всех, кому оно было доступно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Да, удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await notifications.deleteById(id);
      if (!mounted) return;
      showAppSnack(context, 'Уведомление удалено');
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка удаления: $e', isError: true);
    }
  }

  Widget _buildList({
    required List<Map<String, dynamic>> items,
    required NotificationsService notifications,
    required bool allowMarkRead,
    required bool isAdmin,
    required bool showScopeTag,
    required String emptyText,
  }) {
    if (items.isEmpty) {
      return Center(child: Text(emptyText));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final n = items[i];
        final id = (n['id'] ?? '').toString();
        final title = (n['title'] ?? '').toString();
        final body = (n['body'] ?? '').toString();
        final scope = (n['scope'] ?? '').toString();
        final isRead = n['is_read'] == true;
        final createdRaw = n['created_at'];
        DateTime? created;
        if (createdRaw is String) created = DateTime.tryParse(createdRaw);
        if (createdRaw is DateTime) created = createdRaw;

        final isPersonal = scope == 'personal';
        final unreadPersonal = isPersonal && !isRead;

        return Card(
          child: ListTile(
            leading: Icon(
              unreadPersonal ? Icons.mark_email_unread : Icons.notifications_none,
              color: unreadPersonal
                  ? Colors.red
                  : Theme.of(context).colorScheme.outline,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                if (showScopeTag)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isPersonal
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isPersonal ? 'Личное' : 'Общее',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(body),
                if (created != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    timeago.format(created, locale: 'ru'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
            trailing: isAdmin
                ? IconButton(
                    tooltip: 'Удалить уведомление',
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 22,
                    ),
                    onPressed: () => _confirmDeleteNotification(
                      notifications: notifications,
                      id: id,
                      title: title,
                    ),
                  )
                : null,
            onTap: allowMarkRead && unreadPersonal
                ? () async {
                    await notifications.markPersonalReadById(id);
                  }
                : null,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<AuthService>().currentUser!;
    final notifications = context.read<NotificationsService>();
    final admin = context.read<AdminService>();

    return StreamBuilder<bool>(
      stream: admin.streamIsAdmin(me.uid),
      initialData: false,
      builder: (context, adminSnap) {
        final isAdmin = adminSnap.data == true;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Уведомления'),
            actions: [
              IconButton(
                tooltip: 'Отметить все как прочитанные',
                onPressed: () async {
                  await notifications.markAllSeen(me.uid);
                },
                icon: const Icon(Icons.done_all),
              ),
            ],
            bottom: TabBar(
              controller: _tab,
              tabs: const [
                Tab(text: 'Общие'),
                Tab(text: 'Личные'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tab,
            children: [
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: notifications.streamGlobal(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Ошибка: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return _buildList(
                    items: snap.data!,
                    notifications: notifications,
                    allowMarkRead: false,
                    isAdmin: isAdmin,
                    showScopeTag: false,
                    emptyText: 'Пока нет общих уведомлений',
                  );
                },
              ),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: notifications.streamPersonal(me.uid),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Ошибка: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return _buildList(
                    items: snap.data!,
                    notifications: notifications,
                    allowMarkRead: true,
                    isAdmin: isAdmin,
                    showScopeTag: false,
                    emptyText: 'Личных уведомлений пока нет',
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
