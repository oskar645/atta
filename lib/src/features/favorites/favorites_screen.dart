import 'dart:async';

import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/saved_search_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:atta/src/widgets/listing_card.dart';
import 'package:atta/src/widgets/listing_promotion_badges.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  final Set<String> _pendingDeletedSearchKeys = <String>{};
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChanged);
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging || _tabController.index != 1) return;
    final userId = context.read<AuthService>().currentUser?.uid;
    if (userId == null || userId.isEmpty) return;
    unawaited(
      context
          .read<NotificationsService>()
          .markSavedSearchNotificationsRead(userId),
    );
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthService>().currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Нужно войти в аккаунт')),
      );
    }

    final favs = context.read<FavoritesService>();
    final follows = context.read<FollowService>();
    final listings = context.read<ListingsService>();
    final notifications = context.read<NotificationsService>();
    final savedSearches = context.read<SavedSearchService>();
    final history = context.watch<ListingHistoryService>();
    final reviews = context.read<ReviewsService>();

    if (ApiConfig.useTimewebBackend) {
      return _TimewebFavoritesScreen(
        tabController: _tabController,
        userId: user.uid,
        favs: favs,
        follows: follows,
        listings: listings,
        notifications: notifications,
        savedSearches: savedSearches,
        history: history,
        reviews: reviews,
        pendingDeletedSearchKeys: _pendingDeletedSearchKeys,
      );
    }

    return StreamBuilder<int>(
      stream: notifications.streamUnreadSavedSearchCount(user.uid),
      builder: (context, unreadSnap) {
        final hasUnreadSavedSearchMatches = (unreadSnap.data ?? 0) > 0;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Избранное'),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: [
                const Tab(text: 'Объявления'),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Поиски'),
                      if (hasUnreadSavedSearchMatches) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.brightness_1,
                            size: 8, color: Colors.red),
                      ],
                    ],
                  ),
                ),
                const Tab(text: 'Просмотренные'),
                const Tab(text: 'Подписки'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              StreamBuilder<Set<String>>(
                stream: favs.streamFavoriteIds(user.uid),
                builder: (context, favSnap) {
                  final idsSet = favSnap.data ?? <String>{};
                  if (idsSet.isEmpty) {
                    return const Center(
                      child: Text('Пока нет избранных объявлений'),
                    );
                  }

                  return StreamBuilder<List<Listing>>(
                    stream:
                        listings.streamListings(category: 'Все', search: ''),
                    builder: (context, listSnap) {
                      if (!listSnap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final all = listSnap.data ?? <Listing>[];
                      final favListings = all
                          .where((listing) => idsSet.contains(listing.id))
                          .toList();

                      final foundIds =
                          favListings.map((listing) => listing.id).toSet();
                      final missingIds = idsSet.difference(foundIds);
                      if (missingIds.isNotEmpty) {
                        for (final id in missingIds) {
                          favs.toggleFavorite(
                            uid: user.uid,
                            listingId: id,
                            makeFavorite: false,
                          );
                        }
                      }

                      if (favListings.isEmpty) {
                        return const Center(
                          child: Text('Нет доступных объявлений в избранном'),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: favListings.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final listing = favListings[i];
                          final photo = listing.photoUrls.isNotEmpty
                              ? listing.photoUrls.first
                              : null;

                          return ListTile(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ListingDetailScreen(listingId: listing.id),
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            tileColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLowest,
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Container(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      child: photo == null
                                          ? const Icon(
                                              Icons.image_not_supported_outlined)
                                          : CachedNetworkImage(
                                              imageUrl: photo,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                    ListingPromotionBadges(
                                      showVip: listing.hasVipPromotion,
                                      showBump: listing.hasBumpPromotion,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            title: Text(
                              listing.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                                '${formatPrice(listing.price)} ₽ • ${listing.category}'),
                            trailing: IconButton(
                              tooltip: 'Убрать из избранного',
                              icon:
                                  const Icon(Icons.favorite, color: Colors.red),
                              onPressed: () => favs.toggleFavorite(
                                uid: user.uid,
                                listingId: listing.id,
                                makeFavorite: false,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
              StreamBuilder<List<SavedSearch>>(
                stream: savedSearches.streamSavedSearches(user.uid),
                builder: (context, snap) {
                  final items = (snap.data ?? const <SavedSearch>[])
                      .where(
                        (item) =>
                            !_pendingDeletedSearchKeys.contains(item.queryKey),
                      )
                      .toList();
                  if (items.isEmpty) {
                    return const Center(
                      child: Text('Сохранённых поисков пока нет'),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final summary = savedSearches.buildSummary(
                        search: item.search,
                        filters: item.toFilters(),
                      );

                      return ListTile(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                _SavedSearchResultsScreen(savedSearch: item),
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        tileColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLowest,
                        leading: Icon(
                          item.alertsEnabled
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: item.alertsEnabled ? Colors.red : null,
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(summary),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: item.alertsEnabled
                                  ? 'Выключить уведомления'
                                  : 'Включить уведомления',
                              onPressed: () async {
                                try {
                                  await savedSearches.setAlertsEnabled(
                                    savedSearchId: item.id,
                                    enabled: !item.alertsEnabled,
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  final message = savedSearches
                                          .isMissingTableError(e)
                                      ? SavedSearchService.missingTableMessage
                                      : 'Не удалось обновить уведомления: $e';
                                  showAppSnack(context, message, isError: true);
                                }
                              },
                              icon: Icon(
                                item.alertsEnabled
                                    ? Icons.notifications_active
                                    : Icons.notifications_off_outlined,
                                color: item.alertsEnabled ? Colors.red : null,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Удалить поиск',
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) {
                                    return AlertDialog(
                                      title: const Text('Удалить поиск?'),
                                      content: Text(
                                        'Поиск "${item.title}" будет удалён из сохранённых.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(dialogContext)
                                                  .pop(false),
                                          child: const Text('Отмена'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.of(dialogContext)
                                                  .pop(true),
                                          child: const Text('Удалить'),
                                        ),
                                      ],
                                    );
                                  },
                                );

                                if (confirmed != true) return;

                                setState(() {
                                  _pendingDeletedSearchKeys.add(item.queryKey);
                                });

                                try {
                                  await savedSearches.deleteSavedSearch(
                                    userId: user.uid,
                                    queryKey: item.queryKey,
                                  );
                                  if (!context.mounted) return;
                                  showAppSnack(context, 'Поиск удалён');
                                } catch (e) {
                                  if (!context.mounted) return;
                                  setState(() {
                                    _pendingDeletedSearchKeys
                                        .remove(item.queryKey);
                                  });
                                  showAppSnack(
                                    context,
                                    'Не удалось удалить поиск: $e',
                                    isError: true,
                                  );
                                }
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
              _ViewedListingsTab(
                userId: user.uid,
                listings: listings,
                favs: favs,
                history: history,
                reviews: reviews,
              ),
              StreamBuilder<List<FollowedSeller>>(
                stream: follows.streamFollowedSellers(user.uid),
                builder: (context, followSnap) {
                  final followedSellers =
                      followSnap.data ?? const <FollowedSeller>[];
                  if (followedSellers.isEmpty) {
                    return const Center(
                      child: Text(
                          'Подпишитесь на продавцов, чтобы видеть их новые объявления'),
                    );
                  }

                  final followedSinceBySeller = <String, DateTime>{
                    for (final item in followedSellers)
                      item.sellerId: item.followedAt,
                  };

                  return StreamBuilder<Set<String>>(
                    stream: favs.streamFavoriteIds(user.uid),
                    builder: (context, favSnap) {
                      final favIds = favSnap.data ?? <String>{};

                      return StreamBuilder<List<Listing>>(
                        stream: listings.streamListings(
                            category: 'Все', search: ''),
                        builder: (context, listSnap) {
                          if (!listSnap.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          final all = listSnap.data ?? const <Listing>[];
                          final subscribedListings = all.where((listing) {
                            final followedAt =
                                followedSinceBySeller[listing.ownerId];
                            if (followedAt == null) return false;
                            return listing.createdAt.isAfter(followedAt);
                          }).toList()
                            ..sort(
                                (a, b) => b.createdAt.compareTo(a.createdAt));

                          if (subscribedListings.isEmpty) {
                            return const Center(
                              child: Text(
                                  'Пока нет новых объявлений по вашим подпискам'),
                            );
                          }

                          return GridView.builder(
                            padding: const EdgeInsets.all(10),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 0.72,
                            ),
                            itemCount: subscribedListings.length,
                            itemBuilder: (context, index) {
                              final item = subscribedListings[index];
                              return ListingCard(
                                listing: item,
                                isFav: favIds.contains(item.id),
                                isSeen: history.hasViewed(item.id),
                                reviews: reviews,
                                onToggleFav: (makeFav) async {
                                  try {
                                    await favs.toggleFavorite(
                                      uid: user.uid,
                                      listingId: item.id,
                                      makeFavorite: makeFav,
                                    );
                                  } catch (e) {
                                    if (context.mounted) {
                                      showAppSnack(
                                        context,
                                        'Не удалось изменить избранное: $e',
                                        isError: true,
                                      );
                                    }
                                  }
                                },
                                onOpen: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ListingDetailScreen(listingId: item.id),
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
            ],
          ),
        );
      },
    );
  }
}

class _ViewedListingsTab extends StatelessWidget {
  final String userId;
  final ListingsService listings;
  final FavoritesService favs;
  final ListingHistoryService history;
  final ReviewsService reviews;

  const _ViewedListingsTab({
    required this.userId,
    required this.listings,
    required this.favs,
    required this.history,
    required this.reviews,
  });

  @override
  Widget build(BuildContext context) {
    if (!history.isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final viewedIds = history.viewedIdsNewestFirst;
    if (viewedIds.isEmpty) {
      return const Center(child: Text('Вы ещё не просматривали объявления'));
    }

    return StreamBuilder<Set<String>>(
      stream: favs.streamFavoriteIds(userId),
      builder: (context, favSnap) {
        if (favSnap.hasError) {
          return Center(
            child: Text('Не удалось загрузить избранное: ${favSnap.error}'),
          );
        }

        if (!favSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final favIds = favSnap.data ?? const <String>{};

        return StreamBuilder<List<Listing>>(
          stream: listings.streamListings(category: 'Все', search: ''),
          builder: (context, listSnap) {
            if (listSnap.hasError) {
              return Center(
                child: Text(
                  'Не удалось загрузить просмотренные: ${listSnap.error}',
                ),
              );
            }

            if (!listSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final byId = <String, Listing>{
              for (final item in listSnap.data ?? const <Listing>[])
                item.id: item,
            };
            final items = viewedIds
                .map((id) => byId[id])
                .whereType<Listing>()
                .toList(growable: false);

            if (items.isEmpty) {
              return const Center(
                child: Text('Нет доступных просмотренных объявлений'),
              );
            }

            return GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.72,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListingCard(
                  listing: item,
                  isFav: favIds.contains(item.id),
                  isSeen: history.hasViewed(item.id),
                  reviews: reviews,
                  onToggleFav: (makeFav) async {
                    try {
                      await favs.toggleFavorite(
                        uid: userId,
                        listingId: item.id,
                        makeFavorite: makeFav,
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      showAppSnack(
                        context,
                        'Не удалось изменить избранное: $e',
                        isError: true,
                      );
                    }
                  },
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ListingDetailScreen(listingId: item.id),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _TimewebFavoritesScreen extends StatelessWidget {
  const _TimewebFavoritesScreen({
    required this.tabController,
    required this.userId,
    required this.favs,
    required this.follows,
    required this.listings,
    required this.notifications,
    required this.savedSearches,
    required this.history,
    required this.reviews,
    required this.pendingDeletedSearchKeys,
  });

  final TabController tabController;
  final String userId;
  final FavoritesService favs;
  final FollowService follows;
  final ListingsService listings;
  final NotificationsService notifications;
  final SavedSearchService savedSearches;
  final ListingHistoryService history;
  final ReviewsService reviews;
  final Set<String> pendingDeletedSearchKeys;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: notifications.streamUnreadSavedSearchCount(userId),
      builder: (context, unreadSnap) {
        final hasUnreadSavedSearchMatches = (unreadSnap.data ?? 0) > 0;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Избранное'),
            bottom: TabBar(
              controller: tabController,
              isScrollable: false,
              tabs: [
                const Tab(text: 'Объявления'),
                Tab(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Поиски'),
                        if (hasUnreadSavedSearchMatches) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.brightness_1,
                              size: 8, color: Colors.red),
                        ],
                      ],
                    ),
                  ),
                ),
                const Tab(text: 'Просмотренные'),
                const Tab(text: 'Подписки'),
              ],
            ),
          ),
          body: TabBarView(
            controller: tabController,
            children: [
              _TimewebFavoriteListingsTab(
                userId: userId,
                favs: favs,
                listings: listings,
              ),
              _TimewebSavedSearchesTab(
                userId: userId,
                savedSearches: savedSearches,
                pendingDeletedSearchKeys: pendingDeletedSearchKeys,
              ),
              _TimewebViewedListingsTab(
                userId: userId,
                listings: listings,
                favs: favs,
                history: history,
                reviews: reviews,
              ),
              _TimewebFollowedListingsTab(
                userId: userId,
                follows: follows,
                listings: listings,
                favs: favs,
                history: history,
                reviews: reviews,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimewebFavoriteListingsTab extends StatefulWidget {
  const _TimewebFavoriteListingsTab({
    required this.userId,
    required this.favs,
    required this.listings,
  });

  final String userId;
  final FavoritesService favs;
  final ListingsService listings;

  @override
  State<_TimewebFavoriteListingsTab> createState() =>
      _TimewebFavoriteListingsTabState();
}

class _TimewebFavoriteListingsTabState
    extends State<_TimewebFavoriteListingsTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Listing>> _listingsFuture;
  List<Listing>? _items;
  bool _loading = true;
  bool _loadedOnce = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final cachedIds = widget.favs.peekFavoriteIds(widget.userId);
    final cachedListings =
        widget.listings.peekListings(category: 'Все', search: '');
    if (cachedIds.isNotEmpty && cachedListings.isNotEmpty) {
      _items = cachedListings
          .where((listing) => cachedIds.contains(listing.id))
          .toList(growable: false);
      _loading = false;
    }
    _listingsFuture = _loadListings();
  }

  Future<List<Listing>> _loadListings() async {
    final all = await widget.listings.getListings(category: 'Все', search: '');
    final favoriteIds = await widget.favs.getFavoriteIds(widget.userId);
    final items = all
        .where((listing) => favoriteIds.contains(listing.id))
        .toList(growable: false);
    if (!mounted) return items;
    setState(() {
      _items = items;
      _loading = false;
      _loadedOnce = true;
      _errorText = null;
    });
    return items;
  }

  Future<void> _refresh() async {
    final next = _loadListings();
    setState(() => _listingsFuture = next);
    try {
      await Future.wait([
        widget.favs.refreshFavoriteIds(widget.userId),
        next,
      ]);
    } catch (_) {}
  }

  Future<void> _removeFavorite(String listingId) async {
    await widget.favs.toggleFavorite(
      uid: widget.userId,
      listingId: listingId,
      makeFavorite: false,
    );
    await _refresh();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<Set<String>>(
      stream: widget.favs.streamFavoriteIds(widget.userId),
      initialData: widget.favs.peekFavoriteIds(widget.userId),
      builder: (context, favSnap) {
        return FutureBuilder<List<Listing>>(
          future: _listingsFuture,
          builder: (context, snap) {
            final items = _items ?? snap.data ?? const <Listing>[];
            if (favSnap.hasError) {
              return _FavoritesAsyncStateView(
                message: 'Не удалось загрузить избранное.',
                onRetry: _refresh,
              );
            }
            if (snap.hasError) {
              _errorText ??= 'Не удалось загрузить избранное.';
            }
            final favoriteIds = favSnap.data ?? const <String>{};
            if (_loading && items.isEmpty) {
              return const _FavoritesListingsSkeleton();
            }
            if (_errorText != null && items.isEmpty) {
              return _FavoritesAsyncStateView(
                message: _errorText!,
                onRetry: _refresh,
              );
            }

            if (_loadedOnce && favoriteIds.isEmpty) {
              return _RefreshableEmptyState(
                message: 'Пока нет избранных объявлений',
                onRefresh: _refresh,
              );
            }
            if (_loadedOnce && items.isEmpty) {
              return _RefreshableEmptyState(
                message: 'Нет доступных объявлений в избранном',
                onRefresh: _refresh,
              );
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final listing = items[i];
                  final photo = listing.photoUrls.isNotEmpty
                      ? listing.photoUrls.first
                      : null;

                  return ListTile(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ListingDetailScreen(listingId: listing.id),
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    tileColor:
                        Theme.of(context).colorScheme.surfaceContainerLowest,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: photo == null
                                  ? const Icon(Icons.image_not_supported_outlined)
                                  : CachedNetworkImage(
                                      imageUrl: photo,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                            ListingPromotionBadges(
                              showVip: listing.hasVipPromotion,
                              showBump: listing.hasBumpPromotion,
                            ),
                          ],
                        ),
                      ),
                    ),
                    title: Text(
                      listing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${formatPrice(listing.price)} ₽ • ${listing.category}'),
                    trailing: IconButton(
                      tooltip: 'Убрать из избранного',
                      icon: const Icon(Icons.favorite, color: Colors.red),
                      onPressed: () => _removeFavorite(listing.id),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _TimewebSavedSearchesTab extends StatefulWidget {
  const _TimewebSavedSearchesTab({
    required this.userId,
    required this.savedSearches,
    required this.pendingDeletedSearchKeys,
  });

  final String userId;
  final SavedSearchService savedSearches;
  final Set<String> pendingDeletedSearchKeys;

  @override
  State<_TimewebSavedSearchesTab> createState() =>
      _TimewebSavedSearchesTabState();
}

class _TimewebSavedSearchesTabState extends State<_TimewebSavedSearchesTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<SavedSearch>> _future;
  List<SavedSearch>? _items;
  bool _loading = true;
  bool _loadedOnce = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final cached = widget.savedSearches.peekSavedSearches(widget.userId);
    if (cached.isNotEmpty) {
      _items = cached;
      _loading = false;
    }
    _future = _load();
  }

  Future<List<SavedSearch>> _load() async {
    final items = await widget.savedSearches.getSavedSearches(widget.userId);
    if (!mounted) return items;
    setState(() {
      _items = items;
      _loading = false;
      _loadedOnce = true;
      _errorText = null;
    });
    return items;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    try {
      await widget.savedSearches.refreshSavedSearches(widget.userId);
      await next;
    } catch (_) {}
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<SavedSearch>>(
      future: _future,
      builder: (context, snap) {
        final items = (_items ?? snap.data ?? const <SavedSearch>[])
            .where((item) =>
                !widget.pendingDeletedSearchKeys.contains(item.queryKey))
            .toList();
        if (_loading && items.isEmpty) {
          return const _FavoritesListTileSkeleton();
        }
        if (snap.hasError) {
          _errorText ??= 'Не удалось загрузить сохранённые поиски.';
        }
        if (_errorText != null && items.isEmpty) {
          return _FavoritesAsyncStateView(
            message: _errorText!,
            onRetry: _refresh,
          );
        }
        if (_loadedOnce && items.isEmpty) {
          return _RefreshableEmptyState(
            message: 'Сохранённых поисков пока нет',
            onRefresh: _refresh,
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final item = items[i];
              final summary = widget.savedSearches.buildSummary(
                search: item.search,
                filters: item.toFilters(),
              );

              return ListTile(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        _SavedSearchResultsScreen(savedSearch: item),
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                tileColor: Theme.of(context).colorScheme.surfaceContainerLowest,
                leading: Icon(
                  item.alertsEnabled ? Icons.favorite : Icons.favorite_border,
                  color: item.alertsEnabled ? Colors.red : null,
                ),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(summary),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: item.alertsEnabled
                          ? 'Выключить уведомления'
                          : 'Включить уведомления',
                      onPressed: () async {
                        try {
                          await widget.savedSearches.setAlertsEnabled(
                            savedSearchId: item.id,
                            enabled: !item.alertsEnabled,
                          );
                          if (!context.mounted) return;
                          await _refresh();
                        } catch (e) {
                          if (!context.mounted) return;
                          final message =
                              widget.savedSearches.isMissingTableError(e)
                                  ? SavedSearchService.missingTableMessage
                                  : 'Не удалось обновить уведомления: $e';
                          showAppSnack(context, message, isError: true);
                        }
                      },
                      icon: Icon(
                        item.alertsEnabled
                            ? Icons.notifications_active
                            : Icons.notifications_off_outlined,
                        color: item.alertsEnabled ? Colors.red : null,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Удалить поиск',
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) {
                                return AlertDialog(
                                  title: const Text('Удалить поиск?'),
                                  content: Text(
                                    'Поиск "${item.title}" будет удалён из сохранённых.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(dialogContext)
                                              .pop(false),
                                      child: const Text('Отмена'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(true),
                                      child: const Text('Удалить'),
                                    ),
                                  ],
                                );
                              },
                            ) ??
                            false;
                        if (!confirmed) return;

                        setState(() {
                          widget.pendingDeletedSearchKeys.add(item.queryKey);
                        });
                        try {
                          await widget.savedSearches.deleteSavedSearch(
                            userId: widget.userId,
                            queryKey: item.queryKey,
                          );
                          if (!context.mounted) return;
                          showAppSnack(context, 'Поиск удалён');
                          await _refresh();
                        } catch (e) {
                          if (!context.mounted) return;
                          setState(() {
                            widget.pendingDeletedSearchKeys
                                .remove(item.queryKey);
                          });
                          showAppSnack(
                            context,
                            'Не удалось удалить поиск: $e',
                            isError: true,
                          );
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _TimewebViewedListingsTab extends StatefulWidget {
  const _TimewebViewedListingsTab({
    required this.userId,
    required this.listings,
    required this.favs,
    required this.history,
    required this.reviews,
  });

  final String userId;
  final ListingsService listings;
  final FavoritesService favs;
  final ListingHistoryService history;
  final ReviewsService reviews;

  @override
  State<_TimewebViewedListingsTab> createState() =>
      _TimewebViewedListingsTabState();
}

class _TimewebViewedListingsTabState extends State<_TimewebViewedListingsTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Listing>> _future;
  List<Listing>? _items;
  bool _loading = true;
  bool _loadedOnce = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final cachedListings =
        widget.listings.peekListings(category: 'Все', search: '');
    if (cachedListings.isNotEmpty &&
        widget.history.viewedIdsNewestFirst.isNotEmpty) {
      final byId = {
        for (final item in cachedListings) item.id: item,
      };
      _items = widget.history.viewedIdsNewestFirst
          .map((id) => byId[id])
          .whereType<Listing>()
          .toList(growable: false);
      _loading = false;
    }
    _future = _load();
  }

  Future<List<Listing>> _load() async {
    final byId = {
      for (final item
          in await widget.listings.getListings(category: 'Все', search: ''))
        item.id: item,
    };
    final items = widget.history.viewedIdsNewestFirst
        .map((id) => byId[id])
        .whereType<Listing>()
        .toList(growable: false);
    if (!mounted) return items;
    setState(() {
      _items = items;
      _loading = false;
      _loadedOnce = true;
      _errorText = null;
    });
    return items;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {}
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!widget.history.isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<Set<String>>(
      stream: widget.favs.streamFavoriteIds(widget.userId),
      initialData: widget.favs.peekFavoriteIds(widget.userId),
      builder: (context, favSnap) {
        return FutureBuilder<List<Listing>>(
          future: _future,
          builder: (context, snap) {
            final items = _items ?? snap.data ?? const <Listing>[];
            if (_loading && items.isEmpty) {
              return const _FavoritesGridSkeleton();
            }
            if (snap.hasError) {
              _errorText ??= 'Не удалось загрузить просмотренные.';
            }
            if (_errorText != null && items.isEmpty) {
              return _FavoritesAsyncStateView(
                message: _errorText!,
                onRetry: _refresh,
              );
            }
            final favIds = favSnap.data ?? const <String>{};
            if (_loadedOnce && widget.history.viewedIdsNewestFirst.isEmpty) {
              return _RefreshableEmptyState(
                message: 'Вы ещё не просматривали объявления',
                onRefresh: _refresh,
              );
            }
            if (_loadedOnce && items.isEmpty) {
              return _RefreshableEmptyState(
                message: 'Нет доступных просмотренных объявлений',
                onRefresh: _refresh,
              );
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              child: GridView.builder(
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.72,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListingCard(
                    listing: item,
                    isFav: favIds.contains(item.id),
                    isSeen: widget.history.hasViewed(item.id),
                    reviews: widget.reviews,
                    onToggleFav: (makeFav) async {
                      try {
                        await widget.favs.toggleFavorite(
                          uid: widget.userId,
                          listingId: item.id,
                          makeFavorite: makeFav,
                        );
                        if (context.mounted) {
                          await _refresh();
                        }
                      } catch (e) {
                        if (!context.mounted) return;
                        showAppSnack(
                          context,
                          'Не удалось изменить избранное: $e',
                          isError: true,
                        );
                      }
                    },
                    onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ListingDetailScreen(listingId: item.id),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _TimewebFollowedListingsTab extends StatefulWidget {
  const _TimewebFollowedListingsTab({
    required this.userId,
    required this.follows,
    required this.listings,
    required this.favs,
    required this.history,
    required this.reviews,
  });

  final String userId;
  final FollowService follows;
  final ListingsService listings;
  final FavoritesService favs;
  final ListingHistoryService history;
  final ReviewsService reviews;

  @override
  State<_TimewebFollowedListingsTab> createState() =>
      _TimewebFollowedListingsTabState();
}

class _TimewebFollowedListingsTabState
    extends State<_TimewebFollowedListingsTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Listing>> _future;
  List<Listing>? _items;
  bool _loading = true;
  bool _loadedOnce = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final cachedFollowed = widget.follows.peekFollowedSellers(widget.userId);
    final cachedListings =
        widget.listings.peekListings(category: 'Все', search: '');
    if (cachedFollowed.isNotEmpty && cachedListings.isNotEmpty) {
      final followedSinceBySeller = <String, DateTime>{
        for (final item in cachedFollowed) item.sellerId: item.followedAt,
      };
      _items = cachedListings.where((listing) {
        final followedAt = followedSinceBySeller[listing.ownerId];
        if (followedAt == null) return false;
        return listing.createdAt.isAfter(followedAt);
      }).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _loading = false;
    }
    _future = _load();
  }

  Future<List<Listing>> _load() async {
    final followed = await widget.follows.getFollowedSellers(widget.userId);
    final followedSinceBySeller = <String, DateTime>{
      for (final item in followed) item.sellerId: item.followedAt,
    };
    final all = await widget.listings.getListings(category: 'Все', search: '');
    final items = all.where((listing) {
      final followedAt = followedSinceBySeller[listing.ownerId];
      if (followedAt == null) return false;
      return listing.createdAt.isAfter(followedAt);
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return items;
    setState(() {
      _items = items;
      _loading = false;
      _loadedOnce = true;
      _errorText = null;
    });
    return items;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    try {
      await widget.follows.refreshFollowedSellers(widget.userId);
      await next;
    } catch (_) {}
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<Set<String>>(
      stream: widget.favs.streamFavoriteIds(widget.userId),
      initialData: widget.favs.peekFavoriteIds(widget.userId),
      builder: (context, favSnap) {
        return FutureBuilder<List<Listing>>(
          future: _future,
          builder: (context, snap) {
            final items = _items ?? snap.data ?? const <Listing>[];
            if (_loading && items.isEmpty) {
              return const _FavoritesGridSkeleton();
            }
            if (snap.hasError) {
              _errorText ??= 'Не удалось загрузить подписки.';
            }
            if (_errorText != null && items.isEmpty) {
              return _FavoritesAsyncStateView(
                message: _errorText!,
                onRetry: _refresh,
              );
            }
            final favIds = favSnap.data ?? const <String>{};
            if (_loadedOnce && items.isEmpty) {
              return _RefreshableEmptyState(
                message:
                    'Подпишитесь на продавцов, чтобы видеть их новые объявления',
                onRefresh: _refresh,
              );
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              child: GridView.builder(
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.72,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListingCard(
                    listing: item,
                    isFav: favIds.contains(item.id),
                    isSeen: widget.history.hasViewed(item.id),
                    reviews: widget.reviews,
                    onToggleFav: (makeFav) async {
                      try {
                        await widget.favs.toggleFavorite(
                          uid: widget.userId,
                          listingId: item.id,
                          makeFavorite: makeFav,
                        );
                        if (context.mounted) {
                          await _refresh();
                        }
                      } catch (e) {
                        if (!context.mounted) return;
                        showAppSnack(
                          context,
                          'Не удалось изменить избранное: $e',
                          isError: true,
                        );
                      }
                    },
                    onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ListingDetailScreen(listingId: item.id),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _FavoritesAsyncStateView extends StatelessWidget {
  const _FavoritesAsyncStateView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefreshableEmptyState extends StatelessWidget {
  const _RefreshableEmptyState({
    required this.message,
    required this.onRefresh,
  });

  final String message;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 180),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoritesListingsSkeleton extends StatelessWidget {
  const _FavoritesListingsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: const [
        SkeletonAdminModerationCard(),
        SizedBox(height: 10),
        SkeletonAdminModerationCard(),
        SizedBox(height: 10),
        SkeletonAdminModerationCard(),
      ],
    );
  }
}

class _FavoritesListTileSkeleton extends StatelessWidget {
  const _FavoritesListTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: const [
        SkeletonNotificationRow(),
        SizedBox(height: 10),
        SkeletonNotificationRow(),
        SizedBox(height: 10),
        SkeletonNotificationRow(),
      ],
    );
  }
}

class _FavoritesGridSkeleton extends StatelessWidget {
  const _FavoritesGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonListingGrid(
      itemCount: 4,
      shrinkWrap: false,
      physics: AlwaysScrollableScrollPhysics(),
    );
  }
}

class _SavedSearchResultsScreen extends StatelessWidget {
  final SavedSearch savedSearch;

  const _SavedSearchResultsScreen({required this.savedSearch});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final user = auth.currentUser!;
    final listings = context.read<ListingsService>();
    final favs = context.read<FavoritesService>();
    final history = context.watch<ListingHistoryService>();
    final reviews = context.read<ReviewsService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          savedSearch.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.read<SavedSearchService>().buildSummary(
                      search: savedSearch.search,
                      filters: savedSearch.toFilters(),
                    ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.75),
                    ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<Set<String>>(
              stream: favs.streamFavoriteIds(user.uid),
              builder: (context, favSnap) {
                final favIds = favSnap.data ?? <String>{};

                return StreamBuilder<List<Listing>>(
                  stream: listings.streamListings(
                    category: savedSearch.category,
                    search: savedSearch.search,
                    filters: savedSearch.toFilters(),
                  ),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final items = snap.data!;
                    if (items.isEmpty) {
                      return const Center(child: Text('Ничего не найдено'));
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListingCard(
                          listing: item,
                          isFav: favIds.contains(item.id),
                          isSeen: history.hasViewed(item.id),
                          reviews: reviews,
                          onToggleFav: (makeFav) async {
                            try {
                              await favs.toggleFavorite(
                                uid: user.uid,
                                listingId: item.id,
                                makeFavorite: makeFav,
                              );
                            } catch (e) {
                              if (context.mounted) {
                                showAppSnack(
                                  context,
                                  'Не удалось изменить избранное: $e',
                                  isError: true,
                                );
                              }
                            }
                          },
                          onOpen: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ListingDetailScreen(listingId: item.id),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
