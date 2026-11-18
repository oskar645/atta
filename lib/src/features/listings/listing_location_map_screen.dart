import 'dart:convert';

import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/map_config.dart';
import 'package:atta/src/utils/external_route_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class ListingLocationMapScreen extends StatefulWidget {
  const ListingLocationMapScreen({super.key, required this.listing});

  final Listing listing;

  @override
  State<ListingLocationMapScreen> createState() =>
      _ListingLocationMapScreenState();
}

class _ListingLocationMapScreenState extends State<ListingLocationMapScreen> {
  final MapController _controller = MapController();
  LatLng? _destination;
  List<LatLng> _route = const [];
  bool _loading = true;
  bool _routing = false;

  String get _address => widget.listing.cityFull.trim();

  @override
  void initState() {
    super.initState();
    _loadDestination();
  }

  Future<void> _loadDestination() async {
    LatLng? point;
    if (widget.listing.hasCoordinates) {
      point = LatLng(widget.listing.latitude!, widget.listing.longitude!);
    } else if (_address.isNotEmpty) {
      try {
        final locations = await locationFromAddress(_address);
        if (locations.isNotEmpty) {
          point = LatLng(locations.first.latitude, locations.first.longitude);
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _destination = point;
      _loading = false;
    });
  }

  Future<void> _buildRoute() async {
    final destination = _destination;
    if (destination == null || _routing) return;
    setState(() => _routing = true);
    try {
      final base = AttaMapConfig.routingBaseUrl.trim();
      if (base.isEmpty) {
        final opened = await openExternalDrivingRoute(
          latitude: destination.latitude,
          longitude: destination.longitude,
        );
        if (!opened) throw StateError('Не удалось открыть приложение карт.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Для маршрута разрешите доступ к геопозиции.');
      }
      final position = await Geolocator.getCurrentPosition();
      final origin = LatLng(position.latitude, position.longitude);
      final uri = Uri.parse(
        '${base.replaceAll(RegExp(r'/$'), '')}/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError('Маршрут недоступен');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = json['routes'];
      if (routes is! List || routes.isEmpty) {
        throw StateError('Маршрут не найден');
      }
      final coordinates = routes.first['geometry']['coordinates'] as List;
      final points = coordinates
          .whereType<List>()
          .where((item) => item.length >= 2)
          .map((item) => LatLng(
                (item[1] as num).toDouble(),
                (item[0] as num).toDouble(),
              ))
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _route = points);
      _controller.fitCamera(CameraFit.coordinates(
        coordinates: [origin, destination],
        padding: const EdgeInsets.all(64),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  void _zoom(double delta) {
    _controller.move(_controller.camera.center,
        (_controller.camera.zoom + delta).clamp(3, 19));
  }

  @override
  Widget build(BuildContext context) {
    final point = _destination;
    return Scaffold(
      appBar: AppBar(title: const Text('Адрес объявления')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : point == null
              ? const Center(
                  child: Text('Не удалось определить точку по адресу'))
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: _controller,
                      options:
                          MapOptions(initialCenter: point, initialZoom: 15),
                      children: [
                        AttaMapConfig.tiles(),
                        if (_route.isNotEmpty)
                          PolylineLayer(polylines: [
                            Polyline(
                                points: _route,
                                strokeWidth: 5,
                                color: Theme.of(context).colorScheme.primary),
                          ]),
                        MarkerLayer(markers: [
                          Marker(
                            point: point,
                            width: 54,
                            height: 54,
                            child: const Icon(Icons.location_pin,
                                size: 54, color: Color(0xFF1565C0)),
                          ),
                        ]),
                        AttaMapConfig.attribution(),
                      ],
                    ),
                    Positioned(
                      right: 12,
                      top: 16,
                      child: Column(children: [
                        _MapButton(icon: Icons.add, onTap: () => _zoom(1)),
                        const SizedBox(height: 8),
                        _MapButton(icon: Icons.remove, onTap: () => _zoom(-1)),
                      ]),
                    ),
                  ],
                ),
      bottomNavigationBar: point == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_address,
                          maxLines: 2, overflow: TextOverflow.ellipsis)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _routing ? null : _buildRoute,
                      icon: _routing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.directions_outlined),
                      label: const Text('Построить маршрут'),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        elevation: 3,
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: IconButton(icon: Icon(icon), onPressed: onTap),
      );
}
