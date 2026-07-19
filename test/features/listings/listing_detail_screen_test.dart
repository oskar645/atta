import 'dart:async';

import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/models/wallet.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/deep_link_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/reports_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/wallet_service.dart';
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

  testWidgets('similar listings error shows local retry only', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        listingsService: _FakeListingsService(
          listing: _listingFixture(
            description:
                'Очень длинное описание для экрана объявления, чтобы гарантированно появились нижние секции и rebuild сценарий тоже был реалистичным.',
          ),
          similarError: Exception('similar failed'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -2500));
    await tester.pumpAndSettle();

    expect(find.text('Test listing'), findsOneWidget);
    expect(
        find.text('Не удалось загрузить похожие объявления'), findsOneWidget);
    expect(find.text('Что-то пошло не так'), findsNothing);
  });

  testWidgets('reviews error shows local retry only', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        reviewsService: _FakeReviewsService(
          refreshError: Exception('reviews failed'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Test listing'), findsOneWidget);
    expect(find.text('Не удалось загрузить отзывы'), findsOneWidget);
    expect(find.text('Что-то пошло не так'), findsNothing);
  });

  testWidgets('duplicate requests are not fired on rebuild', (tester) async {
    final listingsService = _FakeListingsService(
      listing: _listingFixture(
        description: List<String>.filled(40, 'Длинное описание').join(' '),
      ),
    );

    await tester.pumpWidget(
      _buildTestApp(
        listingsService: listingsService,
      ),
    );

    await tester.pumpAndSettle();

    expect(listingsService.getListingRequests, 1);
    await tester.scrollUntilVisible(
      find.text('Показать полностью'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Показать полностью'), findsOneWidget);

    await tester.tap(find.text('Показать полностью'));
    await tester.pump();

    expect(listingsService.getListingRequests, 1);
  });

  testWidgets('cached listing is shown immediately while detail refreshes',
      (tester) async {
    final listingsService = _CachedDetailListingsService();

    await tester.pumpWidget(
      _buildTestApp(
        listingsService: listingsService,
      ),
    );

    await tester.pump();

    expect(find.text('Test listing'), findsOneWidget);
    expect(find.byType(SkeletonBox), findsNothing);
    expect(listingsService.refreshRequests, 1);
  });

  testWidgets('owner can open sell faster even when listing cannot be promoted',
      (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        listingsService: _FakeListingsService(
          listing: _listingFixture(
            ownerId: 'user-1',
            canPromote: false,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Продать быстрее'), findsOneWidget);
  });

  testWidgets('listing detail shows formatted russian phone', (tester) async {
    await tester.pumpWidget(_buildTestApp());

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Телефон:'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining('+7 999 000 00 00'), findsWidgets);
  });

  testWidgets('listing detail hides empty optional transport fields',
      (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        listingsService: _FakeListingsService(
          listing: Listing.fromMap(<String, dynamic>{
            ..._listingFixture().toMap(),
            'car': <String, dynamic>{
              'brand': 'Changan',
              'model': 'UNI-Z',
              'generation': 'I',
            },
          }),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Пробег'), findsNothing);
    expect(find.text('Кузов'), findsNothing);
    expect(find.text('Топливо'), findsNothing);
    expect(find.text('Коробка'), findsNothing);
    expect(find.text('Привод'), findsNothing);
    expect(find.text('Состояние'), findsNothing);
    expect(find.text('Цвет'), findsNothing);
    expect(find.text('ПТС'), findsNothing);
  });

  testWidgets('favorite toggle in detail does not reload listing', (
    tester,
  ) async {
    final listingsService = _FakeListingsService();
    final favoritesService = _FakeFavoritesService();

    await tester.pumpWidget(
      _buildTestApp(
        listingsService: listingsService,
        favoritesService: favoritesService,
      ),
    );

    await tester.pumpAndSettle();

    expect(listingsService.getListingRequests, 1);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(favoritesService.toggleCalls, 1);
    expect(listingsService.getListingRequests, 1);
    expect(find.text('Test listing'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('detail screen labels seller reviews explicitly', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        reviewsService: _FakeReviewsService(
          rows: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'review-1',
              'rating': 5,
              'seller_id': 'seller-1',
            },
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Отзывы продавца'), findsOneWidget);
  });

  testWidgets('iOS listing detail bottom scroll uses clamping physics',
      (tester) async {
    await tester.pumpWidget(
      _buildTestApp(platform: TargetPlatform.iOS),
    );
    await tester.pumpAndSettle();

    final bodyList = tester.widget<ListView>(_detailBodyListView());

    expect(bodyList.physics, isA<ClampingScrollPhysics>());
  });

  testWidgets('Android listing detail scroll physics remains unchanged',
      (tester) async {
    await tester.pumpWidget(
      _buildTestApp(platform: TargetPlatform.android),
    );
    await tester.pumpAndSettle();

    final bodyList = tester.widget<ListView>(_detailBodyListView());

    expect(bodyList.physics, isNull);
  });

  testWidgets('iOS similar listings empty rebuild keeps bottom position stable',
      (tester) async {
    final listingsService = _DelayedSimilarListingsService(
      listing: _listingFixture(
        description: List<String>.filled(80, 'Длинное описание').join(' '),
      ),
    );

    await tester.pumpWidget(
      _buildTestApp(
        listingsService: listingsService,
        platform: TargetPlatform.iOS,
      ),
    );
    await tester.pump();
    await tester.pump();

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: _detailBodyListView(),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    final before = scrollable.position.pixels;

    listingsService.completeSimilar(const <Listing>[]);
    await tester.pump();
    await tester.pump();

    expect(scrollable.position.pixels, before);
  });

  testWidgets('bottom safe-area inset remains stable on listing detail',
      (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(bottom: 34),
          viewPadding: EdgeInsets.only(bottom: 34),
        ),
        child: _buildTestApp(platform: TargetPlatform.iOS),
      ),
    );
    await tester.pumpAndSettle();

    final bottomSafeArea = tester.widget<SafeArea>(
      find
          .ancestor(
            of: find.text('Позвонить'),
            matching: find.byType(SafeArea),
          )
          .first,
    );

    expect(bottomSafeArea.top, isFalse);
    expect(bottomSafeArea.bottom, isTrue);
  });
}

Finder _detailBodyListView() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is ListView &&
        widget.padding == const EdgeInsets.fromLTRB(12, 12, 12, 20),
  );
}

Widget _buildTestApp({
  ListingsService? listingsService,
  ReviewsService? reviewsService,
  ProfileService? profileService,
  FavoritesService? favoritesService,
  TargetPlatform? platform,
}) {
  return MultiProvider(
    providers: [
      Provider<AuthService>.value(value: _FakeAuthService()),
      Provider<AdminService>.value(value: _FakeAdminService()),
      Provider<ListingsService>.value(
        value: listingsService ?? _FakeListingsService(),
      ),
      Provider<FavoritesService>.value(
        value: favoritesService ?? _FakeFavoritesService(),
      ),
      Provider<ChatService>.value(value: ChatService()),
      ChangeNotifierProvider<ListingHistoryService>.value(
        value: ListingHistoryService(),
      ),
      Provider<PresenceService>.value(value: _FakePresenceService()),
      Provider<ProfileService>.value(
        value: profileService ?? _FakeProfileService(),
      ),
      Provider<DeepLinkService>.value(value: DeepLinkService()),
      Provider<ReportsService>.value(value: ReportsService()),
      Provider<ReviewsService>.value(
        value: reviewsService ?? _FakeReviewsService(),
      ),
      Provider<WalletService>.value(value: _FakeWalletService()),
    ],
    child: MaterialApp(
      theme: platform == null ? null : ThemeData(platform: platform),
      home: const ListingDetailScreen(listingId: 'listing-1'),
    ),
  );
}

Listing _listingFixture({
  String? description,
  bool canPromote = true,
  String ownerId = 'seller-1',
}) {
  return Listing.fromMap(<String, dynamic>{
    'id': 'listing-1',
    'owner_id': ownerId,
    'owner_email': 'seller@example.com',
    'owner_name': 'Seller',
    'title': 'Test listing',
    'description': description ?? 'Описание объявления',
    'category': 'Авто',
    'subcategory': 'Седан',
    'price': 1200000,
    'phone': '+79990000000',
    'phone_hidden': false,
    'city': 'Москва',
    'delivery': <String, dynamic>{'pickup': true},
    'photo_urls': const <String>[],
    'view_count': 3,
    'status': 'approved',
    'rejection_reason': '',
    'can_promote': canPromote,
    'created_at': '2026-06-20T10:00:00.000Z',
    'published_at': '2026-06-20T10:00:00.000Z',
    'car': <String, dynamic>{
      'brand': 'Toyota',
      'model': 'Camry',
      'year': 2020,
      'mileage_km': 12000,
      'body_type': 'Седан',
      'fuel': 'Бензин',
      'engine_volume': 2.5,
      'power_hp': 181,
      'transmission': 'Автомат',
      'drive': 'Передний',
      'condition': 'Хорошее',
      'color': 'Белый',
    },
  });
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'user-1');
}

class _FakeAdminService extends AdminService {
  @override
  Stream<bool> streamIsAdmin(String uid) => Stream<bool>.value(false);
}

class _FakeListingsService extends ListingsService {
  _FakeListingsService({
    Listing? listing,
    this.similarError,
  }) : _listing = listing ?? _listingFixture();

  final Listing _listing;
  final Object? similarError;
  int getListingRequests = 0;
  int similarRequests = 0;

  @override
  Future<Listing?> getListingById(String id) async {
    getListingRequests += 1;
    return _listing;
  }

  @override
  Future<List<Listing>> getSimilarListings(
    Listing base, {
    int limit = 10,
  }) async {
    similarRequests += 1;
    if (similarError != null) {
      throw similarError!;
    }
    return <Listing>[
      Listing.fromMap(<String, dynamic>{
        ..._listingFixture().toMap(),
        'id': 'listing-2',
        'title': 'Similar listing',
      }),
    ];
  }

  @override
  Future<void> incrementView(String listingId) async {}
}

class _CachedDetailListingsService extends ListingsService {
  _CachedDetailListingsService() : _listing = _listingFixture();

  final Listing _listing;
  final Completer<Listing?> _refreshCompleter = Completer<Listing?>();
  int refreshRequests = 0;

  @override
  Listing? peekListingById(String id) => _listing;

  @override
  Future<Listing?> refreshListingById(String listingId) async {
    refreshRequests += 1;
    return _refreshCompleter.future;
  }

  @override
  Future<Listing?> getListingById(String id) async {
    return _listing;
  }

  @override
  Future<List<Listing>> getSimilarListings(
    Listing base, {
    int limit = 10,
  }) async {
    return const <Listing>[];
  }

  @override
  Future<void> incrementView(String listingId) async {}
}

class _DelayedSimilarListingsService extends _FakeListingsService {
  _DelayedSimilarListingsService({
    required super.listing,
  });

  final Completer<List<Listing>> _similarCompleter = Completer<List<Listing>>();

  void completeSimilar(List<Listing> items) {
    _similarCompleter.complete(items);
  }

  @override
  Future<List<Listing>> getSimilarListings(
    Listing base, {
    int limit = 10,
  }) {
    similarRequests += 1;
    return _similarCompleter.future;
  }
}

class _FakeFavoritesService extends FavoritesService {
  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();
  final Set<String> _favoriteIds = <String>{};
  int toggleCalls = 0;

  @override
  Stream<Set<String>> streamFavoriteIds(String uid) async* {
    yield Set<String>.from(_favoriteIds);
    yield* _controller.stream;
  }

  @override
  bool isFavorite(String uid, String listingId) {
    return _favoriteIds.contains(listingId);
  }

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
    toggleCalls += 1;
    if (makeFavorite) {
      _favoriteIds.add(listingId);
    } else {
      _favoriteIds.remove(listingId);
    }
    _controller.add(Set<String>.from(_favoriteIds));
  }
}

class _FakePresenceService extends PresenceService {
  @override
  Stream<bool> streamIsOnline(
    String uid, {
    Duration staleAfter = const Duration(minutes: 2),
  }) {
    return Stream<bool>.value(false);
  }
}

class _FakeProfileService extends ProfileService {
  @override
  Future<Map<String, dynamic>> getProfile(
    String uid, {
    bool forceRefresh = false,
  }) async {
    return <String, dynamic>{
      'display_name': 'Seller',
      'avatar_url': '',
    };
  }
}

class _FakeReviewsService extends ReviewsService {
  _FakeReviewsService({
    this.refreshError,
    this.rows = const <Map<String, dynamic>>[],
  });

  final Object? refreshError;
  final List<Map<String, dynamic>> rows;

  @override
  List<Map<String, dynamic>> peekSellerReviews(String sellerId) {
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> refreshSellerReviews(
    String sellerId,
  ) async {
    if (refreshError != null) {
      throw refreshError!;
    }
    return List<Map<String, dynamic>>.from(rows);
  }
}

class _FakeWalletService extends WalletService {
  @override
  Future<Wallet?> maybeCheckAccrualOncePerSession() async {
    return const Wallet(
      balance: 100,
      maxBalance: 1000,
      welcomeBonus: 100,
      dailyBonusAmount: 25,
      lastDailyBonusAt: null,
      canClaimDailyBonus: false,
      nextDailyBonusAt: null,
      lastBonusAccrualAt: null,
      nextAccrualAt: null,
      daysUntilNextAccrual: 0,
      secondsUntilNextAccrual: 0,
    );
  }

  @override
  Future<Wallet> getWallet({bool forceRefresh = false}) async {
    return const Wallet(
      balance: 100,
      maxBalance: 1000,
      welcomeBonus: 100,
      dailyBonusAmount: 25,
      lastDailyBonusAt: null,
      canClaimDailyBonus: false,
      nextDailyBonusAt: null,
      lastBonusAccrualAt: null,
      nextAccrualAt: null,
      daysUntilNextAccrual: 0,
      secondsUntilNextAccrual: 0,
    );
  }
}
