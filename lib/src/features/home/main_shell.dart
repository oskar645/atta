import 'dart:async';

import 'package:atta/src/features/favorites/favorites_screen.dart';
import 'package:atta/src/features/home/home_screen.dart';
import 'package:atta/src/features/inbox/inbox_screen.dart';
import 'package:atta/src/features/listings/my_listings_screen.dart';
import 'package:atta/src/features/profile/profile_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _i = 0;
  Timer? _presenceTimer;

  final _pages = const [
    HomeScreen(),
    FavoritesScreen(),
    MyListingsScreen(),
    InboxScreen(),
    ProfileScreen(),
  ];

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
      final auth = context.read<AuthService>();
      final presence = context.read<PresenceService>();
      final uid = auth.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      await presence.setOnline(uid: uid, isOnline: true);
      _presenceTimer = Timer.periodic(const Duration(seconds: 45), (_) {
        presence.heartbeat(uid);
      });
    });
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    final auth = context.read<AuthService>();
    final presence = context.read<PresenceService>();
    final uid = auth.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      presence.setOnline(uid: uid, isOnline: false);
    }
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final chat = context.read<ChatService>();
    final admin = context.read<AdminService>();
    final uid = auth.currentUser!.uid;

    final navTheme = NavigationBarThemeData(
      labelTextStyle: MaterialStateProperty.resolveWith<TextStyle?>((states) {
        final selected = states.contains(MaterialState.selected);
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
      body: _pages[_i],
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

          return StreamBuilder<bool>(
            stream: admin.streamIsAdmin(uid),
            builder: (context, adminSnap) {
              final isAdmin = adminSnap.data == true;

              return StreamBuilder<bool>(
                stream: isAdmin ? admin.streamNeedsAttention() : const Stream<bool>.empty(),
                initialData: false,
                builder: (context, attentionSnap) {
                  final hasAdminAlert = isAdmin && (attentionSnap.data == true);

                  return SafeArea(
                    top: false,
                    child: NavigationBarTheme(
                      data: navTheme,
                      child: NavigationBar(
                        selectedIndex: _i,
                        onDestinationSelected: (v) => setState(() => _i = v),
                        destinations: [
                          const NavigationDestination(
                            icon: Icon(Icons.search, color: _inactive),
                            selectedIcon: Icon(Icons.search, color: _search),
                            label: 'Поиск',
                          ),
                          const NavigationDestination(
                            icon: Icon(Icons.favorite_border, color: _inactive),
                            selectedIcon: Icon(Icons.favorite, color: _fav),
                            label: 'Избранное',
                          ),
                          const NavigationDestination(
                            icon: Icon(Icons.list_alt, color: _inactive),
                            selectedIcon: Icon(Icons.list_alt, color: _listings),
                            label: 'Объявления',
                          ),
                          NavigationDestination(
                            icon: msgIcon(_inactive),
                            selectedIcon: msgIcon(_msgs),
                            label: 'Сообщения',
                          ),
                          NavigationDestination(
                            icon: _dotIcon(
                              const Icon(Icons.person_outline, color: _inactive),
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
      ),
    );
  }
}
