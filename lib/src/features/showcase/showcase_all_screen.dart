import 'dart:async';

import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/constants/categories.dart';
import 'package:atta/src/models/showcase_item.dart';
import 'package:atta/src/services/showcase_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ShowcaseAllScreen extends StatefulWidget {
  const ShowcaseAllScreen({
    super.key,
    this.onOpenListing,
  });

  final Future<void> Function(BuildContext context, ShowcaseItem item)?
      onOpenListing;

  @override
  State<ShowcaseAllScreen> createState() => _ShowcaseAllScreenState();
}

class _ShowcaseAllScreenState extends State<ShowcaseAllScreen> {
  static const int _pageSize = 20;
  static const Duration _searchDebounce = Duration(milliseconds: 400);

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  List<ShowcaseItem> _items = const <ShowcaseItem>[];
  String _selectedFilter = 'Все';
  String _search = '';
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _nextCursor;
  Object? _error;
  int _requestSerial = 0;
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter >= 900 ||
        _initialLoading ||
        _loadingMore ||
        !_hasMore) {
      return;
    }
    unawaited(_load(reset: false));
  }

  List<ShowcaseItem> _mergeUnique(
    List<ShowcaseItem> current,
    List<ShowcaseItem> incoming,
  ) {
    final seenKeys = current.map(_dedupeKey).toSet();
    final merged = List<ShowcaseItem>.from(current);
    for (final item in incoming) {
      if (seenKeys.add(_dedupeKey(item))) {
        merged.add(item);
      }
    }
    return merged;
  }

  String _dedupeKey(ShowcaseItem item) {
    final listingId = item.listingId.trim();
    if (listingId.isNotEmpty) return 'listing:$listingId';
    return 'promotion:${item.promotionId.trim()}';
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loadingMore || !_hasMore)) return;
    final serial = ++_requestSerial;
    setState(() {
      if (reset) {
        _initialLoading = true;
        _loadingMore = false;
        _hasMore = true;
        _nextCursor = null;
        _error = null;
      } else {
        _loadingMore = true;
        _error = null;
      }
    });

    try {
      final page = await context.read<ShowcaseService>().getShowcasePage(
            limit: _pageSize,
            cursor: reset ? null : _nextCursor,
            category: _selectedFilter,
            search: _search,
          );
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _items = reset
            ? List<ShowcaseItem>.from(page.items)
            : _mergeUnique(_items, page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore && (page.nextCursor ?? '').trim().isNotEmpty;
        _initialLoading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _initialLoading = false;
        _loadingMore = false;
        _error = error;
      });
    }
  }

  Future<void> _refresh() => _load(reset: true);

  void _resetAndLoad() {
    setState(() {
      _items = const <ShowcaseItem>[];
      _initialLoading = true;
      _loadingMore = false;
      _hasMore = true;
      _nextCursor = null;
      _error = null;
    });
    unawaited(_load(reset: true));
  }

  void _selectCategory(String filter) {
    if (filter == _selectedFilter) {
      return;
    }
    _selectedFilter = filter;
    _resetAndLoad();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounce, () {
      final nextSearch = value.trim();
      if (nextSearch == _search) {
        return;
      }
      _search = nextSearch;
      _resetAndLoad();
    });
  }

  void _submitSearch(String value) {
    _searchDebounceTimer?.cancel();
    final nextSearch = value.trim();
    if (nextSearch == _search) {
      return;
    }
    _search = nextSearch;
    _resetAndLoad();
  }

  void _clearSearch() {
    _searchDebounceTimer?.cancel();
    if (_searchController.text.isEmpty && _search.isEmpty) {
      return;
    }
    _searchController.clear();
    _search = '';
    _resetAndLoad();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Витрина ATTA'),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
              child: TextField(
                key: const ValueKey('showcase_search_field'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: _submitSearch,
                decoration: InputDecoration(
                  hintText: 'Поиск',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Очистить',
                          icon: const Icon(Icons.close),
                          onPressed: _clearSearch,
                        ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView.separated(
                key: const ValueKey('showcase_category_filters'),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final filter = kCategories[index];
                  final selected = filter == _selectedFilter;
                  return ChoiceChip(
                    label: Text(filter),
                    selected: selected,
                    onSelected: (_) => _selectCategory(filter),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: kCategories.length,
              ),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_initialLoading && _items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: _ShowcaseGridSkeleton(),
                    );
                  }

                  if (_items.isEmpty) {
                    return _EmptyShowcaseState(error: _error);
                  }

                  return Column(
                    children: [
                      Expanded(
                        child: GridView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.76,
                          ),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return _ShowcaseGridCard(
                              item: item,
                              onOpenListing: widget.onOpenListing,
                            );
                          },
                        ),
                      ),
                      if (_loadingMore)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShowcaseGridCard extends StatelessWidget {
  const _ShowcaseGridCard({
    required this.item,
    this.onOpenListing,
  });

  final ShowcaseItem item;
  final Future<void> Function(BuildContext context, ShowcaseItem item)?
      onOpenListing;

  Future<void> _openListing(BuildContext context) async {
    final customOpen = onOpenListing;
    if (customOpen != null) {
      await customOpen(context, item);
      return;
    }
    final listingId = item.listingId.trim();
    if (listingId.isEmpty) {
      showAppSnack(context, 'Объявление недоступно', isError: true);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListingDetailScreen(listingId: listingId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openListing(context),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MediaPreviewBox(
                  imageUrl: item.firstPhotoUrl ?? '',
                  categoryHint: 'listings',
                  borderRadius: 0,
                  emptyLabel: 'Фото недоступно',
                  errorLabel: 'Фото недоступно',
                  placeholderLabel: 'Загрузка фото...',
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.00),
                      Colors.black.withValues(alpha: 0.68),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Витрина',
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
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
                    if (item.city.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShowcaseGridSkeleton extends StatelessWidget {
  const _ShowcaseGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.76,
      ),
      itemBuilder: (_, __) => const SkeletonBox(radius: 16),
    );
  }
}

class _EmptyShowcaseState extends StatelessWidget {
  const _EmptyShowcaseState({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 120, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error == null
                    ? 'Витрина пока пустая'
                    : 'Не удалось загрузить витрину',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                error == null
                    ? 'Здесь появятся объявления, которые пользователи продвигают за бонусы.'
                    : 'Потяните вниз, чтобы повторить.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
