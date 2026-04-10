import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:atta/src/constants/categories.dart';
import 'package:atta/src/data/auto_catalog.dart';
import 'package:atta/src/features/listings/add_listing_screen.dart';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/features/notifications/notifications_screen.dart';
import 'package:atta/src/models/feed_ad.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/feed_ads_service.dart';
import 'package:atta/src/services/home_filters_session.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/saved_search_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/widgets/feed_ad_banner.dart';
import 'package:atta/src/widgets/listing_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _category = 'Все';
  String _subcategory = 'Все';
  String _search = '';
  final _searchCtrl = TextEditingController();

  // Avito-like location filter.
  String _location = ''; // "Москва", "Чеченская Республика" и т.п.
  bool _preferLocationFirst = false; // "Сначала из ..."
  int? _radiusKm; // 1/2/3/5/10 км или null
  String _autoBrand = '';
  String _autoModel = '';
  String _autoCondition = '';
  int? _autoMileageTo;
  bool _onlyUncrashed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreFilters();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _restoreFilters() async {
    final uid = context.read<AuthService>().currentUser?.uid ?? '';
    final saved = await homeFiltersSession.read(uid);
    if (saved == null) return;

    setState(() {
      _category = saved.category;
      _subcategory = saved.subcategory;
      _location = saved.location;
      _preferLocationFirst = saved.preferLocationFirst;
      _radiusKm = saved.radiusKm;
      _autoBrand = saved.autoBrand;
      _autoModel = saved.autoModel;
      _autoCondition = saved.autoCondition;
      _autoMileageTo = saved.autoMileageTo;
      _onlyUncrashed = saved.onlyUncrashed;
      _search = saved.search;
      _searchCtrl.text = saved.search;
    });
  }

  Future<void> _persistFilters() async {
    final uid = context.read<AuthService>().currentUser?.uid ?? '';

    await homeFiltersSession.write(
      uid: uid,
      category: _category,
      subcategory: _subcategory,
      location: _location,
      preferLocationFirst: _preferLocationFirst,
      radiusKm: _radiusKm,
      autoBrand: _autoBrand,
      autoModel: _autoModel,
      autoCondition: _autoCondition,
      autoMileageTo: _autoMileageTo,
      onlyUncrashed: _onlyUncrashed,
      search: _search,
    );
  }

  void _selectCategory(String c) {
    setState(() {
      _category = c;
      _subcategory = 'Все';
      _search = '';
      _searchCtrl.clear();
    });
    _persistFilters();
  }

  Future<void> _openFilters() async {
    final res = await Navigator.of(context).push<_HomeFilters>(
      MaterialPageRoute(
        builder: (_) => _FiltersScreen(
          initialCategory: _category,
          initialSubcategory: _subcategory,
          initialLocation: _location,
          initialPreferFirst: _preferLocationFirst,
          initialRadiusKm: _radiusKm,
          initialAutoBrand: _autoBrand,
          initialAutoModel: _autoModel,
          initialAutoCondition: _autoCondition,
          initialAutoMileageTo: _autoMileageTo,
          initialOnlyUncrashed: _onlyUncrashed,
        ),
      ),
    );

    if (!mounted || res == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FilteredListingsScreen(
          search: _search,
          filters: res,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listings = context.read<ListingsService>();
    final favs = context.read<FavoritesService>();
    final feedAds = context.read<FeedAdsService>();
    final history = context.watch<ListingHistoryService>();
    final reviews = context.read<ReviewsService>();
    final notifications = context.read<NotificationsService>();
    final user = context.read<AuthService>().currentUser!;

    // Search hint in Avito-like format: "Поиск в <локация>".
    final hint =
        _location.trim().isEmpty ? 'Поиск по названию' : 'Поиск в $_location';

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const _HomeBrandTitle(),
        actions: [
          StreamBuilder<int>(
            stream: notifications.streamUnreadBadgeCount(user.uid),
            builder: (context, snap) {
              final unread = snap.data ?? 0;
              final icon = IconButton(
                tooltip: 'Уведомления',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                  await notifications.markAllSeen(user.uid);
                  if (!mounted) return;
                  setState(() {});
                },
                padding: const EdgeInsets.symmetric(horizontal: 8),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      unread > 0
                          ? Icons.notifications_active
                          : Icons.notifications_outlined,
                      color: unread > 0 ? Colors.red : null,
                    ),
                    if (unread > 0)
                      Positioned(
                        right: -8,
                        top: -6,
                        child: Container(
                          constraints:
                              const BoxConstraints(minWidth: 14, minHeight: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              fontSize: 8,
                              height: 1.0,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
              return icon;
            },
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddListingScreen()),
            ),
            icon: const Icon(Icons.add_circle, color: Colors.blue, size: 28),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Column(
              children: [
                _CategoryRow(selected: _category, onSelect: _selectCategory),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Фильтры',
                        onPressed: _openFilters,
                        icon: const Icon(Icons.tune),
                      ),
                      hintText: hint,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.6,
                        ),
                      ),
                    ),
                    onChanged: (v) {
                      setState(() => _search = v.trim());
                      _persistFilters();
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<Set<String>>(
              stream: favs.streamFavoriteIds(user.uid),
              builder: (context, favSnap) {
                final favIds = favSnap.data ?? <String>{};

                return StreamBuilder<List<Listing>>(
                  stream: listings.streamListings(
                    category: _category,
                    search: _search,
                    filters: ListingFeedFilters(
                      category: _category,
                      search: _search,
                      subcategory: _subcategory,
                      location: _location,
                      preferLocationFirst: _preferLocationFirst,
                      radiusKm: _radiusKm,
                      autoBrand: _autoBrand,
                      autoModel: _autoModel,
                      autoCondition: _autoCondition,
                      autoMileageTo: _autoMileageTo,
                      onlyUncrashed: _onlyUncrashed,
                    ),
                  ),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    var items = snap.data!;
                    if (items.isEmpty) {
                      return const Center(
                          child: Text('Пока нет объявлений'));
                    }

                    return StreamBuilder<FeedAd?>(
                      stream: feedAds.streamActiveAd(),
                      builder: (context, adSnap) {
                        return _HomeFeedView(
                          items: items,
                          ad: adSnap.data,
                          favIds: favIds,
                          history: history,
                          reviews: reviews,
                          favs: favs,
                          userId: user.uid,
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

class _HomeFeedView extends StatefulWidget {
  final List<Listing> items;
  final FeedAd? ad;
  final Set<String> favIds;
  final ListingHistoryService history;
  final ReviewsService reviews;
  final FavoritesService favs;
  final String userId;

  const _HomeFeedView({
    required this.items,
    required this.ad,
    required this.favIds,
    required this.history,
    required this.reviews,
    required this.favs,
    required this.userId,
  });

  @override
  State<_HomeFeedView> createState() => _HomeFeedViewState();
}

class _HomeFeedViewState extends State<_HomeFeedView> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _adKey = GlobalKey();
  bool _adVisible = false;
  bool _trackingImpression = false;

  static const _gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    childAspectRatio: 0.72,
  );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scheduleVisibilityCheck);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAdVisibility());
  }

  @override
  void didUpdateWidget(covariant _HomeFeedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ad?.id != widget.ad?.id) {
      _adVisible = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAdVisibility());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scheduleVisibilityCheck);
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleVisibilityCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAdVisibility());
  }

  Future<void> _checkAdVisibility() async {
    if (!mounted) return;
    final ad = widget.ad;
    if (ad == null || !ad.isVisibleNow) {
      _adVisible = false;
      return;
    }

    final context = _adKey.currentContext;
    if (context == null) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final offset = renderObject.localToGlobal(Offset.zero);
    final rect = offset & renderObject.size;
    final screenHeight = MediaQuery.sizeOf(this.context).height;
    final visible = rect.bottom > 0 && rect.top < screenHeight;

    if (visible && !_adVisible) {
      _adVisible = true;
      if (_trackingImpression) return;
      _trackingImpression = true;
      try {
        await this.context.read<FeedAdsService>().recordImpression(ad.id);
      } catch (_) {
      } finally {
        _trackingImpression = false;
      }
      return;
    }

    if (!visible) {
      _adVisible = false;
    }
  }

  Future<void> _openAd(FeedAd ad) async {
    if (!ad.hasLink) return;
    final uri = Uri.tryParse(ad.targetUrl);
    if (uri == null) return;
    try {
      await context.read<FeedAdsService>().recordClick(ad.id);
    } catch (_) {}
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildCard(BuildContext context, Listing item) {
    return ListingCard(
      listing: item,
      isFav: widget.favIds.contains(item.id),
      isSeen: widget.history.hasViewed(item.id),
      reviews: widget.reviews,
      onToggleFav: (makeFav) async {
        try {
          await widget.favs.toggleFavorite(
            uid: widget.userId,
            listingId: item.id,
            makeFavorite: makeFav,
          );
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Не удалось изменить избранное: $e')),
            );
          }
        }
      },
      onOpen: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ListingDetailScreen(listingId: item.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleAd = widget.ad != null && widget.ad!.isVisibleNow;
    final firstChunk = visibleAd ? widget.items.take(2).toList() : widget.items;
    final restChunk =
        visibleAd ? widget.items.skip(2).toList() : const <Listing>[];

    return CustomScrollView(
      controller: _scrollController,
      clipBehavior: Clip.hardEdge,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          sliver: SliverGrid(
            gridDelegate: _gridDelegate,
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildCard(context, firstChunk[index]),
              childCount: firstChunk.length,
            ),
          ),
        ),
        if (visibleAd)
          SliverToBoxAdapter(
            child: Padding(
              key: _adKey,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: FeedAdBanner(
                ad: widget.ad!,
                onTap: widget.ad!.hasLink ? () => _openAd(widget.ad!) : null,
              ),
            ),
          ),
        if (restChunk.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            sliver: SliverGrid(
              gridDelegate: _gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildCard(context, restChunk[index]),
                childCount: restChunk.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _CategoryRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: kCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final c = kCategories[i];
          final isSel = c == selected;
          return ChoiceChip(
            label: Text(c),
            selected: isSel,
            selectedColor: Colors.blue,
            checkmarkColor: Colors.white,
            labelStyle: TextStyle(
              color: isSel ? Colors.white : null,
              fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
            ),
            onSelected: (_) => onSelect(c),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}

class _HomeBrandTitle extends StatelessWidget {
  const _HomeBrandTitle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 82,
      height: 34,
      child: Image.asset(
        'assets/branding/atta_logo.png',
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        semanticLabel: 'ATTA',
        errorBuilder: (context, error, stackTrace) {
          final color =
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92);

          return Text(
            'Atta',
            maxLines: 1,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: color,
              fontSize: 30,
              height: 1,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.6,
              fontFamily: 'serif',
            ),
          );
        },
      ),
    );
  }
}

// =====================
// Filters (Avito-like)
// =====================

class _HomeFilters {
  final String category;
  final String subcategory;
  final String location; // Город/регион для поиска
  final bool preferFirst; // Сначала показывать выбранную локацию
  final int? radiusKm;
  final String autoBrand;
  final String autoModel;
  final String autoCondition;
  final int? autoMileageTo;
  final bool onlyUncrashed;

  const _HomeFilters({
    required this.category,
    required this.subcategory,
    required this.location,
    required this.preferFirst,
    required this.radiusKm,
    required this.autoBrand,
    required this.autoModel,
    required this.autoCondition,
    required this.autoMileageTo,
    required this.onlyUncrashed,
  });
}

class _FilteredListingsScreen extends StatelessWidget {
  final String search;
  final _HomeFilters filters;

  const _FilteredListingsScreen({
    required this.search,
    required this.filters,
  });

  ListingFeedFilters get _feedFilters => ListingFeedFilters(
        category: filters.category,
        search: search,
        subcategory: filters.subcategory,
        location: filters.location,
        preferLocationFirst: filters.preferFirst,
        radiusKm: filters.radiusKm,
        autoBrand: filters.autoBrand,
        autoModel: filters.autoModel,
        autoCondition: filters.autoCondition,
        autoMileageTo: filters.autoMileageTo,
        onlyUncrashed: filters.onlyUncrashed,
      );

  String get _summaryText {
    final parts = <String>[];

    if (filters.category.trim().isNotEmpty && filters.category != 'Все') {
      parts.add(filters.category);
    }
    if (filters.subcategory.trim().isNotEmpty && filters.subcategory != 'Все') {
      parts.add(filters.subcategory);
    }
    if (filters.autoBrand.trim().isNotEmpty) {
      parts.add(filters.autoBrand);
    }
    if (filters.autoModel.trim().isNotEmpty) {
      parts.add(filters.autoModel);
    }
    if (filters.autoCondition.trim().isNotEmpty) {
      parts.add(filters.autoCondition);
    }
    if (filters.autoMileageTo != null) {
      parts.add('до ${filters.autoMileageTo} км');
    }
    if (filters.onlyUncrashed) {
      parts.add('не битые');
    }
    if (filters.location.trim().isNotEmpty) {
      parts.add(filters.location);
    }
    if (search.trim().isNotEmpty) {
      parts.add('поиск: $search');
    }

    if (parts.isEmpty) {
      return 'Все объявления';
    }

    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final listings = context.read<ListingsService>();
    final favs = context.read<FavoritesService>();
    final feedAds = context.read<FeedAdsService>();
    final history = context.watch<ListingHistoryService>();
    final reviews = context.read<ReviewsService>();
    final savedSearches = context.read<SavedSearchService>();
    final user = context.read<AuthService>().currentUser!;
    final queryKey = savedSearches.buildQueryKey(
      search: search,
      filters: _feedFilters,
    );
    final canSaveSearch = savedSearches.canSaveSearch(
      search: search,
      filters: _feedFilters,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Результаты поиска'),
        actions: [
          StreamBuilder<List<SavedSearch>>(
            stream: savedSearches.streamSavedSearches(user.uid),
            builder: (context, snap) {
              final items = snap.data ?? const <SavedSearch>[];
              final isSaved = items.any((item) => item.queryKey == queryKey);

              return IconButton(
                tooltip: isSaved
                    ? 'Убрать из избранных поисков'
                    : 'Сохранить поиск',
                onPressed: !canSaveSearch
                    ? null
                    : () async {
                        if (isSaved) {
                          await savedSearches.deleteSavedSearch(
                            userId: user.uid,
                            queryKey: queryKey,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Поиск убран из избранного'),
                            ),
                          );
                          return;
                        }

                        try {
                          await savedSearches.saveSearch(
                            userId: user.uid,
                            search: search,
                            filters: _feedFilters,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Поиск сохранен, уведомления включены',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          final message = savedSearches.isMissingTableError(e)
                              ? SavedSearchService.missingTableMessage
                              : 'Не удалось сохранить поиск: $e';
                          showAppSnack(context, message, isError: true);
                        }
                      },
                icon: Icon(
                  isSaved ? Icons.favorite : Icons.favorite_border,
                  color: isSaved ? Colors.red : null,
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _summaryText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.75),
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
                    category: filters.category,
                    search: search,
                    filters: _feedFilters,
                  ),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final items = snap.data!;
                    if (items.isEmpty) {
                      return const Center(child: Text('Ничего не найдено'));
                    }

                    return StreamBuilder<FeedAd?>(
                      stream: feedAds.streamActiveAd(),
                      builder: (context, adSnap) {
                        return _HomeFeedView(
                          items: items,
                          ad: adSnap.data,
                          favIds: favIds,
                          history: history,
                          reviews: reviews,
                          favs: favs,
                          userId: user.uid,
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

class _FiltersScreen extends StatefulWidget {
  final String initialCategory;
  final String initialSubcategory;
  final String initialLocation;
  final bool initialPreferFirst;
  final int? initialRadiusKm;
  final String initialAutoBrand;
  final String initialAutoModel;
  final String initialAutoCondition;
  final int? initialAutoMileageTo;
  final bool initialOnlyUncrashed;

  const _FiltersScreen({
    required this.initialCategory,
    required this.initialSubcategory,
    required this.initialLocation,
    required this.initialPreferFirst,
    required this.initialRadiusKm,
    required this.initialAutoBrand,
    required this.initialAutoModel,
    required this.initialAutoCondition,
    required this.initialAutoMileageTo,
    required this.initialOnlyUncrashed,
  });

  @override
  State<_FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<_FiltersScreen> {
  late String _category = widget.initialCategory;
  late String _subcategory = widget.initialSubcategory;
  late String _location = widget.initialLocation;
  late bool _preferFirst = widget.initialPreferFirst;
  late int? _radiusKm = widget.initialRadiusKm;
  late String _autoBrand = widget.initialAutoBrand;
  late String _autoModel = widget.initialAutoModel;
  late String _autoCondition = widget.initialAutoCondition;
  late int? _autoMileageTo = widget.initialAutoMileageTo;
  late bool _onlyUncrashed = widget.initialOnlyUncrashed;

  final TextEditingController _mileageCtrl = TextEditingController();

  bool get _isAutoCategory {
    final c = _category.trim().toLowerCase();
    return c == 'авто' || c.contains('авто') || c.contains('транспорт');
  }

  static const List<String> _carConditions = <String>[
    'Все',
    'Битые',
    'Не битые',
  ];

  @override
  void initState() {
    super.initState();
    _mileageCtrl.text = _autoMileageTo?.toString() ?? '';
  }

  @override
  void dispose() {
    _mileageCtrl.dispose();
    super.dispose();
  }

  void _applyFilters() {
    Navigator.pop(
      context,
      _HomeFilters(
        category: _category,
        subcategory: _subcategory,
        location: _location.trim(),
        preferFirst: _preferFirst,
        radiusKm: _radiusKm,
        autoBrand: _autoBrand,
        autoModel: _autoModel,
        autoCondition: _autoCondition,
        autoMileageTo: _autoMileageTo,
        onlyUncrashed: _onlyUncrashed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const cats = kCategories;
    final subs = kSubcategories[_category] ?? const <String>[];
    final subItems = ['Все', ...subs];
    if (!subItems.contains(_subcategory)) {
      _subcategory = 'Все';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Фильтры'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _category = 'Все';
                _subcategory = 'Все';
                _location = '';
                _preferFirst = false;
                _radiusKm = null;
                _autoBrand = '';
                _autoModel = '';
                _autoCondition = '';
                _autoMileageTo = null;
                _onlyUncrashed = false;
                _mileageCtrl.clear();
              });
            },
            child: const Text('Сбросить'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Категория',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: cats.map((c) {
              final selected = _category == c;
              return ChoiceChip(
                label: Text(c),
                selected: selected,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                onSelected: (_) {
                  setState(() {
                    _category = c;
                    _subcategory = 'Все';
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          if (_category != 'Все' && subs.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              initialValue: _subcategory,
              items: subItems
                  .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                  .toList(),
              onChanged: (v) => setState(() => _subcategory = v ?? 'Все'),
              decoration: const InputDecoration(
                labelText: 'Подкатегория',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (_isAutoCategory) ...[
            DropdownButtonFormField<String>(
              initialValue: _autoBrand.isEmpty ? null : _autoBrand,
              items: kAutoBrandsPopular
                  .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _autoBrand = v ?? '';
                  _autoModel = '';
                });
              },
              decoration: const InputDecoration(
                labelText: 'Марка',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _autoModel.isEmpty ? null : _autoModel,
              items: (_autoBrand.isEmpty
                      ? const <String>[]
                      : (kAutoModels[_autoBrand] ?? const <String>[]))
                  .where((m) => !m.toLowerCase().contains('другая'))
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => setState(() => _autoModel = v ?? ''),
              decoration: const InputDecoration(
                labelText: 'Модель',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _autoCondition.isEmpty ? 'Все' : _autoCondition,
              items: _carConditions
                  .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  final selected = v ?? 'Все';
                  _autoCondition = selected == 'Все' ? '' : selected;
                  _onlyUncrashed = selected == 'Не битые';
                });
              },
              decoration: const InputDecoration(
                labelText: 'Состояние',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mileageCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Пробег до (км)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                setState(() {
                  _autoMileageTo = int.tryParse(v.trim());
                });
              },
            ),
          ],

          // Where to search block.
          ListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            leading: const Icon(Icons.place_outlined),
            title: const Text('Где искать'),
            subtitle: Text(_location.trim().isEmpty ? 'Не выбрано' : _location),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final res = await Navigator.of(context).push<_WhereResult>(
                MaterialPageRoute(
                  builder: (_) => _WhereToSearchScreen(
                    initialLocation: _location,
                    initialPreferFirst: _preferFirst,
                    initialRadiusKm: _radiusKm,
                  ),
                ),
              );

              if (!mounted || res == null) return;

              setState(() {
                _location = res.location;
                _preferFirst = res.preferFirst;
                _radiusKm = res.radiusKm;
              });
            },
          ),

          const SizedBox(height: 20),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: FilledButton(
          onPressed: _applyFilters,
          child: const Text('Применить'),
        ),
      ),
    );
  }
}

// =====================
// Where to search (Avito-like)
// =====================

class _WhereResult {
  final String location;
  final bool preferFirst;
  final int? radiusKm;

  const _WhereResult({
    required this.location,
    required this.preferFirst,
    required this.radiusKm,
  });
}

class _WhereToSearchScreen extends StatefulWidget {
  final String initialLocation;
  final bool initialPreferFirst;
  final int? initialRadiusKm;

  const _WhereToSearchScreen({
    required this.initialLocation,
    required this.initialPreferFirst,
    required this.initialRadiusKm,
  });

  @override
  State<_WhereToSearchScreen> createState() => _WhereToSearchScreenState();
}

class _WhereToSearchScreenState extends State<_WhereToSearchScreen> {
  late final TextEditingController _locCtrl =
      TextEditingController(text: widget.initialLocation);

  late bool _preferFirst = widget.initialPreferFirst;
  late int? _radiusKm = widget.initialRadiusKm;

  @override
  void dispose() {
    _locCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationText = _locCtrl.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Где искать'),
        actions: [
          TextButton(
            onPressed: () {
              _locCtrl.clear();
              setState(() {
                _preferFirst = false;
                _radiusKm = null;
              });
            },
            child: const Text('Сбросить'),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Город или регион',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: _locCtrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Например: Москва',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _preferFirst,
            onChanged: (v) => setState(() => _preferFirst = v),
            title: Text(
              locationText.isEmpty
                  ? 'Сначала из выбранного региона'
                  : 'Сначала из $locationText',
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            title: const Text('Радиус'),
            subtitle: Text(_radiusKm == null ? 'Не ограничивать' : '$_radiusKm км'),
            trailing: const Icon(Icons.chevron_right),
            enabled: locationText.isNotEmpty,
            onTap: locationText.isEmpty
                ? null
                : () async {
                    final r = await Navigator.of(context).push<int?>(
                      MaterialPageRoute(
                        builder: (_) => _RadiusPickerScreen(
                          title: locationText,
                          initialRadiusKm: _radiusKm,
                        ),
                      ),
                    );

                    if (!mounted) return;
                    setState(() => _radiusKm = r);
                  },
          ),
          const SizedBox(height: 18),
          SafeArea(
            top: false,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  _WhereResult(
                    location: _locCtrl.text.trim(),
                    preferFirst: _preferFirst,
                    radiusKm: _radiusKm,
                  ),
                );
              },
              child: const Text('Применить'),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================
// Radius (Avito-like)
// =====================

class _RadiusPickerScreen extends StatefulWidget {
  final String title;
  final int? initialRadiusKm;

  const _RadiusPickerScreen({
    required this.title,
    required this.initialRadiusKm,
  });

  @override
  State<_RadiusPickerScreen> createState() => _RadiusPickerScreenState();
}

class _RadiusPickerScreenState extends State<_RadiusPickerScreen> {
  static const _options = <int>[1, 2, 3, 5, 10];

  final MapController _map = MapController();
  int? _radiusKm;
  bool _loadingGeo = true;
  LatLng _center = const LatLng(55.751244, 37.618423); // Москва по умолчанию

  @override
  void initState() {
    super.initState();
    _radiusKm = widget.initialRadiusKm;
    _initGeo();
  }

  Future<void> _initGeo() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        );
        final point = LatLng(pos.latitude, pos.longitude);
        if (!mounted) return;
        setState(() => _center = point);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _map.move(point, 12);
        });
      }
    } catch (_) {
      // Keep the fallback point if geolocation is unavailable.
    } finally {
      if (mounted) setState(() => _loadingGeo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _radiusKm;

    return Scaffold(
      appBar: AppBar(title: const Text('Радиус поиска')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: TextField(
              readOnly: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: widget.title,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                isDense: true,
              ),
            ),
          ),

          Expanded(
            child: _loadingGeo
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: 12,
                      onTap: (tapPos, p) => setState(() => _center = p),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.atta',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _center,
                            width: 44,
                            height: 44,
                            child: const Icon(Icons.location_pin, size: 44),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),

          // Radius chips under the map.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                children: [
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _options.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          final isSel = selected == null;
                          return ChoiceChip(
                            label: const Text('Не ограничивать'),
                            selected: isSel,
                            onSelected: (_) => setState(() => _radiusKm = null),
                          );
                        }

                        final km = _options[i - 1];
                        final isSel = selected == km;
                        return ChoiceChip(
                          label: Text('$km км'),
                          selected: isSel,
                          onSelected: (_) => setState(() => _radiusKm = km),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _radiusKm),
                    child: const Text('Применить'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
