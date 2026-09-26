import 'dart:async';
import 'dart:io';

import 'package:atta/src/services/api/notifications_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/notification_navigation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PushNotificationService {
  PushNotificationService({
    NotificationsApi? api,
    MethodChannel? channel,
    EventChannel? eventChannel,
    bool? platformSupported,
    TokenStorage? tokenStorage,
  })  : _api = api,
        _platformSupported = platformSupported ?? (!kIsWeb && Platform.isIOS),
        _tokenStorage = tokenStorage ?? TokenStorage(),
        _channel = channel ?? const MethodChannel('atta/push_notifications'),
        _eventChannel =
            eventChannel ?? const EventChannel('atta/push_notification_taps');

  final NotificationsApi? _api;
  final bool _platformSupported;
  final TokenStorage _tokenStorage;
  String? _activeUserId;
  String? _registeredUserId;
  int _generation = 0;
  final MethodChannel _channel;
  final EventChannel _eventChannel;
  StreamSubscription<dynamic>? _tapSub;
  String? _registeredToken;
  Future<void>? _bindInFlight;

  Future<void> bindForUser({
    required NotificationsApi api,
    required String userId,
  }) async {
    if (!_platformSupported) return;
    if (_activeUserId != userId) {
      _generation++;
      _activeUserId = userId;
      _registeredToken = null;
      _registeredUserId = null;
      _bindInFlight = null;
    }
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
    final generation = _generation;
    final authGeneration = _tokenStorage.sessionGeneration;
    bool current() =>
        generation == _generation &&
        authGeneration == _tokenStorage.sessionGeneration;
    final token = await _requestToken();
    if (!current()) return;
    if (token == null || token.isEmpty) return;
    if (_registeredToken != token || _registeredUserId != userId) {
      await api.registerDevice(
        token: token,
        platform: 'ios',
        locale: Platform.localeName,
      );
      if (!current()) return;
      _registeredToken = token;
      _registeredUserId = userId;
    }
    _listenForTaps();
    await _consumeInitialNotification(generation);
  }

  Future<void> unbind({NotificationsApi? api}) async {
    final token = _registeredToken;
    final owner = _registeredUserId;
    final authGeneration = _tokenStorage.sessionGeneration;
    ++_generation;
    _activeUserId = null;
    _registeredUserId = null;
    _registeredToken = null;
    _bindInFlight = null;
    final nativeCleanup = _clearNativeState();
    final taps = _tapSub;
    _tapSub = null;
    // Server logout revokes the device's owning session. Never perform an
    // authorized DELETE with the next account's credentials.
    final user = await _tokenStorage.readCurrentUser();
    if (owner != null &&
        user?.uid == owner &&
        authGeneration == _tokenStorage.sessionGeneration &&
        token != null) {
      try {
        await (api ?? _api)?.unregisterDevice(token: token);
      } catch (_) {}
    }
    await taps?.cancel();
    await nativeCleanup;
  }

  Future<void> _clearNativeState() async {
    if (!_platformSupported) return;
    try {
      await _channel.invokeMethod<void>('unregister');
    } catch (_) {}
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

  Future<void> _consumeInitialNotification(int generation) async {
    try {
      final payload = await _channel.invokeMapMethod<String, dynamic>(
        'getInitialNotification',
      );
      if (payload != null && generation == _generation) {
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
    final userId = _activeUserId;
    if (userId == null) return;
    final recipient = payload['recipientId']?.toString();
    if (recipient != null && recipient != userId) return;
    final rawNotification = payload['notification'];
    final notification = rawNotification is Map
        ? rawNotification.map((key, value) => MapEntry(key.toString(), value))
        : payload;
    final owner =
        (notification['user_id'] ?? notification['userId'])?.toString();
    if (owner != null && owner.isNotEmpty && owner != userId) return;
    if ((await _tokenStorage.readCurrentUser())?.uid != userId ||
        _activeUserId != userId) {
      return;
    }
    await NotificationNavigationService.handleNotificationTapFromGlobalContext(
      notification,
    );
  }
}
