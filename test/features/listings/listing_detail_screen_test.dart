import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/models/wallet.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/reports_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/wallet_service.dart';
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
}

Widget _buildTestApp({
  ListingsService? listingsService,
  ReviewsService? reviewsService,
  ProfileService? profileService,
}) {
  return MultiProvider(
    providers: [
      Provider<AuthService>.value(value: _FakeAuthService()),
      Provider<AdminService>.value(value: _FakeAdminService()),
      Provider<ListingsService>.value(
        value: listingsService ?? _FakeListingsService(),
      ),
      Provider<FavoritesService>.value(value: _FakeFavoritesService()),
      Provider<ChatService>.value(value: ChatService()),
      ChangeNotifierProvider<ListingHistoryService>.value(
        value: ListingHistoryService(),
      ),
      Provider<PresenceService>.value(value: _FakePresenceService()),
      Provider<ProfileService>.value(
        value: profileService ?? _FakeProfileService(),
      ),
      Provider<ReportsService>.value(value: ReportsService()),
      Provider<ReviewsService>.value(
        value: reviewsService ?? _FakeReviewsService(),
      ),
      Provider<WalletService>.value(value: _FakeWalletService()),
    ],
    child: const MaterialApp(
      home: ListingDetailScreen(listingId: 'listing-1'),
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

class _FakeFavoritesService extends FavoritesService {
  @override
  Stream<Set<String>> streamFavoriteIds(String uid) {
    return Stream<Set<String>>.value(<String>{});
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
  Future<Map<String, dynamic>> getProfile(String uid) async {
    return <String, dynamic>{
      'display_name': 'Seller',
      'avatar_url': '',
    };
  }
}

class _FakeReviewsService extends ReviewsService {
  _FakeReviewsService({
    this.refreshError,
  });

  final Object? refreshError;

  @override
  List<Map<String, dynamic>> peekSellerReviews(String sellerId) {
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<List<Map<String, dynamic>>> refreshSellerReviews(
    String sellerId,
  ) async {
    if (refreshError != null) {
      throw refreshError!;
    }
    return const <Map<String, dynamic>>[];
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
  Future<Wallet> getWallet() async {
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
