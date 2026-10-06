import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/features/listings/photo_viewer_screen.dart';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/features/support/support_screen.dart';
import 'package:atta/src/models/chat.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/models/message.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/network_resilience.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/utils/last_seen_formatter.dart';
import 'package:atta/src/utils/listing_link_parser.dart';
import 'package:atta/src/utils/price_formatter.dart';
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
  final ScrollController _messagesScrollController = ScrollController();
  final List<XFile> _selectedImages = <XFile>[];
  bool _sending = false;
  bool _loadingOlder = false;
  int _lastSeenMessageCount = 0;
  Timer? _markReadDebounce;
  Timer? _typingTimer;
  bool _typingSent = false;
  ChatMessage? _replyingTo;
  ChatMessage? _editingMessage;
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
    _messagesScrollController.addListener(_handleMessagesScroll);
    _text.addListener(_handleTypingChanged);
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
    _messagesScrollController.removeListener(_handleMessagesScroll);
    _messagesScrollController.dispose();
    _markReadDebounce?.cancel();
    _typingTimer?.cancel();
    if (_typingSent) _chatService.setTyping(widget.chatId, false);
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

  void _handleMessagesScroll() {
    if (_loadingOlder || !_messagesScrollController.hasClients) return;
    final position = _messagesScrollController.position;
    if (position.maxScrollExtent - position.pixels > 260) return;
    if (!context.read<ChatService>().hasMoreMessages(widget.chatId)) return;
    unawaited(_loadOlderMessages());
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || !_messagesScrollController.hasClients) return;
    final beforeMax = _messagesScrollController.position.maxScrollExtent;
    final beforePixels = _messagesScrollController.position.pixels;
    setState(() => _loadingOlder = true);
    try {
      await context.read<ChatService>().loadOlderMessages(widget.chatId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_messagesScrollController.hasClients) return;
        final afterMax = _messagesScrollController.position.maxScrollExtent;
        final target = beforePixels + (afterMax - beforeMax);
        _messagesScrollController.jumpTo(
          target
              .clamp(
                _messagesScrollController.position.minScrollExtent,
                _messagesScrollController.position.maxScrollExtent,
              )
              .toDouble(),
        );
      });
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

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
        if (_editingMessage != null) {
          await chat.editMessage(messageId: _editingMessage!.id, text: t);
        } else {
          await chat.sendMessage(
            chatId: widget.chatId,
            senderId: uid,
            text: t,
            replyToMessageId: _replyingTo?.id,
          );
        }
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
      _replyingTo = null;
      _editingMessage = null;
    } catch (e) {
      if (!mounted) return;
      final message = _friendlyChatError(e);
      showAppSnack(context, message, isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _handleTypingChanged() {
    if (_editingMessage != null) return;
    final typing = _text.text.trim().isNotEmpty;
    _typingTimer?.cancel();
    if (typing && !_typingSent) {
      _typingSent = true;
      _chatService.setTyping(widget.chatId, true);
    }
    if (!typing && _typingSent) {
      _typingSent = false;
      _chatService.setTyping(widget.chatId, false);
      return;
    }
    if (typing) {
      _typingTimer = Timer(const Duration(milliseconds: 1400), () {
        if (!_typingSent) return;
        _typingSent = false;
        _chatService.setTyping(widget.chatId, false);
      });
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

  Future<void> _openChatActions({
    required Chat chat,
    required String otherUserId,
    required String otherUserName,
  }) async {
    var blockedByMe = chat.blockedByMe;
    try {
      blockedByMe = await context.read<ChatService>().peerBlockStatus(
            widget.chatId,
          );
    } catch (_) {
      blockedByMe = chat.blockedByMe;
    }
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.report_outlined),
              title: const Text('Пожаловаться'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openSupportReport(
                  otherUserId: otherUserId,
                  otherUserName: otherUserName,
                );
              },
            ),
            ListTile(
              leading: Icon(
                blockedByMe ? Icons.lock_open_outlined : Icons.block_outlined,
              ),
              title: Text(blockedByMe ? 'Разблокировать' : 'Блокировать'),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (blockedByMe) {
                  await _unblockPeer();
                } else {
                  await _confirmBlockPeer();
                }
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Удалить диалог',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmHideChatForMe();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openSupportReport({
    required String otherUserId,
    required String otherUserName,
  }) {
    final name =
        otherUserName.trim().isEmpty ? 'Пользователь' : otherUserName.trim();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupportScreen(
          initialDraftText: 'Жалоба на пользователя\n'
              'Имя: $name\n'
              'chatId: ${widget.chatId}\n'
              'reportedUserId: $otherUserId\n\n'
              'Опишите, что произошло:',
        ),
      ),
    );
  }

  Future<void> _confirmBlockPeer() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Заблокировать пользователя?'),
            content: const Text('Он больше не сможет писать вам.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Заблокировать'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    try {
      await context.read<ChatService>().blockPeer(widget.chatId);
      if (!mounted) return;
      showAppSnack(context, 'Пользователь заблокирован.');
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, _friendlyChatError(error), isError: true);
    }
  }

  Future<void> _unblockPeer() async {
    try {
      await context.read<ChatService>().unblockPeer(widget.chatId);
      if (!mounted) return;
      showAppSnack(context, 'Пользователь разблокирован.');
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, _friendlyChatError(error), isError: true);
    }
  }

  Future<void> _confirmHideChatForMe() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Удалить диалог?'),
            content: const Text('Он исчезнет только у вас.'),
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
    if (!ok || !mounted) return;
    final uid = _uid(context);
    if (uid.isEmpty) return;
    try {
      await context.read<ChatService>().hideChatForMe(
            chatId: widget.chatId,
            uid: uid,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, _friendlyChatError(error), isError: true);
    }
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

  Future<void> _openMessageActions(ChatMessage m) async {
    final uid = _uid(context);
    if (uid.isEmpty) return;
    final mine = m.senderId == uid;
    final withinWindow = DateTime.now().difference(m.createdAt).inMinutes < 15;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!m.deletedForEveryone)
            ListTile(
                dense: true,
                leading: const Icon(Icons.reply, size: 21),
                title: const Text('Ответить'),
                onTap: () => Navigator.pop(ctx, 'reply')),
          if (mine && withinWindow && m.type == 'text' && !m.deletedForEveryone)
            ListTile(
                dense: true,
                leading: const Icon(Icons.edit_outlined, size: 21),
                title: const Text('Редактировать'),
                onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(
              dense: true,
              leading: const Icon(Icons.delete_outline, size: 21),
              title: const Text('Удалить у меня'),
              onTap: () => Navigator.pop(ctx, 'me')),
          if (mine && withinWindow && !m.deletedForEveryone)
            ListTile(
                dense: true,
                leading: const Icon(Icons.delete_forever_outlined,
                    size: 21, color: Colors.red),
                title: const Text('Удалить у всех',
                    style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(ctx, 'everyone')),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'reply') {
        setState(() {
          _replyingTo = m;
          _editingMessage = null;
        });
        return;
      }
      if (action == 'edit') {
        setState(() {
          _editingMessage = m;
          _replyingTo = null;
          _text.text = m.text;
          _text.selection = TextSelection.collapsed(offset: _text.text.length);
        });
        return;
      }
      if (action == 'everyone') {
        await context
            .read<ChatService>()
            .deleteMessageForEveryone(messageId: m.id);
      } else {
        await context.read<ChatService>().deleteMessage(
              chatId: widget.chatId,
              messageId: m.id,
              uid: uid,
            );
      }
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          _formatDayDivider(dt),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
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
                title: StreamBuilder<PresenceSnapshot>(
                  stream: presence.streamPresence(
                    otherId,
                    seed: PresenceSnapshot(
                      userId: otherId,
                      isOnline: chatRow.otherUserIsOnline(uid),
                      lastSeen: chatRow.otherUserLastSeenAt(uid),
                    ),
                  ),
                  initialData: presence.peekPresence(otherId) ??
                      PresenceSnapshot(
                        userId: otherId,
                        isOnline: chatRow.otherUserIsOnline(uid),
                        lastSeen: chatRow.otherUserLastSeenAt(uid),
                      ),
                  builder: (context, presenceSnap) {
                    final snapshot = presenceSnap.data;
                    final isOnline = snapshot?.isOnline == true;
                    final status = formatLastSeen(
                      snapshot?.lastSeen,
                      isOnline,
                    );
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  otherName.isEmpty ? '...' : otherName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                StreamBuilder<bool>(
                                  stream: chatSvc.streamTyping(widget.chatId),
                                  initialData: false,
                                  builder: (context, typingSnap) => Text(
                                    typingSnap.data == true
                                        ? 'печатает…'
                                        : (status.isEmpty ? ' ' : status),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w400,
                                      color: typingSnap.data == true || isOnline
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: IconButton(
                      tooltip: 'Действия',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        shape: const CircleBorder(),
                      ),
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _openChatActions(
                        chat: chatRow,
                        otherUserId: otherId,
                        otherUserName: otherName,
                      ),
                    ),
                  ),
                ],
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
                          controller: _messagesScrollController,
                          reverse: true,
                          padding: const EdgeInsets.all(12),
                          itemCount: items.length + (_loadingOlder ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (_loadingOlder && i == items.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }
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
                              onDeleteMessage: () => _openMessageActions(m),
                              onOpenImage: _openImageFullScreen,
                              formatMessageTime: _formatMessageTime,
                              onRetryMessage: () async {
                                try {
                                  await context
                                      .read<ChatService>()
                                      .retryMessage(
                                        chatId: widget.chatId,
                                        senderId: uid,
                                        message: m,
                                      );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  showAppSnack(
                                    context,
                                    _friendlyChatError(e),
                                    isError: true,
                                  );
                                }
                              },
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
                          if (_replyingTo != null ||
                              _editingMessage != null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(children: [
                                Icon(
                                    _editingMessage != null
                                        ? Icons.edit_outlined
                                        : Icons.reply,
                                    size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(
                                          _editingMessage != null
                                              ? 'Редактирование'
                                              : 'Ответ',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary)),
                                      Text(
                                          (_editingMessage ?? _replyingTo)!
                                              .text,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ])),
                                IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.close, size: 19),
                                    onPressed: () => setState(() {
                                          _replyingTo = null;
                                          _editingMessage = null;
                                          _text.clear();
                                        })),
                              ]),
                            ),
                            const SizedBox(height: 6),
                          ],
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
                                        ? (_editingMessage != null
                                            ? 'Изменить сообщение...'
                                            : 'Сообщение...')
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
    required this.onRetryMessage,
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
  final Future<void> Function() onRetryMessage;
  final Future<void> Function() onRetryImage;
  final VoidCallback onRemoveFailedImage;

  @override
  Widget build(BuildContext context) {
    const avatarSlotWidth = 30.0;
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
        LayoutBuilder(
          builder: (context, constraints) {
            final availableBubbleWidth = constraints.maxWidth - avatarSlotWidth;
            final preferredBubbleWidth = constraints.maxWidth * 0.76;
            final maxBubbleWidth = preferredBubbleWidth > availableBubbleWidth
                ? availableBubbleWidth
                : preferredBubbleWidth.clamp(180.0, 300.0);

            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: GestureDetector(
                onLongPress: onDeleteMessage,
                child: Row(
                  key: ValueKey<String>('row-${message.stableKey}'),
                  mainAxisAlignment:
                      mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!mine) ...[
                      avatar,
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Column(
                        crossAxisAlignment: mine
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          _ChatMessageBubble(
                            key: ValueKey<String>(
                              'bubble-${message.stableKey}',
                            ),
                            message: message,
                            mine: mine,
                            chatSvc: chatSvc,
                            maxWidth: maxBubbleWidth,
                            onOpenImage: onOpenImage,
                            formatMessageTime: formatMessageTime,
                            onRetryMessage: onRetryMessage,
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
                    ),
                    if (mine) ...[
                      const SizedBox(width: 6),
                      avatar,
                    ],
                  ],
                ),
              ),
            );
          },
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
    required this.maxWidth,
    required this.onOpenImage,
    required this.formatMessageTime,
    required this.onRetryMessage,
  });

  final ChatMessage message;
  final bool mine;
  final ChatService chatSvc;
  final double maxWidth;
  final ValueChanged<String> onOpenImage;
  final String Function(DateTime value) formatMessageTime;
  final Future<void> Function() onRetryMessage;

  @override
  Widget build(BuildContext context) {
    final hasImg = message.hasImage && !message.deletedForEveryone;
    final linkedListingId =
        hasImg ? null : extractListingIdFromMessage(message.text);
    final text = message.deletedForEveryone
        ? 'Сообщение удалено'
        : message.hasText
            ? message.text
            : hasImg
                ? ''
                : 'Сообщение недоступно';
    final bubbleColor = mine
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    if (linkedListingId != null) {
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          _ListingMessagePreview(
            key: ValueKey<String>('listing-preview-${message.stableKey}'),
            listingId: linkedListingId,
            backgroundColor: bubbleColor,
            maxWidth: maxWidth,
          ),
          const SizedBox(height: 2),
          _MessageMeta(
            key: ValueKey<String>('meta-${message.stableKey}'),
            message: message,
            mine: mine,
            formatMessageTime: formatMessageTime,
            onRetry: onRetryMessage,
          ),
        ],
      );
    }

    if (hasImg && text.isEmpty) {
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            constraints: BoxConstraints(maxWidth: maxWidth),
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
            onRetry: onRetryMessage,
          ),
        ],
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: IntrinsicWidth(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.replyTo != null && !message.deletedForEveryone) ...[
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.55),
                    border: Border(
                        left: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3)),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    ((message.replyTo!['text'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                        ? message.replyTo!['text'].toString()
                        : (message.replyTo!['type'] == 'image'
                            ? 'Фотография'
                            : 'Сообщение'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 6),
              ],
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
                  style: !message.deletedForEveryone
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
                  onRetry: onRetryMessage,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListingMessagePreview extends StatefulWidget {
  const _ListingMessagePreview({
    super.key,
    required this.listingId,
    required this.backgroundColor,
    required this.maxWidth,
  });

  final String listingId;
  final Color backgroundColor;
  final double maxWidth;

  @override
  State<_ListingMessagePreview> createState() => _ListingMessagePreviewState();
}

class _ListingMessagePreviewState extends State<_ListingMessagePreview> {
  Future<Listing?>? _listingFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listingFuture != null) return;
    final listings = Provider.of<ListingsService?>(context, listen: false);
    if (listings == null) return;
    final cached = listings.peekListingById(widget.listingId);
    _listingFuture = cached != null
        ? Future<Listing?>.value(cached)
        : listings.getListingById(widget.listingId);
  }

  void _openListing() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: 'chat-listing:${widget.listingId}',
        ),
        builder: (_) => ListingDetailScreen(listingId: widget.listingId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: Material(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openListing,
          child: FutureBuilder<Listing?>(
            future: _listingFuture,
            builder: (context, snapshot) {
              final listing = snapshot.data;
              if (listing == null) {
                return _buildUnavailableOrLoading(
                  context,
                  loading: snapshot.connectionState != ConnectionState.done,
                );
              }
              return _buildListing(context, listing);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildListing(BuildContext context, Listing listing) {
    final photoUrl = listing.firstPhotoUrl?.trim() ?? '';
    final city = listing.cityShort.trim();
    final price = formatPrice(listing.price)
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u202F', ' ');
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: SizedBox(
              width: 78,
              height: 78,
              child: photoUrl.isEmpty
                  ? _photoFallback(context)
                  : CachedNetworkImage(
                      imageUrl: photoUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _photoFallback(context),
                      errorWidget: (_, __, ___) => _photoFallback(context),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$price ₽',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  listing.title.trim().isEmpty
                      ? 'Объявление ATTA'
                      : listing.title.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.12,
                  ),
                ),
                if (city.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailableOrLoading(
    BuildContext context, {
    required bool loading,
  }) {
    return SizedBox(
      height: 94,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            SizedBox(
              width: 78,
              height: 78,
              child: _photoFallback(context, loading: loading),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                loading ? 'Загрузка объявления…' : 'Объявление недоступно',
                maxLines: 2,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoFallback(BuildContext context, {bool loading = false}) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Center(
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.image_not_supported_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
    required this.onRetry,
  });

  final ChatMessage message;
  final bool mine;
  final String Function(DateTime value) formatMessageTime;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final timeStyle = TextStyle(
      fontSize: 11,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    final time = Row(mainAxisSize: MainAxisSize.min, children: [
      if (message.editedAt != null) ...[
        Text('изменено', style: timeStyle),
        const SizedBox(width: 4),
      ],
      Text(formatMessageTime(message.createdAt), style: timeStyle),
    ]);
    if (!mine) return time;

    final isRead = message.status == 'read' || message.readAt != null;
    final isDelivered =
        message.status == 'delivered' || message.deliveredAt != null;
    final isSending =
        message.status == 'pending' || message.status == 'sending';
    final isFailed = message.status == 'failed';
    final iconColor =
        isRead ? Colors.blue : Theme.of(context).colorScheme.onSurfaceVariant;

    if (isFailed) {
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              time,
              const SizedBox(width: 4),
              const Icon(
                Icons.error_outline_rounded,
                size: 15,
                color: Colors.red,
              ),
              const SizedBox(width: 3),
              const Text(
                'Не отправлено',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final statusIcon = isSending
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
