import 'package:atta/src/utils/external_route_launcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  test('prefers Yandex Maps and passes destination as a route', () async {
    final checked = <Uri>[];
    Uri? opened;

    final result = await openExternalDrivingRoute(
      latitude: 43.3530186,
      longitude: 46.1049578,
      canLaunch: (uri) async {
        checked.add(uri);
        return uri.scheme == 'yandexmaps';
      },
      launch: (uri, mode) async {
        opened = uri;
        expect(mode, LaunchMode.externalApplication);
        return true;
      },
    );

    expect(result, isTrue);
    expect(checked, hasLength(1));
    expect(opened?.scheme, 'yandexmaps');
    expect(opened.toString(), contains('43.3530186,46.1049578'));
    expect(opened.toString(), contains('rtt=auto'));
  });

  test('falls back to Google Maps when Yandex Maps is absent', () async {
    Uri? opened;

    await openExternalDrivingRoute(
      latitude: 43.3197031,
      longitude: 45.6934308,
      canLaunch: (uri) async => uri.scheme == 'comgooglemaps',
      launch: (uri, mode) async {
        opened = uri;
        return true;
      },
    );

    expect(opened?.scheme, 'comgooglemaps');
    expect(opened.toString(), contains('directionsmode=driving'));
  });

  test('uses web driving directions when no map app is installed', () async {
    Uri? opened;

    final result = await openExternalDrivingRoute(
      latitude: 42.1152434,
      longitude: 48.1864201,
      canLaunch: (_) async => false,
      launch: (uri, mode) async {
        opened = uri;
        return true;
      },
    );

    expect(result, isTrue);
    expect(opened?.host, 'www.google.com');
    expect(opened?.path, '/maps/dir/');
    expect(opened?.queryParameters['travelmode'], 'driving');
  });
}
