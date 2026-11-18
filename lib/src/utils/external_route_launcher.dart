import 'package:url_launcher/url_launcher.dart';

typedef RouteCanLaunch = Future<bool> Function(Uri uri);
typedef RouteLaunch = Future<bool> Function(Uri uri, LaunchMode mode);

/// Opens an installed navigation app in a predictable order and gives it the
/// destination as a driving route. No origin is supplied: the chosen map app
/// uses the user's current position itself.
Future<bool> openExternalDrivingRoute({
  required double latitude,
  required double longitude,
  RouteCanLaunch? canLaunch,
  RouteLaunch? launch,
}) async {
  final canOpen = canLaunch ?? canLaunchUrl;
  final open = launch ??
      (uri, mode) => launchUrl(
            uri,
            mode: mode,
          );
  final destination = '$latitude,$longitude';
  final installedCandidates = <Uri>[
    Uri.parse('yandexmaps://maps.yandex.ru/?rtext=~$destination&rtt=auto'),
    Uri.parse('comgooglemaps://?daddr=$destination&directionsmode=driving'),
    Uri.parse('maps://?daddr=$destination&dirflg=d'),
    Uri.parse('geo:0,0?q=$destination'),
  ];

  for (final uri in installedCandidates) {
    if (await canOpen(uri) && await open(uri, LaunchMode.externalApplication)) {
      return true;
    }
  }

  return open(
    Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$destination&travelmode=driving'),
    LaunchMode.externalApplication,
  );
}
