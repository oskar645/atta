import 'dart:async';

import 'package:atta/src/features/inbox/chat_screen.dart';
import 'package:atta/src/features/admin/admin_support_message_dialog.dart';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/features/reviews/seller_reviews_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:atta/src/widgets/listing_promotion_badges.dart';
import 'package:atta/src/widgets/admin_copy_user_id_button.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:atta/src/widgets/presence_badge.dart';
import 'package:atta/src/widgets/remote_avatar.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
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
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<_SellerListingsSectionState> _activeListingsKey =
      GlobalKey<_SellerListingsSectionState>();
  final GlobalKey<_SellerListingsSectionState> _archiveListingsKey =
      GlobalKey<_SellerListingsSectionState>();
  bool _followBusy = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _scrollController.addListener(_handleScroll);
    _tab.addListener(() {
      if (!_tab.indexIsChanging && mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _handleRefresh({
    required ProfileService profile,
    required ReviewsService reviews,
  }) async {
    final currentListingsKey =
        _tab.index == 1 ? _archiveListingsKey : _activeListingsKey;
    await Future.wait<void>(<Future<void>>[
      currentListingsKey.currentState?.refresh() ?? Future<void>.value(),
      reviews.refreshSellerReviews(widget.sellerId).then((_) {}),
      profile.getProfile(widget.sellerId).then((_) {}),
    ]);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tab.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels > 420) return;
    final currentListingsKey =
        _tab.index == 1 ? _archiveListingsKey : _activeListingsKey;
    currentListingsKey.currentState?.loadMore();
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

  String _maskedPhone(String rawPhone) {
    final digits = normalizeRuPhoneForApi(rawPhone);
    if (digits.length < 5) return '';
    return '+${digits.substring(0, 1)} *** *** ${digits.substring(digits.length - 4)}';
  }

  String _supportHandle(Map<String, dynamic> userRow, String phone) {
    final candidates = <dynamic>[
      userRow['nickname'],
      userRow['username'],
      userRow['user_name'],
    ];
    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) return '@$value';
    }
    return _maskedPhone(phone);
  }

  Future<void> _writeSupportMessage({
    required String userName,
    required String userHandle,
  }) async {
    final result = await showAdminSupportMessageDialog(
      context: context,
      userId: widget.sellerId,
      userName: userName,
      userHandle: userHandle,
    );
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Сообщение отправлено')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.read<ProfileService>();
    final reviews = context.read<ReviewsService>();
    final listingsSvc = context.read<ListingsService>();
    final chats = context.read<ChatService>();
    final follows = context.read<FollowService>();
    final presence = context.read<PresenceService>();
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

          return RefreshIndicator(
            onRefresh: () => _handleRefresh(profile: profile, reviews: reviews),
            child: ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.18),
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
                                AdminCopyUserIdButton(userId: widget.sellerId),
                              ],
                            ),
                            const SizedBox(height: 6),
                            StreamBuilder<Map<String, dynamic>>(
                              stream:
                                  reviews.streamSellerRating(widget.sellerId),
                              builder: (_, rSnap) {
                                final rating = rSnap.data ??
                                    const {'avg': 0.0, 'count': 0};
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
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
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
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.tonalIcon(
                                  onPressed: () => _writeSupportMessage(
                                    userName: sellerName,
                                    userHandle: _supportHandle(userRow, phone),
                                  ),
                                  icon: const Icon(Icons.support_agent),
                                  label: const Text('Написать'),
                                ),
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
                                ? Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer
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
                  title: const Text('Отзывы продавца'),
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
                    return Column(
                      children: [
                        Offstage(
                          offstage: _tab.index != 0,
                          child: _SellerListingsSection(
                            key: _activeListingsKey,
                            ownerId: widget.sellerId,
                            listingsService: listingsSvc,
                            isArchive: false,
                          ),
                        ),
                        Offstage(
                          offstage: _tab.index != 1,
                          child: _SellerListingsSection(
                            key: _archiveListingsKey,
                            ownerId: widget.sellerId,
                            listingsService: listingsSvc,
                            isArchive: true,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
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

class _SellerListingsSection extends StatefulWidget {
  const _SellerListingsSection({
    super.key,
    required this.ownerId,
    required this.listingsService,
    required this.isArchive,
  });

  final String ownerId;
  final ListingsService listingsService;
  final bool isArchive;

  @override
  State<_SellerListingsSection> createState() => _SellerListingsSectionState();
}

class _SellerListingsSectionState extends State<_SellerListingsSection> {
  static const int _pageSize = 20;
  late StreamSubscription<void> _refreshSubscription;
  List<Listing> _allItems = const <Listing>[];
  Object? _error;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _nextCursor;

  @override
  void initState() {
    super.initState();
    _allItems = widget.isArchive
        ? const <Listing>[]
        : widget.listingsService
            .peekListingsByOwner(widget.ownerId)
            .where((item) => item.status == 'approved')
            .toList(growable: false);
    _refreshSubscription = widget.listingsService.refreshes.listen((_) {
      unawaited(_load(forceRefresh: true));
    });
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _SellerListingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId == widget.ownerId &&
        oldWidget.isArchive == widget.isArchive) {
      return;
    }
    _allItems = widget.isArchive
        ? const <Listing>[]
        : widget.listingsService
            .peekListingsByOwner(widget.ownerId)
            .where((item) => item.status == 'approved')
            .toList(growable: false);
    _error = null;
    _nextCursor = null;
    _hasMore = false;
    _isLoadingMore = false;
    unawaited(_load(forceRefresh: true));
  }

  @override
  void dispose() {
    _refreshSubscription.cancel();
    super.dispose();
  }

  Future<void> refresh() => _load(forceRefresh: true);

  Future<void> _load({bool forceRefresh = false}) async {
    if (_isLoading) return;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isLoadingMore = false;
        _error = null;
      });
    } else {
      _isLoading = true;
      _isLoadingMore = false;
      _error = null;
    }
    try {
      final page = await widget.listingsService.getPublicOwnerListingsPage(
        ownerId: widget.ownerId,
        status: widget.isArchive ? 'archive' : 'approved',
        limit: _pageSize,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _allItems = _dedupe(page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore && (page.nextCursor ?? '').trim().isNotEmpty;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore || _nextCursor == null) {
      return;
    }
    setState(() {
      _isLoadingMore = true;
      _error = null;
    });
    try {
      final page = await widget.listingsService.getPublicOwnerListingsPage(
        ownerId: widget.ownerId,
        status: widget.isArchive ? 'archive' : 'approved',
        limit: _pageSize,
        cursor: _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        _allItems = _dedupe(<Listing>[..._allItems, ...page.items]);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore && (page.nextCursor ?? '').trim().isNotEmpty;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoadingMore = false;
      });
    }
  }

  List<Listing> _dedupe(List<Listing> items) {
    final allowed = widget.isArchive
        ? const <String>{'archived', 'sold'}
        : const <String>{'approved'};
    final byId = <String, Listing>{};
    for (final item in items) {
      if (allowed.contains(item.status)) {
        byId[item.id] = item;
      }
    }
    return byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _allItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Ошибка объявлений: $_error'),
      );
    }

    final cardAspectRatio = widget.isArchive ? 0.66 : 0.72;

    if (_isLoading && _allItems.isEmpty) {
      return GridView.builder(
        itemCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: cardAspectRatio,
        ),
        itemBuilder: (_, __) => const SkeletonListingCard(),
      );
    }

    final items = _allItems;
    if (items.isEmpty) {
      return Center(
        child: Text(
          widget.isArchive ? 'Архив пуст' : 'Пока нет объявлений',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }

    final grid = GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: cardAspectRatio,
      ),
      itemBuilder: (_, i) => _ListingCard(
        listing: items[i],
        isArchive: widget.isArchive,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ListingDetailScreen(listingId: items[i].id),
            ),
          );
        },
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isLoading && _allItems.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Не удалось обновить объявления',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        if (widget.isArchive)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Text(
              'Архив: история объявлений продавца (продано, снято с продажи).',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        grid,
        if (_isLoadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
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
      case 'archived':
        return Colors.grey;
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
