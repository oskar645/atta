import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:atta/src/widgets/remote_avatar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminOnlineUsersScreen extends StatefulWidget {
  const AdminOnlineUsersScreen({super.key});

  @override
  State<AdminOnlineUsersScreen> createState() => _AdminOnlineUsersScreenState();
}

class _AdminOnlineUsersScreenState extends State<AdminOnlineUsersScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load({bool forceRefresh = false}) async {
    final response = await context
        .read<AdminService>()
        .onlineUsers(forceRefresh: forceRefresh);
    final raw = response['items'];
    final items = raw is! List
        ? const <Map<String, dynamic>>[]
        : raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
    if (mounted) {
      setState(() {
        _items = items;
      });
    } else {
      _items = items;
    }
    return items;
  }

  Future<void> _refresh() async {
    final next = _load(forceRefresh: true);
    setState(() {
      _future = next;
    });
    await next;
  }

  String _value(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String _formatLastSeen(Map<String, dynamic> item) {
    final raw = _value(item, const ['last_seen_at']);
    final dt = DateTime.tryParse(raw);
    if (dt == null) {
      return '';
    }
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сейчас онлайн')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && _items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError && _items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Не удалось загрузить онлайн-пользователей.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            );
          }

          final items = _items.isNotEmpty
              ? _items
              : (snap.data ?? const <Map<String, dynamic>>[]);
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  Center(child: Text('Сейчас онлайн пользователей нет.')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                final userId = _value(item, const ['id']);
                final displayName =
                    _value(item, const ['display_name', 'name', 'phone']);
                final avatarUrl = _value(item, const ['avatar_url']);
                final phone = formatRussianPhone(_value(item, const ['phone']));
                final lastSeen = _formatLastSeen(item);

                return Card(
                  child: ListTile(
                    onTap: userId.isEmpty
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SellerPublicProfileScreen(
                                  sellerId: userId,
                                  showAdminFields: true,
                                ),
                              ),
                            ),
                    leading: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        RemoteAvatar(
                          imageUrl: avatarUrl,
                          radius: 24,
                          fallbackText: displayName.isEmpty
                              ? '?'
                              : displayName.characters.first.toUpperCase(),
                        ),
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.surface,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    title: Text(
                      displayName.isEmpty ? 'Пользователь' : displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (phone.isNotEmpty) Text(phone),
                        Text('User ID: $userId'),
                        if (lastSeen.isNotEmpty) Text('Был в сети: $lastSeen'),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
