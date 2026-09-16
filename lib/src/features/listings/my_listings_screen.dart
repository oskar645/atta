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
import 'package:atta/src/utils/price_formatter.dart';
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
    with SingleTickerProviderStateMixin {
  static const double _bottomCreateButtonReserve = 92;
  static const double _scrollDirectionThreshold = 28;
  static const _tabs = <_MyListingsTabConfig>[
    _MyListingsTabConfig(
      title: 'Активные',
      statuses: {'approved'},
      emptyText: 'Нет активных объявлений',
    ),
    _MyListingsTabConfig(
      title: 'На модерации',
      statuses: {'pending'},
      emptyText: 'Нет объявлений на модерации',
    ),
    _MyListingsTabConfig(
      title: 'В архиве',
      statuses: {'archived'},
      emptyText: 'Нет архивных объявлений',
    ),
    _MyListingsTabConfig(
      title: 'Отклонённые',
      statuses: {'rejected'},
      emptyText: 'Нет отклонённых объявлений',
    ),
    _MyListingsTabConfig(
      title: 'Проданные',
      statuses: {'sold'},
      emptyText: 'Нет проданных объявлений',
    ),
    _MyListingsTabConfig(
      title: 'Удалённые',
      statuses: {'deleted'},
      emptyText: 'Нет удалённых объявлений',
    ),
  ];

  late final TabController _tab;
  bool _showCreateButton = true;
  double _scrollDirectionDistance = 0;

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _debugMyListingsLog('dispose screen=${identityHashCode(this)}');
    _tab.removeListener(_handleTabChanged);
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
          isScrollable: true,
          tabs: _tabs.map((tab) => Tab(text: tab.title)).toList(),
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
  late Future<List<Listing>> _future;
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
    _debugMyListingsLog(
      'MyListings load start user=${widget.userId} statuses=${widget.statuses.join(",")}',
    );
    try {
      final page = await listings.getMyListingsPageByStatuses(
        widget.userId,
        statuses: widget.statuses,
        limit: 20,
        cursor: reset ? null : _nextCursor,
        forceRefresh: reset && hadItems,
      );
      final items = reset ? page.items : _appendListings(_items, page.items);
      final loadError = listings.lastMyListingsErrorForUser(widget.userId);
      if (mounted) {
        setState(() {
          _replaceLocalItems(
            items,
            reason: reset ? 'load reset' : 'load append',
            source: '_load',
          );
          _nextCursor = page.nextCursor;
          _hasMore = page.hasMore && (page.nextCursor ?? '').trim().isNotEmpty;
          _errorText = !hadItems && loadError != null
              ? 'Не удалось загрузить объявления. Попробуйте снова.'
              : null;
          _loading = false;
          _loadedOnce = true;
        });
      }
      _lastRefreshAt = DateTime.now();
      _debugMyListingsLog(
        items.isEmpty
            ? 'MyListings load empty'
            : 'MyListings load success count=${items.length}',
      );
      _maybeAutoOpenListing(items);
      return items;
    } catch (error) {
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
      }
    }
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
          return RefreshIndicator(
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
          return RefreshIndicator(
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

        return RefreshIndicator(
          onRefresh: _refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: ListView.separated(
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
                  showFavoriteCount: widget.statuses.length == 1 &&
                      widget.statuses.contains('approved'),
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
            itemBuilder: (_, i) => _MyListingTile(listing: items[i]),
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
    final resubmitLabel = listing.normalizedStatus == 'rejected'
        ? 'Отправить на модерацию'
        : 'Опубликовать снова';
    final canEdit = listing.canOwnerEdit;
    final normalizedStatus = listing.normalizedStatus;
    final canArchive = normalizedStatus == 'approved';
    final showSecondaryAction = canResubmit || canArchive;
    final secondaryLabel = canResubmit ? resubmitLabel : 'Снять с публикации';
    final archiveNote = listing.archiveNote.trim();
    final isOwner = listing.ownerId.trim() == currentUserId.trim();
    _debugMyListingsLog(
      'widget=_MyListingTile listingId=${listing.id} '
      'rawStatus=${listing.status} normalizedStatus=$normalizedStatus '
      'moderatedBy=${listing.moderatedBy} ownerId=${listing.ownerId} '
      'currentUserId=$currentUserId isOwner=$isOwner '
      'canOwnerEdit=${listing.canOwnerEdit} '
      'canOwnerResubmit=${listing.canOwnerResubmit}',
    );

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ListingDetailScreen(listingId: listing.id),
        ),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: listing.hasVipPromotion
                ? vipBorderColor(context)
                : Theme.of(context).colorScheme.outlineVariant,
            width: listing.hasVipPromotion ? 1.25 : 1,
          ),
        ),
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
                      const SizedBox(height: 4),
                      Text(
                        'Статус: ${_statusLabel(normalizedStatus)}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final secondarySpacing = showSecondaryAction ? 8.0 : 0.0;
                  final actionCount = showSecondaryAction ? 2 : 1;
                  final actionWidth =
                      (constraints.maxWidth - secondarySpacing) / actionCount;
                  final isCompact = actionWidth < 168;
                  final editFontSize = isCompact ? 12.0 : 14.0;
                  final archiveFontSize = isCompact ? 11.0 : 12.0;

                  return Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: canEdit
                              ? () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => EditListingScreen(
                                        listingId: listing.id,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          style: isCompact
                              ? OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                )
                              : null,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.edit),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Редактировать',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: editFontSize),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (showSecondaryAction) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: canResubmit
                                ? () async {
                                    await svc.resubmitListing(
                                      listingId: listing.id,
                                    );
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Объявление отправлено на модерацию',
                                        ),
                                      ),
                                    );
                                  }
                                : () async {
                                    await runListingArchiveFlow(
                                      context,
                                      listingId: listing.id,
                                      listingsService: svc,
                                    );
                                  },
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                            ),
                            child: Text(
                              secondaryLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: archiveFontSize),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'Активно';
      case 'pending':
        return 'На модерации';
      case 'rejected':
        return 'Отклонённые';
      case 'sold':
        return 'Проданные';
      case 'deleted':
        return 'Удалённые';
      case 'archived':
        return 'В архиве';
      default:
        return status;
    }
  }
}
