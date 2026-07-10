import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/reviews_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('addReview updates Timeweb cache with returned item', () async {
    final api = _FakeReviewsApi(
      initialItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'review-1',
          'seller_id': 'seller-1',
          'reviewer_id': 'buyer-1',
          'reviewer_name': 'First buyer',
          'rating': 5,
          'comment': 'Great',
          'created_at': '2026-06-18T10:00:00.000Z',
        },
      ],
    );
    final service = ReviewsService(api: api);

    await service.refreshSellerReviews('seller-1');
    expect(service.peekSellerReviews('seller-1').length, 1);

    await service.addReview(
      sellerId: 'seller-1',
      reviewerId: 'buyer-2',
      reviewerName: 'Second buyer',
      listingId: 'listing-1',
      rating: 4,
      text: 'Fast deal',
    );

    final cached = service.peekSellerReviews('seller-1');
    expect(cached.length, 2);
    expect(cached.first['id'], 'review-2');
    expect(cached.first['reviewer_name'], 'Second buyer');
    expect(
      (cached.first['author_preview'] as Map<String, dynamic>)['avatar_url'],
      'https://cdn.example.com/second.jpg',
    );
  });

  test('late streamSellerReviews subscribers receive cached snapshot',
      () async {
    final api = _FakeReviewsApi(
      initialItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'review-1',
          'seller_id': 'seller-1',
          'reviewer_id': 'buyer-1',
          'reviewer_name': 'First buyer',
          'rating': 5,
          'comment': 'Great',
          'created_at': '2026-06-18T10:00:00.000Z',
        },
      ],
    );
    final service = ReviewsService(api: api);

    final firstItemsFuture = service.streamSellerReviews('seller-1').first;
    final firstItems = await firstItemsFuture;
    expect(firstItems, isEmpty);

    await service.refreshSellerReviews('seller-1');
    final lateItems = await service.streamSellerReviews('seller-1').first;

    expect(lateItems.length, 1);
    expect(lateItems.first['id'], 'review-1');
    expect(api.listCalls, 1);
  });

  test('reviews cache stays isolated by sellerId', () async {
    final api = _FakeReviewsApi(
      initialItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'review-1',
          'seller_id': 'seller-1',
          'reviewer_id': 'buyer-1',
          'reviewer_name': 'First buyer',
          'rating': 5,
          'comment': 'Great',
          'created_at': '2026-06-18T10:00:00.000Z',
        },
      ],
    );
    final service = ReviewsService(api: api);

    await service.refreshSellerReviews('seller-1');
    api.itemsBySeller['seller-2'] = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'review-2',
        'seller_id': 'seller-2',
        'reviewer_id': 'buyer-2',
        'reviewer_name': 'Second buyer',
        'rating': 4,
        'comment': 'Nice',
        'created_at': '2026-06-18T11:00:00.000Z',
      },
    ];
    await service.refreshSellerReviews('seller-2');

    expect(
      service.peekSellerReviews('seller-1').map((row) => row['id']).toList(),
      <String>['review-1'],
    );
    expect(
      service.peekSellerReviews('seller-2').map((row) => row['id']).toList(),
      <String>['review-2'],
    );
  });

  test('resetSession clears cached reviews between auth sessions', () async {
    final api = _FakeReviewsApi(
      initialItems: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'review-1',
          'seller_id': 'seller-1',
          'reviewer_id': 'buyer-1',
          'reviewer_name': 'First buyer',
          'rating': 5,
          'comment': 'Great',
          'created_at': '2026-06-18T10:00:00.000Z',
        },
      ],
    );
    final service = ReviewsService(api: api);

    await service.refreshSellerReviews('seller-1');
    service.resetSession();

    expect(service.peekSellerReviews('seller-1'), isEmpty);
    expect(await service.streamSellerReviews('seller-1').first, isEmpty);
  });
}

class _FakeReviewsApi extends ReviewsApi {
  _FakeReviewsApi({
    required List<Map<String, dynamic>> initialItems,
  })  : itemsBySeller = <String, List<Map<String, dynamic>>>{
          if (initialItems.isNotEmpty)
            (initialItems.first['seller_id'] ?? '').toString(): initialItems
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: true),
        },
        super(
          ApiClient(
            tokenStorage: TokenStorage(),
          ),
        );

  final Map<String, List<Map<String, dynamic>>> itemsBySeller;
  int listCalls = 0;

  @override
  Future<Map<String, dynamic>> listSellerReviews(String sellerId) async {
    listCalls += 1;
    final items = itemsBySeller[sellerId] ?? const <Map<String, dynamic>>[];
    return <String, dynamic>{
      'items': items
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
    };
  }

  @override
  Future<Map<String, dynamic>> addReview({
    required String sellerId,
    required String listingId,
    required int rating,
    required String text,
    String? reviewerName,
  }) async {
    final item = <String, dynamic>{
      'id': 'review-2',
      'seller_id': sellerId,
      'reviewer_id': 'buyer-2',
      'reviewer_name': reviewerName,
      'listing_id': listingId,
      'rating': rating,
      'comment': text,
      'created_at': '2026-06-18T11:00:00.000Z',
      'author_preview': <String, dynamic>{
        'id': 'buyer-2',
        'name': reviewerName,
        'avatar_url': 'https://cdn.example.com/second.jpg',
      },
    };
    itemsBySeller.putIfAbsent(sellerId, () => <Map<String, dynamic>>[]).insert(
          0,
          item,
        );
    return <String, dynamic>{'item': item};
  }
}
