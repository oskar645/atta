import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:atta/src/features/auth/auth_gate.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/app_badge_service.dart';

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
            home: const SessionPresenceBinder(child: AuthGate()),
          );
        },
      ),
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
  String? _activeUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnline(true);
    _syncBadge();
    final auth = context.read<AuthService>();
    final badge = context.read<AppBadgeService>();
    final socket = context.read<ChatSocketService>();
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
    });
    _socketSub = socket.events.listen(_handleSocketEvent);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _socketSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleSocketEvent(ChatSocketEvent event) {
    if (event.name != 'notification.new') return;
    final auth = context.read<AuthService>();
    if (auth.currentUser == null || !mounted) return;

    final rawNotification = event.payload['notification'];
    final notification = rawNotification is Map
        ? Map<String, dynamic>.from(rawNotification)
        : Map<String, dynamic>.from(event.payload);
    context.read<NotificationsService>().ingestRealtimeNotification(
          userId: auth.currentUser!.uid,
          notification: notification,
        );
    if ((notification['type'] ?? '').toString().trim().toLowerCase() ==
        'chat_message') {
      context.read<ChatService>().ingestMessageNotification(
            currentUserId: auth.currentUser!.uid,
            notification: notification,
          );
    }
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
      _setOnline(true);
      final auth = context.read<AuthService>();
      final uid = auth.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        context.read<NotificationsService>().refreshActiveSession();
        context.read<ChatService>().handleAppResumed(uid);
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      _setOnline(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
