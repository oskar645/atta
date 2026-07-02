import 'package:atta/src/features/inbox/chat_screen.dart';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/features/reviews/seller_reviews_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:atta/src/widgets/listing_promotion_badges.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:atta/src/widgets/presence_badge.dart';
import 'package:atta/src/widgets/remote_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SellerPublicProfileScreen extends StatefulWidget {
  final String sellerId;
  final String initialSellerName;
  final String initialSellerAvatar;
  final String initialSellerPhone;
  final String initialStatusLabel;
  final bool showAdminFields;
  final bool initialIsAdmin;
  final String titleText;

  const SellerPublicProfileScreen({
    super.key,
    required this.sellerId,
    this.initialSellerName = '',
    this.initialSellerAvatar = '',
    this.initialSellerPhone = '',
    this.initialStatusLabel = '',
    this.showAdminFields = false,
    this.initialIsAdmin = false,
    this.titleText = 'Профиль продавца',
  });

  @override
  State<SellerPublicProfileScreen> createState() =>
      _SellerPublicProfileScreenState();
}

class _SellerPublicProfileScreenState extends State<SellerPublicProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _followBusy = false;

  String _shortUserId(String uid) {
    final text = uid.trim();
    if (text.length <= 14) return text;
    return '${text.substring(0, 8)}...${text.substring(text.length - 4)}';
  }

  Future<void> _copyUserId(BuildContext context, String uid) async {
    final text = uid.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ID пользователя скопирован')),
    );
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _openChat({
    required BuildContext context,
    required ListingsService listingsSvc,
    required ChatService chats,
    required String myUid,
    required String sellerId,
    required String sellerName,
    required String sellerAvatar,
  }) async {
    try {
      final listing =
          await listingsSvc.getLatestApprovedListingByOwner(sellerId);
      if (listing == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('У продавца пока нет объявлений')),
        );
        return;
      }

      final chatId = await chats.getOrCreateChat(
        listingId: listing.id,
        listingTitle: listing.title,
        buyerId: myUid,
        sellerId: sellerId,
      );

      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            initialOtherUserName: sellerName,
            initialOtherUserAvatar: sellerAvatar,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _toggleFollow({
    required FollowService follows,
    required String myUid,
    required bool isFollowing,
  }) async {
    if (_followBusy) return;

    setState(() => _followBusy = true);
    try {
      await follows.toggleFollow(
        followerId: myUid,
        sellerId: widget.sellerId,
        isFollowing: isFollowing,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) {
        setState(() => _followBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.read<ProfileService>();
    final reviews = context.read<ReviewsService>();
    final listingsSvc = context.read<ListingsService>();
    final chats = context.read<ChatService>();
    final follows = context.read<FollowService>();
    final presence = context.read<PresenceService>();
    final admin = context.read<AdminService>();
    final me = context.read<AuthService>().currentUser;

    final myUid = me?.uid ?? '';
    final isMe = myUid.isNotEmpty && myUid == widget.sellerId;
    final seed = <String, dynamic>{
      if (widget.initialSellerName.trim().isNotEmpty)
        'display_name': widget.initialSellerName.trim(),
      if (widget.initialSellerAvatar.trim().isNotEmpty)
        'avatar_url': widget.initialSellerAvatar.trim(),
      if (widget.initialSellerPhone.trim().isNotEmpty)
        'phone': widget.initialSellerPhone.trim(),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titleText),
        centerTitle: false,
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Активные'),
            Tab(text: 'Архив'),
          ],
        ),
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: profile.streamProfile(widget.sellerId, seed: seed),
        builder: (context, pSnap) {
          if (pSnap.connectionState == ConnectionState.waiting &&
              !pSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userRow = pSnap.data ?? const <String, dynamic>{};
          if (userRow.isNotEmpty) {
            profile.seedProfile(widget.sellerId, userRow);
          }

          final sellerName = profile.pickNameFromRow(userRow);
          final photoUrl = profile.pickAvatarFromRow(userRow);
          final phone = (userRow['phone'] ?? '').toString().trim();
          final phoneDisplay =
              phone.isEmpty ? 'Телефон не указан' : formatRussianPhone(phone);
          final statusText = widget.initialStatusLabel.trim().isNotEmpty
              ? widget.initialStatusLabel.trim()
              : (userRow['status'] ?? '').toString().trim();
          final isAdminUser = widget.initialIsAdmin ||
              userRow['is_admin'] == true ||
              userRow['isAdmin'] == true;

          final canCall = phone.isNotEmpty && !isMe;
          final canWrite = myUid.isNotEmpty && !isMe;

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    StreamBuilder<bool>(
                      stream: presence.streamIsOnline(widget.sellerId),
                      builder: (context, onlineSnap) {
                        final isOnline = onlineSnap.data == true;
                        return PresenceBadge(
                          isOnline: isOnline,
                          dotSize: 14,
                          child: _Avatar(
                            photoUrl: photoUrl,
                            fallbackText: sellerName,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  sellerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              StreamBuilder<bool>(
                                stream: myUid.isEmpty
                                    ? const Stream<bool>.empty()
                                    : admin.streamIsAdmin(myUid),
                                initialData: false,
                                builder: (context, adminSnap) {
                                  final canCopyId =
                                      isMe || adminSnap.data == true;
                                  if (!canCopyId) {
                                    return const SizedBox.shrink();
                                  }

                                  return _CopyIdChip(
                                    label: 'ID',
                                    value: _shortUserId(widget.sellerId),
                                    onTap: () =>
                                        _copyUserId(context, widget.sellerId),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          StreamBuilder<Map<String, dynamic>>(
                            stream: reviews.streamSellerRating(widget.sellerId),
                            builder: (_, rSnap) {
                              final rating =
                                  rSnap.data ?? const {'avg': 0.0, 'count': 0};
                              final avg =
                                  (rating['avg'] as num?)?.toDouble() ?? 0.0;
                              final cnt =
                                  (rating['count'] as num?)?.toInt() ?? 0;
                              return Row(
                                children: [
                                  const Icon(
                                    Icons.star,
                                    size: 18,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    avg.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '($cnt)',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          if (widget.showAdminFields) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (statusText.isNotEmpty)
                                  _AdminInfoChip(
                                    icon: Icons.verified_user_outlined,
                                    label: statusText,
                                  ),
                                _AdminInfoChip(
                                  icon: Icons.phone_outlined,
                                  label: phoneDisplay,
                                ),
                                _AdminInfoChip(
                                  icon: isAdminUser
                                      ? Icons.admin_panel_settings_outlined
                                      : Icons.person_outline,
                                  label: isAdminUser
                                      ? 'Администратор'
                                      : 'Пользователь',
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (!isMe && myUid.isNotEmpty)
                StreamBuilder<bool>(
                  stream: follows.streamIsFollowing(
                    followerId: myUid,
                    sellerId: widget.sellerId,
                  ),
                  initialData: false,
                  builder: (context, followSnap) {
                    final isFollowing = followSnap.data == true;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FilledButton.icon(
                        onPressed: _followBusy
                            ? null
                            : () => _toggleFollow(
                                  follows: follows,
                                  myUid: myUid,
                                  isFollowing: isFollowing,
                                ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: isFollowing
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                          foregroundColor: isFollowing
                              ? Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer
                              : null,
                        ),
                        icon: _followBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                isFollowing
                                    ? Icons.notifications_active_outlined
                                    : Icons.person_add_alt_1_outlined,
                              ),
                        label: Text(
                          isFollowing
                              ? 'Вы подписаны на новые объявления'
                              : 'Подписаться на продавца',
                        ),
                      ),
                    );
                  },
                ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canCall
                          ? () async {
                              final normalizedPhone =
                                  normalizeRuPhoneForApi(phone);
                              final uri = Uri(
                                scheme: 'tel',
                                path: normalizedPhone.isEmpty
                                    ? phone
                                    : '+$normalizedPhone',
                              );
                              await launchUrl(uri);
                            }
                          : null,
                      icon: const Icon(Icons.call),
                      label: Text(canCall ? 'Позвонить' : 'Телефон скрыт'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: canWrite
                          ? () => _openChat(
                                context: context,
                                listingsSvc: listingsSvc,
                                chats: chats,
                                myUid: myUid,
                                sellerId: widget.sellerId,
                                sellerName: sellerName,
                                sellerAvatar: photoUrl,
                              )
                          : null,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Написать'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                tileColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                leading: Icon(
                  Icons.rate_review_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Отзывы'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SellerReviewsScreen(
                        sellerId: widget.sellerId,
                        sellerName: sellerName,
                        listingId: '',
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              AnimatedBuilder(
                animation: _tab,
                builder: (context, _) {
                  final tabIndex = _tab.index;
                  return tabIndex == 0
                      ? _SellerListingsGrid(
                          stream: listingsSvc
                              .streamListingsByOwnerAll(widget.sellerId)
                              .map(
                                (items) => items
                                    .where((x) => x.status == 'approved')
                                    .toList(),
                              ),
                          isArchive: false,
                        )
                      : _SellerListingsGrid(
                          stream: listingsSvc
                              .streamListingsByOwnerAll(widget.sellerId)
                              .map(
                                (items) => items
                                    .where(
                                      (x) =>
                                          x.status == 'deleted' ||
                                          x.status == 'archived' ||
                                          x.status == 'sold' ||
                                          x.status == 'rejected',
                                    )
                                    .toList(),
                              ),
                          isArchive: true,
                        );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AdminInfoChip extends StatelessWidget {
  const _AdminInfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.outline),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
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
    return RemoteAvatar(
      imageUrl: (photoUrl ?? '').trim(),
      fallbackText: fallbackText,
      radius: 32,
      textStyle: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w900,
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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

class _SellerListingsGrid extends StatelessWidget {
  final Stream<List<Listing>> stream;
  final bool isArchive;

  const _SellerListingsGrid({
    required this.stream,
    required this.isArchive,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Listing>>(
      stream: stream,
      builder: (context, lSnap) {
        if (lSnap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Ошибка объявлений: ${lSnap.error}'),
          );
        }
        if (lSnap.connectionState == ConnectionState.waiting &&
            !lSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = lSnap.data ?? const <Listing>[];
        if (items.isEmpty) {
          return Center(
            child: Text(
              isArchive ? 'Архив пуст' : 'Пока нет объявлений',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          );
        }

        final grid = GridView.builder(
          itemCount: items.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.78,
          ),
          itemBuilder: (_, i) => _ListingCard(
            listing: items[i],
            isArchive: isArchive,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ListingDetailScreen(listingId: items[i].id),
                ),
              );
            },
          ),
        );

        if (!isArchive) return grid;

        return Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Text(
                'Архив: история объявлений продавца (продано, снято, отклонено).',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            grid,
          ],
        );
      },
    );
  }
}

class _ListingCard extends StatelessWidget {
  final Listing listing;
  final VoidCallback onTap;
  final bool isArchive;

  const _ListingCard({
    required this.listing,
    required this.onTap,
    required this.isArchive,
  });

  String _statusLabel(String status) {
    switch (status) {
      case 'sold':
        return 'Продано';
      case 'rejected':
        return 'На исправлении';
      case 'deleted':
        return 'Удалено админом';
      case 'archived':
        return 'Снято с продажи';
      default:
        return 'Снято';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'sold':
        return Colors.green;
      case 'rejected':
        return Colors.orange;
      case 'deleted':
        return Colors.red;
      case 'archived':
        return Colors.grey;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  String? _archiveNote(Listing listing) {
    final note = listing.archiveNote.trim();
    return note.isEmpty ? null : note;
  }

  @override
  Widget build(BuildContext context) {
    final photo = listing.firstPhotoUrl ?? '';
    final statusText = _statusLabel(listing.status);
    final statusColor = _statusColor(listing.status);
    final archiveNote = isArchive ? _archiveNote(listing) : null;
    final hasVipPromotion = listing.hasVipPromotion;
    final hasBumpPromotion = listing.hasBumpPromotion;
    final image = MediaPreviewBox(
      imageUrl: photo,
      categoryHint: 'listings',
      borderRadius: 0,
      placeholderLabel: 'Загрузка фото...',
      emptyLabel: 'Фото недоступно',
      errorLabel: 'Фото недоступно',
    );

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: isArchive ? null : onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: hasVipPromotion
                ? vipBorderColor(context)
                : Theme.of(context).dividerColor.withValues(alpha: 0.18),
            width: hasVipPromotion ? 1.25 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (isArchive)
                      ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ]),
                        child: Opacity(opacity: 0.78, child: image),
                      )
                    else
                      image,
                    ListingPromotionBadges(
                      showVip: hasVipPromotion,
                      showBump: hasBumpPromotion,
                    ),
                    if (isArchive)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isArchive) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: statusColor.withValues(alpha: 0.14),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    listing.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${listing.price} ₽',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (archiveNote != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      archiveNote,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
