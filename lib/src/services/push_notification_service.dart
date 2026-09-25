import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atta/src/services/api/notifications_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/notification_navigation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const AndroidNotificationChannel attaNotificationChannel =
    AndroidNotificationChannel(
  'atta_notifications',
  'Уведомления ATTA',
  description: 'Сообщения и персональные уведомления ATTA',
  importance: Importance.high,
  playSound: true,
  showBadge: true,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

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
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<dynamic>? _tapSub;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _fcmTapSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
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
    final token = await (_isAndroid ? _requestAndroidToken() : _requestToken());
    if (!current()) return;
    if (token == null || token.isEmpty) return;
    if (_registeredToken != token || _registeredUserId != userId) {
      await api.registerDevice(
        token: token,
        platform: _isAndroid ? 'android' : 'ios',
        locale: Platform.localeName,
      );
      if (!current()) return;
      _registeredToken = token;
      _registeredUserId = userId;
    }
    if (_isAndroid) {
      await _configureAndroidMessaging(api, userId, generation);
    } else {
      _listenForTaps();
      await _consumeInitialNotification(generation);
    }
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
    final tokenRefresh = _tokenRefreshSub;
    _tokenRefreshSub = null;
    final fcmTaps = _fcmTapSub;
    _fcmTapSub = null;
    final foreground = _foregroundSub;
    _foregroundSub = null;
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
    await tokenRefresh?.cancel();
    await fcmTaps?.cancel();
    await foreground?.cancel();
    if (_isAndroid) {
      try {
        await _localNotifications.cancelAll();
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
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
    await _tokenRefreshSub?.cancel();
    await _fcmTapSub?.cancel();
    await _foregroundSub?.cancel();
    _tapSub = null;
  }

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<String?> _requestAndroidToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      return (await messaging.getToken())?.trim();
    } catch (error) {
      if (kDebugMode) debugPrint('FCM token request failed: $error');
      return null;
    }
  }

  Future<void> _configureAndroidMessaging(
    NotificationsApi api,
    String userId,
    int generation,
  ) async {
    try {
      const initialization = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _localNotifications.initialize(
        settings: initialization,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null) return;
          try {
            unawaited(_handleTapPayload(
              Map<String, dynamic>.from(jsonDecode(payload) as Map),
            ));
          } catch (_) {}
        },
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(attaNotificationChannel);

      _tokenRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(
        (token) async {
          if (generation != _generation || _activeUserId != userId) return;
          try {
            await api.registerDevice(
              token: token,
              platform: 'android',
              locale: Platform.localeName,
            );
            if (generation == _generation) {
              _registeredToken = token;
              _registeredUserId = userId;
            }
          } catch (_) {}
        },
      );
      _fcmTapSub ??= FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => unawaited(_handleTapPayload(_payloadFromFcm(message))),
      );
      _foregroundSub ??= FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null) return;
        final notificationCount = int.tryParse(message.data['badge'] ?? '');
        unawaited(_localNotifications.show(
          id: message.messageId?.hashCode ?? message.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'atta_notifications',
              'Уведомления ATTA',
              channelDescription: 'Сообщения и персональные уведомления ATTA',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              number: notificationCount,
            ),
          ),
          payload: jsonEncode(_payloadFromFcm(message)),
        ));
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null && generation == _generation) {
        await _handleTapPayload(_payloadFromFcm(initial));
      }
    } catch (error) {
      if (kDebugMode) debugPrint('FCM setup failed: $error');
    }
  }

  Map<String, dynamic> _payloadFromFcm(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    final encoded = data['notification'];
    if (encoded is String && encoded.isNotEmpty) {
      try {
        data['notification'] =
            Map<String, dynamic>.from(jsonDecode(encoded) as Map);
      } catch (_) {}
    }
    return data;
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
