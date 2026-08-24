import 'dart:async';
import 'dart:io';

import 'package:atta/src/features/admin/admin_screen.dart';
import 'package:atta/src/features/profile/settings_screen.dart';
import 'package:atta/src/features/reviews/seller_reviews_screen.dart';
import 'package:atta/src/features/wallet/wallet_screen.dart';
import 'package:atta/src/models/wallet.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/theme_service.dart';
import 'package:atta/src/utils/media_url.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:atta/src/utils/share_texts.dart';
import 'package:atta/src/services/wallet_service.dart';
import 'package:atta/src/widgets/remote_avatar.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

void _debugProfileLog(String message) {
  assert(() {
    debugPrint(message);
    return true;
  }());
}

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

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  Uint8List? _avatarPreviewBytes;
  bool _isAvatarUploading = false;
  String? _avatarOverrideUrl;
  String? _profileStreamUid;
  Stream<Map<String, dynamic>>? _profileStream;
  StreamSubscription<AuthSessionEvent>? _authSub;
  DateTime? _lastResumeRefreshAt;

  static const Duration _resumeRefreshCooldown = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = context.read<AuthService>().onAuthStateChange.listen((event) {
      if (event.type != AuthSessionEventType.userUpdated || !mounted) {
        return;
      }
      setState(() => _profileStream = null);
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final lastRefreshAt = _lastResumeRefreshAt;
    if (lastRefreshAt != null &&
        DateTime.now().difference(lastRefreshAt) < _resumeRefreshCooldown) {
      return;
    }
    _lastResumeRefreshAt = DateTime.now();
    unawaited(_refreshProfileOnResume());
  }

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
      _debugProfileLog('Profile open');
      _debugProfileLog('auth ready user=${user.uid}');
      _debugProfileLog('Profile cached user shown user=${user.uid}');
      _profileStreamUid = user.uid;
      _profileStream = profile.streamProfile(
        user.uid,
        seed: _profileSeed(user),
      );
    }
    return _profileStream!;
  }

  Future<void> _refreshProfileOnResume() async {
    final auth = context.read<AuthService>();
    final profile = context.read<ProfileService>();
    final user = auth.currentUser;
    if (user == null) return;
    _debugProfileLog('Profile cached user shown user=${user.uid}');
    _debugProfileLog('auth me refresh start user=${user.uid}');
    try {
      await auth.restoreSessionOnResume(force: true);
      _debugProfileLog('auth me success user=${user.uid}');
    } catch (error) {
      _debugProfileLog('auth me error message=$error user=${user.uid}');
    } finally {
      _debugProfileLog('profile finally loading=false user=${user.uid}');
    }
    try {
      await profile.getProfile(user.uid, forceRefresh: true);
      if (mounted) {
        setState(() => _profileStream = null);
      }
    } catch (error) {
      _debugProfileLog('Profile load error message=$error user=${user.uid}');
    }
  }

  Future<void> _shareProfileInvite(
    BuildContext context, {
    required String referralCode,
    required String name,
  }) async {
    final shareText = buildInviteShareText(referralCode: referralCode);
    final message = shareText.text;
    if (message == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shareText.errorMessage ?? appInstallUrlNotConfiguredMessage,
          ),
        ),
      );
      return;
    }

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
          content:
              Text('Не удалось открыть меню отправки. Попробуйте ещё раз.'),
        ),
      );
    }
  }

  Future<void> _editName(
      BuildContext context, String uid, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final profile = context.read<ProfileService>();
    final auth = context.read<AuthService>();

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

    try {
      final updated = await profile
          .updateProfile(uid, {'display_name': name, 'name': name});
      await auth.syncCurrentUserFromProfile(uid, updated);

      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Имя сохранено')));
      }
    } catch (error) {
      if (context.mounted) {
        final message = error is ApiException && error.message.trim().isNotEmpty
            ? error.message.trim()
            : 'Не удалось сохранить имя. Попробуйте ещё раз.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _editPhone(
      BuildContext context, String uid, String currentPhone) async {
    final ctrl =
        TextEditingController(text: formatRuPhoneForField(currentPhone));
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
          inputFormatters: const [
            RuPhoneInputFormatter(),
          ],
          decoration: const InputDecoration(
            hintText: '928 888-86-45',
            prefixText: '+7 ',
          ),
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
    final normalizedPhone = normalizeRuPhoneForApi(phone);
    if (normalizedPhone.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите номер телефона полностью')),
        );
      }
      return;
    }

    await profile.updateProfile(uid, {'phone': normalizedPhone});

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Номер телефона сохранен')));
    }
  }

// ✅ UNIVERSAL: pick -> readAsBytes -> uploadBinary
  Future<void> _pickAndUploadAvatar(BuildContext context, String uid) async {
    final picker = ImagePicker();
    final profile = context.read<ProfileService>();
    final auth = context.read<AuthService>();

    Future<void> doPick(ImageSource src) async {
      final x = await (widget.pickImage?.call(src) ??
          picker.pickImage(source: src, imageQuality: 85));
      if (x == null) return;
      final previousAvatarUrl = _currentAvatarUrl(
        profile,
        auth.currentUser!,
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
        if (uploadedAvatarUrl.isEmpty ||
            avatarResolution.resolvedUrl.trim().isEmpty) {
          throw Exception('backend_empty_avatar_url');
        }
        if (!context.mounted) return;
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
            _avatarOverrideUrl = _avatarOverrideUrl?.trim().isNotEmpty == true
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
    admin.bindAdminUser(user.uid);

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль'), centerTitle: false),
      body: StreamBuilder<Map<String, dynamic>>(
        initialData: (() {
          final cached = profile.getCachedProfile(user.uid);
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
            return RepaintBoundary(
              child: ListView(
                children: const [
                  SkeletonProfileHeader(),
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonWalletCard(),
                  ),
                ],
              ),
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
          final phoneDisplay = phone.isEmpty ? '' : formatRussianPhone(phone);
          final phoneVerified =
              data['phoneVerified'] == true || data['phone_verified'] == true;

          final avatar = _currentAvatarUrl(profile, user, data);

          return RepaintBoundary(
            child: ListView(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  phoneDisplay.isEmpty
                                      ? 'Добавить телефон'
                                      : phoneDisplay,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline),
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
                        tileColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
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
                        tileColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        leading: const Icon(Icons.person_add_alt_1_outlined),
                        title: const Text('Пригласить друга'),
                        subtitle:
                            const Text('Поделиться ссылкой на мой профиль'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _shareProfileInvite(
                          context,
                          referralCode: user.referralCode ?? '',
                          name: name,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        tileColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
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
                      if (user.isAdmin) ...[
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
                      ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        tileColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        leading: const Icon(Icons.logout, color: Colors.red),
                        title: const Text('Выйти',
                            style: TextStyle(color: Colors.red)),
                        onTap: () => _confirmLogout(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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

class _ProfileWalletTileState extends State<_ProfileWalletTile>
    with WidgetsBindingObserver {
  static const Duration _resumeRefreshCooldown = Duration(seconds: 5);
  late Future<Wallet?> _future;
  String? _lastWalletErrorText;
  DateTime? _lastRefreshAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = context.read<WalletService>().maybeCheckAccrualOncePerSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final lastRefreshAt = _lastRefreshAt;
    if (lastRefreshAt != null &&
        DateTime.now().difference(lastRefreshAt) < _resumeRefreshCooldown) {
      return;
    }
    _retry();
  }

  void _retry() {
    final walletService = context.read<WalletService>();
    setState(() {
      _lastWalletErrorText = null;
      _future = walletService.checkAccrual(forceRefresh: true);
    });
    _lastRefreshAt = DateTime.now();
  }

  String _walletErrorText(Object error) {
    if (error is ApiException && error.isUnauthorized) {
      return 'Не удалось обновить кошелёк. Попробуйте позже.';
    }
    return 'Не удалось обновить кошелёк. Попробуйте позже.';
  }

  void _showWalletErrorIfNeeded(Object error) {
    final text = _walletErrorText(error);
    if (_lastWalletErrorText == text) {
      return;
    }
    _lastWalletErrorText = text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final walletService = context.read<WalletService>();
    return FutureBuilder<Wallet?>(
      future: _future,
      initialData: walletService.cachedWallet,
      builder: (context, snapshot) {
        final wallet = snapshot.data ?? walletService.cachedWallet;
        final refreshing = snapshot.connectionState != ConnectionState.done;
        final hasError = snapshot.hasError;
        if (!refreshing) {
          _lastRefreshAt = DateTime.now();
        }
        if (hasError) {
          _showWalletErrorIfNeeded(snapshot.error!);
        } else {
          _lastWalletErrorText = null;
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
              subtitle: const Text('Бонусы для продвижения'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (wallet != null)
                    Text(
                      '${wallet.balance} бонусов',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: refreshing
                        ? const Padding(
                            padding: EdgeInsets.all(2),
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : hasError
                            ? IconButton(
                                padding: EdgeInsets.zero,
                                splashRadius: 18,
                                tooltip: 'Обновить кошелёк',
                                onPressed: _retry,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 20,
                                ),
                              )
                            : IconButton(
                                padding: EdgeInsets.zero,
                                splashRadius: 18,
                                tooltip: 'Обновить кошелёк',
                                onPressed: _retry,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 20,
                                ),
                              ),
                  ),
                ],
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const WalletScreen(),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
