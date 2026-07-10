import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:atta/src/features/inbox/chat_screen.dart';
import 'package:atta/src/features/support/support_screen.dart';
import 'package:atta/src/models/chat.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/main_shell_controller.dart';
import 'package:atta/src/services/network_resilience.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/widgets/app_error_view.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:atta/src/widgets/presence_badge.dart';
import 'package:atta/src/widgets/skeletons.dart';

void _debugInboxLog(String message) {
  assert(() {
    debugPrint(message);
    return true;
  }());
}

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with WidgetsBindingObserver {
  bool _showUnreadOnly = false;
  StreamSubscription<List<Chat>>? _chatsSub;
  String? _boundUid;
  List<Chat>? _items;
  bool _loading = true;
  bool _loadedOnce = false;
  String? _errorText;
  DateTime? _lastResumeRefreshAt;

  static const Duration _resumeRefreshCooldown = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final me = context.read<AuthService>().currentUser;
    final uid = me?.uid;
    if (uid == null || uid.isEmpty || uid == _boundUid) {
      return;
    }
    _bindInbox(uid);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatsSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final uid = _boundUid;
    if (uid == null || uid.isEmpty) return;
    final lastRefreshAt = _lastResumeRefreshAt;
    if (lastRefreshAt != null &&
        DateTime.now().difference(lastRefreshAt) < _resumeRefreshCooldown) {
      return;
    }
    _lastResumeRefreshAt = DateTime.now();
    unawaited(context.read<ChatService>().handleAppResumed(uid));
  }

  void _bindInbox(String uid) {
    _debugInboxLog('Chats open');
    _debugInboxLog('auth ready user=$uid');
    _boundUid = uid;
    _chatsSub?.cancel();
    final chat = context.read<ChatService>();
    _chatsSub = chat.streamMyChats(uid).listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _items = items;
          if (items.isNotEmpty) {
            _loading = false;
            _loadedOnce = true;
            _errorText = null;
          }
        });
        _debugInboxLog(
          items.isEmpty
              ? 'Chats load empty'
              : 'Chats load success count=${items.length}',
        );
      },
      onError: (error) {
        if (!mounted) return;
        final hasItems = (_items ?? const <Chat>[]).isNotEmpty;
        setState(() {
          _loading = false;
          if (hasItems) {
            _errorText = null;
            return;
          }
          _loadedOnce = true;
          _errorText = shouldShowNetworkVpnHint(error)
              ? kNetworkVpnHintMessage
              : 'Не удалось загрузить сообщения.';
        });
        _debugInboxLog('Chats load error message=$error');
      },
    );
    unawaited(_loadInbox(chat, uid));
  }

  Future<void> _loadInbox(ChatService chat, String uid) async {
    _debugInboxLog('Chats list load start user=$uid');
    try {
      await chat.refreshInbox(uid);
      final loadError = chat.lastChatsLoadError;
      final hasItems = (_items ?? const <Chat>[]).isNotEmpty;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadedOnce = true;
        _errorText = !hasItems && loadError != null
            ? (shouldShowNetworkVpnHint(loadError)
                ? kNetworkVpnHintMessage
                : 'Не удалось загрузить сообщения.')
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      final hasItems = (_items ?? const <Chat>[]).isNotEmpty;
      setState(() {
        _loading = false;
        if (hasItems) {
          _errorText = null;
          return;
        }
        _loadedOnce = true;
        _errorText = shouldShowNetworkVpnHint(error)
            ? kNetworkVpnHintMessage
            : 'Не удалось загрузить сообщения.';
      });
      _debugInboxLog('Chats load error message=$error');
    } finally {
      _debugInboxLog('Chats load finally loading=false');
    }
  }

  Future<void> _refreshInbox(ChatService chat, String uid) async {
    try {
      await chat.refreshInbox(uid);
      final loadError = chat.lastChatsLoadError;
      if (loadError != null && mounted && (_items ?? const <Chat>[]).isEmpty) {
        showAppSnack(
          context,
          shouldShowNetworkVpnHint(loadError)
              ? kNetworkVpnHintMessage
              : 'Не удалось обновить сообщения.',
          isError: true,
        );
      }
    } catch (error) {
      if (!mounted) return;
      showAppSnack(
        context,
        shouldShowNetworkVpnHint(error)
            ? kNetworkVpnHintMessage
            : 'Не удалось обновить сообщения.',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    timeago.setLocaleMessages('ru', timeago.RuMessages());

    final me = context.read<AuthService>().currentUser;
    if (me == null) {
      return const Scaffold(body: Center(child: Text('Нужно войти')));
    }

    final uid = me.uid;
    final chat = context.read<ChatService>();
    final profiles = context.read<ProfileService>();
    final presence = context.read<PresenceService>();
    final items = _items ?? const <Chat>[];
    context.watch<MainShellController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сообщения'),
        centerTitle: false,
        titleSpacing: 16,
        toolbarHeight: 54,
      ),
      body: _errorText != null && items.isEmpty
          ? Center(
              child: AppErrorView(
                message: _errorText!,
                onRetry: () async {
                  if (!mounted) return;
                  setState(() {
                    _loading = true;
                    _errorText = null;
                  });
                  await _loadInbox(chat, uid);
                },
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: SegmentedButton<bool>(
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                    segments: const [
                      ButtonSegment<bool>(value: false, label: Text('Все')),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Непрочитанные'),
                      ),
                    ],
                    selected: <bool>{_showUnreadOnly},
                    onSelectionChanged: (selection) {
                      setState(() => _showUnreadOnly = selection.first);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _buildInboxBody(
                    context,
                    chat: chat,
                    uid: uid,
                    profiles: profiles,
                    presence: presence,
                    items: items,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInboxBody(
    BuildContext context, {
    required ChatService chat,
    required String uid,
    required ProfileService profiles,
    required PresenceService presence,
    required List<Chat> items,
  }) {
    final visibleItems = _showUnreadOnly
        ? items.where((chat) => chat.unreadFor(uid) > 0).toList()
        : items;

    if (items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        chat.markChatsDelivered(
          chatIds: items.map((e) => e.id),
          uid: uid,
        );
      });
    }

    if (_loading && items.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: 6,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, __) => const SkeletonChatRow(),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refreshInbox(chat, uid),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        itemCount: visibleItems.isEmpty ? 2 : visibleItems.length + 1,
        separatorBuilder: (_, index) =>
            index == 0 ? const SizedBox(height: 12) : const Divider(height: 1),
        itemBuilder: (_, i) {
          if (i == 0) {
            return _SupportInboxCard(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SupportScreen(),
                  ),
                );
              },
            );
          }
          final chatIndex = i - 1;
          if (_loadedOnce && visibleItems.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 56),
              child: Center(
                child: Text(
                  _showUnreadOnly
                      ? 'Нет непрочитанных сообщений'
                      : 'Пока нет сообщений',
                ),
              ),
            );
          }
          if (chatIndex >= visibleItems.length) {
            return const SizedBox.shrink();
          }
          final c = visibleItems[chatIndex];
          final otherId = c.otherUserId(uid);
          final unread = c.unreadFor(uid);
          final isUnread = unread > 0;
          final activityAt = c.lastMessageAt ?? c.createdAt;
          final stableKey = ValueKey('chat-item:${c.id}:${c.listingId}');

          final tile = StreamBuilder<Map<String, dynamic>>(
            stream: profiles.streamProfile(otherId),
            builder: (context, profileSnap) {
              final row = profileSnap.data ?? const <String, dynamic>{};
              if (row.isNotEmpty) {
                profiles.seedProfile(otherId, row);
              }
              final fallbackRow = row.isEmpty
                  ? {
                      'display_name': c.otherUserName(uid),
                      'avatar_url': c.otherUserAvatar(uid),
                    }
                  : row;
              final otherName = profiles.pickNameFromRow(
                fallbackRow,
                fallback: c.otherUserName(uid),
              );
              final titleName = otherName.isEmpty ? '...' : otherName;
              final avatar = profiles.pickAvatarFromRow(fallbackRow);
              final listingPhoto = c.listingPhotoUrl.trim();

              return StreamBuilder<bool>(
                stream: presence.streamIsOnline(otherId),
                initialData: presence.peekIsOnline(otherId) ?? false,
                builder: (context, presenceSnap) {
                  final isOnline = presenceSnap.data == true;

                  return ListTile(
                    key: stableKey,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    leading: PresenceBadge(
                      isOnline: isOnline,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: MediaPreviewBox(
                            imageUrl: listingPhoto,
                            categoryHint: 'listings',
                            borderRadius: 0,
                            emptyLabel: '',
                            errorLabel: '',
                            placeholderLabel: '',
                          ),
                        ),
                      ),
                    ),
                    onTap: () async {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            chatId: c.id,
                            initialOtherUserName: otherName,
                            initialOtherUserAvatar: avatar,
                          ),
                        ),
                      );
                    },
                    title: Text(
                      titleName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight:
                            isUnread ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${c.listingTitle}\n${c.lastMessage}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(timeago.format(activityAt, locale: 'ru')),
                        if (isUnread) ...[
                          const SizedBox(height: 8),
                          Badge(
                            label: Text(unread > 99 ? '99+' : '$unread'),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          );

          return Dismissible(
            key: ValueKey('chat-dismiss:${c.id}:${c.listingId}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.red.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.red),
            ),
            confirmDismiss: (_) async {
              return (await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Удалить переписку?'),
                      content: const Text(
                        'Все сообщения в этом чате будут удалены.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Отмена'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Удалить'),
                        ),
                      ],
                    ),
                  )) ??
                  false;
            },
            onDismissed: (_) async {
              await chat.deleteChat(chatId: c.id, uid: uid);
            },
            child: tile,
          );
        },
      ),
    );
  }
}

class _SupportInboxCard extends StatelessWidget {
  const _SupportInboxCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2B8CFF);
    const secondary = Color(0xFF1674E0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [
                  primary,
                  secondary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.22),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.support_agent_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Поддержка ATTA',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Будем рады помочь',
                          style: TextStyle(
                            color: Color(0xE6FFFFFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
