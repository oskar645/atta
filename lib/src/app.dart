import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'package:atta/src/features/auth/auth_gate.dart';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/app_badge_service.dart';
import 'package:atta/src/services/deep_link_service.dart';

import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/feed_ads_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/main_shell_controller.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/theme_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/saved_search_service.dart';
import 'package:atta/src/services/support_service.dart';
import 'package:atta/src/services/reports_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/promotions_service.dart';
import 'package:atta/src/services/showcase_service.dart';
import 'package:atta/src/services/wallet_service.dart';

final RouteObserver<ModalRoute<void>> attaRouteObserver =
    RouteObserver<ModalRoute<void>>();
final GlobalKey<NavigatorState> attaNavigatorKey = GlobalKey<NavigatorState>();
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
  StreamSubscription<bool>? _socketConnectionSub;
  StreamSubscription<AttaDeepLink>? _deepLinkSub;
  Future<void>? _resumeSyncInFlight;
  Future<void>? _socketRestoreInFlight;
  String? _activeUid;
  DateTime? _lastResumeSyncAt;
  DateTime? _lastSocketRestoreAt;
  String? _lastOpenedListingId;
  DateTime? _lastOpenedListingAt;

  static const Duration _resumeSyncCooldown = Duration(seconds: 45);
  static const Duration _socketRestoreCooldown = Duration(seconds: 30);
  static const Duration _deepLinkOpenCooldown = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnline(true);
    _syncBadge();
    final auth = context.read<AuthService>();
    final badge = context.read<AppBadgeService>();
    final socket = context.read<ChatSocketService>();
    final deepLinks = context.read<DeepLinkService>();
    final notifications = context.read<NotificationsService>();
    final admin = context.read<AdminService>();
    final support = context.read<SupportService>();
    final presence = context.read<PresenceService>();
    final chats = context.read<ChatService>();
    final follow = context.read<FollowService>();
    final favorites = context.read<FavoritesService>();
    final listingHistory = context.read<ListingHistoryService>();
    final listings = context.read<ListingsService>();
    final profile = context.read<ProfileService>();
    final reviews = context.read<ReviewsService>();
    final walletService = context.read<WalletService>();
    _authSub = auth.onAuthStateChange.listen((_) async {
      final uid = auth.currentUser?.uid;
      final didChangeUser = _activeUid != null && _activeUid != uid;
      if (uid == null || uid.isEmpty) {
        _activeUid = null;
        walletService.resetSession();
        notifications.resetSession();
        admin.resetSession();
        support.resetSession();
        await presence.resetSession();
        await chats.resetSession();
        follow.resetSession();
        favorites.resetSession();
        listings.resetSession();
        profile.resetSession();
        await listingHistory.resetSession();
        reviews.resetSession();
        await badge.clear();
        return;
      }
      if (didChangeUser) {
        favorites.resetSession();
        listings.resetSession();
        profile.resetSession();
        await listingHistory.resetSession();
      }
      _activeUid = uid;
      walletService.activateSession(uid);
      notifications.activateSession(uid);
      admin.activateSession();
      support.activateAdminSession(isAdmin: auth.currentUser?.isAdmin == true);
      await listingHistory.activateSession();
      await _setOnline(true);
      await _syncBadge();
      final pendingListingId = await deepLinks.consumePendingListingId();
      if (pendingListingId != null && pendingListingId.isNotEmpty) {
        await _openListingFromDeepLink(pendingListingId);
      }
    });
    _socketSub = socket.events.listen(_handleSocketEvent);
    _socketConnectionSub = socket.connectionChanges.listen(
      _handleSocketConnectionChanged,
    );
    _deepLinkSub = deepLinks.links.listen(_handleDeepLink);
    unawaited(deepLinks.initialize());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _socketSub?.cancel();
    _socketConnectionSub?.cancel();
    _deepLinkSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleSocketConnectionChanged(bool connected) {
    if (!connected) return;
    unawaited(_handleSocketRestored());
  }

  Future<void> _handleDeepLink(AttaDeepLink deepLink) async {
    switch (deepLink.type) {
      case AttaDeepLinkType.listing:
        final listingId = deepLink.listingId ?? '';
        if (listingId.isEmpty) return;
        if (!context.read<AuthService>().isAuthenticated) {
          await context.read<DeepLinkService>().savePendingListingId(listingId);
        }
        await _openListingFromDeepLink(listingId);
        break;
      case AttaDeepLinkType.invite:
        final referrerId = deepLink.referrerId ?? '';
        if (referrerId.isEmpty) return;
        await context.read<DeepLinkService>().savePendingInviteReferrerId(
              referrerId,
            );
        break;
    }
  }

  Future<void> _openListingFromDeepLink(String listingId) async {
    final normalizedListingId = listingId.trim();
    if (normalizedListingId.isEmpty) return;
    final now = DateTime.now();
    final lastOpenedId = _lastOpenedListingId;
    final lastOpenedAt = _lastOpenedListingAt;
    if (lastOpenedId == normalizedListingId &&
        lastOpenedAt != null &&
        now.difference(lastOpenedAt) < _deepLinkOpenCooldown) {
      return;
    }
    final navigator = attaNavigatorKey.currentState;
    final navContext = attaNavigatorKey.currentContext;
    if (navigator == null || navContext == null) {
      return;
    }
    _lastOpenedListingId = normalizedListingId;
    _lastOpenedListingAt = now;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ListingDetailScreen(listingId: normalizedListingId),
      ),
    );
  }

  void _handleSocketEvent(ChatSocketEvent event) {
    if (event.name != 'notification.new') return;
    final auth = context.read<AuthService>();
    if (auth.currentUser == null || !mounted) return;

    final rawNotification = event.payload['notification'];
    final notification = rawNotification is Map
        ? Map<String, dynamic>.from(rawNotification)
        : Map<String, dynamic>.from(event.payload);
    final notificationType =
        (notification['type'] ?? '').toString().trim().toLowerCase();
    if (notificationType == 'chat_message' ||
        notificationType == 'message' ||
        notificationType == 'chat') {
      context.read<ChatService>().ingestMessageNotification(
            currentUserId: auth.currentUser!.uid,
            notification: notification,
          );
      return;
    }
    if (notificationType == 'moderation') {
      _handleModerationNotification(notification);
    }
    context.read<NotificationsService>().ingestRealtimeNotification(
          userId: auth.currentUser!.uid,
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
      context.read<ListingsService>().refreshListingById(listingId),
    );
  }

  Future<void> _setOnline(bool online) async {
    final auth = context.read<AuthService>();
    final presence = context.read<PresenceService>();
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    await presence.setOnline(uid: uid, isOnline: online);
  }

  Future<void> _syncBadge() async {
    final auth = context.read<AuthService>();
    final uid = auth.currentUser?.uid;
    final badge = context.read<AppBadgeService>();
    final walletService = context.read<WalletService>();
    final notifications = context.read<NotificationsService>();
    final support = context.read<SupportService>();
    final admin = context.read<AdminService>();
    final listingHistory = context.read<ListingHistoryService>();
    final chatService = context.read<ChatService>();
    if (uid == null || uid.isEmpty) {
      _activeUid = null;
      walletService.resetSession();
      notifications.resetSession();
      support.resetSession();
      context.read<FavoritesService>().resetSession();
      context.read<ListingsService>().resetSession();
      context.read<ProfileService>().resetSession();
      await listingHistory.resetSession();
      await badge.clear();
      return;
    }

    _activeUid = uid;
    walletService.activateSession(uid);
    notifications.activateSession(uid);
    admin.activateSession();
    support.activateAdminSession(isAdmin: auth.currentUser?.isAdmin == true);
    await listingHistory.activateSession();
    await badge.bindForUser(
      userId: uid,
      chatService: chatService,
      notificationsService: notifications,
    );

    await walletService.maybeCheckAccrualOncePerSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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

    final now = DateTime.now();
    final lastResumeAt = _lastResumeSyncAt;
    if (lastResumeAt != null &&
        now.difference(lastResumeAt) < _resumeSyncCooldown) {
      return;
    }

    final future = () async {
      await _setOnline(true);
      final auth = context.read<AuthService>();
      final restoredUser = await auth.restoreSessionOnResume(force: true);
      final uid = restoredUser?.uid ?? auth.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        return;
      }
      await context.read<ChatService>().handleAppResumed(uid);
      await context.read<NotificationsService>().refreshActiveSession(
            force: true,
          );
      await _syncBadge();
      _lastResumeSyncAt = DateTime.now();
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

  Future<void> _handleSocketRestored() async {
    final existing = _socketRestoreInFlight;
    if (existing != null) {
      return existing;
    }
    final auth = context.read<AuthService>();
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final lastRestoreAt = _lastSocketRestoreAt;
    if (lastRestoreAt != null &&
        now.difference(lastRestoreAt) < _socketRestoreCooldown) {
      return;
    }
    final future = () async {
      _lastSocketRestoreAt = DateTime.now();
      await _setOnline(true);
      await context.read<ChatService>().handleAppResumed(uid);
      await context.read<NotificationsService>().refreshActiveSession(
            force: false,
          );
    }();
    _socketRestoreInFlight = future;
    try {
      await future;
    } catch (_) {
      // Soft-fail to preserve active session across temporary network changes.
    } finally {
      if (identical(_socketRestoreInFlight, future)) {
        _socketRestoreInFlight = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
