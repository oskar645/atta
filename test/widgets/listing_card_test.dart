import 'dart:typed_data';

import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:atta/src/widgets/listing_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('viewed badge is visible and readable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 320,
            child: ListingCard(
              listing: _listing(),
              isFav: false,
              isSeen: true,
              reviews: _FakeReviewsService(),
              onToggleFav: (_) {},
              onOpen: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('listing_seen_badge')), findsOneWidget);
    expect(find.text('Просмотрено'), findsOneWidget);

    final badgePositioned = tester.widget<Positioned>(
      find.ancestor(
        of: find.byKey(const ValueKey('listing_seen_badge')),
        matching: find.byType(Positioned),
      ),
    );
    expect(badgePositioned.right, 8);
    expect(badgePositioned.left, isNull);

    final badgeContainer = tester.widget<Container>(
      find.byKey(const ValueKey('listing_seen_badge_container')),
    );
    expect(
      badgeContainer.padding,
      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    );

    final badgeText = tester.widget<Text>(
      find.byKey(const ValueKey('listing_seen_badge')),
    );
    expect(badgeText.style?.fontSize, 9);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('listing_seen_badge_container')))
            .height,
        lessThan(24));
  });

  testWidgets('seller rating stays visible when seller has no reviews',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 320,
            child: ListingCard(
              listing: _listing(),
              isFav: false,
              isSeen: false,
              reviews: _FakeReviewsService(),
              onToggleFav: (_) {},
              onOpen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Рейтинг продавца'), findsNothing);
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.text('0.0'), findsOneWidget);
    expect(find.text('(0)'), findsOneWidget);
  });

  testWidgets('seller rating shows star value and review count without label',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 320,
            child: ListingCard(
              listing: _listing(),
              isFav: false,
              isSeen: false,
              reviews: _RatedFakeReviewsService(),
              onToggleFav: (_) {},
              onOpen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Рейтинг продавца'), findsNothing);
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.text('4.7'), findsOneWidget);
    expect(find.text('(3)'), findsOneWidget);
  });

  testWidgets('VIP card fits long content with enlarged system text',
      (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 160,
              height: 222,
              child: ListingCard(
                listing: _listing(
                  title:
                      'Очень длинное название объявления для маленького экрана',
                  city: 'Санкт-Петербург, Петроградский район',
                  price: 999999999,
                  vip: true,
                ),
                isFav: false,
                isSeen: false,
                reviews: _RatedFakeReviewsService(),
                onToggleFav: (_) {},
                onOpen: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('VIP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('city and VIP bottom row stays inside compact and wide cards',
      (tester) async {
    for (final width in [160.0, 180.0, 195.0, 215.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: width * 1.3875,
              child: ListingCard(
                listing: _listing(city: 'Гудермес', vip: true),
                isFav: false,
                isSeen: false,
                reviews: _FakeReviewsService(),
                onToggleFav: (_) {},
                onOpen: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final cardRect = tester.getRect(find.byType(ListingCard));
      expect(tester.getRect(find.text('Гудермес')).bottom,
          lessThan(cardRect.bottom));
      expect(
          tester.getRect(find.text('VIP')).bottom, lessThan(cardRect.bottom));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('ordinary card fits the compact grid proportion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 160,
            height: 222,
            child: ListingCard(
              listing: _listing(
                title: 'Длинное название обычного объявления для проверки',
                city: 'Нижний Новгород, Автозаводский район',
                price: 999999999,
              ),
              isFav: false,
              isSeen: false,
              reviews: _RatedFakeReviewsService(),
              onToggleFav: (_) {},
              onOpen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  for (final scenario in <({String name, int width, int height})>[
    (name: 'horizontal photo', width: 1200, height: 800),
    (name: 'vertical photo', width: 800, height: 1200),
    (name: 'square photo', width: 1000, height: 1000),
    (name: 'very wide photo', width: 2400, height: 600),
  ]) {
    testWidgets('listing photo frame is stable for ${scenario.name}',
        (tester) async {
      const frameSize = Size(220, 165);
      const previewKey = ValueKey('listing_photo_preview');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 220,
              height: 165,
              child: MediaPreviewBox(
                key: previewKey,
                imageUrl: '',
                categoryHint: 'listings',
                borderRadius: 0,
              ),
            ),
          ),
        ),
      );

      final placeholderRect = tester.getRect(find.byKey(previewKey));
      expect(placeholderRect.size, frameSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: frameSize.width,
              height: frameSize.height,
              child: MediaPreviewBox(
                key: previewKey,
                imageUrl: 'https://example.com/${scenario.name}.png',
                categoryHint: 'listings',
                borderRadius: 0,
                debugImageProvider: MemoryImage(
                  _solidImageBytes(scenario.width, scenario.height),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final loadedRect = tester.getRect(find.byKey(previewKey));
      final image = tester.widget<Image>(find.byType(Image));

      expect(loadedRect.size, frameSize);
      expect(loadedRect, placeholderRect);
      expect(tester.getRect(find.byType(Image)).size, frameSize);
      expect(image.fit, BoxFit.cover);
      expect(tester.takeException(), isNull);
    });
  }
}

Uint8List _solidImageBytes(int width, int height) {
  final source = img.Image(width: width, height: height);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      source.setPixelRgb(x, y, 40, 120, 200);
    }
  }
  return Uint8List.fromList(img.encodePng(source));
}

class _FakeReviewsService extends ReviewsService {
  @override
  Stream<Map<String, dynamic>> streamSellerRating(String sellerId) {
    return Stream<Map<String, dynamic>>.value(
      const <String, dynamic>{'avg': 0.0, 'count': 0},
    );
  }
}

class _RatedFakeReviewsService extends ReviewsService {
  @override
  Stream<Map<String, dynamic>> streamSellerRating(String sellerId) {
    return Stream<Map<String, dynamic>>.value(
      const <String, dynamic>{'avg': 4.7, 'count': 3},
    );
  }
}

Listing _listing({
  String title = 'Велосипед',
  String city = 'Москва',
  int price = 10000,
  bool vip = false,
}) {
  return Listing.fromMap(<String, dynamic>{
    'id': 'listing-1',
    'owner_id': 'user-1',
    'owner_email': 'user@example.com',
    'owner_name': 'User',
    'title': title,
    'description': 'Описание',
    'category': 'Транспорт',
    'subcategory': 'Велосипеды',
    'price': price,
    'phone': '',
    'phone_hidden': false,
    'city': city,
    'delivery': <String, dynamic>{},
    'photo_urls': const <String>[],
    'view_count': 0,
    'status': 'approved',
    'rejection_reason': '',
    'can_promote': false,
    'promotions': <String, dynamic>{
      if (vip)
        'activeVip': <String, dynamic>{
          'id': 'promo-vip',
          'type': 'vip',
          'title': 'VIP',
          'status': 'active',
        },
      'activeBump': <String, dynamic>{
        'id': 'promo-1',
        'type': 'bump',
        'title': 'Поднятие',
        'status': 'active',
      },
    },
    'created_at': '2026-06-20T10:00:00.000Z',
  });
}
