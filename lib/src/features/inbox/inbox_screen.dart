import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:chestore2/src/features/inbox/chat_screen.dart';
import 'package:chestore2/src/features/support/support_screen.dart';
import 'package:chestore2/src/models/chat.dart';
import 'package:chestore2/src/services/auth_service.dart';
import 'package:chestore2/src/services/chat_service.dart';
import 'package:chestore2/src/services/presence_service.dart';
import 'package:chestore2/src/services/profile_service.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сообщения'),
        actions: [
          IconButton(
            tooltip: 'Поддержка',
            icon: const Icon(Icons.headset_mic_outlined, color: Colors.blue),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SupportScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Chat>>(
        stream: chat.streamMyChats(uid),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Ошибка чатов:\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snap.data!;
          if (items.isEmpty) return const Center(child: Text('Нет чатов'));

          WidgetsBinding.instance.addPostFrameCallback((_) {
            chat.markChatsDelivered(
              chatIds: items.map((e) => e.id),
              uid: uid,
            );
          });

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = items[i];
              final otherId = c.otherUserId(uid);
              final unread = c.unreadFor(uid);
              final isUnread = unread > 0;

              return Dismissible(
                key: ValueKey(c.id),
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
                              'Все сообщения в этом чате будут удалены.'),
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
                child: StreamBuilder<Map<String, dynamic>>(
                  stream: profiles.streamProfile(otherId),
                  builder: (context, profileSnap) {
                    final row = profileSnap.data ?? const <String, dynamic>{};
                    if (row.isNotEmpty) {
                      profiles.seedProfile(otherId, row);
                    }
                    final otherName = profiles.pickNameFromRow(
                      row,
                      fallback: '',
                    );
                    final titleName = otherName.isEmpty ? '...' : otherName;
                    final avatar = profiles.pickAvatarFromRow(row);

                    return StreamBuilder<bool>(
                      stream: presence.streamIsOnline(otherId),
                      builder: (context, presenceSnap) {
                        final isOnline = presenceSnap.data == true;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundImage: avatar.isEmpty
                                    ? null
                                    : NetworkImage(avatar),
                                child: avatar.isEmpty
                                    ? Text(
                                        titleName == '...'
                                            ? 'U'
                                            : titleName[0].toUpperCase(),
                                      )
                                    : null,
                              ),
                              Positioned(
                                right: -1,
                                bottom: -1,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isOnline
                                        ? Colors.red
                                        : Theme.of(context)
                                            .colorScheme
                                            .outlineVariant,
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          onTap: () async {
                            await chat.markChatRead(chatId: c.id, uid: uid);
                            if (!context.mounted) return;
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
                              Text(timeago.format(c.updatedAt, locale: 'ru')),
                              if (isUnread) ...[
                                const SizedBox(height: 8),
                                Badge(
                                    label:
                                        Text(unread > 99 ? '99+' : '$unread')),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
