import 'dart:async';
import 'dart:io';

import 'package:atta/src/services/api/notifications_api.dart';
import 'package:atta/src/services/notification_navigation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PushNotificationService {
  PushNotificationService({
    NotificationsApi? api,
    MethodChannel? channel,
    EventChannel? eventChannel,
  })  : _api = api,
        _channel = channel ?? const MethodChannel('atta/push_notifications'),
        _eventChannel =
            eventChannel ?? const EventChannel('atta/push_notification_taps');

  final NotificationsApi? _api;
  final MethodChannel _channel;
  final EventChannel _eventChannel;

  StreamSubscription<dynamic>? _tapSub;
  String? _registeredToken;
  Future<void>? _bindInFlight;

  Future<void> bindForUser({
    required NotificationsApi api,
    required String userId,
  }) async {
    if (kIsWeb || !Platform.isIOS) return;
    final existing = _bindInFlight;
    if (existing != null) return existing;
    final future = _bind(api: api, userId: userId);
    _bindInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_bindInFlight, future)) {
        _bindInFlight = null;
      }
    }
  }

  Future<void> _bind({
    required NotificationsApi api,
    required String userId,
  }) async {
    final token = await _requestToken();
    if (token == null || token.isEmpty) return;
    if (_registeredToken != token) {
      await api.registerDevice(
        token: token,
        platform: 'ios',
        locale: Platform.localeName,
      );
      _registeredToken = token;
    }
    _listenForTaps();
    await _consumeInitialNotification();
  }

  Future<void> unbind({NotificationsApi? api}) async {
    final token = _registeredToken;
    _registeredToken = null;
    if (token == null || token.isEmpty) return;
    try {
      await (api ?? _api)?.unregisterDevice(token: token);
    } catch (_) {
      // Push token cleanup is best-effort and must not block logout.
    }
  }

  Future<void> dispose() async {
    await _tapSub?.cancel();
    _tapSub = null;
  }

  Future<String?> _requestToken() async {
    try {
      final token = await _channel.invokeMethod<String>('requestToken');
      return token?.trim();
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint('Push token request failed: ${error.message}');
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _consumeInitialNotification() async {
    try {
      final payload = await _channel.invokeMapMethod<String, dynamic>(
        'getInitialNotification',
      );
      if (payload != null) {
        await _handleTapPayload(payload);
      }
    } catch (_) {
      // Initial payload is optional.
    }
  }

  void _listenForTaps() {
    _tapSub ??= _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        unawaited(
          _handleTapPayload(
            event.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      }
    });
  }

  Future<void> _handleTapPayload(Map<String, dynamic> payload) async {
    final rawNotification = payload['notification'];
    final notification = rawNotification is Map
        ? rawNotification.map((key, value) => MapEntry(key.toString(), value))
        : payload;
    await NotificationNavigationService.handleNotificationTapFromGlobalContext(
      notification,
    );
  }
}
