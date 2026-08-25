import 'dart:async';

import 'package:atta/src/features/favorites/favorites_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/main_shell_controller.dart';
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

  testWidgets('approved favorite opens as before', (tester) async {
    await tester.pumpWidget(
      _wrapFavorites(
        listingsService: _CachedListingsService(
          initialItems: <Listing>[_listingFixture(status: 'approved')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = _favoriteTile(tester, 'Тестовое объявление');

    expect(tile.onTap, isNotNull);
    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets('pending moderation favorite is not grayscale', (tester) async {
    await tester.pumpWidget(
      _wrapFavorites(
        listingsService: _CachedListingsService(
          initialItems: <Listing>[_listingFixture(status: 'pending')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Тестовое объявление'), findsOneWidget);
    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets('pending then approved favorite keeps opening', (tester) async {
    final listings = _MutableCachedListingsService(
      _listingFixture(status: 'pending'),
    );

    await tester.pumpWidget(
      _wrapFavorites(
        listingsService: listings,
      ),
    );
    await tester.pumpAndSettle();

    expect(_favoriteTile(tester, 'Тестовое объявление').onTap, isNotNull);

    listings.item = _listingFixture(status: 'approved');
    await tester.pumpWidget(
      _wrapFavorites(
        listingsService: listings,
      ),
    );
    await tester.pumpAndSettle();

    expect(_favoriteTile(tester, 'Тестовое объявление').onTap, isNotNull);
    expect(find.byType(ColorFiltered), findsNothing);
  });

  for (final status in <String>['sold', 'archived', 'deleted']) {
    testWidgets('$status favorite is grayscale and does not open',
        (tester) async {
      await tester.pumpWidget(
        _wrapFavorites(
          listingsService: _CachedListingsService(
            initialItems: <Listing>[_listingFixture(status: status)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Тестовое объявление'), findsOneWidget);
      expect(find.byType(ColorFiltered), findsOneWidget);

      expect(_favoriteTile(tester, 'Тестовое объявление').onTap, isNull);
    });
  }

  testWidgets('unavailable favorite can still be removed', (tester) async {
    final favorites = _InteractiveFavoritesService();

    await tester.pumpWidget(
      _wrapFavorites(
        favoritesService: favorites,
        listingsService: _CachedListingsService(
          initialItems: <Listing>[_listingFixture(status: 'sold')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ColorFiltered), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite).first);
    await tester.pumpAndSettle();

    expect(find.text('Пока нет избранных объявлений'), findsOneWidget);
  });

  testWidgets('available favorites keep ordinary card visuals', (tester) async {
    await tester.pumpWidget(
      _wrapFavorites(
        listingsService: _CachedListingsService(
          initialItems: <Listing>[
            _listingFixture(id: 'listing-1', title: 'Активное 1'),
            _listingFixture(id: 'listing-2', title: 'Активное 2'),
          ],
        ),
        favoritesService: _StaticFavoritesService(
          ids: <String>{'listing-1', 'listing-2'},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Активное 1'), findsOneWidget);
    expect(find.text('Активное 2'), findsOneWidget);
    expect(find.byType(ColorFiltered), findsNothing);
    expect(find.byIcon(Icons.favorite), findsNWidgets(2));
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

  testWidgets('embedded favorite listing skips getListingById', (tester) async {
    final listings = _CountingDelayedListingsService();

    await tester.pumpWidget(
      _wrapFavorites(
        favoritesService: _EmbeddedFavoritesService(
          items: <Listing>[_listingFixture(title: 'Embedded favorite')],
        ),
        listingsService: listings,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Embedded favorite'), findsOneWidget);
    expect(listings.getListingByIdCalls, 0);
  });

  testWidgets('33 embedded favorites do not start 33 listing requests',
      (tester) async {
    final listings = _CountingDelayedListingsService();

    await tester.pumpWidget(
      _wrapFavorites(
        favoritesService: _EmbeddedFavoritesService(
          items: List<Listing>.generate(
            33,
            (index) => _listingFixture(
              id: 'listing-$index',
              title: 'Embedded $index',
            ),
          ),
        ),
        listingsService: listings,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Embedded 0'), findsOneWidget);
    expect(listings.getListingByIdCalls, 0);
  });

  testWidgets('missing embedded listing keeps old getListingById fallback',
      (tester) async {
    final listings = _CountingDelayedListingsService();

    await tester.pumpWidget(
      _wrapFavorites(
        favoritesService: _EmbeddedFavoritesService(
          idsWithoutListings: const <String>['listing-1'],
        ),
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

  testWidgets('multiple VPN events trigger one refresh', (tester) async {
    final favorites = _CountingFavoritesService();

    await tester.pumpWidget(
      _wrapFavorites(
        favoritesService: favorites,
        listingsService: _CachedListingsService(),
        shellController: MainShellController(initialIndex: 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(favorites.refreshCalls, 1);

    final dynamic state = tester.state(
      find.byWidgetPredicate(
        (widget) =>
            widget.runtimeType.toString() == '_TimewebFavoriteListingsTab',
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 6));
    });
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(favorites.refreshCalls, 2);
  });

  testWidgets('6 IDs / 5 resolved listings do not start another refresh',
      (tester) async {
    final favorites = _RepeatingFavoritesService(
      initialIds: <String>{
        'listing-1',
        'listing-2',
        'listing-3',
        'listing-4',
        'listing-5',
        'listing-6',
      },
    );
    final listings = _MissingOneListingsService();

    await tester.pumpWidget(
      _wrapFavorites(
        favoritesService: favorites,
        listingsService: listings,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(favorites.refreshCalls, 1);
    expect(listings.getListingByIdCalls, 1);
    expect(find.text('Объявление 1'), findsOneWidget);
    expect(find.text('Объявление 5'), findsOneWidget);
    expect(find.text('Объявление 6'), findsNothing);
  });

  testWidgets('hidden Favorites screen ignores connectivity refresh',
      (tester) async {
    final favorites = _CountingFavoritesService();

    await tester.pumpWidget(
      _wrapFavorites(
        favoritesService: favorites,
        listingsService: _CachedListingsService(),
        shellController: MainShellController(initialIndex: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(favorites.refreshCalls, 1);

    final dynamic state = tester.state(
      find.byWidgetPredicate(
        (widget) =>
            widget.runtimeType.toString() == '_TimewebFavoriteListingsTab',
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 6));
    });
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(favorites.refreshCalls, 1);
  });

  testWidgets('cached data remains visible', (tester) async {
    await tester.pumpWidget(
      _wrapFavorites(
        favoritesService: _CachedFavoritesService(),
        listingsService: _CachedListingsService(),
      ),
    );

    expect(find.text('Тестовое объявление'), findsOneWidget);
    expect(find.byType(SkeletonAdminModerationCard), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('dispose cancels subscriptions', (tester) async {
    final favorites = _SubscriptionTrackingFavoritesService();

    await tester.pumpWidget(
      _wrapFavorites(
        favoritesService: favorites,
        listingsService: _CachedListingsService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(favorites.activeListeners, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    expect(favorites.activeListeners, 0);
  });

  testWidgets('favorites listings load more is incremental and stops',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 520));
    final favorites = _PagedFavoritesService();

    await tester.pumpWidget(
      _wrapFavorites(
        favoritesService: favorites,
        listingsService: _ByIdListingsService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(favorites.requests, <String?>[null]);
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(favorites.requests, <String?>[null, 'f2']);
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(favorites.requests, <String?>[null, 'f2', 'f3']);
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(favorites.requests, <String?>[null, 'f2', 'f3']);
  });

  testWidgets('viewed listings load more is incremental and stops',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 520));
    final history = _PagedHistoryService();

    await tester.pumpWidget(
      _wrapFavorites(
        historyService: history,
        listingsService: _ByIdListingsService(),
      ),
    );
    await tester.tap(find.text('Просмотренные'));
    await tester.pumpAndSettle();

    expect(history.requests, <String?>[null]);
    await tester.drag(find.byType(GridView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(history.requests, <String?>[null, 'v2']);
    await tester.drag(find.byType(GridView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(history.requests, <String?>[null, 'v2', 'v3']);

    await tester.drag(find.byType(GridView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(history.requests, <String?>[null, 'v2', 'v3']);
  });

  testWidgets('following load more is incremental and stops', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 520));
    final follows = _PagedFollowService();

    await tester.pumpWidget(
      _wrapFavorites(
        followService: follows,
        listingsService: _FollowListingsService(),
      ),
    );
    await tester.tap(find.text('Подписки'));
    await tester.pumpAndSettle();

    expect(follows.requests, <String?>[null]);
    await tester.drag(find.byType(GridView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(follows.requests, <String?>[null, 's2']);
    await tester.drag(find.byType(GridView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(follows.requests, <String?>[null, 's2', 's3']);
    await tester.drag(find.byType(GridView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(follows.requests, <String?>[null, 's2', 's3']);
  });
}

Widget _wrapFavorites({
  FavoritesService? favoritesService,
  FollowService? followService,
  ListingHistoryService? historyService,
  ListingsService? listingsService,
  MainShellController? shellController,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MainShellController>.value(
        value: shellController ?? MainShellController(initialIndex: 1),
      ),
      Provider<AuthService>.value(value: _FakeAuthService()),
      Provider<FavoritesService>.value(
        value: favoritesService ?? _FakeFavoritesService(),
      ),
      Provider<FollowService>.value(
          value: followService ?? _FakeFollowService()),
      Provider<ListingsService>.value(
        value: listingsService ?? _DelayedListingsService(),
      ),
      Provider<NotificationsService>.value(value: _FakeNotificationsService()),
      Provider<SavedSearchService>.value(value: _FakeSavedSearchService()),
      ChangeNotifierProvider<ListingHistoryService>.value(
        value: historyService ?? ListingHistoryService(),
      ),
      Provider<ReviewsService>.value(value: _FakeReviewsService()),
    ],
    child: const MaterialApp(home: FavoritesScreen()),
  );
}

ListTile _favoriteTile(WidgetTester tester, String title) {
  return tester.widget<ListTile>(
    find.ancestor(
      of: find.text(title),
      matching: find.byType(ListTile),
    ),
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
  Future<Set<String>> refreshFavoriteIds(
    String uid, {
    String reason = 'manual',
  }) async {
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
  Future<Set<String>> refreshFavoriteIds(
    String uid, {
    String reason = 'manual',
  }) async {
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
  Future<Set<String>> refreshFavoriteIds(
    String uid, {
    String reason = 'manual',
  }) async {
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
  Future<Set<String>> refreshFavoriteIds(
    String uid, {
    String reason = 'manual',
  }) async {
    refreshCalls += 1;
    _controller.add(Set<String>.from(_ids));
    return Set<String>.from(_ids);
  }

  @override
  Future<Set<String>> forceRefreshFavoriteIds(
    String uid, {
    String reason = 'manual',
  }) async {
    return refreshFavoriteIds(uid, reason: reason);
  }
}

class _RepeatingFavoritesService extends FavoritesService {
  _RepeatingFavoritesService({required Set<String> initialIds})
      : _ids = Set<String>.from(initialIds);

  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();
  final Set<String> _ids;
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
  Future<Set<String>> refreshFavoriteIds(
    String uid, {
    String reason = 'manual',
  }) async {
    refreshCalls += 1;
    final ids = Set<String>.from(_ids);
    _controller.add(ids);
    scheduleMicrotask(() {
      _controller.add(Set<String>.from(ids));
    });
    return ids;
  }
}

class _CachedFavoritesService extends FavoritesService {
  final Set<String> _ids = <String>{'listing-1'};

  @override
  Set<String> peekFavoriteIds(String uid) => Set<String>.from(_ids);

  @override
  Stream<Set<String>> streamCachedFavoriteIds(String uid) {
    return Stream<Set<String>>.value(Set<String>.from(_ids));
  }

  @override
  Future<Set<String>> refreshFavoriteIds(
    String uid, {
    String reason = 'manual',
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return Set<String>.from(_ids);
  }
}

class _EmbeddedFavoritesService extends FavoritesService {
  _EmbeddedFavoritesService({
    List<Listing> items = const <Listing>[],
    List<String> idsWithoutListings = const <String>[],
  })  : _items = List<Listing>.from(items),
        _idsWithoutListings = List<String>.from(idsWithoutListings);

  final List<Listing> _items;
  final List<String> _idsWithoutListings;

  List<String> get _ids => <String>[
        ..._items.map((item) => item.id),
        ..._idsWithoutListings,
      ];

  @override
  Set<String> peekFavoriteIds(String uid) => const <String>{};

  @override
  Stream<Set<String>> streamCachedFavoriteIds(String uid) {
    return Stream<Set<String>>.value(const <String>{});
  }

  @override
  Future<FavoriteIdsPage> getFavoriteIdsPage({
    required String uid,
    int limit = 50,
    String? cursor,
    bool resetCache = false,
  }) async {
    if ((cursor ?? '').trim().isNotEmpty) {
      return const FavoriteIdsPage(ids: <String>[], hasMore: false);
    }
    return FavoriteIdsPage(
      ids: _ids,
      embeddedListings: <String, Listing>{
        for (final item in _items) item.id: item,
      },
      hasMore: false,
    );
  }
}

class _StaticFavoritesService extends FavoritesService {
  _StaticFavoritesService({required Set<String> ids})
      : _ids = Set<String>.from(ids);

  final Set<String> _ids;

  @override
  Set<String> peekFavoriteIds(String uid) => Set<String>.from(_ids);

  @override
  Future<Set<String>> refreshFavoriteIds(
    String uid, {
    String reason = 'manual',
  }) async {
    return Set<String>.from(_ids);
  }

  @override
  Stream<Set<String>> streamCachedFavoriteIds(String uid) {
    return Stream<Set<String>>.value(Set<String>.from(_ids));
  }
}

class _SubscriptionTrackingFavoritesService extends FavoritesService {
  final Set<String> _ids = <String>{'listing-1'};
  int activeListeners = 0;

  @override
  Set<String> peekFavoriteIds(String uid) => Set<String>.from(_ids);

  @override
  Stream<Set<String>> streamCachedFavoriteIds(String uid) {
    return Stream<Set<String>>.multi(
      (controller) {
        activeListeners += 1;
        controller.add(Set<String>.from(_ids));
        controller.onCancel = () async {
          activeListeners -= 1;
        };
      },
      isBroadcast: true,
    );
  }

  @override
  Future<Set<String>> refreshFavoriteIds(
    String uid, {
    String reason = 'manual',
  }) async {
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

class _MutableCachedListingsService extends ListingsService {
  _MutableCachedListingsService(this.item);

  Listing item;

  @override
  List<Listing> peekListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) {
    return <Listing>[item];
  }

  @override
  Future<List<Listing>> getListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) async {
    return <Listing>[item];
  }

  @override
  Future<Listing?> getListingById(String id) async {
    return item.id == id ? item : null;
  }
}

class _MissingOneListingsService extends ListingsService {
  int getListingByIdCalls = 0;

  @override
  List<Listing> peekListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) {
    return <Listing>[
      for (var i = 1; i <= 5; i++)
        _listingFixture(id: 'listing-$i', title: 'Объявление $i'),
    ];
  }

  @override
  Future<List<Listing>> getListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) async {
    return peekListings(category: category, search: search, filters: filters);
  }

  @override
  Future<Listing?> getListingById(String id) async {
    getListingByIdCalls += 1;
    if (id == 'listing-6') {
      return null;
    }
    return _listingFixture(
      id: id,
      title: 'Объявление ${id.split('-').last}',
    );
  }
}

class _ByIdListingsService extends ListingsService {
  @override
  Future<Listing?> getListingById(String id) async {
    return _listingFixture(id: id, title: id);
  }
}

class _FollowListingsService extends ListingsService {
  @override
  List<Listing> peekListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) {
    return List<Listing>.generate(
      18,
      (index) => _listingFixture(
        id: 'follow-listing-$index',
        title: 'follow-listing-$index',
        ownerId: 'seller-$index',
      ),
    );
  }

  @override
  Future<ListingsFeedPage> getListingsPage({
    required String category,
    required String search,
    ListingFeedFilters? filters,
    int limit = 20,
    String? cursor,
    bool useVipInterleave = false,
    int vipRotation = 0,
  }) async {
    return ListingsFeedPage(
      items: peekListings(category: category, search: search),
      hasMore: false,
    );
  }
}

class _PagedFavoritesService extends FavoritesService {
  final List<String?> requests = <String?>[];
  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();

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
  Future<FavoriteIdsPage> getFavoriteIdsPage({
    required String uid,
    int limit = 50,
    String? cursor,
    bool resetCache = false,
  }) async {
    requests.add(cursor);
    if (cursor == null) {
      return FavoriteIdsPage(
        ids: List<String>.generate(5, (index) => 'listing-$index'),
        hasMore: true,
        nextCursor: 'f2',
      );
    }
    if (cursor == 'f2') {
      return const FavoriteIdsPage(
        ids: <String>['listing-4', 'listing-5', 'listing-6', 'listing-7'],
        hasMore: true,
        nextCursor: 'f3',
      );
    }
    return const FavoriteIdsPage(
      ids: <String>['listing-7', 'listing-8', 'listing-9'],
      hasMore: false,
    );
  }
}

class _PagedHistoryService extends ListingHistoryService {
  final List<String?> requests = <String?>[];

  @override
  bool get isLoaded => true;

  @override
  List<String> get viewedIdsNewestFirst =>
      List<String>.generate(10, (index) => 'listing-$index');

  @override
  bool hasViewed(String listingId) => listingId.trim().isNotEmpty;

  @override
  Future<ViewedListingsPage> getViewedListingsPage({
    int limit = 50,
    String? cursor,
  }) async {
    requests.add(cursor);
    if (cursor == null) {
      return ViewedListingsPage(
        ids: List<String>.generate(5, (index) => 'listing-$index'),
        hasMore: true,
        nextCursor: 'v2',
      );
    }
    if (cursor == 'v2') {
      return const ViewedListingsPage(
        ids: <String>['listing-4', 'listing-5', 'listing-6', 'listing-7'],
        hasMore: true,
        nextCursor: 'v3',
      );
    }
    return const ViewedListingsPage(
      ids: <String>['listing-7', 'listing-8', 'listing-9'],
      hasMore: false,
    );
  }
}

class _PagedFollowService extends FollowService {
  final List<String?> requests = <String?>[];

  @override
  List<FollowedSeller> peekFollowedSellers(String followerId) {
    return const <FollowedSeller>[];
  }

  @override
  Future<FollowedSellersPage> getFollowedSellersPage({
    required String followerId,
    int limit = 50,
    String? cursor,
    bool resetCache = false,
  }) async {
    requests.add(cursor);
    final base = cursor == null
        ? 0
        : cursor == 's2'
            ? 5
            : 9;
    return FollowedSellersPage(
      items: List<FollowedSeller>.generate(
        cursor == 's3' ? 4 : 5,
        (index) => FollowedSeller(
          sellerId: 'seller-${base + index}',
          followedAt: DateTime.utc(2026, 1, 1),
        ),
      ),
      hasMore: cursor != 's3',
      nextCursor: cursor == null
          ? 's2'
          : cursor == 's2'
              ? 's3'
              : null,
    );
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

Listing _listingFixture({
  String id = 'listing-1',
  String title = 'Тестовое объявление',
  String status = 'approved',
  String ownerId = 'seller-1',
}) {
  return Listing.fromMap(<String, dynamic>{
    'id': id,
    'owner_id': ownerId,
    'owner_email': 'seller@example.com',
    'owner_name': 'Seller',
    'title': title,
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
    'status': status,
    'rejection_reason': '',
    'can_promote': false,
    'created_at': '2026-07-01T10:00:00.000Z',
    'published_at': '2026-07-01T10:00:00.000Z',
  });
}
