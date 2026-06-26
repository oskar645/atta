import 'dart:io';

import 'package:atta/src/features/admin/admin_screen.dart';
import 'package:atta/src/features/profile/settings_screen.dart';
import 'package:atta/src/features/reviews/seller_reviews_screen.dart';
import 'package:atta/src/features/wallet/wallet_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/theme_service.dart';
import 'package:atta/src/utils/media_url.dart';
import 'package:atta/src/services/wallet_service.dart';
import 'package:atta/src/widgets/remote_avatar.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.pickImage,
    this.precacheAvatar,
  });

  final Future<XFile?> Function(ImageSource source)? pickImage;
  final Future<void> Function(BuildContext context, String imageUrl)?
      precacheAvatar;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Uint8List? _avatarPreviewBytes;
  bool _isAvatarUploading = false;
  String? _avatarOverrideUrl;
  String? _profileStreamUid;
  Stream<Map<String, dynamic>>? _profileStream;

  Future<void> _precacheAvatar(BuildContext context, String imageUrl) async {
    final customPrecache = widget.precacheAvatar;
    if (customPrecache != null) {
      await customPrecache(context, imageUrl);
      return;
    }
    await precacheImage(
      CachedNetworkImageProvider(imageUrl),
      context,
    );
  }

  String _currentAvatarUrl(
    ProfileService profile,
    AuthUser user,
    Map<String, dynamic> data,
  ) {
    final override = _avatarOverrideUrl?.trim() ?? '';
    if (override.isNotEmpty) {
      return override;
    }
    final cachedAvatar = profile.pickAvatarFromRow(data).trim();
    if (cachedAvatar.isNotEmpty) {
      return cachedAvatar;
    }
    return user.photoUrl?.trim() ?? '';
  }

  String _avatarUploadError(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 413) {
        return 'Фото слишком большое. Выберите изображение меньшего размера.';
      }
      if (error.message.trim().isNotEmpty) {
        return error.message.trim();
      }
    }
    if (error.toString().contains('backend_empty_avatar_url')) {
      return 'Не удалось обновить фото профиля. Попробуйте ещё раз.';
    }
    final text = error.toString().toLowerCase();
    if (text.contains('413') || text.contains('too large')) {
      return 'Фото слишком большое. Выберите изображение меньшего размера.';
    }
    return 'Не удалось загрузить фото профиля. Попробуйте ещё раз.';
  }

  Map<String, dynamic> _profileSeed(AuthUser user) {
    return <String, dynamic>{
      if ((user.displayName?.trim().isNotEmpty ?? false))
        'display_name': user.displayName!.trim(),
      if ((user.email?.trim().isNotEmpty ?? false)) 'email': user.email!.trim(),
      if ((user.phone?.trim().isNotEmpty ?? false)) 'phone': user.phone!.trim(),
      'phoneVerified': user.phoneVerified,
      'phone_verified': user.phoneVerified,
      if ((_avatarOverrideUrl?.trim().isNotEmpty ?? false))
        'avatar_url': _avatarOverrideUrl!.trim()
      else if ((user.photoUrl?.trim().isNotEmpty ?? false))
        'avatar_url': user.photoUrl!.trim(),
    };
  }

  Stream<Map<String, dynamic>> _ensureProfileStream(
    ProfileService profile,
    AuthUser user,
  ) {
    if (_profileStream == null || _profileStreamUid != user.uid) {
      _profileStreamUid = user.uid;
      _profileStream = profile.streamProfile(
        user.uid,
        seed: _profileSeed(user),
      );
    }
    return _profileStream!;
  }

  String _formatPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    String normalized = digits;
    if (normalized.length == 11 &&
        (normalized.startsWith('7') || normalized.startsWith('8'))) {
      normalized = normalized.substring(1);
    }
    if (normalized.length != 10) return value;
    return '+7 ${normalized.substring(0, 3)} ${normalized.substring(3, 6)}-'
        '${normalized.substring(6, 8)}-${normalized.substring(8)}';
  }

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

  Future<void> _shareProfileInvite(
    BuildContext context, {
    required String uid,
    required String name,
  }) async {
    final profileLink = 'https://atta.app/profile/$uid';
    final message =
        'Присоединяйся к ATTA. Удобно покупать и продавать рядом.\nПрофиль $name: $profileLink';

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: 'Приглашение в ATTA',
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось открыть меню отправки. Попробуйте ещё раз.'),
        ),
      );
    }
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
      final x = await (widget.pickImage?.call(src) ??
          picker.pickImage(source: src, imageQuality: 85));
      if (x == null) return;
      final previousAvatarUrl = _currentAvatarUrl(
        profile,
        context.read<AuthService>().currentUser!,
        profile.getCachedProfile(uid),
      );

      try {
        final Uint8List bytes = await x.readAsBytes();
        final fileName = x.name.trim().isNotEmpty
            ? x.name.trim()
            : File(x.path).uri.pathSegments.last;
        if (mounted) {
          setState(() {
            _avatarPreviewBytes = bytes;
            _isAvatarUploading = true;
          });
        }
        final result = await profile.uploadAvatar(
          uid: uid,
          bytes: bytes,
          fileName: fileName,
          contentType: 'image/jpeg',
        );
        final uploadedAvatarUrl = result.avatarUrl.trim();
        final avatarResolution = resolveMediaUrl(
          uploadedAvatarUrl,
          categoryHint: 'avatars',
        );
        if (kDebugMode) {
          debugPrint(
            'Avatar flow uploadResponse.avatarUrl=$uploadedAvatarUrl originalAvatarUrl=${avatarResolution.originalUrl} resolvedAvatarUrl=${avatarResolution.resolvedUrl}',
          );
        }
        if (uploadedAvatarUrl.isEmpty || avatarResolution.resolvedUrl.trim().isEmpty) {
          throw Exception('backend_empty_avatar_url');
        }
        await _precacheAvatar(context, avatarResolution.resolvedUrl.trim());
        if (!mounted) return;
        setState(() {
          _avatarOverrideUrl = uploadedAvatarUrl;
          _avatarPreviewBytes = null;
          _isAvatarUploading = false;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (context.mounted &&
            !_isAvatarUploading &&
            _avatarPreviewBytes == null &&
            result.avatarUrl.trim().isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Фото профиля обновлено')));
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _avatarOverrideUrl =
                _avatarOverrideUrl?.trim().isNotEmpty == true
                    ? _avatarOverrideUrl
                    : (previousAvatarUrl.isEmpty ? null : previousAvatarUrl);
            _avatarPreviewBytes = null;
            _isAvatarUploading = false;
          });
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_avatarUploadError(e))),
          );
        }
      }
    }

    if (!context.mounted) return;
    if (widget.pickImage != null) {
      await doPick(ImageSource.gallery);
      return;
    }

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
    final follows = context.read<FollowService>();

    final user = auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Нужно войти')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль'), centerTitle: false),
      body: StreamBuilder<Map<String, dynamic>>(
        initialData: (() {
          final cached = profile.getCachedProfile(user.uid);
          if (cached.isEmpty &&
              !(_avatarOverrideUrl?.trim().isNotEmpty ?? false)) {
            return null;
          }
          final merged = <String, dynamic>{
            if ((user.displayName?.trim().isNotEmpty ?? false))
              'display_name': user.displayName!.trim(),
            if ((user.email?.trim().isNotEmpty ?? false))
              'email': user.email!.trim(),
            if ((user.phone?.trim().isNotEmpty ?? false))
              'phone': user.phone!.trim(),
            'phoneVerified': user.phoneVerified,
            'phone_verified': user.phoneVerified,
            if ((_avatarOverrideUrl?.trim().isNotEmpty ?? false))
              'avatar_url': _avatarOverrideUrl!.trim()
            else if ((user.photoUrl?.trim().isNotEmpty ?? false))
              'avatar_url': user.photoUrl!.trim(),
            ...cached,
          };
          return merged.isEmpty ? null : merged;
        })(),
        stream: _ensureProfileStream(profile, user),
        builder: (context, snap) {
          if (!snap.hasData) {
            return ListView(
              children: const [
                SkeletonProfileHeader(),
                Padding(
                  padding: EdgeInsets.all(16),
                  child: SkeletonWalletCard(),
                ),
              ],
            );
          }
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
          final phoneDisplay = phone.isEmpty ? '' : _formatPhone(phone);
          final phoneVerified =
              data['phoneVerified'] == true || data['phone_verified'] == true;

          final avatar = _currentAvatarUrl(profile, user, data);

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
                      key: const Key('profile_avatar_tap_target'),
                      onTap: _isAvatarUploading
                          ? null
                          : () => _pickAndUploadAvatar(context, user.uid),
                      child: _Avatar(
                        photoUrl: avatar,
                        fallbackText: name,
                        previewBytes: _avatarPreviewBytes,
                        isLoading: _isAvatarUploading,
                      ),
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
                                phoneDisplay.isEmpty
                                    ? 'Добавить телефон'
                                    : phoneDisplay,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.outline),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (phone.isNotEmpty)
                            Text(
                              phoneVerified
                                  ? 'Номер подтвержден'
                                  : 'Номер не подтвержден',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.outline,
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
                            followersStream:
                                follows.streamFollowersCount(user.uid),
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
                    const _ProfileWalletTile(),
                    const SizedBox(height: 10),
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
                      leading: const Icon(Icons.person_add_alt_1_outlined),
                      title: const Text('Пригласить друга'),
                      subtitle: const Text('Поделиться ссылкой на мой профиль'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _shareProfileInvite(
                        context,
                        uid: user.uid,
                        name: name,
                      ),
                    ),
                    const SizedBox(height: 10),
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
  final Uint8List? previewBytes;
  final bool isLoading;

  const _Avatar({
    this.photoUrl,
    required this.fallbackText,
    this.previewBytes,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surface,
      ),
      child: RemoteAvatar(
        imageUrl: previewBytes == null ? (photoUrl ?? '') : '',
        fallbackText: fallbackText,
        radius: 39,
        imageProvider: previewBytes == null ? null : MemoryImage(previewBytes!),
        isLoading: isLoading,
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

// ignore: unused_element
class _StatsRow extends StatelessWidget {
  final Stream<double> ratingAvgStream;
  final Stream<int> reviewsCountStream;
  final Stream<int> listingsStream;
  final Stream<int> followersStream;
  final VoidCallback onOpenReviews;

  const _StatsRow({
    required this.ratingAvgStream,
    required this.reviewsCountStream,
    required this.listingsStream,
    required this.followersStream,
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
          child: StreamBuilder<int>(
            stream: followersStream,
            builder: (_, s) =>
                _stat(context, (s.data ?? 0).toString(), 'Подписчики'),
          ),
        ),
      ],
    );
  }
}

class _CompactStatsRow extends StatelessWidget {
  final Stream<double> ratingAvgStream;
  final Stream<int> reviewsCountStream;
  final Stream<int> listingsStream;
  final Stream<int> followersStream;
  final VoidCallback onOpenReviews;

  const _CompactStatsRow({
    required this.ratingAvgStream,
    required this.reviewsCountStream,
    required this.listingsStream,
    required this.followersStream,
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
          child: StreamBuilder<int>(
            stream: followersStream,
            builder: (_, s) =>
                _stat(context, (s.data ?? 0).toString(), 'Подписчики'),
          ),
        ),
      ],
    );
  }
}

class _ProfileWalletTile extends StatefulWidget {
  const _ProfileWalletTile();

  @override
  State<_ProfileWalletTile> createState() => _ProfileWalletTileState();
}

class _ProfileWalletTileState extends State<_ProfileWalletTile> {
  Future<dynamic>? _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<WalletService>().maybeCheckAccrualOncePerSession();
  }

  void _retry() {
    final walletService = context.read<WalletService>();
    setState(() {
      _future = walletService.checkAccrual();
    });
  }

  String _walletErrorText(Object error) {
    if (error is ApiException && error.message.trim().isNotEmpty) {
      return 'Кошелёк временно недоступен';
    }
    return 'Кошелёк временно недоступен';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final walletService = context.read<WalletService>();
    return FutureBuilder<dynamic>(
      future: _future,
      builder: (context, snapshot) {
        final wallet = snapshot.data ?? walletService.cachedWallet;
        final loading = snapshot.connectionState != ConnectionState.done &&
            wallet == null &&
            !snapshot.hasError;
        final hasError = snapshot.hasError && wallet == null;
        if (loading) {
          return const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SkeletonWalletCard(),
          );
        }
        return Column(
          children: [
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              tileColor: theme.colorScheme.surfaceContainerHighest,
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('ATTA Кошелёк'),
              subtitle: Text(
                loading
                    ? 'Загрузка бонусов...'
                    : hasError
                        ? _walletErrorText(snapshot.error!)
                        : 'Бонусы для продвижения',
              ),
              trailing: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : wallet != null
                      ? Text(
                          '${wallet.balance} бонусов',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        )
                      : const Icon(Icons.refresh_rounded),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const WalletScreen(),
                  ),
                );
              },
            ),
            if (hasError) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _retry,
                  child: const Text('Повторить'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
