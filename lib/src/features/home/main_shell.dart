import 'dart:async';

import 'package:atta/src/features/favorites/favorites_screen.dart';
import 'package:atta/src/features/auth/guest_auth_prompt.dart';
import 'package:atta/src/features/home/home_screen.dart';
import 'package:atta/src/features/inbox/inbox_screen.dart';
import 'package:atta/src/features/listings/my_listings_screen.dart';
import 'package:atta/src/features/profile/profile_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/main_shell_controller.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/web_app_promo_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

void _debugMyListingsMainShellLog(String message) {
  assert(() {
    debugPrint('[MYLIST] $message');
    return true;
  }());
}

bool _coldStartVpnBannerClaimed = false;

bool _claimColdStartVpnBanner() {
  if (_coldStartVpnBannerClaimed) return false;
  _coldStartVpnBannerClaimed = true;
  return true;
}

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    this.initialIndex = 0,
    this.pageBuilder,
    this.guestMode = false,
  });

  final int initialIndex;
  final Widget Function(int index, HomeTabController controller)? pageBuilder;
  final bool guestMode;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _i = widget.initialIndex;
  Timer? _presenceTimer;
  final _homeTabController = HomeTabController();
  AuthService? _auth;
  MainShellController? _shellController;
  PresenceService? _presence;
  String? _presenceUid;
  late final Set<int> _visitedTabs = <int>{0, widget.initialIndex};
  bool _didCheckWebPromo = false;
  late final bool _showColdStartVpnBanner = _claimColdStartVpnBanner();

  static const _inactive = Color(0xFF8E95A3);
  static const _search = Colors.blue;
  static const _fav = Colors.red;
  static const _listings = Colors.blue;
  static const _msgs = Colors.blue;
  static const _profile = Color.fromARGB(221, 2, 71, 23);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _startPresenceHeartbeatIfNeeded();
      _maybeShowWebAppPromo();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _auth ??= context.read<AuthService>();
    _presence ??= context.read<PresenceService>();
    final nextController = context.read<MainShellController>();
    if (!identical(_shellController, nextController)) {
      _shellController?.removeListener(_handleExternalTabSelection);
      _shellController = nextController;
      _i = nextController.selectedIndex;
      _visitedTabs.add(_i);
      _shellController?.addListener(_handleExternalTabSelection);
    }
  }

  @override
  void dispose() {
    _stopPresenceHeartbeat();
    _shellController?.removeListener(_handleExternalTabSelection);
    final presence = _presence;
    final uid = _presenceUid;
    if (uid != null && uid.isNotEmpty && presence != null) {
      presence.setOnline(uid: uid, isOnline: false);
    }
    super.dispose();
  }

  Future<void> _startPresenceHeartbeatIfNeeded() async {
    final auth = _auth;
    final presence = _presence;
    if (auth == null || presence == null) return;
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;
    if (_presenceTimer != null && _presenceUid == uid) {
      return;
    }
    _stopPresenceHeartbeat();
    _presenceUid = uid;
    await presence.setOnline(uid: uid, isOnline: true);
    if (!mounted || auth.currentUser?.uid != uid || _presenceUid != uid) return;
    _presenceTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      presence.heartbeat(uid);
    });
  }

  void _stopPresenceHeartbeat() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
  }

  Future<void> _maybeShowWebAppPromo() async {
    if (!kIsWeb || _didCheckWebPromo || !mounted) return;
    _didCheckWebPromo = true;
    if (!shouldShowWebAppPromo()) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _WebAppPromoDialog(),
    );
  }

  Widget _dotIcon(Widget icon, bool show) {
    if (!show) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        const Positioned(
          right: -1,
          top: -1,
          child: Icon(Icons.brightness_1, size: 9, color: Colors.red),
        ),
      ],
    );
  }

  void _handleExternalTabSelection() {
    final controller = _shellController;
    if (controller == null || !mounted || controller.selectedIndex == _i) {
      return;
    }
    setState(() {
      _i = controller.selectedIndex;
      _visitedTabs.add(_i);
    });
  }

  Future<void> _onDestinationSelected(int v) async {
    if (v == 2) {
      _debugMyListingsMainShellLog('MAIN_TAB_OPEN');
    }
    if (v == 0) {
      if (_i != 0) {
        setState(() => _i = 0);
        _shellController?.selectTab(0);
        return;
      }

      _homeTabController.scrollToTop();
      return;
    }

    if (v == _i) return;
    if (widget.guestMode && v != 0) {
      final authenticated = await promptGuestAuth(context);
      if (!authenticated || !mounted) return;
    }
    setState(() {
      _i = v;
      _visitedTabs.add(v);
    });
    _shellController?.selectTab(v);
  }

  Widget _buildPage(int index) {
    final customPageBuilder = widget.pageBuilder;
    if (customPageBuilder != null) {
      return customPageBuilder(index, _homeTabController);
    }
    switch (index) {
      case 0:
        return HomeScreen(
          controller: _homeTabController,
          showColdStartVpnBanner: _showColdStartVpnBanner && _i == 0,
        );
      case 1:
        return const FavoritesScreen();
      case 2:
        return const MyListingsScreen();
      case 3:
        return const InboxScreen();
      case 4:
        return const ProfileScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final chat = context.read<ChatService>();
    final admin = context.read<AdminService>();
    final notifications = context.read<NotificationsService>();
    final uid = auth.currentUser?.uid ?? '';

    final navTheme = NavigationBarThemeData(
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w400,
          height: 1.2,
          color: selected ? null : _inactive,
        );
      }),
      height: 64,
      indicatorColor: Colors.transparent,
    );

    return Scaffold(
      body: IndexedStack(
        index: _i,
        children: List<Widget>.generate(5, (index) {
          if (!_visitedTabs.contains(index)) {
            return const SizedBox.shrink();
          }
          return _buildPage(index);
        }),
      ),
      bottomNavigationBar: StreamBuilder<int>(
        stream: widget.guestMode
            ? const Stream<int>.empty()
            : chat.streamUnreadTotal(uid),
        builder: (context, chatSnap) {
          final unreadChats = chatSnap.data ?? 0;

          Widget msgIcon(Color color) {
            final icon = Icon(Icons.chat_bubble_outline, color: color);
            if (unreadChats <= 0) return icon;
            return Badge(
              label: Text(unreadChats > 99 ? '99+' : '$unreadChats'),
              child: icon,
            );
          }

          return StreamBuilder<int>(
            stream: widget.guestMode
                ? const Stream<int>.empty()
                : notifications.streamUnreadSavedSearchCount(uid),
            builder: (context, savedSnap) {
              final hasSavedSearchAlerts = (savedSnap.data ?? 0) > 0;

              return StreamBuilder<bool>(
                stream: admin.streamIsAdmin(uid),
                builder: (context, adminSnap) {
                  final isAdmin = adminSnap.data == true;

                  return StreamBuilder<bool>(
                    stream: isAdmin
                        ? admin.streamNeedsAttention()
                        : const Stream<bool>.empty(),
                    initialData: false,
                    builder: (context, attentionSnap) {
                      final hasAdminAlert =
                          isAdmin && (attentionSnap.data == true);

                      return SafeArea(
                        top: false,
                        child: NavigationBarTheme(
                          data: navTheme,
                          child: NavigationBar(
                            selectedIndex: _i,
                            onDestinationSelected: _onDestinationSelected,
                            destinations: [
                              const NavigationDestination(
                                icon: Icon(Icons.search, color: _inactive),
                                selectedIcon:
                                    Icon(Icons.search, color: _search),
                                label: 'Поиск',
                              ),
                              NavigationDestination(
                                icon: _dotIcon(
                                  const Icon(Icons.favorite_border,
                                      color: _inactive),
                                  hasSavedSearchAlerts,
                                ),
                                selectedIcon: _dotIcon(
                                  const Icon(Icons.favorite, color: _fav),
                                  hasSavedSearchAlerts,
                                ),
                                label: 'Избранное',
                              ),
                              const NavigationDestination(
                                icon: Icon(Icons.list_alt, color: _inactive),
                                selectedIcon:
                                    Icon(Icons.list_alt, color: _listings),
                                label: 'Объявления',
                              ),
                              NavigationDestination(
                                icon: msgIcon(_inactive),
                                selectedIcon: msgIcon(_msgs),
                                label: 'Сообщения',
                              ),
                              NavigationDestination(
                                icon: _dotIcon(
                                  const Icon(Icons.person_outline,
                                      color: _inactive),
                                  hasAdminAlert,
                                ),
                                selectedIcon: _dotIcon(
                                  const Icon(Icons.person, color: _profile),
                                  hasAdminAlert,
                                ),
                                label: 'Профиль',
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _WebAppPromoDialog extends StatelessWidget {
  const _WebAppPromoDialog();

  Future<void> _openStore(String url) async {
    markWebAppPromoDismissed();
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _close(BuildContext context) {
    markWebAppPromoDismissed();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      onPopInvokedWithResult: (_, __) => markWebAppPromoDismissed(),
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 18, 8, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Атта удобнее в приложении',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Закрыть',
              onPressed: () => _close(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: const Text(
          'Скачайте приложение или продолжайте пользоваться Атта в браузере.',
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _openStore(webAppPromoAppStoreUrl),
            icon: const Icon(Icons.apple),
            label: const Text('Загрузить в App Store'),
          ),
          TextButton.icon(
            onPressed: () => _openStore(webAppPromoGooglePlayUrl),
            icon: const Icon(Icons.shop),
            label: const Text('Доступно в Google Play'),
          ),
          FilledButton(
            onPressed: () => _close(context),
            child: const Text('Продолжить в браузере'),
          ),
        ],
      ),
    );
  }
}
