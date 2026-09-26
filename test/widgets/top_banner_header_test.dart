import 'dart:convert';
import 'dart:typed_data';

import 'package:atta/src/models/top_banner.dart';
import 'package:atta/src/services/top_banners_service.dart';
import 'package:atta/src/widgets/top_banner_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _banner = TopBanner(
  id: 'banner-1',
  title: 'Banner',
  imageUrl: 'https://cdn.example/banner.png',
  targetUrl: '',
  enabled: true,
  startAt: DateTime.utc(2026, 9),
  endAt: DateTime.utc(2026, 10),
  sortOrder: 1,
  status: 'active',
  impressions: 0,
  clicks: 0,
);

class _TrackingService extends TopBannersService {
  int impressions = 0;

  @override
  Future<void> impression(TopBanner banner) async {
    impressions++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TopBannerHeaderBackground.debugImageProvider = null;
  });

  testWidgets(
      'ready image is shown and impression is sent once across rebuilds',
      (tester) async {
    final bytes = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ));
    TopBannerHeaderBackground.debugImageProvider = (_) => MemoryImage(bytes);
    final service = _TrackingService();

    Widget app() => MaterialApp(
          home: SizedBox(
            height: kToolbarHeight,
            child: TopBannerHeaderBackground(
              banner: _banner,
              service: service,
            ),
          ),
        );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(service.impressions, 1);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(service.impressions, 1);
  });
}
