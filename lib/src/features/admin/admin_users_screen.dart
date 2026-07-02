import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:atta/src/widgets/remote_avatar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];

  static const Set<String> _protectedAdminPhones = <String>{
    '79288888645',
    '79306939954',
  };

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load({bool forceRefresh = false}) async {
    final response =
        await context.read<AdminService>().users(forceRefresh: forceRefresh);
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

  Future<void> _deleteUser(Map<String, dynamic> item) async {
    final userId = (item['id'] ?? '').toString();
    final currentUserId = context.read<AuthService>().currentUser?.uid ?? '';
    final isSelf = userId == currentUserId;
    final phone = _value(item, const ['phone']);
    final isProtectedAdmin = _protectedAdminPhones.contains(phone);

    if (isProtectedAdmin) {
      showAppSnack(
        context,
        'Этот администратор защищён от удаления',
        isError: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title:
                Text(isSelf ? 'Удалить самого себя?' : 'Удалить пользователя?'),
            content: Text(
              isSelf
                  ? 'Это ваш аккаунт администратора. Такое удаление опасно и будет заблокировано сервером.'
                  : 'Профиль будет деактивирован, а его объявления станут скрыты.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    if (!mounted) return;

    final adminService = context.read<AdminService>();
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await adminService.deleteUser(userId);
      if (!mounted) return;
      if (response['deleted'] == true) {
        setState(() {
          _items = _items
              .where((candidate) =>
                  (candidate['id'] ?? '').toString().trim() != userId)
              .toList(growable: false);
          _future = Future<List<Map<String, dynamic>>>.value(_items);
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Пользователь удалён')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              (response['message'] ?? 'Не удалось удалить пользователя')
                  .toString(),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка удаления пользователя: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _value(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _avatarUrl(Map<String, dynamic> item) {
    return _value(
      item,
      const ['avatar_url', 'avatarUrl', 'photo_url', 'photoUrl'],
    );
  }

  bool _isProtectedAdmin(Map<String, dynamic> item) {
    return _protectedAdminPhones.contains(_value(item, const ['phone']));
  }

  String _statusLabel(Map<String, dynamic> item) {
    if ((item['deleted_at'] ?? '').toString().trim().isNotEmpty) {
      return 'Удалён';
    }
    final status = (item['status'] ?? '').toString().trim().toLowerCase();
    switch (status) {
      case 'blocked':
        return 'Заблокирован';
      case 'inactive':
        return 'Неактивен';
      default:
        return 'Активен';
    }
  }

  Future<void> _openUser(Map<String, dynamic> item) async {
    final userId = _value(item, const ['id']);
    if (userId.isEmpty) return;

    try {
      final response = await context.read<AdminService>().userById(userId);
      final raw = response['user'];
      final details = raw is Map
          ? raw.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SellerPublicProfileScreen(
            sellerId: userId,
            initialSellerName: _value(
              details.isEmpty ? item : details,
              const ['display_name', 'name', 'email', 'phone'],
            ),
            initialSellerAvatar: _avatarUrl(details.isEmpty ? item : details),
            initialSellerPhone:
                _value(details.isEmpty ? item : details, const ['phone']),
            initialStatusLabel: _statusLabel(details.isEmpty ? item : details),
            initialIsAdmin:
                (details['is_admin'] == true || details['isAdmin'] == true) ||
                    item['is_admin'] == true ||
                    item['isAdmin'] == true,
            showAdminFields: true,
            titleText: 'Профиль пользователя',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnack(
        context,
        'Не удалось открыть профиль пользователя: $e',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Пользователи')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError && _items.isEmpty) {
            return _AdminStateView(
              message: 'Не удалось загрузить пользователей.\n${snap.error}',
              onRetry: _refresh,
            );
          }

          final items = _items.isNotEmpty
              ? _items
              : (snap.data ?? const <Map<String, dynamic>>[]);
          if (items.isEmpty) {
            return _AdminStateView(
              message: 'Пользователи пока не получены из Timeweb.',
              onRetry: _refresh,
              showButton: false,
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final name = _value(
                  item,
                  const ['display_name', 'name', 'email', 'phone'],
                );
                final isAdmin =
                    item['is_admin'] == true || item['isAdmin'] == true;
                final isProtectedAdmin = _isProtectedAdmin(item);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _busy ? null : () => _openUser(item),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              RemoteAvatar(
                                imageUrl: _avatarUrl(item),
                                fallbackText:
                                    name.isEmpty ? 'Пользователь' : name,
                                radius: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.isEmpty ? 'Пользователь' : name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _statusLabel(item),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Телефон: ${formatRussianPhone(_value(item, const [
                                  'phone'
                                ]))}',
                          ),
                          Text('User ID: ${_value(item, const ['id'])}'),
                          Text('Дата регистрации: ${_value(item, const [
                                'created_at'
                              ])}'),
                          Text('Last seen: ${_value(item, const [
                                'last_seen',
                                'last_login_at'
                              ])}'),
                          Text('Admin: ${isAdmin ? 'да' : 'нет'}'),
                          if (isProtectedAdmin) const Text('Защита: включена'),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton(
                              onPressed: _busy || isProtectedAdmin
                                  ? null
                                  : () => _deleteUser(item),
                              child: Text(
                                isProtectedAdmin ? 'Защищён' : 'Удалить',
                              ),
                            ),
                          ),
                        ],
                      ),
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

class _AdminStateView extends StatelessWidget {
  const _AdminStateView({
    required this.message,
    required this.onRetry,
    this.showButton = true,
  });

  final String message;
  final Future<void> Function() onRetry;
  final bool showButton;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (showButton) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Повторить'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
