import 'dart:convert';

import 'package:atta/src/app.dart';
import 'package:atta/src/features/admin/admin_screen.dart';
import 'package:atta/src/features/inbox/chat_screen.dart';
import 'package:atta/src/features/listings/my_listings_screen.dart';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/features/reviews/seller_reviews_screen.dart';
import 'package:atta/src/features/support/support_screen.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/support_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationNavigationService {
  static const String _pendingPrefsKey = 'pending_notification_action_v1';
  static const Duration _tapDebounce = Duration(milliseconds: 700);
  static const Duration _sameRouteDebounce = Duration(seconds: 2);
  static bool _tapInFlight = false;
  static DateTime? _lastTapAt;
  static String _lastOpenedActionKey = '';
  static DateTime? _lastOpenedActionAt;

  static const Set<String> _supportActionTypes = <String>{
    'support_reply',
    'report_reply',
    'report_update',
    'personal_admin_notification',
    'admin_personal',
    'support_personal',
  };

  static const Set<String> _markOnlyActionTypes = <String>{
    '',
    'announcement',
    'broadcast',
    'general',
    'admin_general',
    'system_info',
    'generic',
    'moderation',
  };

  @visibleForTesting
  static Future<void> Function(BuildContext, Map<String, dynamic>)?
      debugOpenSupportOverride;

  @visibleForTesting
  static Future<void> Function(BuildContext, Map<String, dynamic>)?
      debugOpenReviewOverride;

  @visibleForTesting
  static Future<void> Function(BuildContext, Map<String, dynamic>)?
      debugOpenAdminReportsOverride;

  @visibleForTesting
  static Future<void> Function(BuildContext, Map<String, dynamic>)?
      debugOpenListingsOverride;

  @visibleForTesting
  static void debugResetState() {
    _tapInFlight = false;
    _lastTapAt = null;
    _lastOpenedActionKey = '';
    _lastOpenedActionAt = null;
    debugOpenSupportOverride = null;
    debugOpenReviewOverride = null;
    debugOpenAdminReportsOverride = null;
    debugOpenListingsOverride = null;
  }

  static String actionTypeForNotification(Map<String, dynamic> notification) {
    final payload = payloadForNotification(notification);
    final inferred = _inferActionType(notification, payload);
    if (inferred.isNotEmpty) {
      return inferred;
    }
    final candidates = <dynamic>[
      payload['actionType'],
      payload['action_type'],
      payload['notificationType'],
      payload['notification_type'],
      payload['type'],
      notification['type'],
    ];
    for (final candidate in candidates) {
      final value = candidate?.toString().trim().toLowerCase() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  static String _inferActionType(
    Map<String, dynamic> notification,
    Map<String, dynamic> payload,
  ) {
    final notificationType =
        (notification['type'] ?? '').toString().trim().toLowerCase();
    final payloadStatus = (payload['status'] ??
            payload['listingStatus'] ??
            payload['listing_status'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    final hasListingId = (payload['listingId'] ?? payload['listing_id'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
    if ((notificationType == 'moderation' || notificationType == 'generic') &&
        hasListingId) {
      switch (payloadStatus) {
        case 'approved':
          return 'listing_approved';
        case 'rejected':
          return 'listing_rejected';
        case 'archived':
          return 'listing_archived';
        case 'sold':
          return 'listing_sold';
        case 'deleted':
          return 'listing_deleted';
      }
    }
    if (notificationType == 'support' &&
        (payload['ticketId'] ?? payload['ticket_id'] ?? '')
            .toString()
            .trim()
            .isNotEmpty) {
      return 'support_reply';
    }
    return '';
  }

  static Map<String, dynamic> payloadForNotification(
    Map<String, dynamic> notification,
  ) {
    final payload = notification['payload'];
    if (payload is Map) {
      return payload.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  static Future<void> handleNotificationTap(
    BuildContext context,
    Map<String, dynamic> notification,
  ) async {
    final now = DateTime.now();
    if (_tapInFlight) {
      return;
    }
    final lastTapAt = _lastTapAt;
    if (lastTapAt != null && now.difference(lastTapAt) < _tapDebounce) {
      return;
    }
    _tapInFlight = true;
    _lastTapAt = now;
    final auth = context.read<AuthService>();
    final normalized = Map<String, dynamic>.from(notification);
    try {
      if (!auth.isAuthenticated) {
        await _savePendingNotification(normalized);
        return;
      }

      await _markNotificationViewed(context, normalized);
      if (!context.mounted) return;
      await _openAction(context, normalized);
    } finally {
      _tapInFlight = false;
    }
  }

  static Future<void> consumePendingIfPossible(BuildContext context) async {
    final auth = context.read<AuthService>();
    if (!auth.isAuthenticated) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingPrefsKey)?.trim();
    if (raw == null || raw.isEmpty) return;
    await prefs.remove(_pendingPrefsKey);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      if (!context.mounted) return;
      await handleNotificationTap(
        context,
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } catch (_) {
      await prefs.remove(_pendingPrefsKey);
    }
  }

  static Future<void> handleNotificationTapFromGlobalContext(
    Map<String, dynamic> notification,
  ) async {
    final context = attaNavigatorKey.currentContext;
    if (context == null) return;
    await handleNotificationTap(context, notification);
  }

  static Future<void> _savePendingNotification(
    Map<String, dynamic> notification,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingPrefsKey, jsonEncode(notification));
  }

  static Future<void> _markNotificationViewed(
    BuildContext context,
    Map<String, dynamic> notification,
  ) async {
    final auth = context.read<AuthService>();
    final notifications = context.read<NotificationsService>();
    final type = (notification['type'] ?? '').toString().trim().toLowerCase();
    if (type == 'chat_message' || type == 'message' || type == 'chat') {
      return;
    }
    final notificationId = (notification['id'] ?? '').toString().trim();
    final scope = (notification['scope'] ?? '').toString().trim().toLowerCase();
    final isRead = notification['is_read'] == true;
    if (scope == 'personal' && !isRead && notificationId.isNotEmpty) {
      await notifications.markPersonalReadById(notificationId);
      return;
    }
    if (scope == 'global' && auth.currentUser != null) {
      await notifications.markAllSeen(auth.currentUser!.uid);
    }
  }

  static Future<void> _openAction(
    BuildContext context,
    Map<String, dynamic> notification,
  ) async {
    final payload = payloadForNotification(notification);
    final actionType = actionTypeForNotification(notification);
    if (_shouldOnlyMarkAsViewed(notification, actionType: actionType)) {
      return;
    }
    switch (actionType) {
      case 'review_new':
        await _openReview(context, payload);
        return;
      case 'chat_message':
      case 'message':
      case 'chat':
        await _openChat(context, notification, payload);
        return;
      case 'listing_approved':
      case 'moderation_approved':
      case 'listing_rejected':
      case 'moderation_rejected':
      case 'listing_archived':
      case 'listing_sold':
      case 'listing_deleted':
        await _openMyListings(context, payload, actionType: actionType);
        return;
      case 'support_reply':
      case 'report_reply':
      case 'report_update':
      case 'personal_admin_notification':
      case 'admin_personal':
      case 'support_personal':
        await _openSupport(context, payload);
        return;
      case 'admin_report_new':
        await _openAdminReports(context, payload);
        return;
      default:
        return;
    }
  }

  @visibleForTesting
  static bool shouldNavigateForNotification(Map<String, dynamic> notification) {
    final actionType = actionTypeForNotification(notification);
    return !_shouldOnlyMarkAsViewed(notification, actionType: actionType) &&
        (actionType == 'review_new' ||
            actionType == 'listing_approved' ||
            actionType == 'moderation_approved' ||
            actionType == 'listing_rejected' ||
            actionType == 'moderation_rejected' ||
            actionType == 'listing_archived' ||
            actionType == 'listing_sold' ||
            actionType == 'listing_deleted' ||
            actionType == 'chat_message' ||
            actionType == 'message' ||
            actionType == 'chat' ||
            _supportActionTypes.contains(actionType) ||
            actionType == 'admin_report_new');
  }

  static bool _shouldOnlyMarkAsViewed(
    Map<String, dynamic> notification, {
    required String actionType,
  }) {
    if (_markOnlyActionTypes.contains(actionType)) {
      return true;
    }
    if (_supportActionTypes.contains(actionType) ||
        actionType == 'review_new' ||
        actionType == 'listing_approved' ||
        actionType == 'moderation_approved' ||
        actionType == 'listing_rejected' ||
        actionType == 'moderation_rejected' ||
        actionType == 'listing_archived' ||
        actionType == 'listing_sold' ||
        actionType == 'listing_deleted' ||
        actionType == 'chat_message' ||
        actionType == 'message' ||
        actionType == 'chat' ||
        actionType == 'admin_report_new') {
      return false;
    }
    final payload = payloadForNotification(notification);
    if (payload.isEmpty) {
      return true;
    }
    final hasNavigablePayload =
        (payload['chatId'] ?? payload['chat_id'] ?? '')
                .toString()
                .trim()
                .isNotEmpty ||
        (payload['ticketId'] ?? payload['ticket_id'] ?? '')
                .toString()
                .trim()
                .isNotEmpty ||
            (payload['reportId'] ?? payload['report_id'] ?? '')
                .toString()
                .trim()
                .isNotEmpty ||
            (payload['reviewId'] ?? payload['review_id'] ?? '')
                .toString()
                .trim()
                .isNotEmpty ||
            (payload['sellerId'] ?? payload['seller_id'] ?? '')
                .toString()
                .trim()
                .isNotEmpty ||
            (payload['listingId'] ?? payload['listing_id'] ?? '')
                .toString()
                .trim()
                .isNotEmpty;
    return !hasNavigablePayload;
  }

  static Future<void> _openReview(
    BuildContext context,
    Map<String, dynamic> payload,
  ) async {
    final override = debugOpenReviewOverride;
    if (override != null) {
      await override(context, payload);
      return;
    }
    final sellerId = (payload['sellerId'] ??
            payload['seller_id'] ??
            payload['targetUserId'] ??
            payload['target_user_id'] ??
            '')
        .toString()
        .trim();
    final reviewId =
        (payload['reviewId'] ?? payload['review_id'] ?? '').toString().trim();
    final listingId =
        (payload['listingId'] ?? payload['listing_id'] ?? '').toString().trim();
    if (listingId.isNotEmpty) {
      final actionKey = 'review:$listingId:$reviewId';
      if (_shouldSkipDuplicateOpen(actionKey)) {
        return;
      }
      try {
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ListingDetailScreen(
              listingId: listingId,
              openReviewsOnStart: true,
              initialReviewId: reviewId,
            ),
          ),
        );
        _rememberOpenedAction(actionKey);
      } on ApiException {
        if (!context.mounted) return;
        showAppSnack(
          context,
          'Отзыв не найден или больше недоступен.',
          isError: true,
        );
      }
      return;
    }
    if (sellerId.isEmpty) {
      showAppSnack(
        context,
        'Отзыв не найден или больше недоступен.',
        isError: true,
      );
      return;
    }
    try {
      final items = await context.read<ReviewsService>().refreshSellerReviews(
            sellerId,
          );
      if (reviewId.isNotEmpty &&
          !items.any(
              (item) => (item['id'] ?? '').toString().trim() == reviewId)) {
        if (!context.mounted) return;
        showAppSnack(
          context,
          'Отзыв не найден или больше недоступен.',
          isError: true,
        );
        return;
      }
      if (!context.mounted) return;
      final actionKey = 'review:seller:$sellerId:$reviewId';
      if (_shouldSkipDuplicateOpen(actionKey)) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SellerReviewsScreen(
            sellerId: sellerId,
            sellerName: '',
            listingId: listingId,
            initialReviewId: reviewId,
          ),
        ),
      );
      _rememberOpenedAction(actionKey);
    } on ApiException {
      if (!context.mounted) return;
      showAppSnack(
        context,
        'Отзыв не найден или больше недоступен.',
        isError: true,
      );
    }
  }

  static Future<void> _openChat(
    BuildContext context,
    Map<String, dynamic> notification,
    Map<String, dynamic> payload,
  ) async {
    final chatId = (payload['chatId'] ??
            payload['chat_id'] ??
            notification['chatId'] ??
            notification['chat_id'] ??
            '')
        .toString()
        .trim();
    if (chatId.isEmpty) {
      return;
    }
    final actionKey = 'chat:$chatId';
    if (_shouldSkipDuplicateOpen(actionKey)) {
      return;
    }
    final uid = context.read<AuthService>().currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      await context.read<ChatService>().preloadChat(chatId, uid: uid);
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(chatId: chatId),
      ),
    );
    _rememberOpenedAction(actionKey);
  }

  static Future<void> _openSupport(
    BuildContext context,
    Map<String, dynamic> payload,
  ) async {
    final override = debugOpenSupportOverride;
    if (override != null) {
      await override(context, payload);
      return;
    }
    final ticketId =
        (payload['ticketId'] ?? payload['ticket_id'] ?? '').toString().trim();
    if (ticketId.isEmpty) {
      const actionKey = 'support:root';
      if (_shouldSkipDuplicateOpen(actionKey)) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SupportScreen(),
        ),
      );
      _rememberOpenedAction(actionKey);
      return;
    }
    try {
      await context.read<SupportService>().refreshMessages(ticketId);
      if (!context.mounted) return;
      final actionKey = 'support:$ticketId';
      if (_shouldSkipDuplicateOpen(actionKey)) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SupportScreen(initialTicketId: ticketId),
        ),
      );
      _rememberOpenedAction(actionKey);
    } on ApiException catch (error) {
      if (!context.mounted) return;
      if (error.isNotFound) {
        showAppSnack(
          context,
          'Обращение в поддержку не найдено.',
          isError: true,
        );
        return;
      }
      rethrow;
    }
  }

  static Future<void> _openAdminReports(
    BuildContext context,
    Map<String, dynamic> payload,
  ) async {
    final auth = context.read<AuthService>();
    final me = auth.currentUser;
    if (me == null) {
      return;
    }
    final admin = context.read<AdminService>();
    final isAdmin = await admin.streamIsAdmin(me.uid).first;
    if (!context.mounted) {
      return;
    }
    if (!isAdmin) {
      return;
    }
    final override = debugOpenAdminReportsOverride;
    if (override != null) {
      await override(context, payload);
      return;
    }
    final reportId =
        (payload['reportId'] ?? payload['report_id'] ?? '').toString().trim();
    final actionKey = 'admin_report:$reportId';
    if (_shouldSkipDuplicateOpen(actionKey)) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminScreen(
          initialTabIndex: 3,
          initialReportId: reportId,
        ),
      ),
    );
    _rememberOpenedAction(actionKey);
  }

  static Future<void> _openMyListings(
    BuildContext context,
    Map<String, dynamic> payload, {
    required String actionType,
  }) async {
    final override = debugOpenListingsOverride;
    if (override != null) {
      await override(context, <String, dynamic>{
        ...payload,
        'actionType': actionType,
      });
      return;
    }
    final listingId =
        (payload['listingId'] ?? payload['listing_id'] ?? '').toString().trim();
    final tabIndex = switch (actionType) {
      'listing_approved' || 'moderation_approved' => 0,
      'listing_archived' => 2,
      'listing_rejected' || 'moderation_rejected' || 'listing_deleted' => 3,
      'listing_sold' => 4,
      _ => 0,
    };
    final actionKey = 'my_listings:$tabIndex:$listingId';
    if (_shouldSkipDuplicateOpen(actionKey)) {
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyListingsScreen(
          initialTabIndex: tabIndex,
          initialListingId: listingId,
          autoOpenInitialListing: listingId.isNotEmpty,
        ),
      ),
    );
    _rememberOpenedAction(actionKey);
  }

  static bool _shouldSkipDuplicateOpen(String actionKey) {
    final lastKey = _lastOpenedActionKey;
    final lastAt = _lastOpenedActionAt;
    if (lastKey.isEmpty || lastAt == null) {
      return false;
    }
    return lastKey == actionKey &&
        DateTime.now().difference(lastAt) < _sameRouteDebounce;
  }

  static void _rememberOpenedAction(String actionKey) {
    _lastOpenedActionKey = actionKey;
    _lastOpenedActionAt = DateTime.now();
  }
}
