import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:atta/src/widgets/remote_avatar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminTodayVisitsScreen extends StatefulWidget {
  const AdminTodayVisitsScreen({super.key});

  @override
  State<AdminTodayVisitsScreen> createState() => _AdminTodayVisitsScreenState();
}

class _AdminTodayVisitsScreenState extends State<AdminTodayVisitsScreen> {
  late Future<Map<String, dynamic>> _future;
  Map<String, dynamic>? _response;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load({bool forceRefresh = false}) async {
    final response = await context
        .read<AdminService>()
        .todayVisits(forceRefresh: forceRefresh);
    if (mounted) {
      setState(() {
        _response = response;
      });
    } else {
      _response = response;
    }
    return response;
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

  String _formatTime(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) {
      return '';
    }
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> response) {
    final raw = response['items'];
    return raw is! List
        ? const <Map<String, dynamic>>[]
        : raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сегодня заходили')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          final response = _response ?? snap.data;
          if (snap.connectionState != ConnectionState.done &&
              response == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError && response == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Не удалось загрузить список посещений.',
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

          final data = response ?? const <String, dynamic>{};
          final items = _items(data);
          final countRaw = data['count'];
          final count = countRaw is num
              ? countRaw.toInt()
              : int.tryParse((countRaw ?? '').toString()) ?? items.length;
          final updatedAt =
              _formatTime((data['last_updated_at'] ?? '').toString().trim());

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: items.isEmpty ? 2 : items.length + 1,
              separatorBuilder: (_, index) =>
                  SizedBox(height: index == 0 ? 8 : 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Сегодня заходили: $count пользователей',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            updatedAt.isEmpty
                                ? 'Последнее обновление: -'
                                : 'Последнее обновление: $updatedAt',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 120),
                    child: Center(
                      child: Text('Сегодня пользователи еще не заходили.'),
                    ),
                  );
                }

                final item = items[index - 1];
                final userId = _value(item, const ['id']);
                final displayName =
                    _value(item, const ['display_name', 'name', 'phone']);
                final avatarUrl = _value(item, const ['avatar_url']);
                final phone = formatRussianPhone(_value(item, const ['phone']));
                final lastActivity =
                    _formatTime(_value(item, const ['last_activity_at']));
                final isOnline = item['is_online'] == true;

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
                              color: isOnline
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.outline,
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
                        if (lastActivity.isNotEmpty)
                          Text('Последняя активность: $lastActivity'),
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
