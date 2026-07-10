import 'dart:async';

import 'package:atta/src/features/favorites/favorites_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/saved_search_service.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('favorites first load skeleton', (tester) async {
    await tester.pumpWidget(_wrapFavorites());

    expect(find.byType(SkeletonAdminModerationCard), findsWidgets);
    await tester.pumpAndSettle();
  });

  testWidgets('favorites load error clears skeleton and shows error state',
      (tester) async {
    await tester.pumpWidget(
      _wrapFavorites(
        favoritesService: _FailingFavoritesService(),
        listingsService: _CachedListingsService.empty(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 13));
    await tester.pumpAndSettle();

    expect(find.byType(SkeletonAdminModerationCard), findsNothing);
    expect(find.text('Не удалось загрузить избранное.'), findsOneWidget);
  });

  testWidgets('removing favorite updates list locally without full reload',
      (tester) async {
    final favorites = _InteractiveFavoritesService();
    final listings = _CachedListingsService();

    await tester.pumpWidget(
      _wrapFavorites(
        favoritesService: favorites,
        listingsService: listings,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Тестовое объявление'), findsOneWidget);
    expect(listings.getListingByIdCalls, 0);

    await tester.tap(find.byIcon(Icons.favorite).first);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Пока нет избранных объявлений'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(SkeletonAdminModerationCard), findsNothing);
    expect(listings.getListingByIdCalls, 0);
  });

  testWidgets(
      'favorites cold start does not launch duplicate missing listing loads',
      (tester) async {
    final listings = _CountingDelayedListingsService();

    await tester.pumpWidget(
      _wrapFavorites(
        favoritesService: _FakeFavoritesService(),
        listingsService: listings,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Тестовое объявление'), findsOneWidget);
    expect(listings.getListingByIdCalls, 1);
  });

  testWidgets('favorites first open starts one backend load', (tester) async {
    final favorites = _CountingFavoritesService();
    final listings = _CachedListingsService();

    await tester.pumpWidget(
      _wrapFavorites(
        favoritesService: favorites,
        listingsService: listings,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(favorites.refreshCalls, 1);
    expect(find.byType(SkeletonAdminModerationCard), findsNothing);
    expect(find.text('Не удалось загрузить избранное.'), findsNothing);
  });
}

Widget _wrapFavorites({
  FavoritesService? favoritesService,
  ListingsService? listingsService,
}) {
  return MultiProvider(
    providers: [
      Provider<AuthService>.value(value: _FakeAuthService()),
      Provider<FavoritesService>.value(
        value: favoritesService ?? _FakeFavoritesService(),
      ),
      Provider<FollowService>.value(value: _FakeFollowService()),
      Provider<ListingsService>.value(
        value: listingsService ?? _DelayedListingsService(),
      ),
      Provider<NotificationsService>.value(value: _FakeNotificationsService()),
      Provider<SavedSearchService>.value(value: _FakeSavedSearchService()),
      ChangeNotifierProvider<ListingHistoryService>.value(
        value: ListingHistoryService(),
      ),
      Provider<ReviewsService>.value(value: _FakeReviewsService()),
    ],
    child: const MaterialApp(home: FavoritesScreen()),
  );
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'user-1');
}

class _FakeFavoritesService extends FavoritesService {
  final Set<String> _ids = <String>{'listing-1'};

  @override
  Set<String> peekFavoriteIds(String uid) => Set<String>.from(_ids);

  @override
  Future<Set<String>> getFavoriteIds(String uid) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return Set<String>.from(_ids);
  }

  @override
  Future<Set<String>> refreshFavoriteIds(String uid) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return Set<String>.from(_ids);
  }

  @override
  Stream<Set<String>> streamCachedFavoriteIds(String uid) {
    return Stream<Set<String>>.value(Set<String>.from(_ids));
  }

  @override
  Stream<Set<String>> streamFavoriteIds(String uid) async* {
    yield Set<String>.from(_ids);
  }
}

class _FailingFavoritesService extends FavoritesService {
  @override
  Set<String> peekFavoriteIds(String uid) => const <String>{};

  @override
  Future<Set<String>> getFavoriteIds(String uid) async {
    throw Exception('favorites failed');
  }

  @override
  Future<Set<String>> refreshFavoriteIds(String uid) async {
    throw Exception('favorites failed');
  }

  @override
  Stream<Set<String>> streamCachedFavoriteIds(String uid) {
    return Stream<Set<String>>.value(const <String>{});
  }

  @override
  Stream<Set<String>> streamFavoriteIds(String uid) async* {
    yield const <String>{};
  }
}

class _InteractiveFavoritesService extends FavoritesService {
  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();
  final Set<String> _ids = <String>{'listing-1'};

  @override
  Set<String> peekFavoriteIds(String uid) => Set<String>.from(_ids);

  @override
  Future<Set<String>> getFavoriteIds(String uid) async {
    return Set<String>.from(_ids);
  }

  @override
  Future<Set<String>> refreshFavoriteIds(String uid) async {
    return Set<String>.from(_ids);
  }

  @override
  Stream<Set<String>> streamCachedFavoriteIds(String uid) {
    return Stream<Set<String>>.multi(
      (controller) {
        controller.add(Set<String>.from(_ids));
        final sub = _controller.stream.listen(controller.add);
        controller.onCancel = () async {
          await sub.cancel();
        };
      },
      isBroadcast: true,
    );
  }

  @override
  Stream<Set<String>> streamFavoriteIds(String uid) async* {
    yield Set<String>.from(_ids);
    yield* _controller.stream;
  }

  @override
  bool isFavorite(String uid, String listingId) => _ids.contains(listingId);

  @override
  Stream<bool> streamIsFavorite(String uid, String listingId) async* {
    yield isFavorite(uid, listingId);
    yield* _controller.stream.map((ids) => ids.contains(listingId));
  }

  @override
  Future<void> toggleFavorite({
    required String uid,
    required String listingId,
    required bool makeFavorite,
  }) async {
    if (makeFavorite) {
      _ids.add(listingId);
    } else {
      _ids.remove(listingId);
    }
    _controller.add(Set<String>.from(_ids));
  }
}

class _CountingFavoritesService extends FavoritesService {
  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();
  final Set<String> _ids = <String>{'listing-1'};
  int refreshCalls = 0;

  @override
  Set<String> peekFavoriteIds(String uid) => const <String>{};

  @override
  Stream<Set<String>> streamCachedFavoriteIds(String uid) {
    return Stream<Set<String>>.multi(
      (controller) {
        controller.add(const <String>{});
        final sub = _controller.stream.listen(controller.add);
        controller.onCancel = () async {
          await sub.cancel();
        };
      },
      isBroadcast: true,
    );
  }

  @override
  Future<Set<String>> refreshFavoriteIds(String uid) async {
    refreshCalls += 1;
    _controller.add(Set<String>.from(_ids));
    return Set<String>.from(_ids);
  }

  @override
  Future<Set<String>> forceRefreshFavoriteIds(String uid) async {
    refreshCalls += 1;
    _controller.add(Set<String>.from(_ids));
    return Set<String>.from(_ids);
  }
}

class _FakeFollowService extends FollowService {
  final Completer<List<FollowedSeller>> _loadCompleter =
      Completer<List<FollowedSeller>>();

  @override
  List<FollowedSeller> peekFollowedSellers(String followerId) {
    return const <FollowedSeller>[];
  }

  @override
  Future<List<FollowedSeller>> getFollowedSellers(String followerId) async {
    return _loadCompleter.future;
  }

  @override
  Future<List<FollowedSeller>> refreshFollowedSellers(String followerId) async {
    return _loadCompleter.future;
  }
}

class _DelayedListingsService extends ListingsService {
  @override
  List<Listing> peekListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) {
    return const <Listing>[];
  }

  @override
  Future<List<Listing>> getListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return const <Listing>[];
  }

  @override
  Future<Listing?> getListingById(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return _listingFixture();
  }
}

class _CountingDelayedListingsService extends ListingsService {
  int getListingByIdCalls = 0;

  @override
  List<Listing> peekListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) {
    return const <Listing>[];
  }

  @override
  Future<List<Listing>> getListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return const <Listing>[];
  }

  @override
  Future<Listing?> getListingById(String id) async {
    getListingByIdCalls += 1;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return _listingFixture();
  }
}

class _CachedListingsService extends ListingsService {
  _CachedListingsService({List<Listing>? initialItems})
      : initialItems = initialItems ?? <Listing>[_listingFixture()];

  _CachedListingsService.empty() : initialItems = const <Listing>[];

  final List<Listing> initialItems;
  int getListingByIdCalls = 0;

  @override
  List<Listing> peekListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) {
    return List<Listing>.from(initialItems);
  }

  @override
  Future<List<Listing>> getListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) async {
    return List<Listing>.from(initialItems);
  }

  @override
  Future<Listing?> getListingById(String id) async {
    getListingByIdCalls += 1;
    return initialItems.isEmpty ? null : initialItems.first;
  }
}

class _FakeNotificationsService extends NotificationsService {
  @override
  Stream<int> streamUnreadSavedSearchCount(String userId) {
    return Stream<int>.value(0);
  }
}

class _FakeSavedSearchService extends SavedSearchService {
  final Completer<List<SavedSearch>> _loadCompleter =
      Completer<List<SavedSearch>>();

  @override
  List<SavedSearch> peekSavedSearches(String userId) => const <SavedSearch>[];

  @override
  Future<List<SavedSearch>> getSavedSearches(String userId) async {
    return _loadCompleter.future;
  }

  @override
  Future<List<SavedSearch>> refreshSavedSearches(String userId) async {
    return _loadCompleter.future;
  }
}

class _FakeReviewsService extends ReviewsService {}

Listing _listingFixture() {
  return Listing.fromMap(<String, dynamic>{
    'id': 'listing-1',
    'owner_id': 'seller-1',
    'owner_email': 'seller@example.com',
    'owner_name': 'Seller',
    'title': 'Тестовое объявление',
    'description': 'Описание',
    'category': 'Авто',
    'subcategory': 'Седан',
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
