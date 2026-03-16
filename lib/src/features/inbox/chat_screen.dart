import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chestore2/src/features/listings/photo_viewer_screen.dart';
import 'package:chestore2/src/features/profile/seller_public_profile_screen.dart';
import 'package:chestore2/src/models/message.dart';
import 'package:chestore2/src/services/auth_service.dart';
import 'package:chestore2/src/services/chat_service.dart';
import 'package:chestore2/src/services/presence_service.dart';
import 'package:chestore2/src/services/profile_service.dart';
import 'package:chestore2/src/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String initialOtherUserName;
  final String initialOtherUserAvatar;

  const ChatScreen({
    super.key,
    required this.chatId,
    this.initialOtherUserName = '',
    this.initialOtherUserAvatar = '',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _picker = ImagePicker();
  bool _sending = false;
  StreamSubscription<List<ChatMessage>>? _messagesSub;

  SupabaseClient get _db => Supabase.instance.client;

  String _uid(BuildContext context) {
    final me = context.read<AuthService>().currentUser;
    return me?.uid ?? '';
  }

  Stream<Map<String, dynamic>?> _streamChatRow(String chatId) {
    return _db.from('chats').stream(primaryKey: ['id']).eq('id', chatId).map(
        (rows) => rows.isEmpty ? null : Map<String, dynamic>.from(rows.first));
  }

  Stream<String> _streamListingThumb(String listingId) {
    return _db
        .from('listings')
        .stream(primaryKey: ['id'])
        .eq('id', listingId)
        .map((rows) {
          if (rows.isEmpty) return '';
          final r = rows.first;
          final urls = r['photo_urls'];
          if (urls is List && urls.isNotEmpty) {
            return (urls.first ?? '').toString().trim();
          }
          if (urls is String) return urls.trim();
          return '';
        });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uid = _uid(context);
      if (uid.isEmpty) return;
      await context
          .read<ChatService>()
          .markChatRead(chatId: widget.chatId, uid: uid);
    });
    _messagesSub = context
        .read<ChatService>()
        .streamMessages(widget.chatId)
        .listen((_) async {
      if (!mounted) return;
      final uid = _uid(context);
      if (uid.isEmpty) return;
      await context
          .read<ChatService>()
          .markChatRead(chatId: widget.chatId, uid: uid);
    });
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;

    final uid = _uid(context);
    if (uid.isEmpty) return;

    final chat = context.read<ChatService>();

    setState(() => _sending = true);
    try {
      await chat.sendMessage(chatId: widget.chatId, senderId: uid, text: t);
      _text.clear();
      await chat.markChatRead(chatId: widget.chatId, uid: uid);
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSend(ImageSource source) async {
    final uid = _uid(context);
    if (uid.isEmpty) return;

    final x = await _picker.pickImage(source: source, imageQuality: 80);
    if (x == null) return;
    if (!mounted) return;

    final chat = context.read<ChatService>();

    setState(() => _sending = true);
    try {
      await chat.sendImage(
          chatId: widget.chatId, senderId: uid, file: File(x.path));
      await chat.markChatRead(chatId: widget.chatId, uid: uid);
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openAttachMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Фото из галереи'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndSend(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Камера'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndSend(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openImageFullScreen(String imageUrl) {
    final url = imageUrl.trim();
    if (url.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(photoUrls: [url]),
      ),
    );
  }

  Widget _messageImage(ChatService chatSvc, String rawImageUrl) {
    return FutureBuilder<String>(
      future: chatSvc.resolveMessageImageUrl(rawImageUrl),
      builder: (context, snap) {
        final resolvedUrl = (snap.data ?? '').trim();

        if (snap.connectionState != ConnectionState.done) {
          return Container(
            width: 240,
            height: 180,
            color: Colors.black12,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          );
        }

        if (resolvedUrl.isEmpty) {
          return Container(
            width: 240,
            height: 180,
            color: Colors.black12,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined),
          );
        }

        return GestureDetector(
          onTap: () => _openImageFullScreen(resolvedUrl),
          child: CachedNetworkImage(
            imageUrl: resolvedUrl,
            width: 240,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 240,
              height: 180,
              color: Colors.black12,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            ),
            errorWidget: (_, __, ___) => Container(
              width: 240,
              height: 180,
              color: Colors.black12,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteMessage(ChatMessage m) async {
    final uid = _uid(context);
    if (uid.isEmpty || m.senderId != uid) return;

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Удалить сообщение?'),
            content: const Text(
                'Сообщение будет удалено без возможности восстановления.'),
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
        ) ??
        false;

    if (!ok) return;
    if (!mounted) return;

    try {
      await context.read<ChatService>().deleteMessage(
            chatId: widget.chatId,
            messageId: m.id,
            uid: uid,
          );
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка удаления: $e', isError: true);
    }
  }

  void _openUserProfile(
    String userId, {
    String initialName = '',
    String initialAvatar = '',
  }) {
    final id = userId.trim();
    if (id.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SellerPublicProfileScreen(
          sellerId: id,
          initialSellerName: initialName,
          initialSellerAvatar: initialAvatar,
        ),
      ),
    );
  }

  String _formatMessageTime(DateTime dt) {
    return DateFormat('HH:mm').format(dt.toLocal());
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final left = a.toLocal();
    final right = b.toLocal();
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _formatDayDivider(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(local.year, local.month, local.day);
    final diffDays = today.difference(target).inDays;

    if (diffDays == 0) return 'Сегодня';
    if (diffDays == 1) return 'Вчера';

    const weekdays = <String>[
      'понедельник',
      'вторник',
      'среда',
      'четверг',
      'пятница',
      'суббота',
      'воскресенье',
    ];
    const months = <String>[
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];

    if (diffDays >= 0 && diffDays < 7) {
      return weekdays[local.weekday - 1];
    }

    final dayMonth = '${local.day} ${months[local.month - 1]}';
    if (local.year == now.year) return dayMonth;
    return '$dayMonth ${local.year}';
  }

  Widget _dayDivider(DateTime dt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _formatDayDivider(dt),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _messageMeta(ChatMessage message, bool mine) {
    final timeStyle = TextStyle(
      fontSize: 11,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    final time = Text(_formatMessageTime(message.createdAt), style: timeStyle);
    if (!mine) return time;

    final isRead = message.readAt != null;
    final isDelivered = message.deliveredAt != null;
    final iconColor =
        isRead ? Colors.blue : Theme.of(context).colorScheme.onSurfaceVariant;

    final statusIcon = isRead
        ? Icon(Icons.done_all_rounded, size: 15, color: iconColor)
        : isDelivered
            ? Icon(Icons.done_all_rounded, size: 15, color: iconColor)
            : Icon(Icons.done_rounded, size: 15, color: iconColor);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        time,
        const SizedBox(width: 4),
        statusIcon,
      ],
    );
  }

  Widget _topListingBar({
    required String listingTitle,
    required String thumbUrl,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: thumbUrl.trim().isEmpty
                  ? Container(
                      width: 44,
                      height: 44,
                      color: Colors.grey.withValues(alpha: 0.2),
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_outlined),
                    )
                  : CachedNetworkImage(
                      imageUrl: thumbUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                listingTitle.trim().isEmpty
                    ? 'Объявление'
                    : listingTitle.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatSvc = context.read<ChatService>();
    final profiles = context.read<ProfileService>();
    final presence = context.read<PresenceService>();
    final uid = _uid(context);

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _streamChatRow(widget.chatId),
      builder: (context, chatSnap) {
        final chatRow = chatSnap.data;
        final listingId = (chatRow?['listing_id'] ?? '').toString();
        final listingTitle = (chatRow?['listing_title'] ?? '').toString();

        final buyerId = (chatRow?['buyer_id'] ?? '').toString();
        final sellerId = (chatRow?['seller_id'] ?? '').toString();
        final otherId = (uid == buyerId) ? sellerId : buyerId;
        final profileSeed = <String, dynamic>{
          if (widget.initialOtherUserName.trim().isNotEmpty)
            'display_name': widget.initialOtherUserName.trim(),
          if (widget.initialOtherUserAvatar.trim().isNotEmpty)
            'avatar_url': widget.initialOtherUserAvatar.trim(),
        };

        return StreamBuilder<Map<String, dynamic>>(
          stream: profiles.streamProfile(otherId, seed: profileSeed),
          builder: (context, profileSnap) {
            final otherRow = profileSnap.data ?? const <String, dynamic>{};
            final otherName =
                profiles.pickNameFromRow(otherRow, fallback: '').trim();
            final otherAvatar = profiles.pickAvatarFromRow(otherRow);

            return StreamBuilder<String>(
              stream: listingId.isEmpty
                  ? Stream.value('')
                  : _streamListingThumb(listingId),
              builder: (context, photoSnap) {
                final thumb = photoSnap.data ?? '';

                return Scaffold(
                  appBar: AppBar(
                    title: StreamBuilder<bool>(
                      stream: presence.streamIsOnline(otherId),
                      builder: (context, onlineSnap) {
                        final isOnline = onlineSnap.data == true;
                        return Row(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundImage: otherAvatar.isEmpty
                                      ? null
                                      : NetworkImage(otherAvatar),
                                  child: otherAvatar.isEmpty
                                      ? Text(
                                          otherName.isEmpty
                                              ? 'U'
                                              : otherName[0].toUpperCase(),
                                          style: const TextStyle(fontSize: 12),
                                        )
                                      : null,
                                ),
                                Positioned(
                                  right: -1,
                                  bottom: -1,
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isOnline
                                          ? Colors.green
                                          : Theme.of(context)
                                              .colorScheme
                                              .outlineVariant,
                                      border: Border.all(
                                        color: Theme.of(context)
                                                .appBarTheme
                                                .backgroundColor ??
                                            Theme.of(context)
                                                .scaffoldBackgroundColor,
                                        width: 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _openUserProfile(
                                  otherId,
                                  initialName: otherName,
                                  initialAvatar: otherAvatar,
                                ),
                                child: Text(
                                  otherName.isEmpty ? '...' : otherName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  body: Column(
                    children: [
                      _topListingBar(
                        listingTitle: listingTitle,
                        thumbUrl: thumb,
                        onTap: () => _openUserProfile(
                          otherId,
                          initialName: otherName,
                          initialAvatar: otherAvatar,
                        ),
                      ),
                      Expanded(
                        child: StreamBuilder<List<ChatMessage>>(
                          stream: chatSvc.streamMessages(widget.chatId),
                          builder: (context, snap) {
                            if (!snap.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }

                            final items = snap.data!;
                            if (items.isEmpty) {
                              return const Center(
                                  child: Text('Напишите первое сообщение'));
                            }

                            return ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.all(12),
                              itemCount: items.length,
                              itemBuilder: (_, i) {
                                final m = items[i];
                                final mine = m.senderId == uid;
                                final hasImg = (m.imageUrl ?? '').isNotEmpty;
                                final showDayDivider =
                                    i == items.length - 1 ||
                                    !_isSameDay(
                                      m.createdAt,
                                      items[i + 1].createdAt,
                                    );

                                return Column(
                                  children: [
                                    if (showDayDivider) _dayDivider(m.createdAt),
                                    Align(
                                      alignment: mine
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: GestureDetector(
                                        onLongPress: mine
                                            ? () => _confirmDeleteMessage(m)
                                            : null,
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 4),
                                          padding: const EdgeInsets.all(10),
                                          constraints: const BoxConstraints(
                                            maxWidth: 300,
                                          ),
                                          decoration: BoxDecoration(
                                            color: mine
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (hasImg)
                                                ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  child: _messageImage(
                                                      chatSvc, m.imageUrl!),
                                                ),
                                              if (m.text.isNotEmpty) ...[
                                                if (hasImg)
                                                  const SizedBox(height: 6),
                                                Text(m.text),
                                              ],
                                              const SizedBox(height: 4),
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: _messageMeta(m, mine),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: _sending ? null : _openAttachMenu,
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _text,
                                  decoration: InputDecoration(
                                    hintText: 'Сообщение...',
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: Theme.of(context).dividerColor,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (_) => _sendText(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: _sending ? null : _sendText,
                                icon: const Icon(Icons.send),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
