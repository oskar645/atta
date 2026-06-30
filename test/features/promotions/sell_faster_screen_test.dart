import 'package:atta/src/features/promotions/sell_faster_screen.dart';
import 'package:atta/src/models/active_promotion.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/models/promotion_plan.dart';
import 'package:atta/src/models/wallet.dart';
import 'package:atta/src/services/promotions_service.dart';
import 'package:atta/src/services/wallet_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('sell faster screen shows all plans and updates after purchase',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final walletService = _FakeWalletService();
    final promotionsService = _FakePromotionsService(walletService);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<WalletService>.value(value: walletService),
          Provider<PromotionsService>.value(value: promotionsService),
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
    expect(find.text('Турбо'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Подключить').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Подключить').last);
    await tester.pumpAndSettle();

    expect(promotionsService.showcaseActive, isTrue);
    expect(find.textContaining('рубл'), findsNothing);
  });

  testWidgets('sell faster screen still shows plans when wallet failed',
      (tester) async {
    final walletService = _FailingWalletService();
    final promotionsService = _FakePromotionsService(_FakeWalletService());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<WalletService>.value(value: walletService),
          Provider<PromotionsService>.value(value: promotionsService),
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
    expect(find.text('0 поинтов'), findsNothing);
  });

  testWidgets('sell faster screen keeps plan visible with low balance',
      (tester) async {
    final walletService = _FakeWalletService()..setBalance(10);
    final promotionsService = _FakePromotionsService(walletService);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<WalletService>.value(value: walletService),
          Provider<PromotionsService>.value(value: promotionsService),
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

    expect(find.text('Недостаточно поинтов'), findsOneWidget);
    expect(find.text('Получить поинты'), findsOneWidget);
  });
}

class _FakeWalletService extends WalletService {
  int _balance = 100;

  void setBalance(int value) {
    _balance = value;
  }

  @override
  Future<Wallet> getWallet() async => _wallet();

  @override
  Future<Wallet> checkAccrual() async => _wallet();

  Wallet _wallet() {
    return Wallet.fromMap({
      'balance': _balance,
      'maxBalance': 1000,
      'welcomeBonus': 100,
      'dailyBonusAmount': 25,
      'canClaimDailyBonus': false,
      'nextDailyBonusAt': '2026-06-20T00:00:00.000Z',
    });
  }
}

class _FakePromotionsService extends PromotionsService {
  _FakePromotionsService(this.walletService);

  final _FakeWalletService walletService;
  bool showcaseActive = false;

  @override
  Future<List<PromotionPlan>> getPlans() async {
    return const [
      PromotionPlan(
        type: 'showcase',
        title: 'Витрина ATTA',
        description: 'Ваше объявление появится на главной.',
        costBonus: 50,
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
        costBonus: 60,
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
      activePromotions: showcaseActive
          ? [
              ActivePromotion.fromMap({
                'id': 'promo-1',
                'type': 'showcase',
                'title': 'Витрина ATTA',
                'status': 'active',
                'costBonus': 50,
                'endsAt': '2026-06-20T10:00:00.000Z',
              }),
            ]
          : const [],
      canPromote: true,
    );
  }

  @override
  Future<Map<String, dynamic>> promoteListing(
      String listingId, String type) async {
    showcaseActive = true;
    walletService.setBalance(50);
    return {
      'message': 'Объявление добавлено в Витрину ATTA',
    };
  }
}

class _FailingWalletService extends WalletService {
  @override
  Future<Wallet> getWallet() async {
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
    viewCount: 0,
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
