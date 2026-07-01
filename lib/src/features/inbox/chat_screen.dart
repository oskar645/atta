import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/features/listings/photo_viewer_screen.dart';
import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/models/chat.dart';
import 'package:atta/src/models/message.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/network_resilience.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:atta/src/widgets/presence_badge.dart';
import 'package:atta/src/widgets/remote_avatar.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:atta/src/app.dart';

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

class _ChatScreenState extends State<ChatScreen> with RouteAware {
  final _text = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _selectedImages = <XFile>[];
  bool _sending = false;
  int _lastSeenMessageCount = 0;
  Timer? _markReadDebounce;
  StreamSubscription<List<ChatMessage>>? _messagesSub;
  Stream<List<ChatMessage>>? _messagesStream;
  late Future<void> _chatLoadFuture;
  late ChatService _chatService;
  ModalRoute<dynamic>? _route;

  String _uid(BuildContext context) {
    final me = context.read<AuthService>().currentUser;
    return me?.uid ?? '';
  }

  @override
  void initState() {
    super.initState();
    _chatService = context.read<ChatService>();
    _chatLoadFuture = _chatService.preloadChat(
      widget.chatId,
      uid: _uid(context),
    );
    _messagesStream = _chatService.streamMessages(widget.chatId);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _scheduleMarkRead(immediate: true);
    });
    _messagesSub = _messagesStream?.listen((messages) async {
      if (!mounted || messages.isEmpty) return;
      final shouldMarkRead =
          _lastSeenMessageCount == 0 || messages.length > _lastSeenMessageCount;
      _lastSeenMessageCount = messages.length;
      if (shouldMarkRead) {
        await _scheduleMarkRead();
      }
    });
  }

  @override
  void dispose() {
    attaRouteObserver.unsubscribe(this);
    _chatService.setForegroundChat(null);
    _markReadDebounce?.cancel();
    _messagesSub?.cancel();
    _text.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && !identical(route, _route)) {
      if (_route != null) {
        attaRouteObserver.unsubscribe(this);
      }
      _route = route;
      if (route is PageRoute<dynamic>) {
        attaRouteObserver.subscribe(this, route);
      }
    }
  }

  @override
  void didPush() {
    _chatService.setForegroundChat(widget.chatId);
  }

  @override
  void didPopNext() {
    _chatService.setForegroundChat(widget.chatId);
    unawaited(_scheduleMarkRead(immediate: true));
  }

  @override
  void didPushNext() {
    _chatService.setForegroundChat(null);
  }

  @override
  void didPop() {
    _chatService.setForegroundChat(null);
  }

  bool _isRouteVisible() => mounted && (_route?.isCurrent ?? true);

  Future<void> _scheduleMarkRead({bool immediate = false}) async {
    final uid = _uid(context);
    if (uid.isEmpty || !_isRouteVisible()) return;
    _markReadDebounce?.cancel();
    if (immediate) {
      await context.read<ChatService>().markChatRead(
            chatId: widget.chatId,
            uid: uid,
          );
      return;
    }
    _markReadDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted || !_isRouteVisible()) return;
      await context.read<ChatService>().markChatRead(
            chatId: widget.chatId,
            uid: uid,
          );
    });
  }

  void _retryChatLoad() {
    final chatService = context.read<ChatService>();
    setState(() {
      _chatLoadFuture = chatService.preloadChat(
        widget.chatId,
        uid: _uid(context),
      );
      _messagesStream = chatService.streamMessages(widget.chatId);
    });
  }

  Future<void> _sendText() async {
    if (_sending) return;
    final t = _text.text.trim();
    if (t.isEmpty && _selectedImages.isEmpty) return;

    final uid = _uid(context);
    if (uid.isEmpty) return;

    final chat = context.read<ChatService>();

    setState(() => _sending = true);
    try {
      if (t.isNotEmpty) {
        await chat.sendMessage(chatId: widget.chatId, senderId: uid, text: t);
      }
      for (final image in List<XFile>.from(_selectedImages)) {
        await chat.sendImage(
          chatId: widget.chatId,
          senderId: uid,
          file: File(image.path),
        );
      }
      _text.clear();
      _selectedImages.clear();
    } catch (e) {
      if (!mounted) return;
      final message = _friendlyChatError(e);
      showAppSnack(context, message, isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _friendlyChatError(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 413 || error.code == 'payload_too_large') {
        return 'Файл слишком большой. Попробуйте выбрать другое фото.';
      }
      if (error.isTimeout || error.isNetworkError) {
        return kNetworkVpnHintMessage;
      }
      if (error.message.trim().isNotEmpty) {
        return error.message.trim();
      }
    }
    return shouldShowNetworkVpnHint(error)
        ? kNetworkVpnHintMessage
        : 'Не удалось отправить сообщение. Попробуйте ещё раз.';
  }

  Future<void> _pickAndSend(ImageSource source) async {
    if (source == ImageSource.gallery) {
      final images = await _picker.pickMultiImage(
        imageQuality: 78,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (images.isEmpty || !mounted) return;
      setState(() {
        for (final image in images) {
          if (_selectedImages.any((item) => item.path == image.path)) continue;
          _selectedImages.add(image);
        }
      });
      return;
    }

    final image = await _picker.pickImage(
      source: source,
      imageQuality: 78,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (image == null || !mounted) return;
    setState(() {
      if (_selectedImages.any((item) => item.path == image.path)) return;
      _selectedImages.add(image);
    });
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
    if (url.isEmpty) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(photoUrls: [url]),
      ),
    );
  }

  Widget _messageImage(ChatService chatSvc, String rawImageUrl) {
    const maxWidth = 248.0;
    const maxHeight = 300.0;

    Widget imageFallback([String message = 'Фото недоступно']) {
      return Container(
        width: maxWidth,
        height: 180,
        color: Colors.black12,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          message,
          textAlign: TextAlign.center,
        ),
      );
    }

    final localPath = rawImageUrl.startsWith('file://')
        ? rawImageUrl.replaceFirst('file://', '')
        : null;
    if (localPath != null && localPath.isNotEmpty) {
      return GestureDetector(
        onTap: () => _openImageFullScreen(localPath),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
          child: AspectRatio(
            aspectRatio: 1,
            child: Image.file(
              File(localPath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => imageFallback(),
            ),
          ),
        ),
      );
    }
    return FutureBuilder<String>(
      future: chatSvc.resolveMessageImageUrl(rawImageUrl),
      builder: (context, snap) {
        if (snap.hasError) {
          return imageFallback();
        }
        final resolvedUrl = (snap.data ?? '').trim();

        if (snap.connectionState != ConnectionState.done) {
          return imageFallback('Загрузка фото...');
        }

        if (resolvedUrl.isEmpty) {
          return imageFallback();
        }

        return GestureDetector(
          onTap: () => _openImageFullScreen(resolvedUrl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: AspectRatio(
              aspectRatio: 1,
              child: CachedNetworkImage(
                imageUrl: resolvedUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => imageFallback('Загрузка фото...'),
                errorWidget: (_, __, ___) => imageFallback(),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteMessage(ChatMessage m) async {
    final uid = _uid(context);
    if (uid.isEmpty) return;
    if (!ApiConfig.useTimewebBackend && m.senderId != uid) return;

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

    final isRead = message.status == 'read' || message.readAt != null;
    final isDelivered =
        message.status == 'delivered' || message.deliveredAt != null;
    final isSending =
        message.status == 'pending' || message.status == 'sending';
    final isFailed = message.status == 'failed';
    final iconColor =
        isRead ? Colors.blue : Theme.of(context).colorScheme.onSurfaceVariant;

    final statusIcon = isFailed
        ? const Icon(Icons.error_outline_rounded, size: 15, color: Colors.red)
        : isSending
            ? Icon(Icons.schedule_rounded, size: 14, color: iconColor)
            : isRead
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

  Widget _buildMessageBubble(
    BuildContext context,
    ChatService chatSvc,
    ChatMessage message,
    bool mine,
    String text,
  ) {
    final hasImg = message.hasImage;
    final bubbleColor = mine
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    if (hasImg && text.isEmpty) {
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: _messageImage(chatSvc, message.imageUrl!),
          ),
          const SizedBox(height: 2),
          _messageMeta(message, mine),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(
        maxWidth: 300,
      ),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasImg)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _messageImage(chatSvc, message.imageUrl!),
            ),
          if (text.isNotEmpty) ...[
            if (hasImg) const SizedBox(height: 8),
            Text(
              text,
              style: message.hasVisibleContent
                  ? null
                  : TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
            ),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: _messageMeta(message, mine),
          ),
        ],
      ),
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
                  : MediaPreviewBox(
                      imageUrl: thumbUrl,
                      categoryHint: 'listings',
                      width: 44,
                      height: 44,
                      borderRadius: 0,
                      emptyLabel: 'Нет фото',
                      errorLabel: 'Фото недоступно',
                      placeholderLabel: 'Загрузка фото...',
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

    return StreamBuilder<Chat?>(
      stream: chatSvc.streamChat(widget.chatId),
      builder: (context, chatSnap) {
        final chatRow = chatSnap.data;
        if (chatRow == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                widget.initialOtherUserName.trim().isEmpty
                    ? 'Чат'
                    : widget.initialOtherUserName.trim(),
              ),
            ),
            body: FutureBuilder<void>(
              future: _chatLoadFuture,
              builder: (context, loadSnap) {
                if (loadSnap.hasError) {
                  final message = shouldShowNetworkVpnHint(loadSnap.error!)
                      ? kNetworkVpnHintMessage
                      : 'Не удалось открыть чат. Попробуйте снова.';
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(message, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _retryChatLoad,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          );
        }
        final listingTitle = chatRow.listingTitle;

        final buyerId = chatRow.buyerId;
        final sellerId = chatRow.sellerId;
        final otherId = (uid == buyerId) ? sellerId : buyerId;
        final profileSeed = <String, dynamic>{
          'display_name': chatRow.otherUserName(uid),
          'avatar_url': chatRow.otherUserAvatar(uid),
          if (widget.initialOtherUserName.trim().isNotEmpty &&
              chatRow.otherUserName(uid).isEmpty)
            'display_name': widget.initialOtherUserName.trim(),
          if (widget.initialOtherUserAvatar.trim().isNotEmpty &&
              chatRow.otherUserAvatar(uid).isEmpty)
            'avatar_url': widget.initialOtherUserAvatar.trim(),
        };

        return StreamBuilder<Map<String, dynamic>>(
          stream: profiles.streamProfile(otherId, seed: profileSeed),
          builder: (context, profileSnap) {
            final otherRow = profileSnap.data ?? const <String, dynamic>{};
            final otherName =
                profiles.pickNameFromRow(otherRow, fallback: '').trim();
            final otherAvatar = profiles.pickAvatarFromRow(otherRow);
            final currentUser = context.read<AuthService>().currentUser;
            final myName = currentUser?.displayName?.trim() ?? '';
            final myAvatar = currentUser?.photoUrl?.trim() ?? '';

            return Scaffold(
              appBar: AppBar(
                title: StreamBuilder<bool>(
                  stream: presence.streamIsOnline(otherId),
                  initialData: presence.peekIsOnline(otherId) ?? false,
                  builder: (context, onlineSnap) {
                    final isOnline = onlineSnap.data == true;
                    return Row(
                      children: [
                        PresenceBadge(
                          isOnline: isOnline,
                          dotSize: 9,
                          borderWidth: 1.4,
                          child: RemoteAvatar(
                            imageUrl: otherAvatar,
                            fallbackText: otherName.isEmpty ? 'U' : otherName,
                            radius: 16,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
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
                    thumbUrl: chatRow.listingPhotoUrl,
                    onTap: () => _openUserProfile(
                      otherId,
                      initialName: otherName,
                      initialAvatar: otherAvatar,
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<List<ChatMessage>>(
                      stream: _messagesStream,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Center(
                            child: Text(
                              shouldShowNetworkVpnHint(snap.error!)
                                  ? kNetworkVpnHintMessage
                                  : 'Не удалось загрузить сообщения. Попробуйте снова.',
                              textAlign: TextAlign.center,
                            ),
                          );
                        }
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
                            final showDayDivider = i == items.length - 1 ||
                                !_isSameDay(
                                  m.createdAt,
                                  items[i + 1].createdAt,
                                );

                            return _ChatMessageListItem(
                              key: ValueKey<String>(m.stableKey),
                              message: m,
                              mine: mine,
                              myAvatarUrl: myAvatar,
                              myFallbackText: myName,
                              otherAvatarUrl: otherAvatar,
                              otherFallbackText: otherName,
                              showDayDivider: showDayDivider,
                              dayDivider: showDayDivider
                                  ? _dayDivider(m.createdAt)
                                  : null,
                              chatSvc: chatSvc,
                              onDeleteMessage: () => _confirmDeleteMessage(m),
                              onOpenImage: _openImageFullScreen,
                              formatMessageTime: _formatMessageTime,
                              onRetryImage: () async {
                                final imageUrl = (m.imageUrl ?? '').trim();
                                if (!imageUrl.startsWith('file://')) {
                                  return;
                                }
                                final localPath =
                                    imageUrl.replaceFirst('file://', '');
                                context.read<ChatService>().removeLocalMessage(
                                      chatId: widget.chatId,
                                      messageId: m.id,
                                    );
                                await context.read<ChatService>().sendImage(
                                      chatId: widget.chatId,
                                      senderId: uid,
                                      file: File(localPath),
                                    );
                              },
                              onRemoveFailedImage: () {
                                context.read<ChatService>().removeLocalMessage(
                                      chatId: widget.chatId,
                                      messageId: m.id,
                                    );
                              },
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_selectedImages.isNotEmpty) ...[
                            SizedBox(
                              height: 72,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _selectedImages.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final image = _selectedImages[index];
                                  return Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.file(
                                          File(image.path),
                                          width: 72,
                                          height: 72,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        right: 4,
                                        top: 4,
                                        child: InkWell(
                                          onTap: _sending
                                              ? null
                                              : () {
                                                  setState(() {
                                                    _selectedImages
                                                        .removeAt(index);
                                                  });
                                                },
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            padding: const EdgeInsets.all(2),
                                            child: const Icon(
                                              Icons.close,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: _sending ? null : _openAttachMenu,
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _text,
                                  decoration: InputDecoration(
                                    hintText: _selectedImages.isEmpty
                                        ? 'Сообщение...'
                                        : 'Сообщение или подпись...',
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
                                  onSubmitted: (_) {
                                    if (_sending) return;
                                    _sendText();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: _sending ? null : _sendText,
                                icon: _sending
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.send),
                              ),
                            ],
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
  }
}

class _ChatMessageListItem extends StatelessWidget {
  const _ChatMessageListItem({
    super.key,
    required this.message,
    required this.mine,
    required this.myAvatarUrl,
    required this.myFallbackText,
    required this.otherAvatarUrl,
    required this.otherFallbackText,
    required this.showDayDivider,
    required this.dayDivider,
    required this.chatSvc,
    required this.onDeleteMessage,
    required this.onOpenImage,
    required this.formatMessageTime,
    required this.onRetryImage,
    required this.onRemoveFailedImage,
  });

  final ChatMessage message;
  final bool mine;
  final String myAvatarUrl;
  final String myFallbackText;
  final String otherAvatarUrl;
  final String otherFallbackText;
  final bool showDayDivider;
  final Widget? dayDivider;
  final ChatService chatSvc;
  final VoidCallback onDeleteMessage;
  final ValueChanged<String> onOpenImage;
  final String Function(DateTime value) formatMessageTime;
  final Future<void> Function() onRetryImage;
  final VoidCallback onRemoveFailedImage;

  @override
  Widget build(BuildContext context) {
    final avatar = RemoteAvatar(
      key: ValueKey<String>(
        'avatar-${mine ? 'mine' : 'other'}-${message.stableKey}',
      ),
      imageUrl: mine ? myAvatarUrl : otherAvatarUrl,
      fallbackText: mine ? myFallbackText : otherFallbackText,
      radius: 12,
      textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
    );

    return Column(
      children: [
        if (showDayDivider && dayDivider != null) dayDivider!,
        Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onLongPress: onDeleteMessage,
            child: Row(
              key: ValueKey<String>('row-${message.stableKey}'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!mine) ...[
                  avatar,
                  const SizedBox(width: 6),
                ],
                Column(
                  crossAxisAlignment:
                      mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    _ChatMessageBubble(
                      key: ValueKey<String>('bubble-${message.stableKey}'),
                      message: message,
                      mine: mine,
                      chatSvc: chatSvc,
                      onOpenImage: onOpenImage,
                      formatMessageTime: formatMessageTime,
                    ),
                    if (mine &&
                        message.type == 'image' &&
                        message.status == 'failed')
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: onRetryImage,
                            child: const Text('Повторить'),
                          ),
                          TextButton(
                            onPressed: onRemoveFailedImage,
                            child: const Text('Удалить'),
                          ),
                        ],
                      ),
                  ],
                ),
                if (mine) ...[
                  const SizedBox(width: 6),
                  avatar,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatMessageBubble extends StatelessWidget {
  const _ChatMessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.chatSvc,
    required this.onOpenImage,
    required this.formatMessageTime,
  });

  final ChatMessage message;
  final bool mine;
  final ChatService chatSvc;
  final ValueChanged<String> onOpenImage;
  final String Function(DateTime value) formatMessageTime;

  @override
  Widget build(BuildContext context) {
    final hasImg = message.hasImage;
    final text = message.hasText
        ? message.text
        : hasImg
            ? ''
            : 'Сообщение недоступно';
    final bubbleColor = mine
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    if (hasImg && text.isEmpty) {
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: _ResolvedMessageImage(
              key: ValueKey<String>('image-${message.stableKey}'),
              chatSvc: chatSvc,
              rawImageUrl: message.imageUrl!,
              onOpenImage: onOpenImage,
            ),
          ),
          const SizedBox(height: 2),
          _MessageMeta(
            key: ValueKey<String>('meta-${message.stableKey}'),
            message: message,
            mine: mine,
            formatMessageTime: formatMessageTime,
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasImg)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _ResolvedMessageImage(
                key: ValueKey<String>('image-${message.stableKey}'),
                chatSvc: chatSvc,
                rawImageUrl: message.imageUrl!,
                onOpenImage: onOpenImage,
              ),
            ),
          if (text.isNotEmpty) ...[
            if (hasImg) const SizedBox(height: 8),
            Text(
              text,
              style: message.hasVisibleContent
                  ? null
                  : TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
            ),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: _MessageMeta(
              key: ValueKey<String>('meta-${message.stableKey}'),
              message: message,
              mine: mine,
              formatMessageTime: formatMessageTime,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageMeta extends StatelessWidget {
  const _MessageMeta({
    super.key,
    required this.message,
    required this.mine,
    required this.formatMessageTime,
  });

  final ChatMessage message;
  final bool mine;
  final String Function(DateTime value) formatMessageTime;

  @override
  Widget build(BuildContext context) {
    final timeStyle = TextStyle(
      fontSize: 11,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    final time = Text(formatMessageTime(message.createdAt), style: timeStyle);
    if (!mine) return time;

    final isRead = message.status == 'read' || message.readAt != null;
    final isDelivered =
        message.status == 'delivered' || message.deliveredAt != null;
    final isSending =
        message.status == 'pending' || message.status == 'sending';
    final isFailed = message.status == 'failed';
    final iconColor =
        isRead ? Colors.blue : Theme.of(context).colorScheme.onSurfaceVariant;

    final statusIcon = isFailed
        ? const Icon(Icons.error_outline_rounded, size: 15, color: Colors.red)
        : isSending
            ? Icon(Icons.schedule_rounded, size: 14, color: iconColor)
            : isRead
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
}

class _ResolvedMessageImage extends StatefulWidget {
  const _ResolvedMessageImage({
    super.key,
    required this.chatSvc,
    required this.rawImageUrl,
    required this.onOpenImage,
  });

  final ChatService chatSvc;
  final String rawImageUrl;
  final ValueChanged<String> onOpenImage;

  @override
  State<_ResolvedMessageImage> createState() => _ResolvedMessageImageState();
}

class _ResolvedMessageImageState extends State<_ResolvedMessageImage> {
  Future<String>? _resolvedUrlFuture;

  @override
  void initState() {
    super.initState();
    _resolvedUrlFuture = _buildFuture(widget.rawImageUrl);
  }

  @override
  void didUpdateWidget(covariant _ResolvedMessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawImageUrl != widget.rawImageUrl) {
      _resolvedUrlFuture = _buildFuture(widget.rawImageUrl);
    }
  }

  Future<String>? _buildFuture(String rawImageUrl) {
    final value = rawImageUrl.trim();
    if (value.isEmpty || value.startsWith('file://')) {
      return null;
    }
    return widget.chatSvc.resolveMessageImageUrl(value);
  }

  Widget _imageFallback([String message = 'Фото недоступно']) {
    return Container(
      width: 248,
      height: 180,
      color: Colors.black12,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        message,
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const maxWidth = 248.0;
    const maxHeight = 300.0;
    final rawImageUrl = widget.rawImageUrl.trim();
    final localPath = rawImageUrl.startsWith('file://')
        ? rawImageUrl.replaceFirst('file://', '')
        : null;
    if (localPath != null && localPath.isNotEmpty) {
      return GestureDetector(
        onTap: () => widget.onOpenImage(localPath),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: AspectRatio(
            aspectRatio: 1,
            child: Image.file(
              File(localPath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _imageFallback(),
            ),
          ),
        ),
      );
    }

    return FutureBuilder<String>(
      future: _resolvedUrlFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return _imageFallback();
        }
        final resolvedUrl = (snap.data ?? rawImageUrl).trim();
        if (_resolvedUrlFuture != null &&
            snap.connectionState != ConnectionState.done) {
          return _imageFallback('Загрузка фото...');
        }
        if (resolvedUrl.isEmpty) {
          return _imageFallback();
        }
        return GestureDetector(
          onTap: () => widget.onOpenImage(resolvedUrl),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
            child: AspectRatio(
              aspectRatio: 1,
              child: CachedNetworkImage(
                imageUrl: resolvedUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => _imageFallback('Загрузка фото...'),
                errorWidget: (_, __, ___) => _imageFallback(),
              ),
            ),
          ),
        );
      },
    );
  }
}
