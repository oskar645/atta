import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class MapPickerScreen extends StatefulWidget {
  final LatLng? initial;
  const MapPickerScreen({super.key, this.initial});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _map = MapController();
  LatLng _picked = const LatLng(55.751244, 37.618423); // Москва по умолчанию
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _picked = widget.initial!;
  }

  Future<void> _goToMyLocation() async {
    setState(() => _loading = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к геолокации')),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      final p = LatLng(pos.latitude, pos.longitude);
      setState(() => _picked = p);
      _map.move(p, 14);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _confirm() {
    Navigator.pop(context, _picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Выбрать на карте'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _goToMyLocation,
            icon: const Icon(Icons.my_location),
            tooltip: 'Моё местоположение',
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: _picked,
          initialZoom: 12,
          onTap: (tapPos, latLng) => setState(() => _picked = latLng),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.atta',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: _picked,
                width: 44,
                height: 44,
                child:
                    const Icon(Icons.location_pin, size: 44, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _confirm,
            child: const Text('Выбрать это место'),
          ),
        ),
      ),
    );
  }
}
