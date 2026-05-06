import 'dart:async';

import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/saved_search_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/widgets/listing_card.dart';
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
                              child: Container(
                                width: 56,
                                height: 56,
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
                            ),
                            title: Text(
                              listing.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                                '${listing.price} ₽ • ${listing.category}'),
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
