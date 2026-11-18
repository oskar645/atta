import 'package:atta/src/features/favorites/favorites_screen.dart';
import 'package:atta/src/features/listings/edit_listing_screen.dart';
import 'package:atta/src/features/listings/listing_archive_flow.dart';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/features/promotions/sell_faster_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/theme/soft_shadows.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:atta/src/widgets/atta_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:atta/src/widgets/listing_promotion_badges.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:atta/src/widgets/add_listing_icon_button.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'dart:async';

void _debugMyListingsLog(String message) {
  assert(() {
    debugPrint('[MYLIST] $message');
    return true;
  }());
}

List<BoxShadow> _myListingCardShadows(BuildContext context) {
  if (Theme.of(context).brightness == Brightness.dark) {
    return attaSoftCardShadows(context);
  }
  return const <BoxShadow>[
    BoxShadow(
      color: Color(0x30547CA5),
      blurRadius: 2,
      offset: Offset.zero,
    ),
    BoxShadow(
      color: Color(0x16547CA5),
      blurRadius: 6,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x08547CA5),
      blurRadius: 12,
      spreadRadius: -2,
      offset: Offset(0, 3),
    ),
  ];
}

List<BoxShadow> _myListingActionShadows(BuildContext context) {
  if (Theme.of(context).brightness == Brightness.dark) {
    return attaSoftCardShadows(context);
  }
  return const <BoxShadow>[
    BoxShadow(
      color: Color(0x28547CA5),
      blurRadius: 2,
      offset: Offset.zero,
    ),
    BoxShadow(
      color: Color(0x10547CA5),
      blurRadius: 5,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x06547CA5),
      blurRadius: 10,
      spreadRadius: -2,
      offset: Offset(0, 2),
    ),
  ];
}

void _debugMyListingsStack(String source, {int maxFrames = 20}) {
  assert(() {
    final frames = StackTrace.current.toString().trimRight().split('\n');
    debugPrint(
      '[MYLIST] STACK source=$source maxFrames=$maxFrames\n'
      '${frames.take(maxFrames).join('\n')}',
    );
    return true;
  }());
}

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.initialListingId = '',
    this.autoOpenInitialListing = false,
  });

  final int initialTabIndex;
  final String initialListingId;
  final bool autoOpenInitialListing;

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _bottomCreateButtonReserve = 92;
  static const double _scrollDirectionThreshold = 28;
  static const _tabs = <_MyListingsTabConfig>[
    _MyListingsTabConfig(
      title: 'Активные',
      statuses: {'approved', 'pending'},
      emptyText: 'Нет активных объявлений',
    ),
    _MyListingsTabConfig(
      title: 'Ждут действия',
      statuses: {'rejected'},
      emptyText: 'Нет объявлений, требующих действия',
    ),
    _MyListingsTabConfig(
      title: 'Архив',
      statuses: {'archived', 'sold'},
      emptyText: 'Нет архивных объявлений',
    ),
  ];

  late final TabController _tab;
  StreamSubscription<void>? _countsRefreshSub;
  Map<int, int> _tabCounts = const <int, int>{};
  bool _showCreateButton = true;
  double _scrollDirectionDistance = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _debugMyListingsLog('RUNTIME_SCREEN_INIT');
    _debugMyListingsLog(
      'init screen=${identityHashCode(this)} initialTab=${widget.initialTabIndex}',
    );
    _tab = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, _tabs.length - 1),
    );
    _tab.addListener(_handleTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final service = context.read<ListingsService>();
      _countsRefreshSub = service.refreshes.listen((_) => _syncTabCounts());
      unawaited(_loadTabCounts());
    });
  }

  @override
  void dispose() {
    _debugMyListingsLog('dispose screen=${identityHashCode(this)}');
    WidgetsBinding.instance.removeObserver(this);
    _tab.removeListener(_handleTabChanged);
    _countsRefreshSub?.cancel();
    _tab.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MyListingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _debugMyListingsLog(
      'didUpdateWidget screen=${identityHashCode(this)} '
      'oldTab=${oldWidget.initialTabIndex} newTab=${widget.initialTabIndex} '
      'oldListing=${oldWidget.initialListingId} newListing=${widget.initialListingId}',
    );
  }

  void _handleTabChanged() {
    _debugMyListingsLog(
      'tabChanged screen=${identityHashCode(this)} index=${_tab.index} changing=${_tab.indexIsChanging}',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadTabCounts());
    }
  }

  Future<void> _loadTabCounts() async {
    final uid = context.read<AuthService>().currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;
    await context.read<ListingsService>().refreshMyListings(uid);
    if (!mounted) return;
    _syncTabCounts();
  }

  void _syncTabCounts() {
    if (!mounted) return;
    final service = context.read<ListingsService>();
    final next = <int, int>{
      for (final entry in _tabs.asMap().entries)
        entry.key: service
            .peekMyListingsByStatuses(statuses: entry.value.statuses)
            .length,
    };
    if (_sameCounts(_tabCounts, next)) return;
    setState(() => _tabCounts = next);
  }

  bool _sameCounts(Map<int, int> current, Map<int, int> next) {
    if (current.length != next.length) return false;
    return next.entries.every((entry) => current[entry.key] == entry.value);
  }

  void _setCreateButtonVisible(bool visible) {
    if (visible != _showCreateButton) {
      setState(() => _showCreateButton = visible);
    }
  }

  bool _handleCreateButtonScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= _scrollDirectionThreshold) {
      _setCreateButtonVisible(true);
      _scrollDirectionDistance = 0;
      return false;
    }
    if (metrics.pixels <= metrics.minScrollExtent + _scrollDirectionThreshold) {
      _setCreateButtonVisible(true);
      _scrollDirectionDistance = 0;
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;
      if (_scrollDirectionDistance.sign != delta.sign) {
        _scrollDirectionDistance = 0;
      }
      _scrollDirectionDistance += delta;
      if (_scrollDirectionDistance.abs() < _scrollDirectionThreshold) {
        return false;
      }
      _setCreateButtonVisible(_scrollDirectionDistance < 0);
      _scrollDirectionDistance = 0;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final svc = context.read<ListingsService>();
    final uid = auth.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои объявления'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: false,
          labelColor: Theme.of(context).colorScheme.primary,
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: _tabs
              .asMap()
              .entries
              .map(
                (entry) => Tab(
                  child: _TabLabel(
                    title: entry.value.title,
                    count: _tabCounts[entry.key] ?? 0,
                  ),
                ),
              )
              .toList(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite_border),
            tooltip: 'Избранное',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FavoritesScreen()),
            ),
          ),
          const AddListingIconButton(),
        ],
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tab,
            children: _tabs
                .asMap()
                .entries
                .map(
                  (entry) => ApiConfig.useTimewebBackend
                      ? _TimewebMyListingsTab(
                          userId: uid,
                          statuses: entry.value.statuses,
                          emptyText: entry.value.emptyText,
                          bottomPadding: _bottomCreateButtonReserve,
                          onScrollNotification: _handleCreateButtonScroll,
                          initialListingId:
                              widget.initialListingId.isNotEmpty &&
                                      widget.initialTabIndex == entry.key
                                  ? widget.initialListingId
                                  : '',
                          autoOpenInitialListing:
                              widget.autoOpenInitialListing &&
                                  widget.initialListingId.isNotEmpty &&
                                  widget.initialTabIndex == entry.key,
                        )
                      : _ListingsTab(
                          stream: svc.streamMyListingsByStatuses(
                            uid,
                            statuses: entry.value.statuses,
                          ),
                          bottomPadding: _bottomCreateButtonReserve,
                          onScrollNotification: _handleCreateButtonScroll,
                        ),
                )
                .toList(),
          ),
          _CreateListingBottomButton(visible: _showCreateButton),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, maxLines: 1),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                key: ValueKey('my_listings_tab_count:$title'),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListingActionButton extends StatelessWidget {
  const _ListingActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const radius = BorderRadius.all(Radius.circular(999));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: _myListingActionShadows(context),
      ),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: theme.brightness == Brightness.light
                ? Colors.white
                : theme.colorScheme.surfaceContainerHighest,
            side: BorderSide.none,
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AsyncListingActionButton extends StatefulWidget {
  const _AsyncListingActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;

  @override
  State<_AsyncListingActionButton> createState() =>
      _AsyncListingActionButtonState();
}

class _AsyncListingActionButtonState extends State<_AsyncListingActionButton> {
  bool _running = false;

  Future<void> _run() async {
    if (_running || widget.onPressed == null) return;
    setState(() => _running = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ListingActionButton(
      label: widget.label,
      icon: widget.icon,
      onPressed: widget.onPressed == null || _running ? null : _run,
    );
  }
}

class _MyListingsTabConfig {
  const _MyListingsTabConfig({
    required this.title,
    required this.statuses,
    required this.emptyText,
  });

  final String title;
  final Set<String> statuses;
  final String emptyText;
}

class _TimewebMyListingsTab extends StatefulWidget {
  const _TimewebMyListingsTab({
    required this.userId,
    required this.statuses,
    required this.emptyText,
    required this.bottomPadding,
    required this.onScrollNotification,
    this.initialListingId = '',
    this.autoOpenInitialListing = false,
  });

  final String userId;
  final Set<String> statuses;
  final String emptyText;
  final double bottomPadding;
  final bool Function(ScrollNotification notification) onScrollNotification;
  final String initialListingId;
  final bool autoOpenInitialListing;

  @override
  State<_TimewebMyListingsTab> createState() => _TimewebMyListingsTabState();
}

class _TimewebMyListingsTabState extends State<_TimewebMyListingsTab>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static const Duration _resumeRefreshCooldown = Duration(seconds: 5);
  static const int _maxAutomaticLoadMorePages = 3;
  late Future<List<Listing>> _future;
  final ScrollController _scrollController = ScrollController();
  final Set<String> _requestedPageCursors = <String>{};
  StreamSubscription<void>? _refreshSub;
  List<Listing>? _items;
  bool _loadedOnce = false;
  String? _errorText;
  bool _loading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _nextCursor;
  double? _lastLoadMoreTriggerPixels;
  bool _didAutoOpenInitialListing = false;
  DateTime? _lastRefreshAt;
  int _loadSerial = 0;
  int _automaticLoadMorePages = 0;

  void _showLoadErrorSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Не удалось обновить объявления. Попробуйте ещё раз.'),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _debugMyListingsLog(
      'init user=${widget.userId} status=$_statusLabelForTrace '
      'state=${identityHashCode(this)} widget=${identityHashCode(widget)}',
    );
    final cached = context.read<ListingsService>().peekMyListingsByStatuses(
          statuses: widget.statuses,
        );
    if (cached.isNotEmpty) {
      _replaceLocalItems(
        cached,
        reason: 'init cached',
        source: 'peekMyListingsByStatuses',
      );
      _loading = false;
    }
    _future = _load();
    _refreshSub = context.read<ListingsService>().refreshes.listen((_) {
      if (!mounted) return;
      final listings = context.read<ListingsService>();
      final nextItems = listings.peekMyListingsByStatuses(
        statuses: widget.statuses,
      );
      setState(() {
        _replaceLocalItems(
          nextItems,
          reason: 'service notify',
          source: 'refresh listener',
        );
        _loadedOnce = true;
        _loading = false;
      });
      _lastRefreshAt = DateTime.now();
      _maybeAutoOpenListing(_items ?? const <Listing>[]);
    });
  }

  @override
  void dispose() {
    _debugMyListingsLog(
      'dispose user=${widget.userId} status=$_statusLabelForTrace '
      'state=${identityHashCode(this)} widget=${identityHashCode(widget)}',
    );
    WidgetsBinding.instance.removeObserver(this);
    _refreshSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _TimewebMyListingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _debugMyListingsLog(
      'didUpdateWidget user=${widget.userId} oldUser=${oldWidget.userId} '
      'status=$_statusLabelForTrace oldStatus=${oldWidget.statuses.join(",")} '
      'state=${identityHashCode(this)} widget=${identityHashCode(widget)}',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final lastRefreshAt = _lastRefreshAt;
    if (lastRefreshAt != null &&
        DateTime.now().difference(lastRefreshAt) < _resumeRefreshCooldown) {
      return;
    }
    unawaited(_refresh());
  }

  Future<List<Listing>> _load({bool reset = true}) async {
    final hadItems = (_items ?? const <Listing>[]).isNotEmpty;
    final listings = context.read<ListingsService>();
    final requestSerial = ++_loadSerial;
    final requestCursor = reset ? null : _nextCursor?.trim();
    if (reset) {
      _requestedPageCursors.clear();
      _automaticLoadMorePages = 0;
    } else if (requestCursor == null ||
        requestCursor.isEmpty ||
        !_requestedPageCursors.add(requestCursor)) {
      if (mounted) {
        setState(() {
          _hasMore = false;
          _nextCursor = null;
        });
      }
      return List<Listing>.from(_items ?? const <Listing>[]);
    }
    _debugMyListingsLog(
      'MyListings load start user=${widget.userId} statuses=${widget.statuses.join(",")}',
    );
    try {
      final page = await listings.getMyListingsPageByStatuses(
        widget.userId,
        statuses: widget.statuses,
        limit: 20,
        cursor: requestCursor,
        forceRefresh: reset && hadItems,
      );
      if (!mounted || requestSerial != _loadSerial) {
        return List<Listing>.from(_items ?? const <Listing>[]);
      }
      final items = reset ? page.items : _appendListings(_items, page.items);
      final nextCursor = page.nextCursor?.trim();
      final repeatedCursor = nextCursor != null &&
          nextCursor.isNotEmpty &&
          nextCursor == requestCursor;
      final loadError = listings.lastMyListingsErrorForUser(widget.userId);
      setState(() {
        _replaceLocalItems(
          items,
          reason: reset ? 'load reset' : 'load append',
          source: '_load',
        );
        _nextCursor = repeatedCursor ? null : nextCursor;
        _hasMore =
            page.hasMore && !repeatedCursor && (nextCursor ?? '').isNotEmpty;
        _errorText = !hadItems && loadError != null
            ? 'Не удалось загрузить объявления. Попробуйте снова.'
            : null;
        _loading = false;
        _loadedOnce = true;
      });
      _lastRefreshAt = DateTime.now();
      _debugMyListingsLog(
        items.isEmpty
            ? 'MyListings load empty'
            : 'MyListings load success count=${items.length}',
      );
      _maybeAutoOpenListing(items);
      _scheduleShortListLoadMore();
      return items;
    } catch (error) {
      if (!reset && requestCursor != null) {
        _requestedPageCursors.remove(requestCursor);
      }
      if (!mounted || requestSerial != _loadSerial) {
        return List<Listing>.from(_items ?? const <Listing>[]);
      }
      if (mounted) {
        setState(() {
          _loading = false;
          if (hadItems) {
            _errorText = null;
          } else {
            _errorText = 'Не удалось загрузить объявления. Попробуйте снова.';
            _loadedOnce = true;
          }
        });
        if (hadItems) {
          _showLoadErrorSnack();
        }
      }
      _debugMyListingsLog('MyListings load error message=$error');
      return List<Listing>.from(_items ?? const <Listing>[]);
    } finally {
      _debugMyListingsLog('MyListings load finally loading=false');
    }
  }

  Future<void> _refresh() async {
    _debugMyListingsLog(
      'MyListings refresh start user=${widget.userId} statuses=${widget.statuses.join(",")}',
    );
    final next = _load(reset: true);
    setState(() {
      _future = next;
      _errorText = null;
      _loading = _items == null;
      _isLoadingMore = false;
      _hasMore = true;
      _nextCursor = null;
      _lastLoadMoreTriggerPixels = null;
    });
    try {
      final items = await next;
      if (!mounted) return;
      final loadError = context
          .read<ListingsService>()
          .lastMyListingsErrorForUser(widget.userId);
      final hasItems = items.isNotEmpty;
      setState(() {
        _replaceLocalItems(
          items,
          reason: 'refresh await',
          source: '_refresh',
        );
        _errorText = !hasItems && loadError != null
            ? 'Не удалось загрузить объявления. Попробуйте снова.'
            : null;
        _loading = false;
        _loadedOnce = true;
      });
      _lastRefreshAt = DateTime.now();
      _maybeAutoOpenListing(items);
      if (loadError != null && hasItems) {
        _showLoadErrorSnack();
      }
    } catch (error) {
      _debugMyListingsLog('MyListings refresh error message=$error');
      if (!mounted) return;
      setState(() {
        if ((_items ?? const <Listing>[]).isEmpty) {
          _errorText = 'Не удалось загрузить объявления. Попробуйте снова.';
        }
        _loading = false;
      });
      if ((_items ?? const <Listing>[]).isNotEmpty) {
        _showLoadErrorSnack();
      } else {
        setState(() {
          _loadedOnce = true;
        });
      }
    } finally {
      _debugMyListingsLog('MyListings refresh finally loading=false');
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _isLoadingMore || !_hasMore || _nextCursor == null) return;
    setState(() {
      _isLoadingMore = true;
    });
    try {
      await _load(reset: false);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
        _scheduleShortListLoadMore();
      }
    }
  }

  void _scheduleShortListLoadMore() {
    if (!_hasMore ||
        _isLoadingMore ||
        _automaticLoadMorePages >= _maxAutomaticLoadMorePages) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_hasMore ||
          _isLoadingMore ||
          _automaticLoadMorePages >= _maxAutomaticLoadMorePages ||
          !_scrollController.hasClients ||
          _scrollController.position.maxScrollExtent > 1) {
        return;
      }
      _automaticLoadMorePages += 1;
      unawaited(_loadMore());
    });
  }

  bool _handleScroll(ScrollNotification notification) {
    widget.onScrollNotification(notification);
    if (notification is! ScrollEndNotification) return false;
    final pixels = notification.metrics.pixels;
    if (notification.metrics.extentAfter < 480 &&
        _lastLoadMoreTriggerPixels != pixels) {
      _lastLoadMoreTriggerPixels = pixels;
      unawaited(_loadMore());
    }
    return false;
  }

  List<Listing> _appendListings(List<Listing>? current, List<Listing> next) {
    final merged = <Listing>[];
    final seen = <String>{};
    final currentItems = current ?? const <Listing>[];
    for (final item in <Listing>[...currentItems, ...next]) {
      if (seen.add(item.id)) merged.add(item);
    }
    return merged;
  }

  String get _statusLabelForTrace {
    final values = widget.statuses.toList(growable: false)..sort();
    return values.join(',');
  }

  void _replaceLocalItems(
    List<Listing> next, {
    required String reason,
    required String source,
  }) {
    final oldItems = _items ?? const <Listing>[];
    final oldCount = oldItems.length;
    final newCount = next.length;
    final oldIds = oldItems.map((item) => item.id).take(30).join(',');
    final cacheRevision =
        context.read<ListingsService>().debugMyListingsCacheRevision;
    _debugMyListingsLog(
      'ITEMS old=$oldCount new=$newCount status=$_statusLabelForTrace '
      'reason=$reason source=$source',
    );
    if (oldCount > 0 && newCount == 0) {
      debugPrint(
        '[MYLIST] BECAME_EMPTY user=${widget.userId} status=$_statusLabelForTrace '
        'oldCount=$oldCount newCount=$newCount oldIds=$oldIds '
        'reason=$reason source=$source cacheRev=$cacheRevision '
        'widget/state identity=${identityHashCode(widget)}/${identityHashCode(this)}',
      );
      _debugMyListingsStack('screen._replaceLocalItems', maxFrames: 20);
    } else {
      _debugMyListingsLog(
        'local items replace user=${widget.userId} status=$_statusLabelForTrace '
        'oldCount=$oldCount newCount=$newCount reason=$reason source=$source '
        'widget/state identity=${identityHashCode(widget)}/${identityHashCode(this)} '
        'cache revision=$cacheRevision',
      );
    }
    _items = List<Listing>.from(next);
  }

  void _maybeAutoOpenListing(List<Listing> items) {
    if (_didAutoOpenInitialListing ||
        !widget.autoOpenInitialListing ||
        widget.initialListingId.trim().isEmpty) {
      return;
    }
    Listing? listing;
    for (final item in items) {
      if (item.id == widget.initialListingId.trim()) {
        listing = item;
        break;
      }
    }
    if (listing == null || !mounted) {
      return;
    }
    final resolvedListing = listing;
    _didAutoOpenInitialListing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ListingDetailScreen(listingId: resolvedListing.id),
        ),
      );
    });
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return FutureBuilder<List<Listing>>(
      future: _future,
      builder: (context, snap) {
        final items = _items ?? snap.data ?? const <Listing>[];
        if (_loading && items.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            children: const [
              SkeletonMyListingTile(),
              SizedBox(height: 10),
              SkeletonMyListingTile(),
              SizedBox(height: 10),
              SkeletonMyListingTile(),
            ],
          );
        }

        if (_errorText != null && items.isEmpty) {
          return _AsyncStateView(
            message: _errorText!,
            actionLabel: 'Повторить',
            onPressed: _refresh,
          );
        }

        if (_errorText != null && items.isNotEmpty) {
          return AttaRefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                12 + widget.bottomPadding,
              ),
              children: [
                ...items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MyListingTile(
                        listing: item,
                        showFavoriteCount: widget.statuses.length == 1 &&
                            widget.statuses.contains('approved'),
                      ),
                    )),
                Text(
                  _errorText!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          );
        }

        if (_loadedOnce && items.isEmpty) {
          return AttaRefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 160),
                Center(child: Text(widget.emptyText)),
                SizedBox(height: widget.bottomPadding),
              ],
            ),
          );
        }

        return AttaRefreshIndicator(
          onRefresh: _refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: ListView.separated(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                12 + widget.bottomPadding,
              ),
              itemCount: items.length + (_isLoadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                if (i >= items.length) {
                  return const _LoadMoreFooter();
                }
                return _MyListingTile(
                  listing: items[i],
                  showFavoriteCount: items[i].normalizedStatus == 'approved',
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _CreateListingBottomButton extends StatelessWidget {
  const _CreateListingBottomButton({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final theme = Theme.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 12 + safeBottom,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1.35),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          child: AnimatedOpacity(
            key: const ValueKey('my_listings_create_button_opacity'),
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () =>
                      AddListingIconButton.openCreateListingFlow(context),
                  child: const Text('Разместить объявление'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ListingsTab extends StatelessWidget {
  final Stream<List<Listing>> stream;
  final double bottomPadding;
  final bool Function(ScrollNotification notification) onScrollNotification;
  const _ListingsTab({
    required this.stream,
    required this.bottomPadding,
    required this.onScrollNotification,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Listing>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            children: const [
              SkeletonMyListingTile(),
              SizedBox(height: 10),
              SkeletonMyListingTile(),
              SizedBox(height: 10),
              SkeletonMyListingTile(),
            ],
          );
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return const Center(child: Text('Пока нет объявлений'));
        }
        return NotificationListener<ScrollNotification>(
          onNotification: onScrollNotification,
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomPadding),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _MyListingTile(
              listing: items[i],
              showFavoriteCount: items[i].normalizedStatus == 'approved',
            ),
          ),
        );
      },
    );
  }
}

class _AsyncStateView extends StatelessWidget {
  const _AsyncStateView({
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final String message;
  final String actionLabel;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onPressed,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyListingTile extends StatelessWidget {
  final Listing listing;
  final bool showFavoriteCount;
  const _MyListingTile({
    required this.listing,
    this.showFavoriteCount = false,
  });

  bool get _canSellFaster =>
      listing.normalizedStatus == 'approved' && !listing.isArchivedStatus;

  @override
  Widget build(BuildContext context) {
    final svc = context.read<ListingsService>();
    final currentUserId = context.read<AuthService>().currentUser?.uid ?? '';
    final photo = listing.photoUrls.isNotEmpty ? listing.photoUrls.first : null;
    final canResubmit = listing.canOwnerResubmit;
    const resubmitLabel = 'Опубликовать снова';
    final canEdit = listing.canOwnerEdit;
    final normalizedStatus = listing.normalizedStatus;
    final canArchive = normalizedStatus == 'approved';
    final showSecondaryAction = canResubmit || canArchive;
    final secondaryLabel = canResubmit ? resubmitLabel : 'Снять с публикации';
    final archiveNote = listing.archiveNote.trim();
    final statusPresentation = _statusPresentation(context, listing);
    final isOwner = listing.ownerId.trim() == currentUserId.trim();
    _debugMyListingsLog(
      'widget=_MyListingTile listingId=${listing.id} '
      'rawStatus=${listing.status} normalizedStatus=$normalizedStatus '
      'moderatedBy=${listing.moderatedBy} ownerId=${listing.ownerId} '
      'currentUserId=$currentUserId isOwner=$isOwner '
      'canOwnerEdit=${listing.canOwnerEdit} '
      'canOwnerResubmit=${listing.canOwnerResubmit}',
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: _myListingCardShadows(context),
      ),
      child: Material(
        key: ValueKey('my_listing_surface:${listing.id}'),
        color: Theme.of(context).brightness == Brightness.light
            ? Colors.white
            : Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: listing.hasVipPromotion
              ? BorderSide(
                  color: vipBorderColor(context),
                  width: 1.25,
                )
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ListingDetailScreen(listingId: listing.id),
            ),
          ),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 92,
                        height: 69,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            (photo?.trim().isNotEmpty ?? false)
                                ? MediaPreviewBox(
                                    imageUrl: photo!,
                                    categoryHint: 'listings',
                                    width: 92,
                                    height: 69,
                                    borderRadius: 12,
                                  )
                                : Container(
                                    width: 92,
                                    height: 69,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.image_outlined),
                                  ),
                            ListingPromotionBadges(
                              showVip: listing.hasVipPromotion,
                              showBump: listing.hasBumpPromotion,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            listing.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: normalizedStatus == 'approved'
                                ? Text(
                                    key: ValueKey(
                                      'my_listing_status:${listing.id}',
                                    ),
                                    statusPresentation.label,
                                    style: TextStyle(
                                      color: statusPresentation.foreground,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : Container(
                                    key: ValueKey(
                                      'my_listing_status:${listing.id}',
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusPresentation.background,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      statusPresentation.label,
                                      style: TextStyle(
                                        color: statusPresentation.foreground,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${formatPrice(listing.price)} ₽',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Flexible(
                                fit: FlexFit.loose,
                                child: Text(
                                  'Просмотров: ${listing.viewCount}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (showFavoriteCount) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.favorite_border,
                                  key: ValueKey(
                                    'my_listing_favorite_icon:${listing.id}',
                                  ),
                                  size: 14,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${listing.favoriteCount}',
                                  key: ValueKey(
                                    'my_listing_favorite_count:${listing.id}',
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.person_outline,
                                  key: ValueKey(
                                    'my_listing_followers_icon:${listing.id}',
                                  ),
                                  size: 14,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                                const SizedBox(width: 4),
                                StreamBuilder<int>(
                                  stream: context
                                      .read<FollowService>()
                                      .streamFollowersCount(listing.ownerId),
                                  builder: (context, snapshot) {
                                    final count = snapshot.data ?? 0;
                                    return Text(
                                      '$count',
                                      key: ValueKey(
                                        'my_listing_followers_count:${listing.id}',
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                          if (archiveNote.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              archiveNote,
                              maxLines: 3,
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
                if (_canSellFaster) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SellFasterScreen(listing: listing),
                          ),
                        );
                      },
                      icon: const Icon(Icons.bolt_outlined),
                      label: const Text('Продать быстрее'),
                    ),
                  ),
                ],
                if (canEdit || showSecondaryAction) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _AsyncListingActionButton(
                          label: 'Редактировать',
                          icon: Icons.edit,
                          onPressed: canEdit
                              ? () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => EditListingScreen(
                                        listingId: listing.id,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                        ),
                      ),
                      if (showSecondaryAction) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AsyncListingActionButton(
                            label: secondaryLabel,
                            onPressed: canResubmit
                                ? () async {
                                    try {
                                      await svc.resubmitListing(
                                        listingId: listing.id,
                                      );
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Объявление отправлено на модерацию',
                                          ),
                                        ),
                                      );
                                    } catch (_) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Не удалось отправить объявление. Проверьте данные и попробуйте снова.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                : () async {
                                    await runListingArchiveFlow(
                                      context,
                                      listingId: listing.id,
                                      listingsService: svc,
                                    );
                                  },
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  _ListingStatusPresentation _statusPresentation(
    BuildContext context,
    Listing listing,
  ) {
    final colors = Theme.of(context).colorScheme;
    switch (listing.normalizedStatus) {
      case 'approved':
        return const _ListingStatusPresentation(
          label: 'Активно',
          background: Color(0xFFE4F6EA),
          foreground: Color(0xFF16713A),
        );
      case 'pending':
        return const _ListingStatusPresentation(
          label: 'На проверке',
          background: Color(0xFFFFEAC7),
          foreground: Color(0xFF9A5700),
        );
      case 'rejected':
        return _ListingStatusPresentation(
          label: 'Требуется действие',
          background: colors.errorContainer,
          foreground: colors.onErrorContainer,
        );
      case 'sold':
        return const _ListingStatusPresentation(
          label: 'Продано',
          background: Color(0xFFE4F6EA),
          foreground: Color(0xFF16713A),
        );
      case 'deleted':
        return _ListingStatusPresentation(
          label: 'Удалено',
          background: colors.errorContainer,
          foreground: colors.onErrorContainer,
        );
      case 'archived':
        if (listing.isAdminArchived) {
          return _ListingStatusPresentation(
            label: 'Удалено модератором',
            background: colors.errorContainer,
            foreground: colors.onErrorContainer,
          );
        }
        return _ListingStatusPresentation(
          label: 'Снято',
          background: colors.surfaceContainerHighest,
          foreground: colors.onSurfaceVariant,
        );
      default:
        return _ListingStatusPresentation(
          label: listing.status,
          background: colors.surfaceContainerHighest,
          foreground: colors.onSurfaceVariant,
        );
    }
  }
}

class _ListingStatusPresentation {
  const _ListingStatusPresentation({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;
}
