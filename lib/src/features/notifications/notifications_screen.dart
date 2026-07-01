import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/main_shell_controller.dart';
import 'package:atta/src/services/network_resilience.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/features/inbox/chat_screen.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/widgets/app_error_view.dart';
import 'package:atta/src/widgets/skeletons.dart';
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
  Stream<List<Map<String, dynamic>>>? _globalStream;
  Stream<List<Map<String, dynamic>>>? _personalStream;
  Future<void>? _preloadFuture;
  Future<void>? _markSeenFuture;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    timeago.setLocaleMessages('ru', timeago.RuMessages());

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final me = context.read<AuthService>().currentUser;
      if (me == null) return;
      final notifications = context.read<NotificationsService>();
      _globalStream ??= notifications.streamGlobal();
      _personalStream ??= notifications.streamPersonal(me.uid);
      _preloadFuture ??= notifications.preload(me.uid);
      _markSeenFuture ??= _preloadFuture!.then((_) {
        return notifications.markAllSeen(me.uid);
      });
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
        final notificationType =
            (n['type'] ?? '').toString().trim().toLowerCase();
        final chatId = (n['chatId'] ?? n['chat_id'] ?? '').toString().trim();
        final senderName =
            (n['senderName'] ?? n['sender_name'] ?? '').toString().trim();
        final senderAvatar =
            (n['senderAvatarUrl'] ?? n['sender_avatar_url'] ?? '')
                .toString()
                .trim();
        final createdRaw = n['created_at'];
        DateTime? created;
        if (createdRaw is String) created = DateTime.tryParse(createdRaw);
        if (createdRaw is DateTime) created = createdRaw;

        final isPersonal = scope == 'personal';
        final unreadPersonal = isPersonal && !isRead;

        return Card(
          child: ListTile(
            leading: Icon(
              unreadPersonal
                  ? Icons.mark_email_unread
                  : Icons.notifications_none,
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
            onTap: notificationType == 'chat_message'
                ? () async {
                    if (allowMarkRead && unreadPersonal) {
                      await notifications.markPersonalReadById(id);
                      if (!mounted) return;
                    }
                    if (chatId.isNotEmpty) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            chatId: chatId,
                            initialOtherUserName: senderName,
                            initialOtherUserAvatar: senderAvatar,
                          ),
                        ),
                      );
                      return;
                    }
                    context.read<MainShellController>().selectTab(3);
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                : null,
          ),
        );
      },
    );
  }

  Widget _buildSkeletonList() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, __) => const SkeletonNotificationRow(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<AuthService>().currentUser!;
    final notifications = context.read<NotificationsService>();
    _globalStream ??= notifications.streamGlobal();
    _personalStream ??= notifications.streamPersonal(me.uid);
    _preloadFuture ??= notifications.preload(me.uid);
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
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(kTextTabBarHeight),
              child: StreamBuilder<int>(
                stream: notifications.streamUnreadGlobalCount(me.uid),
                initialData: 0,
                builder: (context, globalSnap) {
                  return StreamBuilder<int>(
                    stream: notifications.streamUnreadPersonalCount(me.uid),
                    initialData: 0,
                    builder: (context, personalSnap) {
                      return TabBar(
                        controller: _tab,
                        tabs: [
                          _NotificationTab(
                            text: 'Общие',
                            hasUnread: (globalSnap.data ?? 0) > 0,
                          ),
                          _NotificationTab(
                            text: 'Личные',
                            hasUnread: (personalSnap.data ?? 0) > 0,
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
          body: TabBarView(
            controller: _tab,
            children: [
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _globalStream,
                initialData: notifications.peekGlobal(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: AppErrorView(
                        message: shouldShowNetworkVpnHint(snap.error!)
                            ? kNetworkVpnHintMessage
                            : 'Не удалось загрузить уведомления.',
                        onRetry: () async {
                          if (mounted) {
                            setState(() {
                              _globalStream = notifications.streamGlobal();
                            });
                          }
                        },
                      ),
                    );
                  }
                  if (!snap.hasData ||
                      (snap.data!.isEmpty && _preloadFuture != null)) {
                    return FutureBuilder<void>(
                      future: _preloadFuture,
                      builder: (context, preloadSnap) {
                        if (snap.hasData && snap.data!.isNotEmpty) {
                          return _buildList(
                            items: snap.data!,
                            notifications: notifications,
                            allowMarkRead: false,
                            isAdmin: isAdmin,
                            showScopeTag: false,
                            emptyText: 'Пока нет общих уведомлений',
                          );
                        }
                        if (preloadSnap.connectionState !=
                            ConnectionState.done) {
                          return _buildSkeletonList();
                        }
                        return _buildList(
                          items: snap.data ?? const <Map<String, dynamic>>[],
                          notifications: notifications,
                          allowMarkRead: false,
                          isAdmin: isAdmin,
                          showScopeTag: false,
                          emptyText: 'Пока нет общих уведомлений',
                        );
                      },
                    );
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
                stream: _personalStream,
                initialData: notifications.peekPersonal(me.uid),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: AppErrorView(
                        message: shouldShowNetworkVpnHint(snap.error!)
                            ? kNetworkVpnHintMessage
                            : 'Не удалось загрузить уведомления.',
                        onRetry: () async {
                          if (mounted) {
                            setState(() {
                              _personalStream =
                                  notifications.streamPersonal(me.uid);
                            });
                          }
                        },
                      ),
                    );
                  }
                  if (!snap.hasData ||
                      (snap.data!.isEmpty && _preloadFuture != null)) {
                    return FutureBuilder<void>(
                      future: _preloadFuture,
                      builder: (context, preloadSnap) {
                        if (snap.hasData && snap.data!.isNotEmpty) {
                          return _buildList(
                            items: snap.data!,
                            notifications: notifications,
                            allowMarkRead: true,
                            isAdmin: isAdmin,
                            showScopeTag: false,
                            emptyText: 'Пока нет личных уведомлений',
                          );
                        }
                        if (preloadSnap.connectionState !=
                            ConnectionState.done) {
                          return _buildSkeletonList();
                        }
                        return _buildList(
                          items: snap.data ?? const <Map<String, dynamic>>[],
                          notifications: notifications,
                          allowMarkRead: true,
                          isAdmin: isAdmin,
                          showScopeTag: false,
                          emptyText: 'Пока нет личных уведомлений',
                        );
                      },
                    );
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

class _NotificationTab extends StatelessWidget {
  const _NotificationTab({
    required this.text,
    required this.hasUnread,
  });

  final String text;
  final bool hasUnread;

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (hasUnread) ...[
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
    );
  }
}
