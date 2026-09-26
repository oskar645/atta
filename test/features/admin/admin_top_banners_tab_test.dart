import 'dart:convert';
import 'dart:typed_data';

import 'package:atta/src/features/admin/admin_top_banners_tab.dart';
import 'package:atta/src/models/top_banner.dart';
import 'package:atta/src/services/top_banners_service.dart';
import 'package:atta/src/utils/media_url.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('create and edit reload outside setState without an exception',
      (tester) async {
    final service = _FakeTopBannersService();
    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(service.listCalls, 2);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(service.listCalls, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved relative image uses resolved remote media preview',
      (tester) async {
    final service = _FakeTopBannersService();
    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();

    final preview =
        tester.widget<MediaPreviewBox>(find.byType(MediaPreviewBox));
    expect(preview.imageUrl, _relativeImageUrl);
    expect(
      resolvePublicMediaUrl(preview.imageUrl,
          categoryHint: preview.categoryHint),
      'https://attamarket.online$_relativeImageUrl',
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is FileImage,
      ),
      findsNothing,
    );

    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();
    expect(find.byType(MediaPreviewBox), findsNWidgets(2));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is FileImage,
      ),
      findsNothing,
    );
  });

  testWidgets('picked image uses an in-memory preview before upload',
      (tester) async {
    final service = _FakeTopBannersService();
    final bytes = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ));
    await tester.pumpWidget(_host(
      service,
      pickImage: () async => XFile.fromData(
        bytes,
        name: 'banner.png',
        mimeType: 'image/png',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать изображение'));
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor preview mirrors the Home safe-area overlays',
      (tester) async {
    final service = _FakeTopBannersService();
    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();

    expect(find.text('ATTA'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/branding/atta_logo.png',
      ),
      findsOneWidget,
    );
    expect(find.text('9:41'), findsOneWidget);
    expect(find.text('LTE'), findsOneWidget);
    expect(find.byIcon(Icons.wifi), findsOneWidget);
    expect(find.byIcon(Icons.battery_full), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);
    expect(
      find.text(
        '1170 × 240 px · Важный текст и логотипы размещайте в свободной центральной зоне. Не размещайте их под логотипом AT, камерой/Dynamic Island, статус-баром, колокольчиком и кнопкой +.',
      ),
      findsOneWidget,
    );
  });
}

const _relativeImageUrl = '/media/object?category=feed-ads&key=banner.jpg';

Widget _host(
  TopBannersService service, {
  Future<XFile?> Function()? pickImage,
}) {
  return Provider<TopBannersService>.value(
    value: service,
    child: MaterialApp(
      home: Scaffold(
        body: AdminTopBannersTab(pickImage: pickImage),
      ),
    ),
  );
}

class _FakeTopBannersService extends TopBannersService {
  int listCalls = 0;
  var items = <TopBanner>[_banner()];

  @override
  Future<List<TopBanner>> list() async {
    listCalls += 1;
    return items;
  }

  @override
  Future<TopBanner> save({
    TopBanner? existing,
    required String title,
    required String url,
    required DateTime start,
    required DateTime end,
    required int order,
  }) async {
    final saved = _banner(id: existing?.id ?? 'created');
    items = <TopBanner>[saved];
    return saved;
  }
}

TopBanner _banner({String id = 'banner-1'}) => TopBanner(
      id: id,
      title: 'Top banner',
      imageUrl: _relativeImageUrl,
      targetUrl: '',
      enabled: false,
      startAt: DateTime.utc(2026, 9, 26),
      endAt: DateTime.utc(2026, 10, 3),
      sortOrder: 0,
      status: 'paused',
      impressions: 0,
      clicks: 0,
    );
