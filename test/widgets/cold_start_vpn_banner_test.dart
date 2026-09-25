import 'package:atta/src/widgets/cold_start_vpn_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const title = 'ATTA лучше работает без VPN';
  const searchKey = ValueKey('home-search');

  Widget buildSubject({required bool show}) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const Positioned(
              top: 80,
              left: 12,
              right: 12,
              child: TextField(key: searchKey),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: ColdStartVpnBanner(show: show),
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets(
      'overlays Home without moving search and hides after four seconds',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 20);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    await tester.pumpWidget(buildSubject(show: true));
    final initialSearchTop = tester.getTopLeft(find.byKey(searchKey)).dy;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text(title), findsOneWidget);
    expect(find.text('Если есть проблемы с загрузкой, отключите VPN'),
        findsOneWidget);

    expect(tester.getTopLeft(find.byKey(searchKey)).dy, initialSearchTop);
    expect(tester.getTopLeft(find.text(title)).dy, greaterThanOrEqualTo(20));
    expect(
      tester.getBottomLeft(find.byType(ColdStartVpnBanner)).dy,
      greaterThan(initialSearchTop),
    );
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 320));

    expect(tester.getTopLeft(find.text(title)).dy, lessThan(0));
    expect(tester.getTopLeft(find.byKey(searchKey)).dy, initialSearchTop);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waits until enabled and only runs once', (tester) async {
    await tester.pumpWidget(buildSubject(show: false));
    await tester.pump(const Duration(seconds: 5));
    expect(tester.getTopLeft(find.text(title)).dy, lessThan(0));

    await tester.pumpWidget(buildSubject(show: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(tester.getTopLeft(find.text(title)).dy, greaterThanOrEqualTo(0));

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpWidget(buildSubject(show: false));
    await tester.pumpWidget(buildSubject(show: true));
    await tester.pump(const Duration(milliseconds: 320));

    expect(tester.getTopLeft(find.text(title)).dy, lessThan(0));
  });
}
