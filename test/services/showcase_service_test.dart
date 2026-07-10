import 'package:atta/src/models/showcase_item.dart';
import 'package:atta/src/services/showcase_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('showcase home preparation deduplicates items and keeps latest first',
      () {
    final prepared = ShowcaseService.prepareHomeShowcase(
      <ShowcaseItem>[
        _item(
          promotionId: 'promo-1',
          listingId: 'listing-1',
          startsAt: DateTime(2026, 7, 1),
        ),
        _item(
          promotionId: 'promo-2',
          listingId: 'listing-2',
          startsAt: DateTime(2026, 7, 8),
        ),
        _item(
          promotionId: 'promo-3',
          listingId: 'listing-1',
          startsAt: DateTime(2026, 7, 7),
        ),
        _item(
          promotionId: 'promo-4',
          listingId: 'listing-4',
          startsAt: DateTime(2026, 7, 6),
        ),
      ],
      homeLoadCount: 0,
      rotationOffset: 0,
    );

    expect(
      prepared.items.map((item) => item.listingId).toList(),
      <String>['listing-2', 'listing-4', 'listing-1'],
    );
  });

  test('showcase home preparation rotates non-priority tail on refresh', () {
    final items = <ShowcaseItem>[
      _item(
        promotionId: 'promo-1',
        listingId: 'listing-1',
        startsAt: DateTime(2026, 7, 8),
      ),
      _item(
        promotionId: 'promo-2',
        listingId: 'listing-2',
        startsAt: DateTime(2026, 7, 7),
      ),
      _item(
        promotionId: 'promo-3',
        listingId: 'listing-3',
        startsAt: DateTime(2026, 7, 6),
      ),
      _item(
        promotionId: 'promo-4',
        listingId: 'listing-4',
        startsAt: DateTime(2026, 7, 5),
      ),
    ];

    final first = ShowcaseService.prepareHomeShowcase(
      items,
      homeLoadCount: 0,
      rotationOffset: 0,
    );
    final second = ShowcaseService.prepareHomeShowcase(
      items,
      homeLoadCount: 1,
      rotationOffset: first.nextRotationOffset,
    );

    expect(
      first.items.take(2).map((item) => item.listingId).toList(),
      <String>['listing-1', 'listing-2'],
    );
    expect(
      second.items.take(2).map((item) => item.listingId).toList(),
      <String>['listing-1', 'listing-2'],
    );
    expect(
      first.items.skip(2).map((item) => item.listingId).toList(),
      isNot(
          equals(second.items.skip(2).map((item) => item.listingId).toList())),
    );
  });
}

ShowcaseItem _item({
  required String promotionId,
  required String listingId,
  required DateTime startsAt,
}) {
  return ShowcaseItem.fromMap(<String, dynamic>{
    'promotion_id': promotionId,
    'listing_id': listingId,
    'title': listingId,
    'price': 1000,
    'city': 'Москва',
    'seller_id': 'seller-1',
    'seller_name': 'Seller',
    'category': 'Электроника',
    'starts_at': startsAt.toIso8601String(),
    'impressions_count': 0,
    'clicks_count': 0,
  });
}
