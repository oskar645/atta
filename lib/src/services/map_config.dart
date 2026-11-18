import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

class AttaMapConfig {
  static const tileUrl = String.fromEnvironment(
    'OSM_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );
  static const routingBaseUrl = String.fromEnvironment('ROUTING_BASE_URL');
  static const userAgentPackage = 'ru.atta.market';

  static TileLayer tiles() => TileLayer(
        urlTemplate: tileUrl,
        userAgentPackageName: userAgentPackage,
      );

  static Widget attribution() => RichAttributionWidget(
        attributions: [
          TextSourceAttribution(
            '© OpenStreetMap contributors',
            onTap: () => launchUrl(
              Uri.parse('https://www.openstreetmap.org/copyright'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      );
}
