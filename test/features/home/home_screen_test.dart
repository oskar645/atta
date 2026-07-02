import 'dart:async';

import 'package:atta/src/features/home/home_screen.dart';
import 'package:atta/src/models/feed_ad.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/models/showcase_item.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/feed_ads_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/showcase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'home feed loads next page near bottom and does not duplicate showcase or listings',
    (tester) async {
      final showcase = _FakeShowcaseService();
      final listings = _FakeListingsService(
        onGetListingsPage: (request) async {
          if (request.cursor == null) {
            return ListingsFeedPage(
              items: List<Listing>.generate(
                20,
                (index) => _listing(
                  id: 'listing-$index',
                  title: index == 19 ? 'Дубль' : 'Товар $index',
                ),
              ),
              hasMore: true,
              nextCursor: 'cursor-1',
            );
          }
          return ListingsFeedPage(
            items: <Listing>[
              _listing(id: 'listing-19', title: 'Дубль'),
              for (var index = 20; index <= 28; index++)
                _listing(id: 'listing-$index', title: 'Товар $index'),
            ],
            hasMore: false,
            nextCursor: null,
          );
        },
      );

      await tester.pumpWidget(
        _buildHomeTestApp(
          listings: listings,
          showcase: showcase,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(listings.requests.length, 1);

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -8000),
        20000,
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(listings.requests.length, 2);
      expect(listings.requests.last.cursor, 'cursor-1');
      expect(showcase.homeShowcaseCalls, 1);
      expect(find.text('Дубль'), findsNothing);
      expect(find.text('Больше объявлений нет'), findsNothing);
    },
  );

  testWidgets(
    'home feed does not start repeated loadMore while page request is in flight',
    (tester) async {
      final secondPageCompleter = Completer<ListingsFeedPage>();
      final listings = _FakeListingsService(
        onGetListingsPage: (request) async {
          if (request.cursor == null) {
            return ListingsFeedPage(
              items: List<Listing>.generate(
                20,
                (index) => _listing(
                  id: 'listing-$index',
                  title: 'Товар $index',
                ),
              ),
              hasMore: true,
              nextCursor: 'cursor-1',
            );
          }
          return secondPageCompleter.future;
        },
      );

      await tester.pumpWidget(_buildHomeTestApp(listings: listings));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -8000),
        20000,
      );
      await tester.pump();
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -1200),
        12000,
      );
      await tester.pump();

      expect(listings.requests.length, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      secondPageCompleter.complete(
        ListingsFeedPage(
          items: <Listing>[
            _listing(id: 'listing-20', title: 'Товар 20'),
          ],
          hasMore: false,
          nextCursor: null,
        ),
      );

      await tester.pumpAndSettle();

      expect(listings.requests.length, 2);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'home feed keeps category and search on loadMore',
    (tester) async {
      final listings = _FakeListingsService(
        onGetListingsPage: (request) async {
          if (request.category == 'Электроника' &&
              request.search == 'ноут' &&
              request.cursor == null) {
            return ListingsFeedPage(
              items: List<Listing>.generate(
                20,
                (index) => _listing(
                  id: 'electronics-$index',
                  title: 'Ноутбук $index',
                  category: 'Электроника',
                ),
              ),
              hasMore: true,
              nextCursor: 'filtered-1',
            );
          }

          if (request.category == 'Электроника' &&
              request.search == 'ноут' &&
              request.cursor == 'filtered-1') {
            return ListingsFeedPage(
              items: List<Listing>.generate(
                5,
                (index) => _listing(
                  id: 'tail-$index',
                  title: 'Хвост $index',
                  category: 'Электроника',
                ),
              ),
              hasMore: false,
              nextCursor: null,
            );
          }

          return ListingsFeedPage(
            items: List<Listing>.generate(
              20,
              (index) => _listing(
                id: 'default-$index',
                title: 'Лента $index',
              ),
            ),
            hasMore: false,
            nextCursor: null,
          );
        },
      );

      await tester.pumpWidget(_buildHomeTestApp(listings: listings));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Электроника'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ноут');
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -8000),
        20000,
      );
      await tester.pump();
      await tester.pumpAndSettle();

      final loadMoreRequest = listings.requests.last;
      expect(loadMoreRequest.category, 'Электроника');
      expect(loadMoreRequest.search, 'ноут');
      expect(loadMoreRequest.cursor, 'filtered-1');
    },
  );

  testWidgets(
    'home feed does not call loadMore when hasMore is false',
    (tester) async {
      final listings = _FakeListingsService(
        onGetListingsPage: (request) async => ListingsFeedPage(
          items: List<Listing>.generate(
            20,
            (index) => _listing(
              id: 'listing-$index',
              title: 'Товар $index',
            ),
          ),
          hasMore: false,
          nextCursor: null,
        ),
      );

      await tester.pumpWidget(_buildHomeTestApp(listings: listings));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -8000),
        20000,
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(listings.requests.length, 1);
      expect(find.text('Больше объявлений нет'), findsNothing);
    },
  );
}

Widget _buildHomeTestApp({
  required _FakeListingsService listings,
  _FakeShowcaseService? showcase,
}) {
  return MultiProvider(
    providers: [
      Provider<AuthService>.value(value: _FakeAuthService()),
      Provider<ListingsService>.value(value: listings),
      Provider<FavoritesService>.value(value: _FakeFavoritesService()),
      Provider<FeedAdsService>.value(value: _FakeFeedAdsService()),
      Provider<ShowcaseService>.value(
          value: showcase ?? _FakeShowcaseService()),
      Provider<ReviewsService>.value(value: _FakeReviewsService()),
      Provider<NotificationsService>.value(value: _FakeNotificationsService()),
      ChangeNotifierProvider<ListingHistoryService>.value(
        value: ListingHistoryService(),
      ),
    ],
    child: const MaterialApp(home: HomeScreen()),
  );
}

class _PageRequest {
  const _PageRequest({
    required this.category,
    required this.search,
    required this.filters,
    required this.limit,
    required this.cursor,
  });

  final String category;
  final String search;
  final ListingFeedFilters? filters;
  final int limit;
  final String? cursor;
}

class _FakeListingsService extends ListingsService {
  _FakeListingsService({
    required this.onGetListingsPage,
  });

  final Future<ListingsFeedPage> Function(_PageRequest request)
      onGetListingsPage;
  final List<_PageRequest> requests = <_PageRequest>[];

  @override
  Future<ListingsFeedPage> getListingsPage({
    required String category,
    required String search,
    ListingFeedFilters? filters,
    int limit = 20,
    String? cursor,
  }) {
    final request = _PageRequest(
      category: category,
      search: search,
      filters: filters,
      limit: limit,
      cursor: cursor,
    );
    requests.add(request);
    return onGetListingsPage(request);
  }
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'user-1');
}

class _FakeFavoritesService extends FavoritesService {
  @override
  Stream<Set<String>> streamFavoriteIds(String uid) {
    return Stream<Set<String>>.value(const <String>{});
  }

  @override
  Future<void> toggleFavorite({
    required String uid,
    required String listingId,
    required bool makeFavorite,
  }) async {}
}

class _FakeFeedAdsService extends FeedAdsService {
  @override
  Stream<FeedAd?> streamActiveAd({String placement = 'home'}) {
    return Stream<FeedAd?>.value(null);
  }
}

class _FakeShowcaseService extends ShowcaseService {
  int homeShowcaseCalls = 0;

  @override
  Future<List<ShowcaseItem>> getHomeShowcase() async {
    homeShowcaseCalls += 1;
    return <ShowcaseItem>[
      ShowcaseItem.fromMap(
        const <String, dynamic>{
          'promotion_id': 'promo-1',
          'listing_id': 'listing-showcase',
          'title': 'Витрина',
          'price': 1500,
          'city': 'Москва',
          'seller_id': 'seller-1',
          'seller_name': 'Seller',
          'category': 'Электроника',
          'impressions_count': 0,
          'clicks_count': 0,
        },
      ),
    ];
  }

  @override
  Future<void> recordImpression(String promotionId) async {}

  @override
  Future<void> recordClick(String promotionId) async {}
}

class _FakeReviewsService extends ReviewsService {
  @override
  Stream<Map<String, dynamic>> streamSellerRating(String sellerId) {
    return Stream<Map<String, dynamic>>.value(
      const <String, dynamic>{'avg': 0.0, 'count': 0},
    );
  }
}

class _FakeNotificationsService extends NotificationsService {
  @override
  Stream<int> streamUnreadBadgeCount(String userId) {
    return Stream<int>.value(0);
  }
}

Listing _listing({
  required String id,
  required String title,
  String category = 'Все',
}) {
  return Listing.fromMap(<String, dynamic>{
    'id': id,
    'owner_id': 'user-1',
    'owner_email': 'user@example.com',
    'owner_name': 'User',
    'title': title,
    'description': 'Описание',
    'category': category,
    'subcategory': 'Телефоны',
    'price': 1000,
    'phone': '+79990000000',
    'phone_hidden': false,
    'city': 'Москва',
    'delivery': const <String, dynamic>{'pickup': true},
    'photo_urls': const <String>[],
    'view_count': 0,
    'status': 'approved',
    'rejection_reason': '',
    'can_promote': false,
    'created_at': '2026-07-01T10:00:00.000Z',
    'published_at': '2026-07-01T10:00:00.000Z',
  });
}
