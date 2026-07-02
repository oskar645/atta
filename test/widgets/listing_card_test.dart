import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/widgets/listing_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
}

class _FakeReviewsService extends ReviewsService {
  @override
  Stream<Map<String, dynamic>> streamSellerRating(String sellerId) {
    return Stream<Map<String, dynamic>>.value(
      const <String, dynamic>{'avg': 0.0, 'count': 0},
    );
  }
}

Listing _listing() {
  return Listing.fromMap(<String, dynamic>{
    'id': 'listing-1',
    'owner_id': 'user-1',
    'owner_email': 'user@example.com',
    'owner_name': 'User',
    'title': 'Велосипед',
    'description': 'Описание',
    'category': 'Транспорт',
    'subcategory': 'Велосипеды',
    'price': 10000,
    'phone': '',
    'phone_hidden': false,
    'city': 'Москва',
    'delivery': <String, dynamic>{},
    'photo_urls': const <String>[],
    'view_count': 0,
    'status': 'approved',
    'rejection_reason': '',
    'can_promote': false,
    'promotions': <String, dynamic>{
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
