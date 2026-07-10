import 'dart:async';

import 'package:atta/src/features/favorites/favorites_screen.dart';
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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    this.initialIndex = 0,
    this.pageBuilder,
  });

  final int initialIndex;
  final Widget Function(int index, HomeTabController controller)? pageBuilder;

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
      _shellController?.addListener(_handleExternalTabSelection);
    }
  }

  @override
  void dispose() {
    _stopPresenceHeartbeat();
    _shellController?.removeListener(_handleExternalTabSelection);
    final presence = _presence;
    final uid = _presenceUid;
    if (uid != null && uid.isNotEmpty) {
      presence?.setOnline(uid: uid, isOnline: false);
    }
    super.dispose();
  }

  Future<void> _startPresenceHeartbeatIfNeeded() async {
    final auth = _auth;
    final presence = _presence;
    if (auth == null || presence == null) return;
    final uid = auth.currentUser?.uid?.trim() ?? '';
    if (uid.isEmpty) return;
    if (_presenceTimer != null && _presenceUid == uid) {
      return;
    }
    _stopPresenceHeartbeat();
    _presenceUid = uid;
    await presence.setOnline(uid: uid, isOnline: true);
    _presenceTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      presence.heartbeat(uid);
    });
  }

  void _stopPresenceHeartbeat() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
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

  void _onDestinationSelected(int v) {
    if (v == 0) {
      if (_i != 0) {
        setState(() => _i = 0);
        _shellController?.selectTab(0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _homeTabController.scrollToTop();
        });
        return;
      }

      _homeTabController.scrollToTop();
      return;
    }

    if (v == _i) return;
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
        return HomeScreen(controller: _homeTabController);
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
    final uid = auth.currentUser!.uid;

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
        stream: chat.streamUnreadTotal(uid),
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
            stream: notifications.streamUnreadSavedSearchCount(uid),
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
