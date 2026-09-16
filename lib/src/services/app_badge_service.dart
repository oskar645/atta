import 'dart:async';

import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/platform_badge_stub.dart'
    if (dart.library.io) 'package:atta/src/services/platform_badge_native.dart'
    if (dart.library.js_interop) 'package:atta/src/services/platform_badge_web.dart'
    as platform;

typedef BadgeSupportChecker = Future<bool> Function();
typedef BadgeUpdater = Future<void> Function(int count);

class AppBadgeService {
  AppBadgeService({BadgeSupportChecker? isSupported, BadgeUpdater? updateBadge})
      : _isSupported = isSupported ?? platform.isBadgeSupported,
        _updateBadge = updateBadge ?? platform.updateBadge;

  final BadgeSupportChecker _isSupported;
  final BadgeUpdater _updateBadge;
  StreamSubscription<int>? _chatSub;
  StreamSubscription<int>? _notificationSub;
  String? _activeUserId;
  int _generation = 0;
  int _unreadChats = 0;
  int _unreadNotifications = 0;
  Future<void> _writes = Future.value();

  Future<void> bindForUser({
    required String userId,
    required ChatService chatService,
    required NotificationsService notificationsService,
  }) async {
    if (_activeUserId == userId) return;
    final generation = ++_generation;
    _activeUserId = userId;
    _unreadChats = 0;
    _unreadNotifications = notificationsService.peekUnreadBadgeCount(userId);
    final cancelled = _cancelSubscriptions();
    unawaited(_pushBadge());
    await cancelled;
    if (generation != _generation) return;
    _chatSub = chatService.streamUnreadTotal(userId).listen((count) {
      if (generation != _generation) return;
      _unreadChats = count.clamp(0, 2147483647);
      unawaited(_pushBadge());
    }, onError: (_, __) {});
    // This stream already excludes chat records and includes saved-search,
    // support, moderation, personal and unseen global notifications once.
    _notificationSub =
        notificationsService.streamUnreadBadgeCount(userId).listen((count) {
      if (generation != _generation) return;
      _unreadNotifications = count.clamp(0, 2147483647);
      unawaited(_pushBadge());
    }, onError: (_, __) {});
  }

  Future<void> clear() async {
    ++_generation;
    _activeUserId = null;
    _unreadChats = 0;
    _unreadNotifications = 0;
    final cancelled = _cancelSubscriptions();
    final write = _pushBadge();
    await cancelled;
    await write;
  }

  Future<void> dispose() => clear();

  Future<void> _cancelSubscriptions() async {
    final chat = _chatSub;
    final notification = _notificationSub;
    _chatSub = null;
    _notificationSub = null;
    await chat?.cancel();
    await notification?.cancel();
  }

  Future<void> _pushBadge() {
    final generation = _generation;
    final count = _unreadChats + _unreadNotifications;
    // Native writes must complete in order: an old async update cannot finish
    // after logout's zero or after the next account's count.
    return _writes = _writes.then((_) async {
      try {
        if (generation != _generation || !await _isSupported()) return;
        if (generation != _generation) return;
        await _updateBadge(count);
      } catch (_) {
        // Unsupported launcher/browser or denied permission.
      }
    });
  }
}
