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
}

class _FakeReviewsApi extends ReviewsApi {
  _FakeReviewsApi({
    required List<Map<String, dynamic>> initialItems,
  })  : _items = initialItems
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: true),
        super(
          ApiClient(
            tokenStorage: TokenStorage(),
          ),
        );

  final List<Map<String, dynamic>> _items;

  @override
  Future<Map<String, dynamic>> listSellerReviews(String sellerId) async {
    return <String, dynamic>{
      'items': _items
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
    _items.insert(0, item);
    return <String, dynamic>{'item': item};
  }
}
