import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atta/src/models/chat.dart';
import 'package:atta/src/models/message.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/api/chats_api.dart';
import 'package:atta/src/services/api/media_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:atta/src/services/image_preparation_service.dart';
import 'package:atta/src/utils/media_url.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ChatService {
  ChatService({
    ChatSocketService? socketService,
    ChatsApi? api,
    MediaApi? mediaApi,
    Duration socketReadyTimeout = const Duration(seconds: 8),
  })  : _socketService = socketService,
        _api = api ?? ChatsApi(ApiClient(tokenStorage: _tokenStorage)),
        _mediaApi =
            mediaApi ?? MediaApi(ApiClient(tokenStorage: _tokenStorage)),
        _imagePreparationService = ImagePreparationService(),
        _socketReadyTimeout = socketReadyTimeout {
    _socketSub = _socketService?.events.listen(_handleSocketEvent);
  }
  final _uuid = const Uuid();
  final ChatSocketService? _socketService;

  static final TokenStorage _tokenStorage = TokenStorage();
  final ChatsApi _api;
  final MediaApi _mediaApi;
  final ImagePreparationService _imagePreparationService;
  final Duration _socketReadyTimeout;

  StreamSubscription<ChatSocketEvent>? _socketSub;
  String? _activeUserId;
  bool _loadedChats = false;
  final Set<String> _loadedChatIds = <String>{};
  final Set<String> _loadedMessageChatIds = <String>{};
  final _chatsController = StreamController<List<Chat>>.broadcast();
  final _unreadController = StreamController<int>.broadcast();
  final Map<String, Chat> _chatsById = {};
  final Map<String, StreamController<Chat?>> _chatControllers = {};
  final Map<String, List<ChatMessage>> _messagesByChat = {};
  final Map<String, StreamController<List<ChatMessage>>> _messageControllers =
      {};
  final Map<String, int> _messageOrderByKey = {};
  final Map<String, Future<void>> _chatRefreshInFlight = {};
  final Map<String, Future<void>> _messagesRefreshInFlight = {};
  final Map<String, Future<void>> _markReadInFlight = {};
  final Map<String, Future<void>> _messageSendInFlight = {};
  final Map<String, Future<void>> _imageSendInFlight = {};
  final Set<String> _restoredCacheUserIds = <String>{};
  Future<void>? _refreshChatsInFlight;
  Object? _lastChatsLoadError;
  final Map<String, DateTime> _lastMarkReadAt = {};
  DateTime? _lastAppResumeRefreshAt;
  final Set<String> _activeChatIds = <String>{};
  String? _foregroundChatId;
  int _messageOrderSequence = 0;
  Future<void>? _ensureReadyInFlight;
  String? _ensureReadyUserId;

  static const Duration _markReadCooldown = Duration(seconds: 2);
  static const Duration _resumeRefreshCooldown = Duration(seconds: 5);

  Object? get lastChatsLoadError => _lastChatsLoadError;

  void _ensureSocketConnectedInBackground([String? uid]) {
    final normalizedUid = uid?.trim() ?? _activeUserId?.trim() ?? '';
    if (normalizedUid.isNotEmpty) {
      _activeUserId = normalizedUid;
    }
    final future = _socketService?.connect(reason: 'chat.backgroundReady');
    if (future != null) {
      unawaited(future.catchError((_) {}));
    }
  }

  void _ensureChatsRefreshStarted([String? uid]) {
    final normalizedUid = uid?.trim() ?? _activeUserId?.trim() ?? '';
    if (normalizedUid.isNotEmpty) {
      _activeUserId = normalizedUid;
    }
    if (_refreshChatsInFlight != null) {
      return;
    }
    if (_loadedChats && _chatsById.isNotEmpty) {
      return;
    }
    _loadedChats = true;
    unawaited(refreshChats());
  }

  Future<void> resetSession() async {
    _activeUserId = null;
    _loadedChats = false;
    _loadedChatIds.clear();
    _loadedMessageChatIds.clear();
    _chatRefreshInFlight.clear();
    _messagesRefreshInFlight.clear();
    _markReadInFlight.clear();
    _messageSendInFlight.clear();
    _imageSendInFlight.clear();
    _restoredCacheUserIds.clear();
    _refreshChatsInFlight = null;
    _lastChatsLoadError = null;
    _lastMarkReadAt.clear();
    _activeChatIds.clear();
    _foregroundChatId = null;
    _ensureReadyInFlight = null;
    _ensureReadyUserId = null;
    _chatsById.clear();
    _messagesByChat.clear();
    _messageOrderByKey.clear();
    _messageOrderSequence = 0;
    _chatsController.add(const <Chat>[]);
    _unreadController.add(0);
    for (final controller in _chatControllers.values) {
      controller.add(null);
    }
    for (final controller in _messageControllers.values) {
      controller.add(const <ChatMessage>[]);
    }
    await _socketService?.resetSession();
  }

  void _debugSource(String message) {
    if (!kDebugMode ||
        message == 'Chat source: Timeweb' ||
        message.startsWith('Socket event:')) {
      return;
    }
    debugPrint(message);
  }

  Future<void> _ensureTimewebReady([String? uid]) async {
    _debugSource('Chat source: Timeweb');
    final normalizedUid = uid?.trim() ?? '';
    if (normalizedUid.isNotEmpty) {
      _activeUserId = normalizedUid;
    }
    final effectiveUid = _activeUserId?.trim() ?? '';
    final existing = _ensureReadyInFlight;
    if (existing != null && _ensureReadyUserId == effectiveUid) {
      _debugSource('Chats load skipped reason=in_flight user=$effectiveUid');
      return existing;
    }
    if ((_socketService?.isConnected == true) &&
        _ensureReadyUserId == effectiveUid) {
      _debugSource('Chats load skipped reason=cache_only user=$effectiveUid');
      return;
    }
    final future = () async {
      _debugSource('auth ready user=$effectiveUid');
      try {
        await _socketService
            ?.connect(reason: 'chat.ensureReady')
            .timeout(_socketReadyTimeout);
        if (!_loadedChats) {
          _loadedChats = true;
          unawaited(refreshChats());
        }
      } catch (error) {
        _debugSource('Chats load error message=$error user=$effectiveUid');
      } finally {
        _debugSource('Chats load finally loading=false user=$effectiveUid');
      }
    }();
    _ensureReadyUserId = effectiveUid;
    _ensureReadyInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_ensureReadyInFlight, future)) {
        _ensureReadyInFlight = null;
        _debugSource('Chats inFlight cleared user=$effectiveUid');
      }
    }
  }

  Future<void> _ensureReadyAndJoinChat(String chatId) async {
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) return;
    await _ensureTimewebReady();
    await _socketService?.joinChat(
      normalizedChatId,
      reason: 'chat.joinAfterEnsureReady',
    );
  }

  StreamController<Chat?> _chatControllerFor(String chatId) {
    return _chatControllers.putIfAbsent(
      chatId,
      () => StreamController<Chat?>.broadcast(),
    );
  }

  StreamController<List<ChatMessage>> _messageControllerFor(String chatId) {
    return _messageControllers.putIfAbsent(
      chatId,
      () => StreamController<List<ChatMessage>>.broadcast(),
    );
  }

  void _emitChats() {
    final items = _sortedChats();
    _chatsController.add(items);
    final uid = _activeUserId ?? '';
    _unreadController.add(
      items.fold<int>(0, (sum, chat) => sum + chat.unreadFor(uid)),
    );
    for (final chat in items) {
      _chatControllers[chat.id]?.add(chat);
    }
  }

  String _cacheKey(String uid) => 'atta.chat.cache.v1.${uid.trim()}';

  Future<void> _restoreCachedState(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty || !_restoredCacheUserIds.add(normalizedUid)) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(normalizedUid));
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final chats = (decoded['chats'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Chat.fromMap(Map<String, dynamic>.from(item)))
          .where((chat) => chat.id.trim().isNotEmpty)
          .toList();
      for (final chat in chats) {
        _chatsById.putIfAbsent(chat.id, () => chat);
      }
      final messagesByChat = decoded['messagesByChat'];
      if (messagesByChat is Map) {
        for (final entry in messagesByChat.entries) {
          final chatId = entry.key.toString().trim();
          if (chatId.isEmpty || entry.value is! List) continue;
          final items = _messagesByChat.putIfAbsent(
            chatId,
            () => <ChatMessage>[],
          );
          for (final rawMessage in entry.value as List) {
            if (rawMessage is! Map) continue;
            final message = ChatMessage.fromMap(
              Map<String, dynamic>.from(rawMessage),
            );
            if (message.type != 'text' || message.hasImage) continue;
            _upsertMessageIntoList(items, message);
          }
          _loadedMessageChatIds.add(chatId);
        }
      }
      _emitChats();
      for (final chatId in _messagesByChat.keys.toList()) {
        _emitMessages(chatId);
      }
    } catch (error) {
      _debugSource('Chat cache restore skipped: $error');
    }
  }

  Future<void> _persistCachedState() async {
    final uid = _activeUserId?.trim() ?? '';
    if (uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'chats': _sortedChats().map(_chatToCacheMap).toList(),
        'messagesByChat': _messagesByChat.map(
          (chatId, messages) => MapEntry(
            chatId,
            messages
                .where((message) => message.type == 'text' && !message.hasImage)
                .map(_messageToCacheMap)
                .toList(),
          ),
        ),
      };
      await prefs.setString(_cacheKey(uid), jsonEncode(payload));
    } catch (error) {
      _debugSource('Chat cache persist skipped: $error');
    }
  }

  Map<String, dynamic> _chatToCacheMap(Chat chat) {
    return <String, dynamic>{
      'id': chat.id,
      'listingId': chat.listingId,
      'listingTitle': chat.listingTitle,
      'buyerId': chat.buyerId,
      'sellerId': chat.sellerId,
      'buyerPreview': <String, dynamic>{'displayName': chat.buyerName},
      'sellerPreview': <String, dynamic>{'displayName': chat.sellerName},
      'listingPreview': <String, dynamic>{
        'id': chat.listingId,
        'title': chat.listingTitle,
      },
      'lastMessage': chat.lastMessage,
      'lastMessageAt': chat.lastMessageAt?.toUtc().toIso8601String(),
      'createdAt': chat.createdAt.toUtc().toIso8601String(),
      'updatedAt': chat.updatedAt.toUtc().toIso8601String(),
      'unreadCount': chat.unreadCount,
      'unread_for_buyer': chat.unreadForBuyer,
      'unread_for_seller': chat.unreadForSeller,
    };
  }

  Map<String, dynamic> _messageToCacheMap(ChatMessage message) {
    return <String, dynamic>{
      'id': message.id,
      'chatId': message.chatId,
      'senderId': message.senderId,
      'text': message.text,
      'type': 'text',
      'status': message.status,
      'createdAt': message.createdAt.toUtc().toIso8601String(),
      'updatedAt': message.updatedAt?.toUtc().toIso8601String(),
      'deliveredAt': message.deliveredAt?.toUtc().toIso8601String(),
      'readAt': message.readAt?.toUtc().toIso8601String(),
      'clientMessageId': message.clientMessageId,
    };
  }

  List<Chat> _sortedChats() {
    final items = _chatsById.values.toList()..sort(_compareChatsForList);
    return items;
  }

  int _compareChatsForList(Chat a, Chat b) {
    final aHasMessages = a.lastMessageAt != null;
    final bHasMessages = b.lastMessageAt != null;
    if (aHasMessages != bHasMessages) {
      return aHasMessages ? -1 : 1;
    }

    if (a.lastMessageAt != null && b.lastMessageAt != null) {
      final byLastMessage = b.lastMessageAt!.compareTo(a.lastMessageAt!);
      if (byLastMessage != 0) return byLastMessage;
    }

    final byCreatedAt = b.createdAt.compareTo(a.createdAt);
    if (byCreatedAt != 0) return byCreatedAt;
    return b.updatedAt.compareTo(a.updatedAt);
  }

  void _emitMessages(String chatId) {
    final items = List<ChatMessage>.from(_messagesByChat[chatId] ?? const [])
      ..sort(_compareMessagesNewestFirst);
    _messagesByChat[chatId] = items;
    _messageControllers[chatId]?.add(items);
  }

  void _upsertChat(Chat chat) {
    _chatsById[chat.id] = chat;
    _emitChats();
    unawaited(_persistCachedState());
  }

  void setForegroundChat(String? chatId) {
    final normalized = chatId?.trim();
    if (normalized == null || normalized.isEmpty) {
      _foregroundChatId = null;
      return;
    }
    _foregroundChatId = normalized;
  }

  void _upsertMessage(ChatMessage message) {
    final items =
        _messagesByChat.putIfAbsent(message.chatId, () => <ChatMessage>[]);
    _upsertMessageIntoList(items, message);
    _emitMessages(message.chatId);
    unawaited(_persistCachedState());
  }

  void _removeMessage(String chatId, String messageId) {
    final items = _messagesByChat[chatId];
    if (items == null) return;
    items.removeWhere((entry) => entry.id == messageId);
    _messageOrderByKey.remove(messageId);
    _emitMessages(chatId);
    unawaited(_persistCachedState());
  }

  void _replaceLocalMessage(String chatId, ChatMessage message) {
    final items = _messagesByChat.putIfAbsent(chatId, () => <ChatMessage>[]);
    final index = items.indexWhere((entry) => entry.id == message.id);
    if (index == -1) {
      items.add(_normalizeMessage(message));
    } else {
      items[index] = _mergeMessages(items[index], message);
    }
    _emitMessages(chatId);
    unawaited(_persistCachedState());
  }

  ChatMessage _normalizeMessage(ChatMessage message) {
    final normalizedType = message.type.trim().toLowerCase();
    final type = normalizedType == 'image' || normalizedType == 'system'
        ? normalizedType
        : message.hasImage
            ? 'image'
            : 'text';
    return message.copyWith(
      type: type,
      status: _normalizeStatus(message.status),
      text: message.text.trim(),
      imageUrl: (message.imageUrl ?? '').trim().isEmpty
          ? null
          : message.imageUrl!.trim(),
    );
  }

  ChatMessage _mergeMessages(ChatMessage previous, ChatMessage incoming) {
    final normalizedIncoming = _normalizeMessage(incoming);
    final resolvedId = () {
      final incomingId = normalizedIncoming.id.trim();
      final previousId = previous.id.trim();
      if (incomingId.isEmpty) return previous.id;
      if (previousId.startsWith('temp-') && incomingId.isNotEmpty) {
        return normalizedIncoming.id;
      }
      return incomingId.isNotEmpty ? normalizedIncoming.id : previous.id;
    }();
    final resolvedChatId = normalizedIncoming.chatId.trim().isNotEmpty
        ? normalizedIncoming.chatId
        : previous.chatId;
    final resolvedSenderId = normalizedIncoming.senderId.trim().isNotEmpty
        ? normalizedIncoming.senderId
        : previous.senderId;
    final resolvedText = normalizedIncoming.text.trim().isNotEmpty
        ? normalizedIncoming.text.trim()
        : previous.text;
    final resolvedImage = (normalizedIncoming.imageUrl ?? '').trim().isNotEmpty
        ? normalizedIncoming.imageUrl!.trim()
        : previous.imageUrl;
    final merged = normalizedIncoming.copyWith(
      id: resolvedId,
      chatId: resolvedChatId,
      senderId: resolvedSenderId,
      text: resolvedText,
      imageUrl: resolvedImage,
      type: normalizedIncoming.type == 'text' &&
              resolvedText.trim().isEmpty &&
              previous.type.isNotEmpty
          ? previous.type
          : normalizedIncoming.type == 'text' &&
                  (resolvedImage ?? '').isNotEmpty &&
                  resolvedText.trim().isEmpty
              ? 'image'
              : normalizedIncoming.type,
      status: _mergeStatus(previous.status, normalizedIncoming.status),
      createdAt: previous.createdAt.isBefore(normalizedIncoming.createdAt)
          ? previous.createdAt
          : normalizedIncoming.createdAt,
      updatedAt: normalizedIncoming.updatedAt ?? previous.updatedAt,
      deliveredAt: normalizedIncoming.deliveredAt ?? previous.deliveredAt,
      readAt: normalizedIncoming.readAt ?? previous.readAt,
      clientMessageId:
          normalizedIncoming.clientMessageId ?? previous.clientMessageId,
    );
    if (!merged.hasVisibleContent && merged.status != 'pending') {
      _debugSource(
        'Chat warning: message ${merged.id} has no text or image after merge',
      );
    }
    return merged;
  }

  String _normalizeStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'sending':
        return 'pending';
      case 'pending':
      case 'sent':
      case 'delivered':
      case 'read':
      case 'failed':
        return status.trim().toLowerCase();
      default:
        return 'sent';
    }
  }

  String _mergeStatus(String previous, String incoming) {
    final previousStatus = _normalizeStatus(previous);
    final incomingStatus = _normalizeStatus(incoming);
    if (incomingStatus == 'failed' && previousStatus == 'pending') {
      return 'failed';
    }
    if (incomingStatus == 'failed' && previousStatus != 'pending') {
      return previousStatus;
    }
    const rank = <String, int>{
      'failed': 0,
      'pending': 1,
      'sent': 2,
      'delivered': 3,
      'read': 4,
    };
    return (rank[incomingStatus] ?? 0) >= (rank[previousStatus] ?? 0)
        ? incomingStatus
        : previousStatus;
  }

  void _handleSocketEvent(ChatSocketEvent event) {
    final payload = event.payload;
    final chatMap = payload['chat'] is Map
        ? Map<String, dynamic>.from(payload['chat'] as Map)
        : null;
    final messageMap = payload['message'] is Map
        ? Map<String, dynamic>.from(payload['message'] as Map)
        : null;

    switch (event.name) {
      case 'chat.updated':
        if (chatMap != null) _upsertChat(Chat.fromMap(chatMap));
        break;
      case 'message.new':
      case 'message.sent':
        _debugSource('Socket event: ${event.name}');
        if (chatMap != null) _upsertChat(Chat.fromMap(chatMap));
        if (messageMap != null) {
          final message = ChatMessage.fromMap(messageMap);
          _upsertMessage(message);
          if (message.senderId != (_activeUserId ?? '')) {
            _socketService?.sendDelivered(message.id);
          }
        }
        break;
      case 'message.delivered':
      case 'message.read':
        _debugSource('Socket event: ${event.name}');
        if (messageMap != null) {
          _upsertMessage(ChatMessage.fromMap(messageMap));
        }
        break;
      case 'message.deleted':
        _debugSource('Socket event: message.deleted');
        final deletedMessageId = (payload['messageId'] ?? '').toString();
        final deletedChatId = (payload['chatId'] ?? '').toString();
        if (deletedChatId.isNotEmpty && deletedMessageId.isNotEmpty) {
          _removeMessage(deletedChatId, deletedMessageId);
          unawaited(_refreshChat(deletedChatId));
        }
        break;
      case 'chat.deleted':
        _debugSource('Socket event: chat.deleted');
        final deletedChatId = (payload['chatId'] ?? '').toString();
        if (deletedChatId.isNotEmpty) {
          _chatsById.remove(deletedChatId);
          _messagesByChat.remove(deletedChatId);
          _messageControllers[deletedChatId]?.add(const <ChatMessage>[]);
          _chatControllers[deletedChatId]?.add(null);
          _emitChats();
        }
        break;
      case 'unread.changed':
        _debugSource('Socket event: unread.changed');
        final chatId = (payload['chatId'] ?? '').toString();
        final unread = (payload['unreadCount'] as num?)?.toInt() ?? 0;
        final current = _chatsById[chatId];
        if (current != null) {
          final isBuyer = (_activeUserId ?? '') == current.buyerId;
          final isSeller = (_activeUserId ?? '') == current.sellerId;
          _upsertChat(
            Chat(
              id: current.id,
              listingId: current.listingId,
              listingTitle: current.listingTitle,
              listingPhotoUrl: current.listingPhotoUrl,
              buyerId: current.buyerId,
              sellerId: current.sellerId,
              buyerName: current.buyerName,
              sellerName: current.sellerName,
              buyerAvatar: current.buyerAvatar,
              sellerAvatar: current.sellerAvatar,
              lastMessage: current.lastMessage,
              lastMessageAt: current.lastMessageAt,
              createdAt: current.createdAt,
              updatedAt: current.updatedAt,
              unreadCount: unread,
              unreadForBuyer: isBuyer ? unread : current.unreadForBuyer,
              unreadForSeller: isSeller ? unread : current.unreadForSeller,
            ),
          );
        }
        break;
    }
  }

  Future<void> refreshChats() async {
    final existing = _refreshChatsInFlight;
    if (existing != null) {
      _debugSource('Chats load skipped reason=in_flight');
      return existing;
    }
    final future = _refreshChatsInternal();
    _refreshChatsInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_refreshChatsInFlight, future)) {
        _refreshChatsInFlight = null;
        _debugSource('Chats list inFlight cleared');
      }
    }
  }

  Future<void> _refreshChatsInternal() async {
    final uid = _activeUserId?.trim() ?? '';
    _debugSource('Chats list load start user=$uid');
    try {
      await _restoreCachedState(uid);
      // REST inbox loading must not inherit a pre-send auth/socket timeout.
      final response = await _api.listChats();
      final items = (response['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Chat.fromMap(Map<String, dynamic>.from(item)))
          .toList();
      _chatsById
        ..clear()
        ..addEntries(items.map((item) => MapEntry(item.id, item)));
      _lastChatsLoadError = null;
      _emitChats();
      unawaited(_persistCachedState());
      _debugSource(
        items.isEmpty
            ? 'Chats load empty'
            : 'Chats load success count=${items.length}',
      );
    } catch (error) {
      _lastChatsLoadError = error;
      _debugSource('Chats load error message=$error user=$uid');
    } finally {
      _debugSource('Chats load finally loading=false user=$uid');
    }
  }

  Future<void> _refreshChat(String chatId) async {
    final id = chatId.trim();
    if (id.isEmpty) return;
    final existing = _chatRefreshInFlight[id];
    if (existing != null) return existing;
    final future = _refreshChatInternal(id);
    _chatRefreshInFlight[id] = future;
    try {
      await future;
    } finally {
      if (identical(_chatRefreshInFlight[id], future)) {
        _chatRefreshInFlight.remove(id);
      }
    }
  }

  Future<void> _refreshChatInternal(String chatId) async {
    final response = await _api.getChat(chatId);
    final rawChat = response['chat'];
    if (rawChat is Map) {
      _upsertChat(Chat.fromMap(Map<String, dynamic>.from(rawChat)));
    }
    _loadedChatIds.add(chatId);
  }

  Future<void> _refreshMessages(String chatId) async {
    final id = chatId.trim();
    if (id.isEmpty) return;
    final existing = _messagesRefreshInFlight[id];
    if (existing != null) return existing;
    final future = _refreshMessagesInternal(id);
    _messagesRefreshInFlight[id] = future;
    try {
      await future;
    } finally {
      if (identical(_messagesRefreshInFlight[id], future)) {
        _messagesRefreshInFlight.remove(id);
      }
    }
  }

  Future<void> _refreshMessagesInternal(String chatId) async {
    final response = await _api.listMessages(chatId);
    final rawChat = response['chat'];
    if (rawChat is Map) {
      _upsertChat(Chat.fromMap(Map<String, dynamic>.from(rawChat)));
    }
    final incoming = (response['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ChatMessage.fromMap(Map<String, dynamic>.from(item)))
        .toList()
      ..sort(_compareMessagesNewestFirst);
    final mergedMessages = List<ChatMessage>.from(
      _messagesByChat[chatId] ?? const <ChatMessage>[],
    );
    for (final message in incoming) {
      _upsertMessageIntoList(mergedMessages, message);
    }
    _messagesByChat[chatId] = mergedMessages;
    for (final message in _messagesByChat[chatId] ?? const <ChatMessage>[]) {
      _messageOrderByKey.putIfAbsent(
        _messageMergeKey(message),
        () => ++_messageOrderSequence,
      );
    }
    _loadedMessageChatIds.add(chatId);
    _emitMessages(chatId);
    unawaited(_persistCachedState());
  }

  Stream<List<Chat>> streamMyChats(String uid) {
    _activeUserId = uid.trim();
    unawaited(_restoreCachedState(uid));
    _ensureChatsRefreshStarted(uid);
    _ensureSocketConnectedInBackground(uid);
    return Stream<List<Chat>>.multi((controller) {
      controller.add(_sortedChats());
      final sub = _chatsController.stream.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.onCancel = () async {
        await sub.cancel();
      };
    });
  }

  Stream<int> streamUnreadTotal(String uid) {
    _activeUserId = uid.trim();
    unawaited(_restoreCachedState(uid));
    _ensureChatsRefreshStarted(uid);
    _ensureSocketConnectedInBackground(uid);
    return Stream<int>.multi((controller) {
      controller.add(
        _sortedChats().fold<int>(0, (sum, chat) => sum + chat.unreadFor(uid)),
      );
      final sub = _unreadController.stream.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.onCancel = () async {
        await sub.cancel();
      };
    });
  }

  Stream<Chat?> streamChat(String chatId) {
    final uid = _activeUserId?.trim() ?? '';
    if (uid.isNotEmpty) {
      unawaited(_restoreCachedState(uid));
    }
    unawaited(_ensureTimewebReady());
    if (!_loadedChatIds.contains(chatId) &&
        !_chatRefreshInFlight.containsKey(chatId)) {
      unawaited(_refreshChat(chatId));
    }
    return Stream<Chat?>.multi((controller) {
      controller.add(_chatsById[chatId]);
      final sub = _chatControllerFor(chatId).stream.listen(
            controller.add,
            onError: controller.addError,
          );
      controller.onCancel = () async {
        await sub.cancel();
      };
    });
  }

  Future<void> preloadChat(String chatId, {String? uid}) async {
    final normalizedUid = uid?.trim() ?? _activeUserId?.trim() ?? '';
    if (normalizedUid.isNotEmpty) {
      _activeUserId = normalizedUid;
      await _restoreCachedState(normalizedUid);
    }
    await _ensureTimewebReady(uid);
    await _refreshChat(chatId);
  }

  Future<void> refreshInbox(String uid) async {
    _activeUserId = uid.trim();
    await _restoreCachedState(uid);
    _ensureSocketConnectedInBackground(uid);
    await refreshChats();
  }

  Future<void> handleAppResumed(String uid) async {
    _activeUserId = uid.trim();
    if (_socketService?.isConnected != true) {
      final reconnectFuture =
          _socketService?.reconnect(reason: 'chat.handleAppResumed');
      if (reconnectFuture != null) {
        unawaited(reconnectFuture.catchError((_) {}));
      }
    }
    final now = DateTime.now();
    final lastRefreshAt = _lastAppResumeRefreshAt;
    if (lastRefreshAt != null &&
        now.difference(lastRefreshAt) < _resumeRefreshCooldown) {
      for (final chatId in _activeChatIds.toList()) {
        await _socketService?.joinChat(
          chatId,
          reason: 'chat.rejoinAfterResume',
        );
      }
      final foregroundChatId = _foregroundChatId;
      if (foregroundChatId != null && foregroundChatId.isNotEmpty) {
        await markChatRead(chatId: foregroundChatId, uid: uid);
      }
      return;
    }
    _lastAppResumeRefreshAt = now;
    await refreshChats();
    for (final chatId in _activeChatIds.toList()) {
      await _refreshChat(chatId);
      await _socketService?.joinChat(
        chatId,
        reason: 'chat.rejoinAfterResume',
      );
    }
    final foregroundChatId = _foregroundChatId;
    if (foregroundChatId != null && foregroundChatId.isNotEmpty) {
      await markChatRead(chatId: foregroundChatId, uid: uid);
    }
  }

  Future<void> handleNetworkChanged(String uid) async {
    _activeUserId = uid.trim();
    await _restoreCachedState(uid);
    final reconnect = _socketService?.forceReconnect(
      reason: 'chat.networkChanged',
    );
    if (reconnect != null) {
      unawaited(reconnect.catchError((_) {}));
    }
    await refreshChats();
    for (final chatId in _activeChatIds.toList()) {
      await _refreshChat(chatId);
      await _socketService?.joinChat(
        chatId,
        reason: 'chat.rejoinAfterNetworkChange',
      );
    }
    final foregroundChatId = _foregroundChatId;
    if (foregroundChatId != null && foregroundChatId.isNotEmpty) {
      await markChatRead(chatId: foregroundChatId, uid: uid);
    }
    await retryFailedTextMessages(senderId: uid);
  }

  Stream<List<ChatMessage>> streamMessages(String chatId) {
    final uid = _activeUserId?.trim() ?? '';
    if (uid.isNotEmpty) {
      unawaited(_restoreCachedState(uid));
    }
    unawaited(_ensureReadyAndJoinChat(chatId));
    _activeChatIds.add(chatId);
    if (!_loadedMessageChatIds.contains(chatId) &&
        !_messagesRefreshInFlight.containsKey(chatId)) {
      unawaited(_refreshMessages(chatId));
    }
    return Stream<List<ChatMessage>>.multi((controller) {
      controller.add(
        List<ChatMessage>.from(_messagesByChat[chatId] ?? const []),
      );
      final sub = _messageControllerFor(chatId).stream.listen(
            controller.add,
            onError: controller.addError,
          );
      controller.onCancel = () async {
        _activeChatIds.remove(chatId);
        _socketService?.leaveChat(chatId);
        await sub.cancel();
      };
    });
  }

  Future<String> getOrCreateChat({
    required String listingId,
    required String listingTitle,
    required String buyerId,
    required String sellerId,
  }) async {
    _activeUserId = buyerId;
    await _ensureTimewebReady(buyerId);
    final response = await _api.createChat(
      listingId: listingId,
      sellerId: sellerId,
    );
    final rawChat = response['chat'];
    if (rawChat is! Map) {
      throw Exception('Чат не создан');
    }
    final chat = Chat.fromMap(Map<String, dynamic>.from(rawChat));
    _upsertChat(chat);
    return chat.id;
  }

  Future<void> markChatRead({
    required String chatId,
    required String uid,
  }) async {
    _activeUserId = uid;
    final trimmedChatId = chatId.trim();
    if (trimmedChatId.isEmpty) return;
    final unreadCount = _chatsById[trimmedChatId]?.unreadFor(uid) ?? 0;
    final hasUnreadIncomingMessages = (_messagesByChat[trimmedChatId] ??
            const <ChatMessage>[])
        .any((message) => message.senderId != uid && message.readAt == null);
    final now = DateTime.now();
    final lastMarkedAt = _lastMarkReadAt[trimmedChatId];
    if (unreadCount <= 0 &&
        !hasUnreadIncomingMessages &&
        lastMarkedAt == null) {
      return;
    }
    if (unreadCount <= 0 &&
        !hasUnreadIncomingMessages &&
        lastMarkedAt != null &&
        now.difference(lastMarkedAt) < _markReadCooldown) {
      return;
    }

    final existing = _markReadInFlight[trimmedChatId];
    if (existing != null) return existing;

    final future = () async {
      final response = await _api.markChatRead(trimmedChatId);
      _lastMarkReadAt[trimmedChatId] = DateTime.now();
      final rawChat = response['chat'];
      if (rawChat is Map) {
        _upsertChat(Chat.fromMap(Map<String, dynamic>.from(rawChat)));
      }
      final readAt = DateTime.tryParse((response['readAt'] ?? '').toString());
      final messageIds = (response['messageIds'] as List? ?? const [])
          .map((item) => item.toString())
          .toSet();
      if (messageIds.isNotEmpty) {
        final current =
            List<ChatMessage>.from(_messagesByChat[trimmedChatId] ?? const []);
        _messagesByChat[trimmedChatId] = current
            .map(
              (message) => messageIds.contains(message.id)
                  ? message.copyWith(
                      status: 'read',
                      deliveredAt: readAt ?? message.deliveredAt,
                      readAt: readAt ?? message.readAt,
                    )
                  : message,
            )
            .toList();
        _emitMessages(trimmedChatId);
      }
    }();
    _markReadInFlight[trimmedChatId] = future;
    try {
      await future;
    } finally {
      if (identical(_markReadInFlight[trimmedChatId], future)) {
        _markReadInFlight.remove(trimmedChatId);
      }
    }
  }

  Future<void> markChatDelivered({
    required String chatId,
    required String uid,
  }) async {
    try {
      _activeUserId = uid;
      await _ensureTimewebReady(uid);
      if (!_messagesByChat.containsKey(chatId)) {
        return;
      }
      final messages =
          List<ChatMessage>.from(_messagesByChat[chatId] ?? const []);
      for (final message in messages) {
        if (message.senderId == uid || message.deliveredAt != null) continue;
        try {
          final response = await _api.markMessageDelivered(message.id);
          final rawMessage = response['message'];
          if (rawMessage is Map) {
            _upsertMessage(
                ChatMessage.fromMap(Map<String, dynamic>.from(rawMessage)));
          }
        } catch (error) {
          _debugSource(
              'markMessageDelivered skipped for ${message.id}: $error');
        }
      }
    } catch (error) {
      _debugSource('markChatDelivered skipped for $chatId: $error');
    }
  }

  Future<void> markChatsDelivered({
    required Iterable<String> chatIds,
    required String uid,
  }) async {
    final ids = chatIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    for (final chatId in ids) {
      try {
        await markChatDelivered(chatId: chatId, uid: uid);
      } catch (error) {
        _debugSource('markChatsDelivered skipped for $chatId: $error');
      }
    }
  }

  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _activeUserId = senderId;
    final sendKey = 'text|${chatId.trim()}|${senderId.trim()}|$trimmed';
    final existing = _messageSendInFlight[sendKey];
    if (existing != null) return existing;

    final future = _sendMessageInternal(
      chatId: chatId,
      senderId: senderId,
      text: trimmed,
    );
    _messageSendInFlight[sendKey] = future;
    try {
      await future;
    } finally {
      if (identical(_messageSendInFlight[sendKey], future)) {
        _messageSendInFlight.remove(sendKey);
      }
    }
  }

  Future<void> retryMessage({
    required String chatId,
    required String senderId,
    required ChatMessage message,
  }) async {
    if (message.status != 'failed') return;
    if (message.type != 'text' || message.hasImage) return;
    final trimmed = message.text.trim();
    if (trimmed.isEmpty) return;
    _activeUserId = senderId;
    final clientMessageId = message.clientMessageId?.trim().isNotEmpty == true
        ? message.clientMessageId!.trim()
        : message.id.trim().startsWith('temp-')
            ? message.id.trim().replaceFirst('temp-', '')
            : _uuid.v4();
    final sendKey =
        'retry|${chatId.trim()}|${senderId.trim()}|$clientMessageId';
    final existing = _messageSendInFlight[sendKey];
    if (existing != null) return existing;
    final future = _sendMessageInternal(
      chatId: chatId,
      senderId: senderId,
      text: trimmed,
      clientMessageId: clientMessageId,
      tempId: message.id,
      createdAt: message.createdAt,
    );
    _messageSendInFlight[sendKey] = future;
    try {
      await future;
    } finally {
      if (identical(_messageSendInFlight[sendKey], future)) {
        _messageSendInFlight.remove(sendKey);
      }
    }
  }

  Future<void> retryFailedTextMessages({required String senderId}) async {
    final failed = _messagesByChat.values
        .expand((messages) => messages)
        .where(
          (message) =>
              message.senderId == senderId &&
              message.status == 'failed' &&
              message.type == 'text' &&
              !message.hasImage &&
              message.text.trim().isNotEmpty,
        )
        .toList();
    for (final message in failed) {
      try {
        await retryMessage(
          chatId: message.chatId,
          senderId: senderId,
          message: message,
        );
      } catch (error) {
        _debugSource('retry failed message skipped for ${message.id}: $error');
      }
    }
  }

  Future<void> _sendMessageInternal({
    required String chatId,
    required String senderId,
    required String text,
    String? clientMessageId,
    String? tempId,
    DateTime? createdAt,
  }) async {
    await _ensureTimewebReady(senderId);
    await _socketService?.joinChat(chatId);
    final localClientMessageId = clientMessageId ?? _uuid.v4();
    final localTempId = tempId ?? 'temp-$localClientMessageId';
    final localCreatedAt = createdAt ?? DateTime.now();
    _upsertMessage(
      ChatMessage(
        id: localTempId,
        chatId: chatId,
        senderId: senderId,
        text: text,
        clientMessageId: localClientMessageId,
        status: 'pending',
        createdAt: localCreatedAt,
      ),
    );

    try {
      final response = await _api.sendMessage(
        chatId: chatId,
        text: text,
        clientMessageId: localClientMessageId,
      );
      final rawChat = response['chat'];
      if (rawChat is Map) {
        _upsertChat(Chat.fromMap(Map<String, dynamic>.from(rawChat)));
      }
      final rawMessage = response['message'];
      if (rawMessage is Map) {
        final normalized = Map<String, dynamic>.from(rawMessage);
        if ((normalized['text'] ?? '').toString().trim().isEmpty) {
          normalized['text'] = text;
        }
        normalized['clientMessageId'] =
            normalized['clientMessageId'] ?? localClientMessageId;
        _upsertMessage(
          ChatMessage.fromMap(normalized),
        );
      }
    } catch (_) {
      _replaceLocalMessage(
        chatId,
        ChatMessage(
          id: localTempId,
          chatId: chatId,
          senderId: senderId,
          text: text,
          clientMessageId: localClientMessageId,
          status: 'failed',
          createdAt: localCreatedAt,
        ),
      );
      rethrow;
    }
  }

  Future<void> sendImage({
    required String chatId,
    required String senderId,
    required File file,
  }) async {
    _activeUserId = senderId;
    final fileKey = file.path.trim();
    final sendKey = 'image|${chatId.trim()}|${senderId.trim()}|$fileKey';
    final existing = _imageSendInFlight[sendKey];
    if (existing != null) return existing;

    final future = _sendImageInternal(
      chatId: chatId,
      senderId: senderId,
      file: file,
    );
    _imageSendInFlight[sendKey] = future;
    try {
      await future;
    } finally {
      if (identical(_imageSendInFlight[sendKey], future)) {
        _imageSendInFlight.remove(sendKey);
      }
    }
  }

  Future<void> _sendImageInternal({
    required String chatId,
    required String senderId,
    required File file,
  }) async {
    final tempId = 'temp-${_uuid.v4()}';
    final createdAt = DateTime.now();
    _upsertMessage(
      ChatMessage(
        id: tempId,
        chatId: chatId,
        senderId: senderId,
        text: '',
        imageUrl: 'file://${file.path}',
        clientMessageId: tempId,
        status: 'pending',
        createdAt: createdAt,
      ),
    );

    try {
      final prepared = await _imagePreparationService.prepareChatImage(file);
      final response = await _mediaApi.uploadChatImage(
        chatId: chatId,
        bytes: prepared.bytes,
        fileName: prepared.fileName,
        contentType: prepared.contentType,
      );
      if (kDebugMode) {
        final rawMessage = response['message'];
        final rawImageUrl = (rawMessage is Map
                ? (rawMessage['image_url'] ??
                    rawMessage['imageUrl'] ??
                    rawMessage['media_url'] ??
                    '')
                : '')
            .toString()
            .trim();
        final resolution = resolveMediaUrl(
          rawImageUrl,
          categoryHint: 'chats',
        );
        debugPrint(
          'Chat upload response imageUrl=$rawImageUrl resolved=${resolution.resolvedUrl} category=chat provider=${resolution.provider}',
        );
      }
      final rawChat = response['chat'];
      if (rawChat is Map) {
        _upsertChat(Chat.fromMap(Map<String, dynamic>.from(rawChat)));
      }
      final rawMessage = response['message'];
      if (rawMessage is Map) {
        final normalized = Map<String, dynamic>.from(rawMessage);
        normalized['clientMessageId'] = tempId;
        _upsertMessage(
          ChatMessage.fromMap(normalized),
        );
      }
      return;
    } catch (_) {
      _replaceLocalMessage(
        chatId,
        ChatMessage(
          id: tempId,
          chatId: chatId,
          senderId: senderId,
          text: '',
          type: 'image',
          imageUrl: 'file://${file.path}',
          clientMessageId: tempId,
          status: 'failed',
          createdAt: createdAt,
        ),
      );
      rethrow;
    }
  }

  void ingestMessageNotification({
    required String currentUserId,
    required Map<String, dynamic> notification,
  }) {
    final chatId = (notification['chatId'] ?? notification['chat_id'] ?? '')
        .toString()
        .trim();
    if (chatId.isEmpty) return;
    _activeUserId = currentUserId.trim();
    if (_activeUserId == null || _activeUserId!.isEmpty) return;
    if (_foregroundChatId == chatId) {
      unawaited(markChatRead(chatId: chatId, uid: _activeUserId!));
      return;
    }
    unawaited(_refreshChat(chatId));
  }

  Future<String> resolveMessageImageUrl(String rawValue) async {
    final value = rawValue.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('file://')) return value;
    final token = await _tokenStorage.readAccessToken();
    final resolution = resolveMediaUrl(value, categoryHint: 'chats');
    final resolvedUrl = resolution.resolvedUrl.trim();
    if (resolvedUrl.isEmpty) {
      return '';
    }

    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null) {
      return resolvedUrl;
    }

    final baseUri = Uri.parse(ApiConfig.baseUrl);
    final isBackendMedia = uri.host.isEmpty || uri.host == baseUri.host;
    final mediaPath = uri.host.isEmpty ? uri.path : uri.path;
    if (!isBackendMedia || !mediaPath.startsWith('/media/chats/')) {
      if (kDebugMode) {
        debugPrint(
          'Media resolve category=chat original=$value resolved=$resolvedUrl provider=${resolution.provider}',
        );
      }
      return resolvedUrl;
    }

    final effectiveUri = uri.host.isEmpty
        ? ApiConfig.uri(
            mediaPath,
            uri.queryParameters.isEmpty ? null : uri.queryParameters,
          )
        : uri;
    final withToken = token == null || token.isEmpty
        ? effectiveUri
        : effectiveUri.replace(
            queryParameters: <String, String>{
              ...effectiveUri.queryParameters,
              'token': token,
            },
          );
    if (kDebugMode) {
      debugPrint(
        'Media resolve category=chat original=$value resolved=${withToken.toString()} provider=proxy',
      );
    }
    return withToken.toString();
  }

  void removeLocalMessage({
    required String chatId,
    required String messageId,
  }) {
    _removeMessage(chatId, messageId);
  }

  Future<void> deleteChat({
    required String chatId,
    required String uid,
  }) async {
    _activeUserId = uid;
    await _api.deleteChat(chatId);
    _chatsById.remove(chatId);
    _messagesByChat.remove(chatId);
    _messageControllers[chatId]?.add(const <ChatMessage>[]);
    _chatControllers[chatId]?.add(null);
    _emitChats();
  }

  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
    required String uid,
  }) async {
    _activeUserId = uid;
    await _api.deleteMessage(messageId);
    _removeMessage(chatId, messageId);
    await _refreshChat(chatId);
  }

  Future<void> dispose() async {
    await _socketSub?.cancel();
    await _chatsController.close();
    await _unreadController.close();
    for (final controller in _chatControllers.values) {
      await controller.close();
    }
    for (final controller in _messageControllers.values) {
      await controller.close();
    }
  }

  int _compareMessagesNewestFirst(ChatMessage left, ChatMessage right) {
    final byCreatedAt = right.createdAt.compareTo(left.createdAt);
    if (byCreatedAt != 0) return byCreatedAt;
    final leftOrder = _messageOrderByKey[_messageMergeKey(left)] ?? 0;
    final rightOrder = _messageOrderByKey[_messageMergeKey(right)] ?? 0;
    return rightOrder.compareTo(leftOrder);
  }

  String _messageMergeKey(ChatMessage message) {
    final clientMessageId = message.clientMessageId?.trim();
    if (clientMessageId != null && clientMessageId.isNotEmpty) {
      return clientMessageId;
    }
    final messageId = message.id.trim();
    if (messageId.isNotEmpty) {
      return messageId;
    }
    final imageUrl = (message.imageUrl ?? '').trim();
    final normalizedImage = imageUrl.startsWith('file://')
        ? imageUrl.replaceFirst('file://', '')
        : imageUrl;
    final text = message.text.trim();
    final createdAt = message.createdAt.toUtc().toIso8601String();
    return [
      message.chatId.trim(),
      message.senderId.trim(),
      createdAt,
      text,
      normalizedImage,
    ].join('|');
  }

  String _messageDedupSignature(ChatMessage message) {
    final createdAt = message.createdAt.toUtc();
    final normalizedCreatedAt = DateTime.utc(
      createdAt.year,
      createdAt.month,
      createdAt.day,
      createdAt.hour,
      createdAt.minute,
      createdAt.second,
    ).toIso8601String();
    final imageUrl = (message.imageUrl ?? '').trim();
    final normalizedImage = imageUrl.startsWith('file://')
        ? imageUrl.replaceFirst('file://', '')
        : imageUrl;
    return [
      message.chatId.trim(),
      message.senderId.trim(),
      normalizedCreatedAt,
      message.text.trim(),
      normalizedImage,
    ].join('|');
  }

  void _upsertMessageIntoList(
    List<ChatMessage> items,
    ChatMessage message,
  ) {
    final normalized = _normalizeMessage(message);
    final index = _findExistingMessageIndex(items, normalized);
    final mergeKey = _messageMergeKey(normalized);
    if (index == -1) {
      items.add(normalized);
      _messageOrderByKey.putIfAbsent(mergeKey, () => ++_messageOrderSequence);
      return;
    }

    final previous = items[index];
    items[index] = _mergeMessages(previous, normalized);
  }

  int _findExistingMessageIndex(
    List<ChatMessage> items,
    ChatMessage message,
  ) {
    final messageId = message.id.trim();
    final clientMessageId = message.clientMessageId?.trim() ?? '';
    final dedupSignature = _messageDedupSignature(message);
    return items.indexWhere((entry) {
      if (messageId.isNotEmpty && entry.id == messageId) {
        return true;
      }
      if (clientMessageId.isNotEmpty &&
          (entry.clientMessageId?.trim() ?? '') == clientMessageId) {
        return true;
      }
      if (_messageDedupSignature(entry) == dedupSignature) {
        return true;
      }
      return _isLikelyOptimisticMatch(entry, message);
    });
  }

  bool _isLikelyOptimisticMatch(ChatMessage existing, ChatMessage incoming) {
    final existingClientId = existing.clientMessageId?.trim() ?? '';
    final isLocalPending = existingClientId.isNotEmpty ||
        existing.id.trim().startsWith('temp-') ||
        existing.status == 'pending';
    if (!isLocalPending) {
      return false;
    }
    if (existing.chatId.trim() != incoming.chatId.trim() ||
        existing.senderId.trim() != incoming.senderId.trim()) {
      return false;
    }

    final ageDifference =
        existing.createdAt.difference(incoming.createdAt).abs();
    if (ageDifference > const Duration(seconds: 30)) {
      return false;
    }

    if (existing.hasImage || incoming.hasImage) {
      return existing.hasImage == incoming.hasImage &&
          existing.text.trim() == incoming.text.trim();
    }

    return existing.text.trim().isNotEmpty &&
        existing.text.trim() == incoming.text.trim();
  }
}
