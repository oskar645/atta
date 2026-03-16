import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chestore2/src/features/admin/admin_screen.dart';
import 'package:chestore2/src/features/reviews/seller_reviews_screen.dart';
import 'package:chestore2/src/features/profile/settings_screen.dart';
import 'package:chestore2/src/services/admin_service.dart';
import 'package:chestore2/src/services/auth_service.dart';
import 'package:chestore2/src/services/profile_service.dart';
import 'package:chestore2/src/services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  String _shortUserId(String uid) {
    final text = uid.trim();
    if (text.length <= 14) return text;
    return '${text.substring(0, 8)}...${text.substring(text.length - 4)}';
  }

  Future<void> _copyText(
    BuildContext context,
    String value, {
    String message = 'Скопировано',
  }) async {
    final text = value.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _editName(
      BuildContext context, String uid, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final profile = context.read<ProfileService>();

    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Имя'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Введите имя'),
          onSubmitted: (_) => Navigator.pop(context, ctrl.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Сохранить')),
        ],
      ),
    );

    final name = (res ?? '').trim();
    if (name.isEmpty) return;

    await profile.updateProfile(uid, {'display_name': name, 'name': name});

    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Имя сохранено')));
    }
  }

  Future<void> _editPhone(
      BuildContext context, String uid, String currentPhone) async {
    final ctrl = TextEditingController(text: currentPhone);
    final profile = context.read<ProfileService>();

    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Номер телефона'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Введите номер телефона'),
          onSubmitted: (_) => Navigator.pop(context, ctrl.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Сохранить')),
        ],
      ),
    );

    final phone = (res ?? '').trim();
    if (phone.isEmpty) return;

    await profile.updateProfile(uid, {'phone': phone});

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Номер телефона сохранен')));
    }
  }

// ✅ UNIVERSAL: pick -> readAsBytes -> uploadBinary
  Future<void> _pickAndUploadAvatar(BuildContext context, String uid) async {
    final picker = ImagePicker();
    final profile = context.read<ProfileService>();

    Future<void> doPick(ImageSource src) async {
      final x = await picker.pickImage(source: src, imageQuality: 85);
      if (x == null) return;

      try {
        final Uint8List bytes = await x.readAsBytes();

// contentType можно определять по mime, но достаточно jpg
        await profile.uploadAvatar(
            uid: uid, bytes: bytes, contentType: 'image/jpeg');

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Фото профиля обновлено')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Ошибка аватара: $e')));
        }
      }
    }

    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать из галереи'),
              onTap: () async {
                Navigator.pop(ctx);
                await doPick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Сделать фото'),
              onTap: () async {
                Navigator.pop(ctx);
                await doPick(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AuthService>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Нет')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Да')),
        ],
      ),
    );

    if (ok == true) {
      await auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final profile = context.read<ProfileService>();
    final admin = context.read<AdminService>();

    final user = auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Нужно войти')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль'), centerTitle: false),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: profile.streamProfile(
          user.uid,
          seed: <String, dynamic>{
            if ((user.displayName?.trim().isNotEmpty ?? false))
              'display_name': user.displayName!.trim(),
            if ((user.email?.trim().isNotEmpty ?? false))
              'email': user.email!.trim(),
            if ((user.photoUrl?.trim().isNotEmpty ?? false))
              'avatar_url': user.photoUrl!.trim(),
          },
        ),
        builder: (context, snap) {
          final data = snap.data ?? const <String, dynamic>{};
          if (data.isNotEmpty) {
            profile.seedProfile(user.uid, data);
          }

          final authFallbackName =
              (user.displayName?.trim().isNotEmpty ?? false)
                  ? user.displayName!.trim()
                  : ((user.email?.trim().isNotEmpty ?? false)
                      ? user.email!.trim()
                      : 'Профиль');
          final name =
              profile.pickNameFromRow(data, fallback: authFallbackName);
          final phone = (data['phone'] ?? '').toString().trim();

          final avatar = profile.pickAvatarFromRow(data).isNotEmpty
              ? profile.pickAvatarFromRow(data)
              : (user.photoUrl?.trim() ??
                  ''); // ✅ сразу показываем auth fallback

          return ListView(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _pickAndUploadAvatar(context, user.uid),
                      child: _Avatar(photoUrl: avatar, fallbackText: name),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _editName(context, user.uid, name),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(Icons.edit,
                                      size: 18,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _editPhone(context, user.uid, phone),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                phone.isEmpty ? 'Добавить телефон' : phone,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.outline),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _CopyIdChip(
                            label: 'ID',
                            value: _shortUserId(user.uid),
                            onTap: () => _copyText(
                              context,
                              user.uid,
                              message: 'ID аккаунта скопирован',
                            ),
                          ),
                          const SizedBox(height: 14),
                          _CompactStatsRow(
                            ratingAvgStream:
                                profile.streamMyRatingAvg(user.uid),
                            reviewsCountStream:
                                profile.streamMyReviewsCount(user.uid),
                            listingsStream:
                                profile.streamMyListingsCount(user.uid),
                            followers: '0',
                            onOpenReviews: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => SellerReviewsScreen(
                                    sellerId: user.uid,
                                    sellerName: name,
                                    listingId: '',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      tileColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      leading: const Icon(Icons.dark_mode_outlined),
                      title: const Text('Тёмная тема'),
                      trailing: Switch(
                        value: context.watch<ThemeService>().mode ==
                            ThemeMode.dark,
                        onChanged: (v) =>
                            context.read<ThemeService>().toggle(v),
                      ),
                    ),
                    const SizedBox(height: 10),
                    StreamBuilder<bool>(
	                      stream: admin.streamIsAdmin(user.uid),
	                      initialData: false,
	                      builder: (context, adminSnap) {
	                        if (adminSnap.data != true) {
	                          return const SizedBox.shrink();
	                        }

                        return Column(
                          children: [
                            StreamBuilder<bool>(
                              stream: admin.streamNeedsAttention(),
                              initialData: false,
                              builder: (context, attSnap) {
                                final hasAlert = attSnap.data == true;

                                return ListTile(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  tileColor: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  leading: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      const Icon(
                                          Icons.admin_panel_settings_outlined),
                                      if (hasAlert)
                                        const Positioned(
                                          right: -2,
                                          top: -2,
                                          child: Icon(Icons.brightness_1,
                                              size: 10, color: Colors.red),
                                        ),
                                    ],
                                  ),
                                  title: Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Админ-панель',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (hasAlert) ...[
                                        const SizedBox(width: 6),
                                        const Icon(Icons.brightness_1,
                                            size: 8, color: Colors.red),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text(
                                    hasAlert
                                        ? 'Есть новые задачи: проверьте разделы'
                                        : 'Управление приложением',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => const AdminScreen()),
                                    );
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 10),
                          ],
                        );
                      },
                    ),
                    ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      tileColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text('Настройки'),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      tileColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text('Выйти',
                          style: TextStyle(color: Colors.red)),
                      onTap: () => _confirmLogout(context),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final String fallbackText;

  const _Avatar({this.photoUrl, required this.fallbackText});

  @override
  Widget build(BuildContext context) {
    final t = fallbackText.trim();
    final letter = t.isEmpty ? 'U' : t[0].toUpperCase();

    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surface,
      ),
      child: ClipOval(
        child: (photoUrl == null || photoUrl!.isEmpty)
            ? Center(
                child: Text(letter,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w800)),
              )
            : CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (_, __, ___) => Center(
                  child: Text(letter,
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w800)),
                ),
              ),
      ),
    );
  }
}

class _CopyIdChip extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _CopyIdChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              if (value.trim().isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Icon(
                Icons.copy_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final Stream<double> ratingAvgStream;
  final Stream<int> reviewsCountStream;
  final Stream<int> listingsStream;
  final String followers;
  final VoidCallback onOpenReviews;

  const _StatsRow({
    required this.ratingAvgStream,
    required this.reviewsCountStream,
    required this.listingsStream,
    required this.followers,
    required this.onOpenReviews,
  });

  Widget _stat(BuildContext context, String value, String label) {
    return Column(
      children: [
        FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800))),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label,
              maxLines: 1,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.outline)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StreamBuilder<double>(
            stream: ratingAvgStream,
            builder: (_, s) =>
                _stat(context, (s.data ?? 0.0).toStringAsFixed(1), 'Рейтинг'),
          ),
        ),
        Expanded(
          child: StreamBuilder<int>(
            stream: reviewsCountStream,
            builder: (_, s) => GestureDetector(
              onTap: onOpenReviews,
              child: _stat(context, (s.data ?? 0).toString(), 'Отзывы'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<int>(
            stream: listingsStream,
            builder: (_, s) =>
                _stat(context, (s.data ?? 0).toString(), 'Объявления'),
          ),
        ),
        Expanded(
          child: _stat(context, followers, 'Подписчики'),
        ),
      ],
    );
  }
}

class _CompactStatsRow extends StatelessWidget {
  final Stream<double> ratingAvgStream;
  final Stream<int> reviewsCountStream;
  final Stream<int> listingsStream;
  final String followers;
  final VoidCallback onOpenReviews;

  const _CompactStatsRow({
    required this.ratingAvgStream,
    required this.reviewsCountStream,
    required this.listingsStream,
    required this.followers,
    required this.onOpenReviews,
  });

  Widget _stat(BuildContext context, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Expanded(
          child: StreamBuilder<double>(
            stream: ratingAvgStream,
            builder: (_, s) =>
                _stat(context, (s.data ?? 0.0).toStringAsFixed(1), 'Рейтинг'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: StreamBuilder<int>(
            stream: reviewsCountStream,
            builder: (_, s) => GestureDetector(
              onTap: onOpenReviews,
              child: _stat(context, (s.data ?? 0).toString(), 'Отзывы'),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: StreamBuilder<int>(
            stream: listingsStream,
            builder: (_, s) =>
                _stat(context, (s.data ?? 0).toString(), 'Объявления'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _stat(context, followers, 'Подписчики'),
        ),
      ],
    );
  }
}
