import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:atta/src/app.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:atta/src/constants/categories.dart';
import 'package:atta/src/data/auto_catalog.dart';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/features/listings/vip_showcase_screen.dart';
import 'package:atta/src/features/notifications/notifications_screen.dart';
import 'package:atta/src/models/feed_ad.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/models/showcase_item.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/feed_ads_service.dart';
import 'package:atta/src/services/home_filters_session.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/saved_search_service.dart';
import 'package:atta/src/services/showcase_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:atta/src/widgets/feed_ad_banner.dart';
import 'package:atta/src/widgets/listing_card.dart';
import 'package:atta/src/widgets/listing_price_row.dart';
import 'package:atta/src/widgets/listing_promotion_badges.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:atta/src/widgets/add_listing_icon_button.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:atta/src/features/showcase/showcase_all_screen.dart';
import 'package:atta/src/features/showcase/showcase_preview_screen.dart';

class HomeTabController {
  VoidCallback? _scrollToTop;

  void attach({required VoidCallback scrollToTop}) {
    _scrollToTop = scrollToTop;
  }

  void detach() {
    _scrollToTop = null;
  }

  void scrollToTop() {
    _scrollToTop?.call();
  }
}

class HomeScreen extends StatefulWidget {
  final HomeTabController? controller;

  const HomeScreen({
    super.key,
    this.controller,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  static const int _feedPageSize = 20;
  static const int _vipPreviewPageSize = 20;
  static const Duration _showcaseStaleAfter = Duration(minutes: 5);
  String _category = 'Все';
  String _subcategory = 'Все';
  String _search = '';
  final _searchCtrl = TextEditingController();
  final GlobalKey<_HomeFeedViewState> _feedKey =
      GlobalKey<_HomeFeedViewState>();
  List<ShowcaseItem> _showcaseItems = const <ShowcaseItem>[];
  List<Listing> _vipItems = const <Listing>[];
  bool _vipHasMore = false;
  bool _vipIsLoadingMore = false;
  String? _vipNextCursor;
  bool _showcaseLoading = true;
  bool _showcaseLoadedOnce = false;
  DateTime? _showcaseRefreshedAt;
  Future<void>? _showcaseRefreshFuture;
  Future<void>? _vipRefreshFuture;
  Future<void>? _vipLoadMoreFuture;
  int _vipHomeRotationOffset = 0;
  int _vipHomeLoadCount = 0;
  ModalRoute<dynamic>? _route;

  // Avito-like location filter.
  String _location = ''; // "Москва", "Чеченская Республика" и т.п.
  bool _preferLocationFirst = false; // "Сначала из ..."
  int? _radiusKm; // 1/2/3/5/10 км или null
  int? _priceFrom;
  int? _priceTo;
  String _autoBrand = '';
  String _autoModel = '';
  String _autoCondition = '';
  int? _autoYearFrom;
  int? _autoYearTo;
  int? _autoMileageFrom;
  int? _autoMileageTo;
  String _autoTransmission = '';
  String _autoDrive = '';
  String _autoBodyType = '';
  String _autoFuel = '';
  String _autoColor = '';
  double? _autoEngineVolumeFrom;
  double? _autoEngineVolumeTo;
  int? _autoOwners;
  bool? _autoCleared;
  bool _onlyUncrashed = false;
  bool _onlyWithPhoto = false;
  List<Listing> _feedItems = const <Listing>[];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _nextCursor;
  Object? _feedError;
  int _feedRequestSerial = 0;
  int _mainFeedVipRotationOffset = 0;
  int _activeMainFeedVipRotationOffset = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshShowcase());
    unawaited(_refreshVipShowcase());
    widget.controller?.attach(scrollToTop: _handleScrollToTop);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreFilters();
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach();
      widget.controller?.attach(scrollToTop: _handleScrollToTop);
    }
  }

  @override
  void dispose() {
    attaRouteObserver.unsubscribe(this);
    widget.controller?.detach();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && !identical(route, _route)) {
      if (_route != null) {
        attaRouteObserver.unsubscribe(this);
      }
      _route = route;
      if (route is PageRoute<dynamic>) {
        attaRouteObserver.subscribe(this, route);
      }
    }
  }

  @override
  void didPopNext() {
    if (_showcaseNeedsRefresh) {
      unawaited(_refreshShowcase());
    }
    if (_showcaseNeedsRefresh) {
      unawaited(_refreshVipShowcase());
    }
  }

  ListingFeedFilters get _currentFeedFilters => ListingFeedFilters(
        category: _category,
        search: _search,
        subcategory: _subcategory,
        priceFrom: _priceFrom,
        priceTo: _priceTo,
        location: _location,
        preferLocationFirst: _preferLocationFirst,
        radiusKm: _radiusKm,
        autoBrand: _autoBrand,
        autoModel: _autoModel,
        autoCondition: _autoCondition,
        autoYearFrom: _autoYearFrom,
        autoYearTo: _autoYearTo,
        autoMileageFrom: _autoMileageFrom,
        autoMileageTo: _autoMileageTo,
        autoTransmission: _autoTransmission,
        autoDrive: _autoDrive,
        autoBodyType: _autoBodyType,
        autoFuel: _autoFuel,
        autoColor: _autoColor,
        autoEngineVolumeFrom: _autoEngineVolumeFrom,
        autoEngineVolumeTo: _autoEngineVolumeTo,
        autoOwners: _autoOwners,
        autoCleared: _autoCleared,
        onlyUncrashed: _onlyUncrashed,
        onlyWithPhoto: _onlyWithPhoto,
      );

  Future<void> _restoreFilters() async {
    final uid = context.read<AuthService>().currentUser?.uid ?? '';
    final saved = await homeFiltersSession.read(uid);
    if (saved == null) {
      await _reloadFeed(reset: true);
      return;
    }

    setState(() {
      _category = saved.category;
      _subcategory = saved.subcategory;
      _priceFrom = saved.priceFrom;
      _priceTo = saved.priceTo;
      _location = saved.location;
      _preferLocationFirst = saved.preferLocationFirst;
      _radiusKm = saved.radiusKm;
      _autoBrand = saved.autoBrand;
      _autoModel = saved.autoModel;
      _autoCondition = saved.autoCondition;
      _autoYearFrom = saved.autoYearFrom;
      _autoYearTo = saved.autoYearTo;
      _autoMileageFrom = saved.autoMileageFrom;
      _autoMileageTo = saved.autoMileageTo;
      _autoTransmission = saved.autoTransmission;
      _autoDrive = saved.autoDrive;
      _autoBodyType = saved.autoBodyType;
      _autoFuel = saved.autoFuel;
      _autoColor = saved.autoColor;
      _autoEngineVolumeFrom = saved.autoEngineVolumeFrom;
      _autoEngineVolumeTo = saved.autoEngineVolumeTo;
      _autoOwners = saved.autoOwners;
      _autoCleared = saved.autoCleared;
      _onlyUncrashed = saved.onlyUncrashed;
      _onlyWithPhoto = saved.onlyWithPhoto;
      _search = saved.search;
      _searchCtrl.text = saved.search;
    });
    await _reloadFeed(reset: true);
  }

  Future<void> _persistFilters() async {
    final uid = context.read<AuthService>().currentUser?.uid ?? '';

    await homeFiltersSession.write(
      uid: uid,
      category: _category,
      subcategory: _subcategory,
      priceFrom: _priceFrom,
      priceTo: _priceTo,
      location: _location,
      preferLocationFirst: _preferLocationFirst,
      radiusKm: _radiusKm,
      autoBrand: _autoBrand,
      autoModel: _autoModel,
      autoCondition: _autoCondition,
      autoYearFrom: _autoYearFrom,
      autoYearTo: _autoYearTo,
      autoMileageFrom: _autoMileageFrom,
      autoMileageTo: _autoMileageTo,
      autoTransmission: _autoTransmission,
      autoDrive: _autoDrive,
      autoBodyType: _autoBodyType,
      autoFuel: _autoFuel,
      autoColor: _autoColor,
      autoEngineVolumeFrom: _autoEngineVolumeFrom,
      autoEngineVolumeTo: _autoEngineVolumeTo,
      autoOwners: _autoOwners,
      autoCleared: _autoCleared,
      onlyUncrashed: _onlyUncrashed,
      onlyWithPhoto: _onlyWithPhoto,
      search: _search,
    );
  }

  void _handleScrollToTop() {
    _feedKey.currentState?.scrollToTop();
  }

  Future<void> _handleRefresh() async {
    final showcaseFuture = _refreshShowcase();
    final vipFuture = _refreshVipShowcase();
    final feedAdFuture =
        context.read<FeedAdsService>().refreshActiveAd(rotate: true);

    await Future.wait([
      _reloadFeed(reset: true, clearExistingItems: false),
      showcaseFuture,
      vipFuture,
      feedAdFuture,
      Future<void>.delayed(const Duration(milliseconds: 350)),
    ]);
  }

  Future<void> _refreshShowcase() async {
    final inFlight = _showcaseRefreshFuture;
    if (inFlight != null) return inFlight;

    if (mounted) {
      setState(() {
        _showcaseLoading = true;
      });
    }
    final future = _loadShowcase();
    _showcaseRefreshFuture = future;
    await future;
  }

  bool get _showcaseNeedsRefresh {
    final refreshedAt = _showcaseRefreshedAt;
    if (refreshedAt == null) return true;
    return DateTime.now().difference(refreshedAt) >= _showcaseStaleAfter;
  }

  Future<void> _loadShowcase() async {
    try {
      final items = await context.read<ShowcaseService>().getHomeShowcase();
      if (!mounted) return;
      setState(() {
        _showcaseItems = items;
        _showcaseLoading = false;
        _showcaseLoadedOnce = true;
        _showcaseRefreshedAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _showcaseLoading = false;
      });
    } finally {
      _showcaseRefreshFuture = null;
    }
  }

  Future<void> _refreshVipShowcase() async {
    final inFlight = _vipRefreshFuture;
    if (inFlight != null) return inFlight;

    final future = _loadVipShowcase();
    _vipRefreshFuture = future;
    await future;
  }

  Future<void> _loadVipShowcase() async {
    try {
      final page = await context.read<ListingsService>().getVipListingsPage(
            limit: _vipPreviewPageSize,
          );
      final items = _deduplicateVipItems(page.items);
      final nextRotationOffset = _nextHomeVipRotationOffset(
        itemCount: items.length,
        homeLoadCount: _vipHomeLoadCount,
        rotationOffset: _vipHomeRotationOffset,
      );
      if (!mounted) return;
      setState(() {
        _vipItems = items;
        _vipHasMore = page.hasMore;
        _vipNextCursor = page.nextCursor;
        _vipHomeRotationOffset = nextRotationOffset;
        _vipHomeLoadCount += 1;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _vipItems = const <Listing>[];
        _vipHasMore = false;
        _vipNextCursor = null;
      });
    } finally {
      _vipRefreshFuture = null;
    }
  }

  Future<void> _loadMoreVipShowcase() async {
    if (!_vipHasMore || _vipIsLoadingMore) return;

    final inFlight = _vipLoadMoreFuture;
    if (inFlight != null) return inFlight;

    final cursor = _vipNextCursor;
    if ((cursor ?? '').trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _vipHasMore = false;
      });
      return;
    }

    final future = () async {
      setState(() {
        _vipIsLoadingMore = true;
      });
      try {
        final page = await context.read<ListingsService>().getVipListingsPage(
              limit: _vipPreviewPageSize,
              cursor: cursor,
            );
        if (!mounted) return;
        setState(() {
          _vipItems = _mergeUniqueVipItems(_vipItems, page.items);
          _vipHasMore = page.hasMore;
          _vipNextCursor = page.nextCursor;
        });
      } catch (_) {
      } finally {
        if (mounted) {
          setState(() {
            _vipIsLoadingMore = false;
          });
        }
        _vipLoadMoreFuture = null;
      }
    }();

    _vipLoadMoreFuture = future;
    return future;
  }

  static int _nextHomeVipRotationOffset({
    required int itemCount,
    required int homeLoadCount,
    required int rotationOffset,
  }) {
    if (itemCount <= 1) return rotationOffset;
    final nextRotationOffset = homeLoadCount > 0
        ? (rotationOffset + 1) % itemCount
        : rotationOffset % itemCount;
    return nextRotationOffset;
  }

  static List<Listing> _deduplicateVipItems(List<Listing> items) {
    final seenIds = <String>{};
    final result = <Listing>[];
    for (final item in items) {
      if (item.activeVip?.isActive != true) continue;
      final id = item.id.trim();
      if (id.isEmpty || !seenIds.add(id)) continue;
      result.add(item);
    }
    return result;
  }

  static List<Listing> _mergeUniqueVipItems(
    List<Listing> current,
    List<Listing> incoming,
  ) {
    final seenIds = <String>{};
    final result = <Listing>[];
    for (final item in current) {
      if (item.activeVip?.isActive != true) continue;
      final id = item.id.trim();
      if (id.isEmpty || !seenIds.add(id)) continue;
      result.add(item);
    }
    for (final item in incoming) {
      if (item.activeVip?.isActive != true) continue;
      final id = item.id.trim();
      if (id.isEmpty || !seenIds.add(id)) continue;
      result.add(item);
    }
    return result;
  }

  void _selectCategory(String c) {
    setState(() {
      _category = c;
      _subcategory = 'Все';
      _search = '';
      _searchCtrl.clear();
    });
    _persistFilters();
    unawaited(_reloadFeed(reset: true));
  }

  List<Listing> _mergeUniqueListings(
    List<Listing> current,
    List<Listing> incoming,
  ) {
    final seenIds = current.map((item) => item.id).toSet();
    final merged = List<Listing>.from(current);
    for (final item in incoming) {
      if (seenIds.add(item.id)) {
        merged.add(item);
      }
    }
    return merged;
  }

  Future<void> _reloadFeed({
    required bool reset,
    bool clearExistingItems = true,
  }) async {
    final listings = context.read<ListingsService>();
    final requestId = ++_feedRequestSerial;
    final vipRotationOffset =
        reset ? _mainFeedVipRotationOffset : _activeMainFeedVipRotationOffset;

    setState(() {
      if (reset) {
        _isInitialLoading = true;
        _isLoadingMore = false;
        _hasMore = true;
        _nextCursor = null;
        _feedError = null;
        if (clearExistingItems) {
          _feedItems = const <Listing>[];
        }
      } else {
        _isLoadingMore = true;
        _feedError = null;
      }
    });

    try {
      final page = await listings.getListingsPage(
        category: _category,
        search: _search,
        filters: _currentFeedFilters,
        limit: _feedPageSize,
        cursor: reset ? null : _nextCursor,
        useVipInterleave: true,
        vipRotation: vipRotationOffset,
      );
      if (!mounted || requestId != _feedRequestSerial) return;
      setState(() {
        _feedItems = reset
            ? List<Listing>.from(page.items)
            : _mergeUniqueListings(_feedItems, page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore && (page.nextCursor ?? '').trim().isNotEmpty;
        _isInitialLoading = false;
        _isLoadingMore = false;
        _feedError = null;
        if (reset) {
          _activeMainFeedVipRotationOffset = vipRotationOffset;
          _mainFeedVipRotationOffset = vipRotationOffset + 1;
        }
      });
    } catch (error) {
      if (!mounted || requestId != _feedRequestSerial) return;
      setState(() {
        _isInitialLoading = false;
        _isLoadingMore = false;
        _feedError = error;
      });
    }
  }

  Future<void> _loadMoreFeed() async {
    if (_isInitialLoading || _isLoadingMore || !_hasMore) {
      return;
    }
    await _reloadFeed(reset: false);
  }

  Future<void> _openFilters() async {
    final res = await Navigator.of(context).push<_HomeFilters>(
      MaterialPageRoute(
        builder: (_) => _FiltersScreen(
          initialCategory: _category,
          initialSubcategory: _subcategory,
          initialPriceFrom: _priceFrom,
          initialPriceTo: _priceTo,
          initialLocation: _location,
          initialPreferFirst: _preferLocationFirst,
          initialRadiusKm: _radiusKm,
          initialAutoBrand: _autoBrand,
          initialAutoModel: _autoModel,
          initialAutoCondition: _autoCondition,
          initialAutoYearFrom: _autoYearFrom,
          initialAutoYearTo: _autoYearTo,
          initialAutoMileageFrom: _autoMileageFrom,
          initialAutoMileageTo: _autoMileageTo,
          initialAutoTransmission: _autoTransmission,
          initialAutoDrive: _autoDrive,
          initialAutoBodyType: _autoBodyType,
          initialAutoFuel: _autoFuel,
          initialAutoColor: _autoColor,
          initialAutoEngineVolumeFrom: _autoEngineVolumeFrom,
          initialAutoEngineVolumeTo: _autoEngineVolumeTo,
          initialAutoOwners: _autoOwners,
          initialAutoCleared: _autoCleared,
          initialOnlyUncrashed: _onlyUncrashed,
          initialOnlyWithPhoto: _onlyWithPhoto,
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
          const AddListingIconButton(),
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
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
                      unawaited(_reloadFeed(reset: true));
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _handleRefresh,
              edgeOffset: 8,
              child: Builder(
                builder: (context) {
                  if (_isInitialLoading && _feedItems.isEmpty) {
                    return const SkeletonListingGrid(
                      physics: AlwaysScrollableScrollPhysics(),
                    );
                  }

                  if (_feedError != null && _feedItems.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(top: 120),
                          child: Center(
                            child: Text(
                              'Не удалось загрузить объявления. Потяните вниз, чтобы повторить.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return StreamBuilder<FeedAd?>(
                    stream: feedAds.streamActiveAd(),
                    builder: (context, adSnap) {
                      return _HomeFeedView(
                        key: _feedKey,
                        items: _feedItems,
                        ad: adSnap.data,
                        showcaseItems: _showcaseItems,
                        vipItems: _vipItems,
                        vipHasMore: _vipHasMore,
                        vipInitialIndex: _vipHomeRotationOffset,
                        showcaseLoading:
                            _showcaseLoading && !_showcaseLoadedOnce,
                        history: history,
                        reviews: reviews,
                        favs: favs,
                        userId: user.uid,
                        isLoadingMore: _isLoadingMore,
                        hasMore: _hasMore,
                        onLoadMore: _loadMoreFeed,
                        onLoadMoreVip: _loadMoreVipShowcase,
                      );
                    },
                  );
                },
              ),
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
  final List<ShowcaseItem> showcaseItems;
  final List<Listing> vipItems;
  final bool vipHasMore;
  final int vipInitialIndex;
  final bool showcaseLoading;
  final ListingHistoryService history;
  final ReviewsService reviews;
  final FavoritesService favs;
  final String userId;
  final bool isLoadingMore;
  final bool hasMore;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onLoadMoreVip;

  const _HomeFeedView({
    super.key,
    required this.items,
    required this.ad,
    required this.showcaseItems,
    required this.vipItems,
    required this.vipHasMore,
    required this.vipInitialIndex,
    required this.showcaseLoading,
    required this.history,
    required this.reviews,
    required this.favs,
    required this.userId,
    required this.isLoadingMore,
    required this.hasMore,
    required this.onLoadMore,
    required this.onLoadMoreVip,
  });

  @override
  State<_HomeFeedView> createState() => _HomeFeedViewState();
}

class _HomeFeedViewState extends State<_HomeFeedView> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _adKey = GlobalKey();
  FeedAd? _displayedAd;
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
    _displayedAd = widget.ad;
    _scrollController.addListener(_scheduleVisibilityCheck);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAdVisibility());
  }

  @override
  void didUpdateWidget(covariant _HomeFeedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ad == null) {
      _displayedAd = null;
      _adVisible = false;
    } else if (oldWidget.ad == null && _displayedAd == null) {
      _displayedAd = widget.ad;
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
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 900) {
      unawaited(widget.onLoadMore());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAdVisibility());
  }

  void scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _checkAdVisibility() async {
    if (!mounted) return;
    final ad = _displayedAd;
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
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }
    try {
      await context.read<FeedAdsService>().recordClick(ad.id);
    } catch (_) {}
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _handleDisplayedAdChanged(FeedAd ad) {
    if (_displayedAd?.id == ad.id && _displayedAd?.imageUrl == ad.imageUrl) {
      return;
    }
    _displayedAd = ad;
    _adVisible = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAdVisibility());
  }

  Future<void> _openShowcaseItem(ShowcaseItem item) async {
    try {
      await context.read<ShowcaseService>().recordClick(item.promotionId);
    } catch (_) {}

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShowcasePreviewScreen(item: item),
      ),
    );
  }

  Widget _buildCard(BuildContext context, Listing item) {
    return FavoriteListingCard(
      listing: item,
      favoritesService: widget.favs,
      userId: widget.userId,
      isSeen: widget.history.hasViewed(item.id),
      reviews: widget.reviews,
      onError: (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось изменить избранное: $error')),
        );
      },
      onOpen: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ListingDetailScreen(listingId: item.id),
        ),
      ),
    );
  }

  Future<void> _openVipItem(Listing item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListingDetailScreen(listingId: item.id),
      ),
    );
  }

  List<Widget> _buildPromoSlivers({
    required bool visibleAd,
    required List<ShowcaseItem> showcaseItems,
  }) {
    final slivers = <Widget>[];

    if (visibleAd) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            key: _adKey,
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: FeedAdBanner(
              ad: widget.ad!,
              onTapAd: (ad) {
                if (ad.hasLink) {
                  unawaited(_openAd(ad));
                }
              },
              onDisplayedAdChanged: _handleDisplayedAdChanged,
            ),
          ),
        ),
      );
    }

    if (widget.showcaseLoading) {
      slivers.add(
        const SliverToBoxAdapter(
          child: _ShowcaseSectionSkeleton(),
        ),
      );
    } else if (showcaseItems.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _ShowcaseSection(
            items: showcaseItems,
            onOpenAll: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ShowcaseAllScreen(),
                ),
              );
            },
            onOpenItem: _openShowcaseItem,
          ),
        ),
      );
    }

    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    final visibleAd = widget.ad != null && widget.ad!.isVisibleNow;

    if (widget.items.isEmpty) {
      final showcaseItems = widget.showcaseItems;
      return CustomScrollView(
        controller: _scrollController,
        clipBehavior: Clip.hardEdge,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          ..._buildPromoSlivers(
            visibleAd: visibleAd,
            showcaseItems: showcaseItems,
          ),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text('Пока нет объявлений'),
            ),
          ),
        ],
      );
    }

    final showcaseItems = widget.showcaseItems;
    final vipItems = widget.vipItems;

    return CustomScrollView(
      controller: _scrollController,
      clipBehavior: Clip.hardEdge,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        ..._buildPromoSlivers(
          visibleAd: visibleAd,
          showcaseItems: showcaseItems,
        ),
        ..._buildListingSlivers(vipItems),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
            child: Center(
              child: widget.isLoadingMore
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildListingSlivers(List<Listing> vipItems) {
    const insertionIndex = 12;
    final headCount = widget.items.length < insertionIndex
        ? widget.items.length
        : insertionIndex;
    final tailCount = widget.items.length - headCount;
    final slivers = <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        sliver: SliverGrid(
          gridDelegate: _gridDelegate,
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildCard(context, widget.items[index]),
            childCount: headCount,
          ),
        ),
      ),
    ];

    if (vipItems.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _VipShowcaseSection(
            items: vipItems,
            hasMore: widget.vipHasMore,
            initialIndex: widget.vipInitialIndex,
            favoritesService: widget.favs,
            userId: widget.userId,
            onOpenAll: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const VipShowcaseScreen(),
                ),
              );
            },
            onOpenItem: _openVipItem,
            onLoadMore: widget.onLoadMoreVip,
            onError: (error) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('Не удалось изменить избранное: $error')),
              );
            },
          ),
        ),
      );
    }

    if (tailCount > 0) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          sliver: SliverGrid(
            gridDelegate: _gridDelegate,
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _buildCard(context, widget.items[headCount + index]),
              childCount: tailCount,
            ),
          ),
        ),
      );
    }

    return slivers;
  }
}

class _ShowcaseSection extends StatefulWidget {
  const _ShowcaseSection({
    required this.items,
    required this.onOpenAll,
    required this.onOpenItem,
  });

  final List<ShowcaseItem> items;
  final VoidCallback onOpenAll;
  final Future<void> Function(ShowcaseItem item) onOpenItem;

  @override
  State<_ShowcaseSection> createState() => _ShowcaseSectionState();
}

class _ShowcaseSectionSkeleton extends StatelessWidget {
  const _ShowcaseSectionSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = _homeShowcaseCardWidth(constraints.maxWidth - 24);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(height: 28, width: 160, radius: 8),
              const SizedBox(height: 12),
              SizedBox(
                height: _homeShowcaseCardHeight(cardWidth),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: 3,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, __) => SizedBox(
                    width: cardWidth,
                    child: const SkeletonBox(radius: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShowcaseSectionState extends State<_ShowcaseSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordVisibleCards());
  }

  @override
  void didUpdateWidget(covariant _ShowcaseSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _recordVisibleCards());
    }
  }

  Future<void> _recordVisibleCards() async {
    final showcaseService = context.read<ShowcaseService>();
    for (final item in widget.items.take(6)) {
      try {
        await showcaseService.recordImpression(item.promotionId);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = _homeShowcaseCardWidth(constraints.maxWidth - 24);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Витрина ATTA',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onOpenAll,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Смотреть все'),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              SizedBox(
                height: _homeShowcaseCardHeight(cardWidth),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: widget.items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    return _ShowcaseCard(
                      key: ValueKey('home_showcase_card:$index'),
                      width: cardWidth,
                      item: item,
                      onTap: () => widget.onOpenItem(item),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShowcaseCard extends StatelessWidget {
  const _ShowcaseCard({
    super.key,
    required this.width,
    required this.item,
    required this.onTap,
  });

  final double width;
  final ShowcaseItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final photo = item.firstPhotoUrl?.trim() ?? '';
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: scheme.outlineVariant,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: MediaPreviewBox(
                    imageUrl: photo,
                    categoryHint: 'listings',
                    borderRadius: 0,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.06),
                        Colors.black.withValues(alpha: 0.00),
                        Colors.black.withValues(alpha: 0.62),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          shadows: [
                            Shadow(
                              blurRadius: 10,
                              color: Color(0x66000000),
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatPrice(item.price)} ₽',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          shadows: [
                            Shadow(
                              blurRadius: 10,
                              color: Color(0x66000000),
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VipShowcaseSection extends StatefulWidget {
  const _VipShowcaseSection({
    required this.items,
    required this.hasMore,
    required this.initialIndex,
    required this.favoritesService,
    required this.userId,
    required this.onOpenAll,
    required this.onOpenItem,
    required this.onLoadMore,
    this.onError,
  });

  final List<Listing> items;
  final bool hasMore;
  final int initialIndex;
  final FavoritesService favoritesService;
  final String userId;
  final VoidCallback onOpenAll;
  final ValueChanged<Listing> onOpenItem;
  final Future<void> Function() onLoadMore;
  final ValueChanged<Object>? onError;

  @override
  State<_VipShowcaseSection> createState() => _VipShowcaseSectionState();
}

class _VipShowcaseSectionState extends State<_VipShowcaseSection> {
  final ScrollController _scrollController = ScrollController();

  static const double _loadMoreExtentAfter = 900;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant _VipShowcaseSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFirstId =
        oldWidget.items.isEmpty ? null : oldWidget.items.first.id;
    final nextFirstId = widget.items.isEmpty ? null : widget.items.first.id;
    if (oldWidget.initialIndex != widget.initialIndex ||
        oldFirstId != nextFirstId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.jumpTo(0);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleScroll());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!widget.hasMore || !_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < _loadMoreExtentAfter) {
      unawaited(widget.onLoadMore());
    }
  }

  int get _startIndex {
    final length = widget.items.length;
    if (length <= 1) return 0;
    return widget.initialIndex.clamp(0, length - 1);
  }

  List<Listing> get _visibleItems {
    final items = widget.items;
    if (items.length <= 1) return items;
    final startIndex = _startIndex;
    return <Listing>[
      ...items.skip(startIndex),
      ...items.take(startIndex),
    ];
  }

  @override
  Widget build(BuildContext context) {
    const vipBlue = Color(0xFF2563D9);
    const vipBlueDark = Color(0xFF163A8A);
    return Padding(
      key: const ValueKey('home_vip_showcase_section'),
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF8FBFF),
              Color(0xFFEFF6FF),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF8BB8FF),
            width: 1.2,
          ),
          boxShadow: [
            const BoxShadow(
              color: Color(0x262563D9),
              blurRadius: 22,
              spreadRadius: 1,
              offset: Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.72),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth =
                  _homeVipCardWidth(constraints.maxWidth).toDouble();
              final visibleItems = _visibleItems;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: vipBlue.withValues(alpha: 0.20),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x1A2563D9),
                                    blurRadius: 10,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.workspace_premium_rounded,
                                size: 18,
                                color: vipBlue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Flexible(
                              child: Text(
                                'Витрина VIP',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: vipBlueDark,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: vipAccentColor(context),
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(
                                    color: vipAccentColor(context)
                                        .withValues(alpha: 0.22),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Text(
                                'VIP',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onOpenAll,
                        style: TextButton.styleFrom(
                          foregroundColor: vipBlueDark,
                          backgroundColor: Colors.white.withValues(alpha: 0.82),
                          padding: const EdgeInsets.symmetric(horizontal: 11),
                          minimumSize: const Size(0, 34),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                            side: BorderSide(
                              color: vipBlue.withValues(alpha: 0.26),
                            ),
                          ),
                        ),
                        child: const Text('Смотреть все'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: _homeVipCardHeight(cardWidth),
                    child: ListView.builder(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.zero,
                      itemCount: visibleItems.length,
                      itemBuilder: (context, index) {
                        final item = visibleItems[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _VipPreviewCard(
                            key: ValueKey('home_vip_card:$index'),
                            width: cardWidth,
                            listing: item,
                            favoritesService: widget.favoritesService,
                            userId: widget.userId,
                            onTap: () => widget.onOpenItem(item),
                            onError: widget.onError,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _VipPreviewCard extends StatelessWidget {
  const _VipPreviewCard({
    super.key,
    required this.width,
    required this.listing,
    required this.favoritesService,
    required this.userId,
    required this.onTap,
    this.onError,
  });

  final double width;
  final Listing listing;
  final FavoritesService favoritesService;
  final String userId;
  final VoidCallback onTap;
  final ValueChanged<Object>? onError;

  @override
  Widget build(BuildContext context) {
    final photo = listing.firstPhotoUrl ?? '';
    final cityShort = listing.cityShort.trim();
    final scheme = Theme.of(context).colorScheme;
    const vipBlue = Color(0xFF2563D9);
    final compactTextScaler =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.05);

    return SizedBox(
      width: width,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        elevation: 2,
        shadowColor: vipBlue.withValues(alpha: 0.16),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: vipBlue.withValues(alpha: 0.18),
              ),
            ),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: compactTextScaler,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(14),
                          ),
                          child: SizedBox.expand(
                            child: MediaPreviewBox(
                              imageUrl: photo,
                              categoryHint: 'listings',
                              borderRadius: 0,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: vipAccentColor(context),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: vipAccentColor(context)
                                      .withValues(alpha: 0.22),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Text(
                              'VIP',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: FavoriteToggleButton(
                            favoritesService: favoritesService,
                            userId: userId,
                            listingId: listing.id,
                            activeColor: Colors.red,
                            onError: onError,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(7, 5, 7, 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          listing.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: ListingPriceRow(
                            listing: listing,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: vipBlue,
                              height: 1.05,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cityShort.isEmpty ? 'Город не указан' : cityShort,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.outline,
                            height: 1.05,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double _homeShowcaseCardWidth(double availableWidth) {
  final visibleCards = availableWidth < 340 ? 3.08 : 2.89;
  final width = (availableWidth - 16) / visibleCards;
  return width.clamp(98.0, 128.0).toDouble();
}

double _homeShowcaseCardHeight(double width) {
  return (width * 0.92).clamp(100.0, 116.0).toDouble();
}

double _homeVipCardWidth(double availableWidth) {
  final visibleCards = availableWidth < 340 ? 2.58 : 2.92;
  final width = (availableWidth - 16) / visibleCards;
  return width.clamp(106.0, 132.0).toDouble();
}

double _homeVipCardHeight(double width) {
  return (width * 1.28).clamp(138.0, 160.0).toDouble();
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
  final int? priceFrom;
  final int? priceTo;
  final String location; // Город/регион для поиска
  final bool preferFirst; // Сначала показывать выбранную локацию
  final int? radiusKm;
  final String autoBrand;
  final String autoModel;
  final String autoCondition;
  final int? autoYearFrom;
  final int? autoYearTo;
  final int? autoMileageFrom;
  final int? autoMileageTo;
  final String autoTransmission;
  final String autoDrive;
  final String autoBodyType;
  final String autoFuel;
  final String autoColor;
  final double? autoEngineVolumeFrom;
  final double? autoEngineVolumeTo;
  final int? autoOwners;
  final bool? autoCleared;
  final bool onlyUncrashed;
  final bool onlyWithPhoto;

  const _HomeFilters({
    required this.category,
    required this.subcategory,
    required this.priceFrom,
    required this.priceTo,
    required this.location,
    required this.preferFirst,
    required this.radiusKm,
    required this.autoBrand,
    required this.autoModel,
    required this.autoCondition,
    required this.autoYearFrom,
    required this.autoYearTo,
    required this.autoMileageFrom,
    required this.autoMileageTo,
    required this.autoTransmission,
    required this.autoDrive,
    required this.autoBodyType,
    required this.autoFuel,
    required this.autoColor,
    required this.autoEngineVolumeFrom,
    required this.autoEngineVolumeTo,
    required this.autoOwners,
    required this.autoCleared,
    required this.onlyUncrashed,
    required this.onlyWithPhoto,
  });
}

class _FilteredListingsScreen extends StatefulWidget {
  final String search;
  final _HomeFilters filters;

  const _FilteredListingsScreen({
    required this.search,
    required this.filters,
  });

  @override
  State<_FilteredListingsScreen> createState() =>
      _FilteredListingsScreenState();
}

class _FilteredListingsScreenState extends State<_FilteredListingsScreen> {
  static const int _pageSize = 20;
  final GlobalKey<_HomeFeedViewState> _feedKey =
      GlobalKey<_HomeFeedViewState>();
  List<Listing> _items = const <Listing>[];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _nextCursor;
  Object? _error;
  int _requestSerial = 0;

  String get search => widget.search;
  _HomeFilters get filters => widget.filters;

  ListingFeedFilters get _feedFilters => ListingFeedFilters(
        category: filters.category,
        search: search,
        subcategory: filters.subcategory,
        priceFrom: filters.priceFrom,
        priceTo: filters.priceTo,
        location: filters.location,
        preferLocationFirst: filters.preferFirst,
        radiusKm: filters.radiusKm,
        autoBrand: filters.autoBrand,
        autoModel: filters.autoModel,
        autoCondition: filters.autoCondition,
        autoYearFrom: filters.autoYearFrom,
        autoYearTo: filters.autoYearTo,
        autoMileageFrom: filters.autoMileageFrom,
        autoMileageTo: filters.autoMileageTo,
        autoTransmission: filters.autoTransmission,
        autoDrive: filters.autoDrive,
        autoBodyType: filters.autoBodyType,
        autoFuel: filters.autoFuel,
        autoColor: filters.autoColor,
        autoEngineVolumeFrom: filters.autoEngineVolumeFrom,
        autoEngineVolumeTo: filters.autoEngineVolumeTo,
        autoOwners: filters.autoOwners,
        autoCleared: filters.autoCleared,
        onlyUncrashed: filters.onlyUncrashed,
        onlyWithPhoto: filters.onlyWithPhoto,
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
    if (filters.priceFrom != null || filters.priceTo != null) {
      parts.add(
        '${filters.priceFrom == null ? '' : 'от ${filters.priceFrom} ₽'}'
                ' ${filters.priceTo == null ? '' : 'до ${filters.priceTo} ₽'}'
            .trim(),
      );
    }
    if (filters.autoYearFrom != null || filters.autoYearTo != null) {
      parts.add(
        '${filters.autoYearFrom == null ? '' : 'от ${filters.autoYearFrom} г.'}'
                ' ${filters.autoYearTo == null ? '' : 'до ${filters.autoYearTo} г.'}'
            .trim(),
      );
    }
    if (filters.autoMileageFrom != null) {
      parts.add('от ${filters.autoMileageFrom} км');
    }
    if (filters.autoMileageTo != null) {
      parts.add('до ${filters.autoMileageTo} км');
    }
    if (filters.autoTransmission.trim().isNotEmpty) {
      parts.add(filters.autoTransmission);
    }
    if (filters.autoDrive.trim().isNotEmpty) {
      parts.add(filters.autoDrive);
    }
    if (filters.onlyWithPhoto) {
      parts.add('с фото');
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
  void initState() {
    super.initState();
    unawaited(_reload(reset: true));
  }

  List<Listing> _mergeUniqueListings(
    List<Listing> current,
    List<Listing> incoming,
  ) {
    final seenIds = current.map((item) => item.id).toSet();
    final merged = List<Listing>.from(current);
    for (final item in incoming) {
      if (seenIds.add(item.id)) {
        merged.add(item);
      }
    }
    return merged;
  }

  Future<void> _reload({required bool reset}) async {
    final listings = context.read<ListingsService>();
    final requestId = ++_requestSerial;
    setState(() {
      if (reset) {
        _isInitialLoading = true;
        _isLoadingMore = false;
        _hasMore = true;
        _nextCursor = null;
        _error = null;
        _items = const <Listing>[];
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final page = await listings.getListingsPage(
        category: filters.category,
        search: search,
        filters: _feedFilters,
        limit: _pageSize,
        cursor: reset ? null : _nextCursor,
      );
      if (!mounted || requestId != _requestSerial) return;
      setState(() {
        _items = reset
            ? List<Listing>.from(page.items)
            : _mergeUniqueListings(_items, page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore && (page.nextCursor ?? '').trim().isNotEmpty;
        _isInitialLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || requestId != _requestSerial) return;
      setState(() {
        _isInitialLoading = false;
        _isLoadingMore = false;
        _error = error;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isInitialLoading || _isLoadingMore || !_hasMore) return;
    await _reload(reset: false);
  }

  @override
  Widget build(BuildContext context) {
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
                tooltip:
                    isSaved ? 'Убрать из избранных поисков' : 'Сохранить поиск',
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
            child: RefreshIndicator(
              onRefresh: () => _reload(reset: true),
              child: Builder(
                builder: (context) {
                  if (_isInitialLoading && _items.isEmpty) {
                    return const SkeletonListingGrid(
                      physics: AlwaysScrollableScrollPhysics(),
                    );
                  }

                  if (_error != null && _items.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(top: 120),
                          child: Center(
                            child: Text(
                              'Не удалось загрузить объявления. Потяните вниз, чтобы повторить.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  if (_items.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(top: 120),
                          child: Center(child: Text('Ничего не найдено')),
                        ),
                      ],
                    );
                  }

                  return StreamBuilder<FeedAd?>(
                    stream: feedAds.streamActiveAd(),
                    builder: (context, adSnap) {
                      return _HomeFeedView(
                        key: _feedKey,
                        items: _items,
                        ad: adSnap.data,
                        showcaseItems: const <ShowcaseItem>[],
                        vipItems: const <Listing>[],
                        vipHasMore: false,
                        vipInitialIndex: 0,
                        showcaseLoading: false,
                        history: history,
                        reviews: reviews,
                        favs: favs,
                        userId: user.uid,
                        isLoadingMore: _isLoadingMore,
                        hasMore: _hasMore,
                        onLoadMore: _loadMore,
                        onLoadMoreVip: () async {},
                      );
                    },
                  );
                },
              ),
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
  final int? initialPriceFrom;
  final int? initialPriceTo;
  final String initialLocation;
  final bool initialPreferFirst;
  final int? initialRadiusKm;
  final String initialAutoBrand;
  final String initialAutoModel;
  final String initialAutoCondition;
  final int? initialAutoYearFrom;
  final int? initialAutoYearTo;
  final int? initialAutoMileageFrom;
  final int? initialAutoMileageTo;
  final String initialAutoTransmission;
  final String initialAutoDrive;
  final String initialAutoBodyType;
  final String initialAutoFuel;
  final String initialAutoColor;
  final double? initialAutoEngineVolumeFrom;
  final double? initialAutoEngineVolumeTo;
  final int? initialAutoOwners;
  final bool? initialAutoCleared;
  final bool initialOnlyUncrashed;
  final bool initialOnlyWithPhoto;

  const _FiltersScreen({
    required this.initialCategory,
    required this.initialSubcategory,
    required this.initialPriceFrom,
    required this.initialPriceTo,
    required this.initialLocation,
    required this.initialPreferFirst,
    required this.initialRadiusKm,
    required this.initialAutoBrand,
    required this.initialAutoModel,
    required this.initialAutoCondition,
    required this.initialAutoYearFrom,
    required this.initialAutoYearTo,
    required this.initialAutoMileageFrom,
    required this.initialAutoMileageTo,
    required this.initialAutoTransmission,
    required this.initialAutoDrive,
    required this.initialAutoBodyType,
    required this.initialAutoFuel,
    required this.initialAutoColor,
    required this.initialAutoEngineVolumeFrom,
    required this.initialAutoEngineVolumeTo,
    required this.initialAutoOwners,
    required this.initialAutoCleared,
    required this.initialOnlyUncrashed,
    required this.initialOnlyWithPhoto,
  });

  @override
  State<_FiltersScreen> createState() => _FiltersScreenState();
}

const double _filterCardRadius = 16;

class _FiltersScreenState extends State<_FiltersScreen> {
  late String _category = widget.initialCategory;
  late String _subcategory = widget.initialSubcategory;
  late int? _priceFrom = widget.initialPriceFrom;
  late int? _priceTo = widget.initialPriceTo;
  late String _location = widget.initialLocation;
  late bool _preferFirst = widget.initialPreferFirst;
  late int? _radiusKm = widget.initialRadiusKm;
  late String _autoBrand = widget.initialAutoBrand;
  late String _autoModel = widget.initialAutoModel;
  late String _autoCondition = widget.initialAutoCondition;
  late int? _autoYearFrom = widget.initialAutoYearFrom;
  late int? _autoYearTo = widget.initialAutoYearTo;
  late int? _autoMileageFrom = widget.initialAutoMileageFrom;
  late int? _autoMileageTo = widget.initialAutoMileageTo;
  late String _autoTransmission = widget.initialAutoTransmission;
  late String _autoDrive = widget.initialAutoDrive;
  late String _autoBodyType = widget.initialAutoBodyType;
  late String _autoFuel = widget.initialAutoFuel;
  late String _autoColor = widget.initialAutoColor;
  late double? _autoEngineVolumeFrom = widget.initialAutoEngineVolumeFrom;
  late double? _autoEngineVolumeTo = widget.initialAutoEngineVolumeTo;
  late int? _autoOwners = widget.initialAutoOwners;
  late bool? _autoCleared = widget.initialAutoCleared;
  late bool _onlyUncrashed = widget.initialOnlyUncrashed;
  late bool _onlyWithPhoto = widget.initialOnlyWithPhoto;
  bool _advancedExpanded = false;

  final TextEditingController _priceFromCtrl = TextEditingController();
  final TextEditingController _priceToCtrl = TextEditingController();
  final TextEditingController _yearFromCtrl = TextEditingController();
  final TextEditingController _yearToCtrl = TextEditingController();
  final TextEditingController _mileageFromCtrl = TextEditingController();
  final TextEditingController _mileageCtrl = TextEditingController();
  final TextEditingController _engineFromCtrl = TextEditingController();
  final TextEditingController _engineToCtrl = TextEditingController();

  bool get _isAutoCategory {
    final c = _category.trim().toLowerCase();
    return c == 'авто' || c.contains('авто') || c.contains('транспорт');
  }

  static const List<String> _carConditions = <String>[
    'Все',
    'Не битая',
    'Битая',
    'Требует ремонта',
  ];

  static const List<String> _transmissions = <String>[
    'Все',
    'Механика',
    'Автомат',
    'Робот',
    'Вариатор',
  ];

  static const List<String> _drives = <String>[
    'Все',
    'Передний',
    'Задний',
    'Полный',
  ];

  static const List<String> _bodyTypes = <String>[
    'Все',
    'Седан',
    'Хэтчбек',
    'Лифтбек',
    'Универсал',
    'Внедорожник',
    'Кроссовер',
    'Купе',
    'Минивэн',
    'Пикап',
  ];

  static const List<String> _fuels = <String>[
    'Все',
    'Бензин',
    'Дизель',
    'Гибрид',
    'Электро',
    'Газ',
  ];

  static const List<String> _colors = <String>[
    'Все',
    'Белый',
    'Черный',
    'Серый',
    'Серебристый',
    'Синий',
    'Красный',
    'Зеленый',
    'Коричневый',
    'Бежевый',
  ];

  static const List<String> _owners = <String>[
    'Все',
    '1',
    '2',
    '3',
    '4',
  ];

  static const List<String> _clearedOptions = <String>[
    'Все',
    'Растаможен',
    'Не растаможен',
  ];

  @override
  void initState() {
    super.initState();
    _priceFromCtrl.text = _priceFrom?.toString() ?? '';
    _priceToCtrl.text = _priceTo?.toString() ?? '';
    _yearFromCtrl.text = _autoYearFrom?.toString() ?? '';
    _yearToCtrl.text = _autoYearTo?.toString() ?? '';
    _mileageFromCtrl.text = _autoMileageFrom?.toString() ?? '';
    _mileageCtrl.text = _autoMileageTo?.toString() ?? '';
    _engineFromCtrl.text = _autoEngineVolumeFrom?.toString() ?? '';
    _engineToCtrl.text = _autoEngineVolumeTo?.toString() ?? '';
  }

  @override
  void dispose() {
    _priceFromCtrl.dispose();
    _priceToCtrl.dispose();
    _yearFromCtrl.dispose();
    _yearToCtrl.dispose();
    _mileageFromCtrl.dispose();
    _mileageCtrl.dispose();
    _engineFromCtrl.dispose();
    _engineToCtrl.dispose();
    super.dispose();
  }

  void _applyFilters() {
    Navigator.pop(
      context,
      _HomeFilters(
        category: _category,
        subcategory: _subcategory,
        priceFrom: _priceFrom,
        priceTo: _priceTo,
        location: _location.trim(),
        preferFirst: _preferFirst,
        radiusKm: _radiusKm,
        autoBrand: _autoBrand,
        autoModel: _autoModel,
        autoCondition: _autoCondition,
        autoYearFrom: _autoYearFrom,
        autoYearTo: _autoYearTo,
        autoMileageFrom: _autoMileageFrom,
        autoMileageTo: _autoMileageTo,
        autoTransmission: _autoTransmission,
        autoDrive: _autoDrive,
        autoBodyType: _autoBodyType,
        autoFuel: _autoFuel,
        autoColor: _autoColor,
        autoEngineVolumeFrom: _autoEngineVolumeFrom,
        autoEngineVolumeTo: _autoEngineVolumeTo,
        autoOwners: _autoOwners,
        autoCleared: _autoCleared,
        onlyUncrashed: _onlyUncrashed,
        onlyWithPhoto: _onlyWithPhoto,
      ),
    );
  }

  void _resetFilters() {
    setState(() {
      _category = 'Все';
      _subcategory = 'Все';
      _priceFrom = null;
      _priceTo = null;
      _location = '';
      _preferFirst = false;
      _radiusKm = null;
      _autoBrand = '';
      _autoModel = '';
      _autoCondition = '';
      _autoYearFrom = null;
      _autoYearTo = null;
      _autoMileageFrom = null;
      _autoMileageTo = null;
      _autoTransmission = '';
      _autoDrive = '';
      _autoBodyType = '';
      _autoFuel = '';
      _autoColor = '';
      _autoEngineVolumeFrom = null;
      _autoEngineVolumeTo = null;
      _autoOwners = null;
      _autoCleared = null;
      _onlyUncrashed = false;
      _onlyWithPhoto = false;
      _advancedExpanded = false;
      _priceFromCtrl.clear();
      _priceToCtrl.clear();
      _yearFromCtrl.clear();
      _yearToCtrl.clear();
      _mileageFromCtrl.clear();
      _mileageCtrl.clear();
      _engineFromCtrl.clear();
      _engineToCtrl.clear();
    });
  }

  String _valueOrAll(String value) => value.trim().isEmpty ? 'Все' : value;

  Future<void> _pickOption({
    required String title,
    required List<String> options,
    required String current,
    required ValueChanged<String> onSelected,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: options.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final option = options[index];
            final selected = option == current;
            return ListTile(
              title: Text(option),
              trailing: selected ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, option),
            );
          },
        ),
      ),
    );
    if (selected == null || !mounted) return;
    onSelected(selected);
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _selector({
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        InkWell(
          borderRadius: BorderRadius.circular(_filterCardRadius),
          onTap: onTap,
          child: InputDecorator(
            decoration: InputDecoration(
              enabled: enabled,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_filterCardRadius),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled ? null : Theme.of(context).disabledColor,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: enabled ? null : Theme.of(context).disabledColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
    String? suffixText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        hintText: hint,
        suffixText: suffixText,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_filterCardRadius),
        ),
      ),
      onChanged: onChanged,
    );
  }

  Widget _rangeFields({
    required String label,
    required TextEditingController fromController,
    required TextEditingController toController,
    required ValueChanged<String> onFromChanged,
    required ValueChanged<String> onToChanged,
    String? suffixText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        Row(
          children: [
            Expanded(
              child: _numberField(
                controller: fromController,
                hint: 'От',
                suffixText: suffixText,
                onChanged: onFromChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numberField(
                controller: toController,
                hint: 'До',
                suffixText: suffixText,
                onChanged: onToChanged,
              ),
            ),
          ],
        ),
      ],
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
    final modelItems = _autoBrand.isEmpty
        ? const <String>[]
        : autoModelsForBrand(_autoBrand)
            .where((model) => model != kAutoCustomModelLabel)
            .toList();
    if (_autoModel.isNotEmpty && !modelItems.contains(_autoModel)) {
      _autoModel = '';
    }
    final selectedCleared = _autoCleared == null
        ? 'Все'
        : _autoCleared == true
            ? 'Растаможен'
            : 'Не растаможен';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Фильтры'),
        actions: [
          TextButton(
            onPressed: _resetFilters,
            child: const Text('Сбросить'),
          ),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _selector(
            label: 'Категория',
            value: _category == 'Все' ? 'Все категории' : _category,
            onTap: () => _pickOption(
              title: 'Категория',
              options: cats,
              current: _category,
              onSelected: (value) {
                setState(() {
                  _category = value;
                  _subcategory = 'Все';
                  if (!_isAutoCategory) {
                    _autoBrand = '';
                    _autoModel = '';
                    _autoCondition = '';
                    _autoYearFrom = null;
                    _autoYearTo = null;
                    _autoMileageFrom = null;
                    _autoMileageTo = null;
                    _autoTransmission = '';
                    _autoDrive = '';
                    _autoBodyType = '';
                    _autoFuel = '';
                    _autoColor = '';
                    _autoEngineVolumeFrom = null;
                    _autoEngineVolumeTo = null;
                    _autoOwners = null;
                    _autoCleared = null;
                    _onlyUncrashed = false;
                    _onlyWithPhoto = false;
                    _yearFromCtrl.clear();
                    _yearToCtrl.clear();
                    _mileageFromCtrl.clear();
                    _mileageCtrl.clear();
                    _engineFromCtrl.clear();
                    _engineToCtrl.clear();
                  }
                });
              },
            ),
          ),
          if (_category != 'Все') ...[
            const SizedBox(height: 16),
            _selector(
              label: 'Подкатегория',
              value: _subcategory,
              onTap: () => _pickOption(
                title: 'Подкатегория',
                options: subItems,
                current: _subcategory,
                onSelected: (value) => setState(() => _subcategory = value),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _rangeFields(
            label: 'Цена',
            fromController: _priceFromCtrl,
            toController: _priceToCtrl,
            suffixText: '₽',
            onFromChanged: (value) =>
                setState(() => _priceFrom = int.tryParse(value.trim())),
            onToChanged: (value) =>
                setState(() => _priceTo = int.tryParse(value.trim())),
          ),
          if (_isAutoCategory) ...[
            const SizedBox(height: 16),
            _selector(
              label: 'Марка',
              value: _valueOrAll(_autoBrand),
              onTap: () => _pickOption(
                title: 'Марка',
                options: ['Все', ...kAutoBrandsPopular],
                current: _valueOrAll(_autoBrand),
                onSelected: (value) {
                  setState(() {
                    _autoBrand = value == 'Все' ? '' : value;
                    _autoModel = '';
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            _selector(
              label: 'Модель',
              value: _valueOrAll(_autoModel),
              onTap: _autoBrand.isEmpty
                  ? null
                  : () => _pickOption(
                        title: 'Модель',
                        options: ['Все', ...modelItems],
                        current: _valueOrAll(_autoModel),
                        onSelected: (value) => setState(
                          () => _autoModel = value == 'Все' ? '' : value,
                        ),
                      ),
            ),
            const SizedBox(height: 16),
            _rangeFields(
              label: 'Год выпуска',
              fromController: _yearFromCtrl,
              toController: _yearToCtrl,
              onFromChanged: (value) =>
                  setState(() => _autoYearFrom = int.tryParse(value.trim())),
              onToChanged: (value) =>
                  setState(() => _autoYearTo = int.tryParse(value.trim())),
            ),
            const SizedBox(height: 16),
            _rangeFields(
              label: 'Пробег (км)',
              fromController: _mileageFromCtrl,
              toController: _mileageCtrl,
              onFromChanged: (value) =>
                  setState(() => _autoMileageFrom = int.tryParse(value.trim())),
              onToChanged: (value) =>
                  setState(() => _autoMileageTo = int.tryParse(value.trim())),
            ),
            const SizedBox(height: 16),
            _selector(
              label: 'Коробка передач',
              value: _valueOrAll(_autoTransmission),
              onTap: () => _pickOption(
                title: 'Коробка передач',
                options: _transmissions,
                current: _valueOrAll(_autoTransmission),
                onSelected: (value) => setState(
                  () => _autoTransmission = value == 'Все' ? '' : value,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _selector(
              label: 'Привод',
              value: _valueOrAll(_autoDrive),
              onTap: () => _pickOption(
                title: 'Привод',
                options: _drives,
                current: _valueOrAll(_autoDrive),
                onSelected: (value) =>
                    setState(() => _autoDrive = value == 'Все' ? '' : value),
              ),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
              title: Text(
                'Дополнительно',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              initiallyExpanded: _advancedExpanded,
              onExpansionChanged: (value) =>
                  setState(() => _advancedExpanded = value),
              children: [
                _selector(
                  label: 'Состояние',
                  value: _valueOrAll(_autoCondition),
                  onTap: () => _pickOption(
                    title: 'Состояние',
                    options: _carConditions,
                    current: _valueOrAll(_autoCondition),
                    onSelected: (value) {
                      setState(() {
                        _autoCondition = value == 'Все' ? '' : value;
                        _onlyUncrashed = value == 'Не битая';
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                _selector(
                  label: 'Тип кузова',
                  value: _valueOrAll(_autoBodyType),
                  onTap: () => _pickOption(
                    title: 'Тип кузова',
                    options: _bodyTypes,
                    current: _valueOrAll(_autoBodyType),
                    onSelected: (value) => setState(
                      () => _autoBodyType = value == 'Все' ? '' : value,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _selector(
                  label: 'Тип топлива',
                  value: _valueOrAll(_autoFuel),
                  onTap: () => _pickOption(
                    title: 'Тип топлива',
                    options: _fuels,
                    current: _valueOrAll(_autoFuel),
                    onSelected: (value) =>
                        setState(() => _autoFuel = value == 'Все' ? '' : value),
                  ),
                ),
                const SizedBox(height: 16),
                _selector(
                  label: 'Цвет',
                  value: _valueOrAll(_autoColor),
                  onTap: () => _pickOption(
                    title: 'Цвет',
                    options: _colors,
                    current: _valueOrAll(_autoColor),
                    onSelected: (value) => setState(
                      () => _autoColor = value == 'Все' ? '' : value,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _rangeFields(
                  label: 'Объем двигателя',
                  fromController: _engineFromCtrl,
                  toController: _engineToCtrl,
                  onFromChanged: (value) => setState(
                    () => _autoEngineVolumeFrom =
                        double.tryParse(value.trim().replaceAll(',', '.')),
                  ),
                  onToChanged: (value) => setState(
                    () => _autoEngineVolumeTo =
                        double.tryParse(value.trim().replaceAll(',', '.')),
                  ),
                ),
                const SizedBox(height: 16),
                _selector(
                  label: 'Количество владельцев',
                  value: _autoOwners?.toString() ?? 'Все',
                  onTap: () => _pickOption(
                    title: 'Количество владельцев',
                    options: _owners,
                    current: _autoOwners?.toString() ?? 'Все',
                    onSelected: (value) => setState(
                      () => _autoOwners =
                          value == 'Все' ? null : int.tryParse(value),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _selector(
                  label: 'Растаможка',
                  value: selectedCleared,
                  onTap: () => _pickOption(
                    title: 'Растаможка',
                    options: _clearedOptions,
                    current: selectedCleared,
                    onSelected: (value) {
                      setState(() {
                        _autoCleared =
                            value == 'Все' ? null : value == 'Растаможен';
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _onlyWithPhoto,
                  title: const Text('Только с фото'),
                  onChanged: (value) => setState(() => _onlyWithPhoto = value),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_filterCardRadius),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
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
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: _applyFilters,
          child: const Text('Показать результаты'),
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
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Например: Москва',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(_filterCardRadius),
                ),
              ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_filterCardRadius),
            ),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            title: const Text('Радиус'),
            subtitle:
                Text(_radiusKm == null ? 'Не ограничивать' : '$_radiusKm км'),
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
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(_filterCardRadius),
                ),
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
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(_filterCardRadius),
                            ),
                            onSelected: (_) => setState(() => _radiusKm = null),
                          );
                        }

                        final km = _options[i - 1];
                        final isSel = selected == km;
                        return ChoiceChip(
                          label: Text('$km км'),
                          selected: isSel,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(_filterCardRadius),
                          ),
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
