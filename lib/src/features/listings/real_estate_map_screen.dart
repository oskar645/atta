import 'dart:math' as math;

import 'package:atta/src/models/map_listing.dart';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/map_config.dart';
import 'package:atta/src/theme/soft_shadows.dart';
import 'package:atta/src/theme/ui_metrics.dart';
import 'package:atta/src/utils/media_url.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:atta/src/widgets/atta_cool_surface.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

class RealEstateMapScreen extends StatefulWidget {
  const RealEstateMapScreen({
    super.key,
    required this.filters,
    this.subcategories = const [],
  });

  final ListingFeedFilters filters;
  final List<String> subcategories;

  @override
  State<RealEstateMapScreen> createState() => _RealEstateMapScreenState();
}

class _RealEstateMapScreenState extends State<RealEstateMapScreen> {
  final MapController _map = MapController();
  final TextEditingController _search = TextEditingController();
  List<MapListing> _items = const [];
  MapListing? _selected;
  bool _loading = false;
  bool _areaChanged = false;
  bool _mapReady = false;
  double _zoom = 11;
  late ListingFeedFilters _filters;

  @override
  void initState() {
    super.initState();
    _filters = widget.filters;
    _search.text = _filters.location;
  }

  void _onMapReady() {
    if (!mounted || _mapReady) return;
    setState(() => _mapReady = true);
    _initializeMap();
  }

  void _onMapEvent(MapEvent event) {
    final zoomChanged = (_zoom - event.camera.zoom).abs() > 0.001;
    if (zoomChanged) _zoom = event.camera.zoom;

    final areaChanged =
        event.source != MapEventSource.mapController && !_areaChanged;
    if (zoomChanged || areaChanged) {
      setState(() {
        if (areaChanged) _areaChanged = true;
      });
    }
  }

  Future<void> _initializeMap() async {
    final location = _filters.location.trim();
    if (location.isNotEmpty) {
      try {
        final points = await locationFromAddress(location);
        if (points.isNotEmpty) {
          _map.move(LatLng(points.first.latitude, points.first.longitude), 12);
        }
      } catch (_) {}
    }
    await _loadArea();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadArea() async {
    if (!_mapReady || _loading) return;
    final bounds = _map.camera.visibleBounds;
    setState(() {
      _loading = true;
      _areaChanged = false;
    });
    try {
      final items =
          await context.read<ListingsService>().getRealEstateMapListings(
                north: bounds.north,
                south: bounds.south,
                east: bounds.east,
                west: bounds.west,
                filters: _filters,
              );
      if (!mounted) return;
      setState(() {
        _items = items;
        if (_selected != null &&
            !items.any((item) => item.id == _selected!.id)) {
          _selected = null;
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить точки: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _findAddress(String value) async {
    final query = value.trim();
    if (!_mapReady || query.isEmpty) return;
    try {
      final locations = await locationFromAddress(query);
      if (locations.isEmpty) return;
      _map.move(
          LatLng(locations.first.latitude, locations.first.longitude), 14);
      setState(() => _areaChanged = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Адрес не найден')),
        );
      }
    }
  }

  Future<void> _moveToMe() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    final position = await Geolocator.getCurrentPosition();
    _map.move(LatLng(position.latitude, position.longitude), 14);
    if (mounted) setState(() => _areaChanged = true);
  }

  List<_MapCluster> _clusters() {
    final cell = 360 / math.pow(2, _zoom) * 0.45;
    final groups = <String, List<MapListing>>{};
    for (final item in _items) {
      final key =
          '${(item.latitude / cell).floor()}:${(item.longitude / cell).floor()}';
      groups.putIfAbsent(key, () => []).add(item);
    }
    return groups.values.map((items) => _MapCluster(items)).toList();
  }

  Future<void> _showCluster(_MapCluster cluster) async {
    if (!_mapReady) return;
    if (cluster.items.length == 1) {
      setState(() => _selected = cluster.items.first);
      return;
    }
    // Listings that only contain a town/city address legitimately share the
    // exact same point. Zooming cannot separate those markers, so show their
    // choices immediately instead of making the user tap through many zooms.
    if (!cluster.hasSamePoint && _zoom < 18) {
      _map.move(cluster.center, _zoom + 2);
      setState(() => _areaChanged = true);
      return;
    }
    final chosen = await showModalBottomSheet<MapListing>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: AttaCoolSurface(
          borderRadius: 24,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: cluster.items.length,
            itemBuilder: (context, index) {
              final item = cluster.items[index];
              return ListTile(
                leading: const Icon(Icons.home_work_outlined),
                title: Text(item.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${formatPrice(item.price)} ₽ · ${item.locationLabel}'),
                onTap: () => Navigator.pop(context, item),
              );
            },
          ),
        ),
      ),
    );
    if (chosen != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ListingDetailScreen(listingId: chosen.id)));
    }
  }

  Future<void> _openFilters() async {
    final from =
        TextEditingController(text: _filters.priceFrom?.toString() ?? '');
    final to = TextEditingController(text: _filters.priceTo?.toString() ?? '');
    var subcategory = _filters.subcategory;
    var dealType = _filters.dealType;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: AttaCoolSurface(
            borderRadius: 24,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Фильтры недвижимости',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: subcategory,
                  decoration: const InputDecoration(labelText: 'Подкатегория'),
                  items: {
                    'Все',
                    ...widget.subcategories.where((item) => item != 'Все')
                  }
                      .map((item) =>
                          DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: (value) =>
                      setModalState(() => subcategory = value ?? 'Все'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: dealType.isEmpty ? '' : dealType,
                  decoration: const InputDecoration(labelText: 'Тип сделки'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Любой')),
                    DropdownMenuItem(value: 'Продажа', child: Text('Продажа')),
                    DropdownMenuItem(value: 'Аренда', child: Text('Аренда')),
                  ],
                  onChanged: (value) =>
                      setModalState(() => dealType = value ?? ''),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: from,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Цена от'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: to,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Цена до'))),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Показать'))),
              ]),
            ),
          ),
        ),
      ),
    );
    if (applied != true) return;
    setState(() {
      _filters = ListingFeedFilters(
        category: 'Недвижимость',
        search: _filters.search,
        subcategory: subcategory,
        priceFrom: int.tryParse(from.text),
        priceTo: int.tryParse(to.text),
        location: _filters.location,
        dealType: dealType,
      );
    });
    await _loadArea();
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    _map.move(_map.camera.center, (_zoom + delta).clamp(3, 19));
  }

  @override
  Widget build(BuildContext context) {
    final clusters = _clusters();
    return Scaffold(
      appBar: AppBar(title: const Text('Недвижимость на карте')),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            // Start with the main Chechen Republic market area visible. At the
            // previous city-level zoom, valid listings in Gudermes and nearby
            // towns were outside the first viewport and therefore outside the
            // initial /listings/map request.
            initialCenter: const LatLng(43.32, 45.90),
            initialZoom: 9,
            onMapReady: _onMapReady,
            onMapEvent: _onMapEvent,
          ),
          children: [
            AttaMapConfig.tiles(),
            MarkerLayer(
                markers: clusters
                    .map((cluster) => Marker(
                          point: cluster.center,
                          width: 48,
                          height: 48,
                          child: GestureDetector(
                            onTap: () => _showCluster(cluster),
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1565C0),
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                                boxShadow: const [
                                  BoxShadow(
                                      blurRadius: 4, color: Colors.black26)
                                ],
                              ),
                              alignment: Alignment.center,
                              child: cluster.items.length == 1
                                  ? const Icon(Icons.home_rounded,
                                      color: Colors.white, size: 24)
                                  : Text('${cluster.items.length}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ))
                    .toList()),
            AttaMapConfig.attribution(),
          ],
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Row(children: [
            Expanded(
                child: SizedBox(
              height: kStandardSearchFieldHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: attaFloatingControlShadows(context),
                ),
                child: Material(
                  elevation: 0,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    key: const Key('real-estate-map-search'),
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _findAddress,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                      hintText: 'Город, улица или адрес',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 40, minHeight: 40),
                      suffixIcon: IconButton(
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 40, minHeight: 40),
                          icon: const Icon(Icons.arrow_forward, size: 20),
                          onPressed: () => _findAddress(_search.text)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      filled: true,
                    ),
                  ),
                ),
              ),
            )),
            const SizedBox(width: 8),
            DecoratedBox(
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: attaFloatingControlShadows(context)),
                child: Material(
                    elevation: 0,
                    borderRadius: BorderRadius.circular(14),
                    child: IconButton(
                        tooltip: 'Фильтры',
                        onPressed: _openFilters,
                        icon: const Icon(Icons.tune)))),
          ]),
        ),
        Positioned(
            right: 12,
            top: 84,
            child: Column(children: [
              _MapControl(icon: Icons.add, onTap: () => _zoomBy(1)),
              const SizedBox(height: 8),
              _MapControl(icon: Icons.remove, onTap: () => _zoomBy(-1)),
              const SizedBox(height: 8),
              _MapControl(icon: Icons.my_location, onTap: _moveToMe),
            ])),
        if (_areaChanged)
          Positioned(
              top: 86,
              left: 0,
              right: 0,
              child: Center(
                  child: FilledButton.tonalIcon(
                      onPressed: _loadArea,
                      icon: const Icon(Icons.search),
                      label: const Text('Искать в этой области')))),
        if (_loading)
          const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2)),
        if (_selected case final selected?)
          Positioned(
              left: 12,
              right: 12,
              bottom: 18,
              child: _ListingPreview(
                listing: selected,
                onClose: () => setState(() => _selected = null),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        ListingDetailScreen(listingId: selected.id))),
              )),
      ]),
    );
  }
}

class _MapCluster {
  _MapCluster(this.items)
      : center = LatLng(
          items.map((e) => e.latitude).reduce((a, b) => a + b) / items.length,
          items.map((e) => e.longitude).reduce((a, b) => a + b) / items.length,
        );
  final List<MapListing> items;
  final LatLng center;

  bool get hasSamePoint {
    if (items.length < 2) return true;
    final first = items.first;
    return items.skip(1).every((item) =>
        (item.latitude - first.latitude).abs() < 0.000001 &&
        (item.longitude - first.longitude).abs() < 0.000001);
  }
}

class _MapControl extends StatelessWidget {
  const _MapControl({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: attaFloatingControlShadows(context),
        ),
        child: Material(
          elevation: 0,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox.square(
            dimension: 34,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 19,
              icon: Icon(icon),
              onPressed: onTap,
            ),
          ),
        ),
      );
}

class _ListingPreview extends StatelessWidget {
  const _ListingPreview(
      {required this.listing, required this.onTap, required this.onClose});
  final MapListing listing;
  final VoidCallback onTap;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final photoUrl = resolvePublicMediaUrl(
      listing.photoUrl ?? '',
      categoryHint: 'listings',
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: attaModalOverlayShadows(context),
      ),
      child: Material(
        elevation: 0,
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).brightness == Brightness.light
            ? Colors.white.withValues(alpha: 0.93)
            : Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                        width: 88,
                        height: 78,
                        child: photoUrl.isEmpty
                            ? const ColoredBox(
                                color: Color(0xFFECEFF1),
                                child: Icon(Icons.home_work_outlined))
                            : CachedNetworkImage(
                                imageUrl: photoUrl, fit: BoxFit.cover))),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      Text(listing.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      Text('${formatPrice(listing.price)} ₽',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      Text(listing.locationLabel,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ])),
                IconButton(icon: const Icon(Icons.close), onPressed: onClose),
              ])),
        ),
      ),
    );
  }
}
