import 'dart:async';

import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/main_shell_controller.dart';
import 'package:atta/src/services/network_resilience.dart';
import 'package:atta/src/services/notification_navigation_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/features/inbox/chat_screen.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/widgets/app_error_view.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

typedef NotificationUrlOpener = Future<bool> Function(Uri uri);

@visibleForTesting
NotificationUrlOpener? debugNotificationUrlOpener;

String notificationActionLabelForUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  final host = (uri?.host ?? '').trim().toLowerCase();
  final normalizedHost = host.startsWith('www.') ? host.substring(4) : host;
  if (normalizedHost == 'instagram.com' ||
      normalizedHost.endsWith('.instagram.com')) {
    return 'Открыть в Instagram';
  }
  if (normalizedHost == 't.me' ||
      normalizedHost == 'telegram.me' ||
      normalizedHost.endsWith('.telegram.me')) {
    return 'Открыть в Telegram';
  }
  if (normalizedHost == 'wa.me' ||
      normalizedHost == 'whatsapp.com' ||
      normalizedHost.endsWith('.whatsapp.com')) {
    return 'Открыть в WhatsApp';
  }
  return 'Открыть ссылку';
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tab;
  Stream<List<Map<String, dynamic>>>? _globalStream;
  Stream<List<Map<String, dynamic>>>? _personalStream;
  Future<void>? _preloadFuture;
  Future<void>? _markSeenFuture;
  bool _markedCurrentPersonalTabVisit = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(_handleTabChanged);
    timeago.setLocaleMessages('ru', timeago.RuMessages());

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final me = context.read<AuthService>().currentUser;
      if (me == null) return;
      final notifications = context.read<NotificationsService>();
      _globalStream ??= notifications.streamGlobal();
      _personalStream ??= notifications.streamPersonal(me.uid);
      _preloadFuture ??= notifications.preload(me.uid);
      if (_tab.index == 1) {
        _markPersonalTabSeen();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tab.removeListener(_handleTabChanged);
    _tab.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tab.index != 1) {
      _markedCurrentPersonalTabVisit = false;
      return;
    }
    if (_markedCurrentPersonalTabVisit) return;
    _markedCurrentPersonalTabVisit = true;
    _markPersonalTabSeen();
  }

  void _markPersonalTabSeen() {
    final me = context.read<AuthService>().currentUser;
    if (me == null) return;
    final notifications = context.read<NotificationsService>();
    _preloadFuture ??= notifications.preload(me.uid);
    _markSeenFuture ??= _preloadFuture!.then((_) {
      return notifications.markAllSeen(me.uid);
    }).whenComplete(() {
      _markSeenFuture = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final user = context.read<AuthService>().currentUser;
    if (user == null) return;
    unawaited(
      context
          .read<NotificationsService>()
          .refreshActiveSession(force: true)
          .catchError((_) {}),
    );
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
        return _NotificationListItem(
          notification: n,
          notifications: notifications,
          allowMarkRead: allowMarkRead,
          isAdmin: isAdmin,
          showScopeTag: showScopeTag,
          onDelete: ({required id, required title}) =>
              _confirmDeleteNotification(
            notifications: notifications,
            id: id,
            title: title,
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
                            unreadDotKey:
                                const ValueKey('personal_tab_unread_dot'),
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

class _NotificationListItem extends StatefulWidget {
  const _NotificationListItem({
    required this.notification,
    required this.notifications,
    required this.allowMarkRead,
    required this.isAdmin,
    required this.showScopeTag,
    required this.onDelete,
  });

  final Map<String, dynamic> notification;
  final NotificationsService notifications;
  final bool allowMarkRead;
  final bool isAdmin;
  final bool showScopeTag;
  final Future<void> Function({
    required String id,
    required String title,
  }) onDelete;

  @override
  State<_NotificationListItem> createState() => _NotificationListItemState();
}

class _NotificationListItemState extends State<_NotificationListItem> {
  bool _openingUrl = false;

  Map<String, dynamic> get _payload =>
      NotificationNavigationService.payloadForNotification(widget.notification);

  Future<void> _handleTap() async {
    final n = widget.notification;
    final id = (n['id'] ?? '').toString();
    final scope = (n['scope'] ?? '').toString();
    final isRead = n['is_read'] == true;
    final notificationType = (n['type'] ?? '').toString().trim().toLowerCase();
    final chatId = (n['chatId'] ?? n['chat_id'] ?? '').toString().trim();
    final senderName =
        (n['senderName'] ?? n['sender_name'] ?? '').toString().trim();
    final senderAvatar = (n['senderAvatarUrl'] ?? n['sender_avatar_url'] ?? '')
        .toString()
        .trim();
    final isPersonal = scope == 'personal';
    final unreadPersonal = isPersonal && !isRead;

    if (notificationType == 'chat_message') {
      if (widget.allowMarkRead && unreadPersonal) {
        await widget.notifications.markPersonalReadById(id);
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
      return;
    }
    await NotificationNavigationService.handleNotificationTap(
      context,
      widget.notification,
    );
  }

  Future<void> _openActionUrl() async {
    final url = (_payload['actionUrl'] ?? _payload['action_url'] ?? '')
        .toString()
        .trim();
    if (url.isEmpty || _openingUrl) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      showAppSnack(context, 'Не удалось открыть ссылку.', isError: true);
      return;
    }
    setState(() => _openingUrl = true);
    try {
      final opener = debugNotificationUrlOpener;
      final opened = opener != null
          ? await opener(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        showAppSnack(context, 'Не удалось открыть ссылку.', isError: true);
      }
    } catch (_) {
      if (mounted) {
        showAppSnack(context, 'Не удалось открыть ссылку.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _openingUrl = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    final title = (n['title'] ?? '').toString();
    final body = (n['body'] ?? '').toString().trim();
    final scope = (n['scope'] ?? '').toString();
    final isRead = n['is_read'] == true;
    final createdRaw = n['created_at'];
    final imageUrl =
        (_payload['imageUrl'] ?? _payload['image_url'] ?? '').toString().trim();
    final description = (_payload['description'] ?? '').toString().trim();
    final actionUrl = (_payload['actionUrl'] ?? _payload['action_url'] ?? '')
        .toString()
        .trim();
    DateTime? created;
    if (createdRaw is String) created = DateTime.tryParse(createdRaw);
    if (createdRaw is DateTime) created = createdRaw;

    final isPersonal = scope == 'personal';
    final unreadPersonal = isPersonal && !isRead;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _handleTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      unreadPersonal
                          ? Icons.mark_email_unread
                          : Icons.notifications_none,
                      color: unreadPersonal
                          ? Colors.red
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (widget.showScopeTag)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
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
                  if (widget.isAdmin)
                    IconButton(
                      tooltip: 'Удалить уведомление',
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 22,
                      ),
                      onPressed: () => widget.onDelete(
                        id: (n['id'] ?? '').toString(),
                        title: title,
                      ),
                    ),
                ],
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(body),
              ],
              if (imageUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: 180,
                    width: double.infinity,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                    ),
                  ),
                ),
              ],
              if (description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(description),
              ],
              if (actionUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: _openingUrl ? null : _openActionUrl,
                    child: Text(notificationActionLabelForUrl(actionUrl)),
                  ),
                ),
              ],
              if (created != null) ...[
                const SizedBox(height: 8),
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
        ),
      ),
    );
  }
}

class _NotificationTab extends StatelessWidget {
  const _NotificationTab({
    required this.text,
    required this.hasUnread,
    this.unreadDotKey,
  });

  final String text;
  final bool hasUnread;
  final Key? unreadDotKey;

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
              key: unreadDotKey,
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
