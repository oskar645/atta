import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:atta/src/features/auth/auth_gate.dart';
import 'package:atta/src/services/admin_service.dart';

import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/feed_ads_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/theme_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/support_service.dart';
import 'package:atta/src/services/reports_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/presence_service.dart';

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
        Provider<ListingsService>(create: (_) => ListingsService()),
        Provider<FavoritesService>(create: (_) => FavoritesService()),
        Provider<FeedAdsService>(create: (_) => FeedAdsService()),
        ChangeNotifierProvider(create: (_) => ListingHistoryService()),
        Provider<ProfileService>(create: (_) => ProfileService()),
        Provider<ChatService>(create: (_) => ChatService()),
        Provider<ReviewsService>(create: (_) => ReviewsService()),
        Provider<SupportService>(create: (_) => SupportService()),
        Provider<ReportsService>(create: (_) => ReportsService()),
        Provider<AdminService>(create: (_) => AdminService()),
        Provider<PresenceService>(create: (_) => PresenceService()),

// новый сервис уведомлений
        Provider<NotificationsService>(create: (_) => NotificationsService()),
      ],
      child: Consumer<ThemeService>(
        builder: (_, theme, __) {
          return MaterialApp(
            title: 'ATTA',
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
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnline(true);
    final auth = context.read<AuthService>();
    _authSub = auth.onAuthStateChange.listen((_) async {
      final uid = auth.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      await _setOnline(true);
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _setOnline(bool online) async {
    final auth = context.read<AuthService>();
    final presence = context.read<PresenceService>();
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    await presence.setOnline(uid: uid, isOnline: online);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnline(true);
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
