import 'dart:async';
import 'dart:io';

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:flutter/foundation.dart';

class AppBadgeService {
  StreamSubscription<int>? _chatSub;
  StreamSubscription<int>? _notificationsSub;

  String? _activeUserId;
  int _unreadChats = 0;
  int _unreadNotifications = 0;

  Future<void> bindForUser({
    required String userId,
    required ChatService chatService,
    required NotificationsService notificationsService,
  }) async {
    if (_activeUserId == userId) return;

    await _cancelSubscriptions();
    _activeUserId = userId;
    _unreadChats = 0;
    _unreadNotifications = 0;

    _chatSub = chatService.streamUnreadTotal(userId).listen(
      (count) async {
        _unreadChats = count;
        await _pushBadge();
      },
      onError: (_, __) async {
        _unreadChats = 0;
        await _pushBadge();
      },
    );

    _notificationsSub =
        notificationsService.streamUnreadBadgeCount(userId).listen(
      (count) async {
        _unreadNotifications = count;
        await _pushBadge();
      },
      onError: (_, __) async {
        _unreadNotifications = 0;
        await _pushBadge();
      },
    );
  }

  Future<void> clear() async {
    _activeUserId = null;
    _unreadChats = 0;
    _unreadNotifications = 0;
    await _cancelSubscriptions();
    await _setBadgeCount(0);
  }

  Future<void> dispose() async {
    await _cancelSubscriptions();
  }

  Future<void> _cancelSubscriptions() async {
    await _chatSub?.cancel();
    await _notificationsSub?.cancel();
    _chatSub = null;
    _notificationsSub = null;
  }

  Future<void> _pushBadge() async {
    final total = _unreadChats + _unreadNotifications;
    await _setBadgeCount(total);
  }

  Future<void> _setBadgeCount(int count) async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) return;

    try {
      final supported = await AppBadgePlus.isSupported();
      if (!supported) return;
      await AppBadgePlus.updateBadge(count.clamp(0, 999));
    } catch (_) {
      // Ignore badge errors on unsupported launchers/devices.
    }
  }
}
