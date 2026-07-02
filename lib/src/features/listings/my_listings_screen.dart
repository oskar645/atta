import 'package:atta/src/features/favorites/favorites_screen.dart';
import 'package:atta/src/features/listings/add_listing_screen.dart';
import 'package:atta/src/features/listings/edit_listing_screen.dart';
import 'package:atta/src/features/listings/listing_archive_flow.dart';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/features/promotions/sell_faster_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:atta/src/widgets/listing_promotion_badges.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'dart:async';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen>
    with SingleTickerProviderStateMixin {
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
      title: 'Архивные',
      statuses: {'archived'},
      emptyText: 'Нет архивных объявлений',
    ),
    _MyListingsTabConfig(
      title: 'Удалённые',
      statuses: {'deleted', 'rejected'},
      emptyText: 'Нет удалённых объявлений',
    ),
    _MyListingsTabConfig(
      title: 'Проданные',
      statuses: {'sold'},
      emptyText: 'Нет проданных объявлений',
    ),
  ];

  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
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
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.blue, size: 28),
            tooltip: 'Добавить',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddListingScreen()),
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: _tabs
            .map(
              (tab) => ApiConfig.useTimewebBackend
                  ? _TimewebMyListingsTab(
                      userId: uid,
                      statuses: tab.statuses,
                      emptyText: tab.emptyText,
                    )
                  : _ListingsTab(
                      stream: svc.streamMyListingsByStatuses(
                        uid,
                        statuses: tab.statuses,
                      ),
                    ),
            )
            .toList(),
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
  });

  final String userId;
  final Set<String> statuses;
  final String emptyText;

  @override
  State<_TimewebMyListingsTab> createState() => _TimewebMyListingsTabState();
}

class _TimewebMyListingsTabState extends State<_TimewebMyListingsTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Listing>> _future;
  StreamSubscription<void>? _refreshSub;
  List<Listing>? _items;
  bool _loadedOnce = false;
  String? _errorText;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final cached = context.read<ListingsService>().peekMyListingsByStatuses(
          statuses: widget.statuses,
        );
    if (cached.isNotEmpty) {
      _items = cached;
      _loading = false;
    }
    _future = _load();
    _refreshSub = context.read<ListingsService>().refreshes.listen((_) {
      if (!mounted) return;
      setState(() {
        _items = context.read<ListingsService>().peekMyListingsByStatuses(
              statuses: widget.statuses,
            );
        _loadedOnce = true;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    super.dispose();
  }

  Future<List<Listing>> _load() {
    return context
        .read<ListingsService>()
        .getMyListingsByStatuses(
          widget.userId,
          statuses: widget.statuses,
        )
        .then((items) {
      if (mounted) {
        setState(() {
          _items = items;
          _errorText = null;
          _loading = false;
          _loadedOnce = true;
        });
      }
      return items;
    }).catchError((error) {
      if (mounted) {
        setState(() {
          _errorText = 'Не удалось загрузить объявления. Попробуйте снова.';
          _loading = false;
          _loadedOnce = true;
        });
      }
      throw error;
    });
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
      _errorText = null;
      _loading = _items == null;
    });
    try {
      await next;
    } catch (_) {}
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
              SkeletonAdminModerationCard(),
              SkeletonAdminModerationCard(),
              SkeletonAdminModerationCard(),
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
              padding: const EdgeInsets.all(12),
              children: [
                ...items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MyListingTile(listing: item),
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
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _MyListingTile(listing: items[i]),
          ),
        );
      },
    );
  }
}

class _ListingsTab extends StatelessWidget {
  final Stream<List<Listing>> stream;
  const _ListingsTab({required this.stream});

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
              SkeletonAdminModerationCard(),
              SkeletonAdminModerationCard(),
              SkeletonAdminModerationCard(),
            ],
          );
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return const Center(child: Text('Пока нет объявлений'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _MyListingTile(listing: items[i]),
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
  const _MyListingTile({required this.listing});

  bool get _canSellFaster =>
      listing.status == 'approved' && !listing.isArchivedStatus;

  @override
  Widget build(BuildContext context) {
    final svc = context.read<ListingsService>();
    final photo = listing.photoUrls.isNotEmpty ? listing.photoUrls.first : null;
    final isArchived = listing.isArchivedStatus;
    final canEdit = listing.canOwnerEdit &&
        listing.status != 'deleted' &&
        listing.status != 'sold';
    final archiveNote = listing.archiveNote.trim();

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
                      Text('Просмотров: ${listing.viewCount}'),
                      const SizedBox(height: 4),
                      Text(
                        'Статус: ${_statusLabel(listing.status)}',
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canEdit
                        ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    EditListingScreen(listingId: listing.id),
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.edit),
                    label: const Text('Редактировать'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isArchived
                        ? null
                        : () async {
                            await runListingArchiveFlow(
                              context,
                              listingId: listing.id,
                              listingsService: svc,
                            );
                          },
                    icon: Icon(
                      isArchived
                          ? Icons.inventory_2_outlined
                          : Icons.archive_outlined,
                      color: isArchived ? null : Colors.red,
                    ),
                    label: Text(isArchived ? 'В архиве' : 'В архив'),
                  ),
                ),
              ],
            ),
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
        return 'Отклонено';
      case 'sold':
        return 'Продано';
      case 'deleted':
        return 'Удалено админом';
      case 'archived':
        return 'В архиве';
      default:
        return status;
    }
  }
}
