import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'package:atta/src/features/auth/auth_gate.dart';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/app_badge_service.dart';
import 'package:atta/src/services/deep_link_service.dart';
import 'package:atta/src/services/api/api_exception.dart';

import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/feed_ads_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/main_shell_controller.dart';
import 'package:atta/src/services/notification_navigation_service.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/theme_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/saved_search_service.dart';
import 'package:atta/src/services/support_service.dart';
import 'package:atta/src/services/reports_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/network_recovery_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/promotions_service.dart';
import 'package:atta/src/services/push_notification_service.dart';
import 'package:atta/src/services/showcase_service.dart';
import 'package:atta/src/services/wallet_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';

final RouteObserver<ModalRoute<void>> attaRouteObserver =
    RouteObserver<ModalRoute<void>>();
final GlobalKey<NavigatorState> attaNavigatorKey = GlobalKey<NavigatorState>();
@visibleForTesting
Widget Function(String listingId)? debugDeepLinkListingScreenBuilder;
const Locale attaDefaultLocale = Locale('ru', 'RU');
const List<Locale> attaSupportedLocales = <Locale>[
  attaDefaultLocale,
];
const List<LocalizationsDelegate<dynamic>> attaLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class AttaApp extends StatelessWidget {
  const AttaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B2D33)),
    );

    final darkBase = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2B2D33),
        brightness: Brightness.dark,
      ),
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeService()),

        Provider<AuthService>(create: (_) => AuthService()),
        Provider<DeepLinkService>(
          create: (_) => DeepLinkService(),
          dispose: (_, service) => unawaited(service.dispose()),
        ),
        ChangeNotifierProvider(create: (_) => MainShellController()),
        Provider<ListingsService>(create: (_) => ListingsService()),
        Provider<FollowService>(create: (_) => FollowService()),
        Provider<FavoritesService>(create: (_) => FavoritesService()),
        Provider<FeedAdsService>(create: (_) => FeedAdsService()),
        ChangeNotifierProvider(create: (_) => ListingHistoryService()),
        Provider<ProfileService>(create: (_) => ProfileService()),
        Provider<WalletService>(create: (_) => WalletService()),
        Provider<ShowcaseService>(create: (_) => ShowcaseService()),
        Provider<PromotionsService>(create: (_) => PromotionsService()),
        Provider<ChatSocketService>(
          create: (_) => ChatSocketService(),
          dispose: (_, service) => service.disconnect(),
        ),
        Provider<NetworkRecoveryService>(
          create: (_) => NetworkRecoveryService(),
          dispose: (_, service) => unawaited(service.dispose()),
        ),
        Provider<ChatService>(
          create: (context) =>
              ChatService(socketService: context.read<ChatSocketService>()),
        ),
        Provider<ReviewsService>(create: (_) => ReviewsService()),
        Provider<SavedSearchService>(create: (_) => SavedSearchService()),
        Provider<SupportService>(create: (_) => SupportService()),
        Provider<ReportsService>(create: (_) => ReportsService()),
        Provider<AdminService>(create: (_) => AdminService()),
        Provider<PresenceService>(
          create: (context) =>
              PresenceService(socketService: context.read<ChatSocketService>()),
        ),

// новый сервис уведомлений
        Provider<AppBadgeService>(
          create: (_) => AppBadgeService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<NotificationsService>(create: (_) => NotificationsService()),
        Provider<PushNotificationService>(
          create: (_) => PushNotificationService(),
          dispose: (_, service) => unawaited(service.dispose()),
        ),
      ],
      child: Consumer<ThemeService>(
        builder: (_, theme, __) {
          return MaterialApp(
            title: 'Atta',
            debugShowCheckedModeBanner: false,
            theme: base,
            darkTheme: darkBase,
            themeMode: theme.mode,
            locale: attaDefaultLocale,
            supportedLocales: attaSupportedLocales,
            localizationsDelegates: attaLocalizationsDelegates,
            navigatorKey: attaNavigatorKey,
            builder: (context, child) => AppKeyboardDismissOnTap(
              child: child ?? const SizedBox.shrink(),
            ),
            navigatorObservers: [attaRouteObserver],
            home: const SessionPresenceBinder(child: AuthGate()),
          );
        },
      ),
    );
  }
}

class AppKeyboardDismissOnTap extends StatelessWidget {
  const AppKeyboardDismissOnTap({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}

class SessionPresenceBinder extends StatefulWidget {
  final Widget child;
  const SessionPresenceBinder({super.key, required this.child});

  @override
  State<SessionPresenceBinder> createState() => _SessionPresenceBinderState();
}

class _SessionPresenceBinderState extends State<SessionPresenceBinder>
    with WidgetsBindingObserver {
  StreamSubscription<AuthSessionEvent>? _authSub;
  StreamSubscription<ChatSocketEvent>? _socketSub;
  StreamSubscription<void>? _networkRecoverySub;
  StreamSubscription<AttaDeepLink>? _deepLinkSub;
  Future<void>? _resumeSyncInFlight;
  Future<bool>? _deepLinkOpenInFlight;
  String? _deepLinkOpenListingId;
  String? _activeDeepLinkedListingId;
  String? _activeUid;
  bool _consumePendingListingAfterAuth = false;
  String? _lastOpenedListingId;
  DateTime? _lastOpenedListingAt;
  DateTime? _lastAppOpenMarkedAt;
  late final AuthService _auth;
  late final AppBadgeService _badge;
  late final ChatSocketService _socket;
  late final DeepLinkService _deepLinks;
  late final NotificationsService _notifications;
  late final PushNotificationService _pushNotifications;
  late final AdminService _admin;
  late final SupportService _support;
  late final PresenceService _presence;
  late final ChatService _chats;
  late final FollowService _follow;
  late final FavoritesService _favorites;
  late final ListingHistoryService _listingHistory;
  late final ListingsService _listings;
  late final ProfileService _profile;
  late final ReviewsService _reviews;
  late final WalletService _walletService;
  late final NetworkRecoveryService _networkRecovery;

  static const Duration _deepLinkOpenCooldown = Duration(seconds: 2);

  void _runSoftStartupTask(Future<void> Function() task) {
    unawaited(
      task().catchError((_) {
        // Keep bootstrap resilient when secondary startup work fails.
      }),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = context.read<AuthService>();
    _badge = context.read<AppBadgeService>();
    _socket = context.read<ChatSocketService>();
    _deepLinks = context.read<DeepLinkService>();
    _notifications = context.read<NotificationsService>();
    _pushNotifications = context.read<PushNotificationService>();
    _admin = context.read<AdminService>();
    _support = context.read<SupportService>();
    _presence = context.read<PresenceService>();
    _chats = context.read<ChatService>();
    _follow = context.read<FollowService>();
    _favorites = context.read<FavoritesService>();
    _listingHistory = context.read<ListingHistoryService>();
    _listings = context.read<ListingsService>();
    _profile = context.read<ProfileService>();
    _reviews = context.read<ReviewsService>();
    _walletService = context.read<WalletService>();
    // Some focused widget tests provide the legacy service graph. Recovery is
    // optional there, while production AttaApp always provides the shared
    // instance above.
    _networkRecovery =
        Provider.of<NetworkRecoveryService?>(context, listen: false) ??
            NetworkRecoveryService();
    _setOnline(true);
    _syncBadge();
    _runSoftStartupTask(_markAppOpened);
    _authSub = _auth.onAuthStateChange.listen((_) async {
      final uid = _auth.currentUser?.uid;
      final didChangeUser = _activeUid != null && _activeUid != uid;
      if (uid == null || uid.isEmpty) {
        _activeUid = null;
        _walletService.resetSession();
        _notifications.resetSession();
        await _pushNotifications.unbind(api: _auth.notificationsApi);
        _admin.resetSession();
        _support.resetSession();
        await _presence.resetSession();
        await _chats.resetSession();
        _follow.resetSession();
        _favorites.resetSession();
        _listings.resetSession();
        _profile.resetSession();
        await _listingHistory.resetSession();
        _reviews.resetSession();
        await _badge.clear();
        return;
      }
      if (didChangeUser) {
        _favorites.resetSession();
        _listings.resetSession();
        _profile.resetSession();
        await _listingHistory.resetSession();
      }
      _activeUid = uid;
      final isAdminUser = _auth.currentUser?.isAdmin == true;
      _walletService.activateSession(uid);
      _notifications.activateSession(uid);
      _runSoftStartupTask(
        () => _pushNotifications.bindForUser(
          api: _auth.notificationsApi,
          userId: uid,
        ),
      );
      if (isAdminUser) {
        _admin.activateSession();
        _admin.bindAdminUser(uid);
        _runSoftStartupTask(() => _admin.refreshAdminAttention(force: false));
      } else {
        _admin.resetSession();
      }
      _support.activateAdminSession(isAdmin: isAdminUser);
      _runSoftStartupTask(_markAppOpened);
      _runSoftStartupTask(() => _listingHistory.activateSession());
      _runSoftStartupTask(() => _setOnline(true));
      _runSoftStartupTask(_syncBadge);
      _runSoftStartupTask(() async {
        if (_consumePendingListingAfterAuth) {
          final pendingListingId = await _deepLinks.readPendingListingId();
          if (pendingListingId != null && pendingListingId.isNotEmpty) {
            await _openListingFromDeepLink(
              pendingListingId,
              clearPendingOnSuccess: true,
            );
          }
          _consumePendingListingAfterAuth = false;
        }
        if (!mounted) return;
        await NotificationNavigationService.consumePendingIfPossible(context);
      });
    });
    _socketSub = _socket.events.listen(_handleSocketEvent);
    _networkRecoverySub = _networkRecovery.recoveries.listen((_) {
      unawaited(_handleNetworkRecovered());
    });
    unawaited(_networkRecovery.start());
    _deepLinkSub = _deepLinks.links.listen(_handleDeepLink);
    unawaited(_deepLinks.initialize());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _socketSub?.cancel();
    _networkRecoverySub?.cancel();
    _deepLinkSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _handleDeepLink(AttaDeepLink deepLink) async {
    switch (deepLink.type) {
      case AttaDeepLinkType.listing:
        final listingId = deepLink.listingId ?? '';
        if (listingId.isEmpty) return;
        if (!_auth.isAuthenticated) {
          _consumePendingListingAfterAuth = true;
          await _deepLinks.savePendingListingId(listingId);
          return;
        }
        await _openListingFromDeepLink(
          listingId,
          clearPendingOnSuccess: true,
        );
        break;
      case AttaDeepLinkType.invite:
        final referrerId = deepLink.referrerId ?? '';
        if (referrerId.isEmpty) return;
        await _deepLinks.savePendingInviteReferrerId(
          referrerId,
        );
        break;
    }
  }

  Future<bool> _openListingFromDeepLink(
    String listingId, {
    bool clearPendingOnSuccess = false,
  }) async {
    final normalizedListingId = listingId.trim();
    if (normalizedListingId.isEmpty) return false;
    if (_activeDeepLinkedListingId == normalizedListingId) {
      return true;
    }
    final now = DateTime.now();
    final lastOpenedId = _lastOpenedListingId;
    final lastOpenedAt = _lastOpenedListingAt;
    if (lastOpenedId == normalizedListingId &&
        lastOpenedAt != null &&
        now.difference(lastOpenedAt) < _deepLinkOpenCooldown) {
      return true;
    }
    if (_deepLinkOpenListingId == normalizedListingId &&
        _deepLinkOpenInFlight != null) {
      return _deepLinkOpenInFlight!;
    }

    final future = _openListingFromDeepLinkImpl(
      normalizedListingId,
      clearPendingOnSuccess: clearPendingOnSuccess,
    );
    _deepLinkOpenListingId = normalizedListingId;
    _deepLinkOpenInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_deepLinkOpenInFlight, future)) {
        _deepLinkOpenInFlight = null;
        _deepLinkOpenListingId = null;
      }
    }
  }

  Future<bool> _openListingFromDeepLinkImpl(
    String listingId, {
    required bool clearPendingOnSuccess,
  }) async {
    final navigator = attaNavigatorKey.currentState;
    final navContext = attaNavigatorKey.currentContext;
    if (navigator == null || navContext == null) {
      return false;
    }

    try {
      final listing = await _listings.getListingById(listingId);
      if (!mounted || !navContext.mounted) return false;
      if (listing == null) {
        if (clearPendingOnSuccess) {
          await _deepLinks.clearPendingListingIdIfMatches(listingId);
        }
        if (!navContext.mounted) return false;
        showAppSnack(
          navContext,
          'Объявление недоступно',
          isError: true,
        );
        return false;
      }
    } on ApiException catch (error) {
      if (!mounted || !navContext.mounted) return false;
      if (error.isNotFound && clearPendingOnSuccess) {
        await _deepLinks.clearPendingListingIdIfMatches(listingId);
      }
      if (!navContext.mounted) return false;
      showAppSnack(
        navContext,
        'Объявление недоступно',
        isError: true,
      );
      return false;
    } catch (_) {
      if (!mounted || !navContext.mounted) return false;
      showAppSnack(
        navContext,
        'Объявление недоступно',
        isError: true,
      );
      return false;
    }

    final now = DateTime.now();
    _lastOpenedListingId = listingId;
    _lastOpenedListingAt = now;
    _activeDeepLinkedListingId = listingId;
    navigator
        .push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: 'deep-link-listing:$listingId'),
        builder: (_) =>
            debugDeepLinkListingScreenBuilder?.call(listingId) ??
            ListingDetailScreen(listingId: listingId),
      ),
    )
        .then((_) {
      if (_activeDeepLinkedListingId == listingId) {
        _activeDeepLinkedListingId = null;
      }
    });
    if (clearPendingOnSuccess) {
      await _deepLinks.clearPendingListingIdIfMatches(listingId);
    }
    return true;
  }

  void _handleSocketEvent(ChatSocketEvent event) {
    if (event.name != 'notification.new') return;
    if (_auth.currentUser == null || !mounted) return;

    final rawNotification = event.payload['notification'];
    final notification = rawNotification is Map
        ? Map<String, dynamic>.from(rawNotification)
        : Map<String, dynamic>.from(event.payload);
    final notificationType =
        (notification['type'] ?? '').toString().trim().toLowerCase();
    if (notificationType == 'chat_message' ||
        notificationType == 'message' ||
        notificationType == 'chat') {
      _chats.ingestMessageNotification(
        currentUserId: _auth.currentUser!.uid,
        notification: notification,
      );
      return;
    }
    if (notificationType == 'moderation') {
      _handleModerationNotification(notification);
    }
    _notifications.ingestRealtimeNotification(
      userId: _auth.currentUser!.uid,
      notification: notification,
    );
  }

  void _handleModerationNotification(Map<String, dynamic> notification) {
    final payload = notification['payload'];
    final payloadMap = payload is Map
        ? payload.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final listingId = (payloadMap['listingId'] ??
            payloadMap['listing_id'] ??
            notification['listing_id'] ??
            notification['listingId'] ??
            '')
        .toString()
        .trim();
    if (listingId.isEmpty) {
      return;
    }
    unawaited(
      _listings.refreshListingById(listingId),
    );
  }

  Future<void> _setOnline(bool online) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    await _presence.setOnline(uid: uid, isOnline: online);
  }

  Future<void> _markAppOpened() async {
    if (_auth.currentUser == null) {
      return;
    }
    final now = DateTime.now();
    final lastMarkedAt = _lastAppOpenMarkedAt;
    if (lastMarkedAt != null &&
        now.difference(lastMarkedAt) < const Duration(minutes: 5)) {
      return;
    }
    _lastAppOpenMarkedAt = now;
    await _auth.markAppOpened();
  }

  Future<void> _syncBadge() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _activeUid = null;
      _walletService.resetSession();
      _notifications.resetSession();
      await _pushNotifications.unbind(api: _auth.notificationsApi);
      _support.resetSession();
      _favorites.resetSession();
      _listings.resetSession();
      _profile.resetSession();
      await _listingHistory.resetSession();
      await _badge.clear();
      return;
    }

    _activeUid = uid;
    final isAdminUser = _auth.currentUser?.isAdmin == true;
    _walletService.activateSession(uid);
    _notifications.activateSession(uid);
    _runSoftStartupTask(
      () => _pushNotifications.bindForUser(
        api: _auth.notificationsApi,
        userId: uid,
      ),
    );
    if (isAdminUser) {
      _admin.activateSession();
      _admin.bindAdminUser(uid);
      _runSoftStartupTask(() => _admin.refreshAdminAttention(force: false));
    } else {
      _admin.resetSession();
    }
    _support.activateAdminSession(isAdmin: isAdminUser);
    _runSoftStartupTask(() => _listingHistory.activateSession());
    await _badge.bindForUser(
      userId: uid,
      chatService: _chats,
      notificationsService: _notifications,
    );
    _runSoftStartupTask(() async {
      await _walletService.maybeCheckAccrualOncePerSession();
      final context = attaNavigatorKey.currentContext;
      if (_walletService.lastAccrualAwarded &&
          mounted &&
          context != null &&
          context.mounted) {
        showAppSnack(context, 'Ежедневный бонус: +25');
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kDebugMode) {
      debugPrint('AppLifecycleState: $state');
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleAppResumed());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      _setOnline(false);
    }
  }

  Future<void> _handleAppResumed() async {
    final existing = _resumeSyncInFlight;
    if (existing != null) {
      return existing;
    }

    final future = () async {
      final restoredUser = await _auth.restoreSessionOnResume(force: true);
      if (!mounted) return;
      final uid = restoredUser?.uid ?? _auth.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        return;
      }
      _runSoftStartupTask(() => _presence.recoverAfterResume(uid));
      _runSoftStartupTask(() => _chats.handleAppResumed(uid));
      _runSoftStartupTask(
        () => _notifications.refreshActiveSession(
          force: true,
        ),
      );
      _runSoftStartupTask(
        () => _pushNotifications.bindForUser(
          api: _auth.notificationsApi,
          userId: uid,
        ),
      );
      if ((_auth.currentUser?.isAdmin ?? restoredUser?.isAdmin) == true) {
        _admin.activateSession();
        _admin.bindAdminUser(uid);
        _runSoftStartupTask(() => _admin.refreshAdminAttention(force: true));
      }
      _runSoftStartupTask(_markAppOpened);
      _runSoftStartupTask(_syncBadge);
    }();
    _resumeSyncInFlight = future;
    try {
      await future;
    } catch (_) {
      // Soft-fail on resume to avoid false logout or UI breakage.
    } finally {
      if (identical(_resumeSyncInFlight, future)) {
        _resumeSyncInFlight = null;
      }
    }
  }

  Future<void> _handleNetworkRecovered() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    // A route change can leave a TCP socket marked as connected even though it
    // belongs to the old network. Recreate it before reloading chat data.
    _runSoftStartupTask(() => _chats.handleNetworkChanged(uid));
    _runSoftStartupTask(() => _notifications.refreshActiveSession(force: true));
    if (_auth.currentUser?.isAdmin == true) {
      _admin.activateSession();
      _admin.bindAdminUser(uid);
      _runSoftStartupTask(() => _admin.refreshAdminAttention(force: true));
    }
    _runSoftStartupTask(_syncBadge);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
