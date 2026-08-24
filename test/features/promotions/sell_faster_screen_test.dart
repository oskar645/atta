import 'package:atta/src/features/promotions/sell_faster_screen.dart';
import 'package:atta/src/models/active_promotion.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/models/promotion_plan.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/models/wallet.dart';
import 'package:atta/src/services/promotions_service.dart';
import 'package:atta/src/services/wallet_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
      'sell faster screen shows updated plan prices in list and confirmation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final walletService = _FakeWalletService();
    final promotionsService = _FakePromotionsService(walletService);
    final listingsService = _FakeListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<WalletService>.value(value: walletService),
          Provider<PromotionsService>.value(value: promotionsService),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: MaterialApp(
          home: SellFasterScreen(listing: _listing()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Витрина ATTA'), findsOneWidget);
    expect(find.text('Поднятие'), findsOneWidget);
    expect(find.text('VIP'), findsOneWidget);
    expect(find.text('230 бонусов'), findsOneWidget);
    expect(find.text('35 бонусов'), findsOneWidget);
    expect(find.text('150 бонусов'), findsOneWidget);
    expect(find.text('Турбо'), findsNothing);

    await tester
        .ensureVisible(find.widgetWithText(FilledButton, 'Подключить').first);
    await tester.tap(find.widgetWithText(FilledButton, 'Подключить').first);
    await tester.pumpAndSettle();

    expect(find.text('Добавить в Витрину ATTA?'), findsOneWidget);
    expect(find.text('Стоимость: 230 бонусов'), findsOneWidget);
    expect(find.textContaining('рубл'), findsNothing);
  });

  testWidgets('showcase confirmation changes days and total price',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final walletService = _FakeWalletService();
    final promotionsService = _FakePromotionsService(walletService);
    final listingsService = _FakeListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<WalletService>.value(value: walletService),
          Provider<PromotionsService>.value(value: promotionsService),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: MaterialApp(
          home: SellFasterScreen(listing: _listing()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .ensureVisible(find.widgetWithText(FilledButton, 'Подключить').first);
    await tester.tap(find.widgetWithText(FilledButton, 'Подключить').first);
    await tester.pumpAndSettle();

    expect(find.text('1 день'), findsOneWidget);
    expect(find.text('Срок: 1 день'), findsOneWidget);
    expect(find.text('Стоимость: 230 бонусов'), findsOneWidget);

    await tester.tap(find.byTooltip('Увеличить'));
    await tester.pumpAndSettle();

    expect(find.text('2 дня'), findsOneWidget);
    expect(find.text('Срок: 2 дня'), findsOneWidget);
    expect(find.text('Стоимость: 460 бонусов'), findsOneWidget);
  });

  testWidgets('VIP confirmation shows 48-hour periods as calendar days',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final walletService = _FakeWalletService();
    final promotionsService = _FakePromotionsService(walletService);
    final listingsService = _FakeListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<WalletService>.value(value: walletService),
          Provider<PromotionsService>.value(value: promotionsService),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: MaterialApp(
          home: SellFasterScreen(listing: _listing()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .ensureVisible(find.widgetWithText(FilledButton, 'Подключить').at(2));
    await tester.tap(find.widgetWithText(FilledButton, 'Подключить').at(2));
    await tester.pumpAndSettle();

    expect(find.text('2 дня'), findsOneWidget);
    expect(find.text('Срок: 2 дня'), findsOneWidget);
    expect(find.text('Стоимость: 150 бонусов'), findsOneWidget);

    await tester.tap(find.byTooltip('Увеличить'));
    await tester.tap(find.byTooltip('Увеличить'));
    await tester.pumpAndSettle();

    expect(find.text('6 дней'), findsOneWidget);
    expect(find.text('Срок: 6 дней'), findsOneWidget);
    expect(find.text('Стоимость: 450 бонусов'), findsOneWidget);
  });

  testWidgets('duration selector stops at 30 quantity steps', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final walletService = _FakeWalletService()..setBalance(10000);
    final promotionsService = _FakePromotionsService(walletService);
    final listingsService = _FakeListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<WalletService>.value(value: walletService),
          Provider<PromotionsService>.value(value: promotionsService),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: MaterialApp(
          home: SellFasterScreen(listing: _listing()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .ensureVisible(find.widgetWithText(FilledButton, 'Подключить').at(2));
    await tester.tap(find.widgetWithText(FilledButton, 'Подключить').at(2));
    await tester.pumpAndSettle();

    for (var i = 0; i < 40; i += 1) {
      await tester.tap(find.byTooltip('Увеличить'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('60 дней'), findsOneWidget);
    expect(find.text('Стоимость: 4500 бонусов'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.add),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('sell faster screen still shows plans when wallet failed',
      (tester) async {
    final walletService = _FailingWalletService();
    final promotionsService = _FakePromotionsService(_FakeWalletService());
    final listingsService = _FakeListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<WalletService>.value(value: walletService),
          Provider<PromotionsService>.value(value: promotionsService),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: MaterialApp(
          home: SellFasterScreen(listing: _listing()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Витрина ATTA'), findsOneWidget);
    expect(
      find.text('Не удалось загрузить кошелёк. Повторите попытку.'),
      findsWidgets,
    );
    expect(find.text('Повторить'), findsOneWidget);
    expect(find.text('0 бонусов'), findsNothing);
  });

  testWidgets('sell faster screen keeps plan visible with low balance',
      (tester) async {
    final walletService = _FakeWalletService()..setBalance(10);
    final promotionsService = _FakePromotionsService(walletService);
    final listingsService = _FakeListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<WalletService>.value(value: walletService),
          Provider<PromotionsService>.value(value: promotionsService),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: MaterialApp(
          home: SellFasterScreen(listing: _listing()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Витрина ATTA'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Подключить').first);
    await tester.pumpAndSettle();

    expect(find.text('Недостаточно бонусов'), findsOneWidget);
    expect(find.text('Получить бонусы'), findsOneWidget);
  });

  testWidgets('successful activation refreshes public feed caches',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final walletService = _FakeWalletService();
    final promotionsService = _FakePromotionsService(walletService);
    final listingsService = _FakeListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<WalletService>.value(value: walletService),
          Provider<PromotionsService>.value(value: promotionsService),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: MaterialApp(
          home: SellFasterScreen(listing: _listing()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .ensureVisible(find.widgetWithText(FilledButton, 'Подключить').at(1));
    await tester.tap(find.widgetWithText(FilledButton, 'Подключить').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Подключить').last);
    await tester.pumpAndSettle();

    expect(listingsService.refreshCalls, 1);
    expect(listingsService.lastListing?.activeBump?.type, 'bump');
  });
}

class _FakeWalletService extends WalletService {
  int _balance = 1000;

  void setBalance(int value) {
    _balance = value;
  }

  @override
  Future<Wallet> getWallet({bool forceRefresh = false}) async => _wallet();

  @override
  Future<Wallet> checkAccrual({bool forceRefresh = false}) async => _wallet();

  Wallet _wallet() {
    return Wallet.fromMap({
      'balance': _balance,
      'maxBalance': 1000,
      'welcomeBonus': 200,
      'dailyBonusAmount': 15,
      'canClaimDailyBonus': false,
      'nextDailyBonusAt': '2026-06-20T00:00:00.000Z',
    });
  }
}

class _FakePromotionsService extends PromotionsService {
  _FakePromotionsService(this.walletService);

  final _FakeWalletService walletService;
  final Set<String> activeTypes = <String>{};
  int? lastDays;
  String? lastType;

  @override
  Future<List<PromotionPlan>> getPlans() async {
    return const [
      PromotionPlan(
        type: 'showcase',
        title: 'Витрина ATTA',
        description: 'Ваше объявление появится на главной.',
        costBonus: 230,
        durationHours: 24,
      ),
      PromotionPlan(
        type: 'bump',
        title: 'Поднятие',
        description: 'Объявление поднимется в ленте.',
        costBonus: 35,
        durationHours: 24,
      ),
      PromotionPlan(
        type: 'vip',
        title: 'VIP',
        description: 'Объявление станет заметнее.',
        costBonus: 150,
        durationHours: 48,
      ),
      PromotionPlan(
        type: 'turbo',
        title: 'Турбо',
        description: 'Максимальное продвижение.',
        costBonus: 100,
        durationHours: 96,
      ),
    ].where((plan) => plan.type != 'turbo').toList();
  }

  @override
  Future<ListingPromotionState> getListingPromotionState(
      String listingId) async {
    return ListingPromotionState(
      activePromotions: [
        if (activeTypes.contains('showcase'))
          ActivePromotion.fromMap({
            'id': 'promo-1',
            'type': 'showcase',
            'title': 'Витрина ATTA',
            'status': 'active',
            'costBonus': 230,
            'endsAt': '2026-06-20T10:00:00.000Z',
          }),
        if (activeTypes.contains('bump'))
          ActivePromotion.fromMap({
            'id': 'promo-bump',
            'type': 'bump',
            'title': 'Поднятие',
            'status': 'active',
            'costBonus': 35,
            'endsAt': '2026-06-20T10:00:00.000Z',
          }),
        if (activeTypes.contains('vip'))
          ActivePromotion.fromMap({
            'id': 'promo-vip',
            'type': 'vip',
            'title': 'VIP',
            'status': 'active',
            'costBonus': 150,
            'endsAt': '2026-06-20T10:00:00.000Z',
          }),
      ],
      canPromote: true,
    );
  }

  @override
  Future<Map<String, dynamic>> promoteListing(
    String listingId,
    String type, {
    int days = 1,
    String? idempotencyKey,
  }) async {
    lastType = type;
    lastDays = days;
    activeTypes.add(type);
    walletService.setBalance(0);
    final listingMap = _listing().toMap();
    listingMap['promotions'] = <String, dynamic>{
      'activeBump': type == 'bump'
          ? ActivePromotion.fromMap({
              'id': 'promo-bump',
              'type': 'bump',
              'title': 'Поднятие',
              'status': 'active',
              'endsAt': '2026-06-20T10:00:00.000Z',
            }).toMap()
          : null,
      'activeVip': type == 'vip'
          ? ActivePromotion.fromMap({
              'id': 'promo-vip',
              'type': 'vip',
              'title': 'VIP',
              'status': 'active',
              'endsAt': '2026-06-20T10:00:00.000Z',
            }).toMap()
          : null,
      'activeShowcase': null,
      'activeTurbo': null,
    };
    return {
      'message': 'Объявление добавлено в Витрину ATTA',
      'listing': listingMap,
    };
  }
}

class _FakeListingsService extends ListingsService {
  int refreshCalls = 0;
  Listing? lastListing;

  @override
  void refreshFeedAfterPromotion({Listing? listing}) {
    refreshCalls += 1;
    lastListing = listing;
  }
}

class _FailingWalletService extends WalletService {
  @override
  Future<Wallet> getWallet({bool forceRefresh = false}) async {
    throw Exception('wallet failed');
  }
}

Listing _listing() {
  return Listing(
    id: 'listing-1',
    ownerId: 'user-1',
    ownerEmail: '',
    ownerName: 'Seller',
    title: 'Велосипед',
    description: 'Описание',
    category: 'Транспорт',
    subcategory: 'Велосипеды',
    price: 10000,
    phone: '',
    phoneHidden: false,
    city: 'Москва',
    location: const ListingLocation(raw: 'Москва'),
    delivery: const {},
    photoUrls: const [],
    photoItems: const [],
    car: null,
    dealType: null,
    realEstateType: null,
    clothesType: null,
    clothesSize: null,
    viewCount: 0,
    favoriteCount: 0,
    status: 'approved',
    rejectionReason: '',
    activeShowcase: null,
    activeBump: null,
    activeVip: null,
    activeTurbo: null,
    canPromote: true,
    cannotPromoteReason: null,
    publishedAt: null,
    createdAt: DateTime.parse('2026-06-19T10:00:00.000Z'),
    updatedAt: null,
  );
}
