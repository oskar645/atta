import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:atta/src/constants/categories.dart';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/widgets/listing_card.dart';
import 'package:atta/src/widgets/skeletons.dart';

class VipShowcaseScreen extends StatefulWidget {
  const VipShowcaseScreen({super.key});

  @override
  State<VipShowcaseScreen> createState() => _VipShowcaseScreenState();
}

class _VipShowcaseScreenState extends State<VipShowcaseScreen> {
  static const int _pageSize = 20;
  static const Duration _searchDebounce = Duration(milliseconds: 400);

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  List<Listing> _items = const <Listing>[];
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _nextCursor;
  String _selectedCategory = 'Все';
  String _search = '';
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

  List<Listing> _mergeUnique(List<Listing> current, List<Listing> incoming) {
    final seenIds = current.map((item) => item.id).toSet();
    final merged = List<Listing>.from(current);
    for (final item in incoming) {
      if (seenIds.add(item.id)) {
        merged.add(item);
      }
    }
    return merged;
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
      final page = await context.read<ListingsService>().getVipListingsPage(
            limit: _pageSize,
            cursor: reset ? null : _nextCursor,
            category: _selectedCategory,
            search: _search,
          );
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _items = reset
            ? List<Listing>.from(page.items)
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

  void _selectCategory(String category) {
    if (category == _selectedCategory) {
      return;
    }
    setState(() {
      _selectedCategory = category;
      _items = const <Listing>[];
      _initialLoading = true;
      _loadingMore = false;
      _hasMore = true;
      _nextCursor = null;
      _error = null;
    });
    unawaited(_load(reset: true));
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounce, () {
      final nextSearch = value.trim();
      if (nextSearch == _search) {
        return;
      }
      setState(() {
        _search = nextSearch;
        _items = const <Listing>[];
        _initialLoading = true;
        _loadingMore = false;
        _hasMore = true;
        _nextCursor = null;
        _error = null;
      });
      unawaited(_load(reset: true));
    });
  }

  void _clearSearch() {
    _searchDebounceTimer?.cancel();
    if (_searchController.text.isEmpty && _search.isEmpty) {
      return;
    }
    _searchController.clear();
    setState(() {
      _search = '';
      _items = const <Listing>[];
      _initialLoading = true;
      _loadingMore = false;
      _hasMore = true;
      _nextCursor = null;
      _error = null;
    });
    unawaited(_load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final favs = context.read<FavoritesService>();
    final reviews = context.read<ReviewsService>();
    final history = context.watch<ListingHistoryService>();
    final userId = context.read<AuthService>().currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Витрина VIP'),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
              child: TextField(
                key: const ValueKey('vip_showcase_search_field'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: (value) {
                  _searchDebounceTimer?.cancel();
                  final nextSearch = value.trim();
                  if (nextSearch == _search) return;
                  setState(() {
                    _search = nextSearch;
                    _items = const <Listing>[];
                    _initialLoading = true;
                    _loadingMore = false;
                    _hasMore = true;
                    _nextCursor = null;
                    _error = null;
                  });
                  unawaited(_load(reset: true));
                },
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
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final category = kCategories[index];
                  final selected = category == _selectedCategory;
                  return ChoiceChip(
                    label: Text(category),
                    selected: selected,
                    onSelected: (_) => _selectCategory(category),
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
                    return const SkeletonListingGrid(
                      physics: AlwaysScrollableScrollPhysics(),
                    );
                  }

                  if (_items.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 120),
                          child: Center(
                            child: Text(
                              _error == null
                                  ? 'VIP-витрина пока пустая'
                                  : 'Не удалось загрузить VIP-витрину. Потяните вниз, чтобы повторить.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      Expanded(
                        child: GridView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.all(10),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return FavoriteListingCard(
                              listing: item,
                              favoritesService: favs,
                              userId: userId,
                              isSeen: history.hasViewed(item.id),
                              reviews: reviews,
                              onOpen: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ListingDetailScreen(listingId: item.id),
                                ),
                              ),
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
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
