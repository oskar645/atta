import 'package:atta/src/features/admin/admin_promotions_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('admin promotions screen renders', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpScreen(tester, _FakeAdminService());

    expect(find.text('Продвижение'), findsOneWidget);
    expect(find.text('Обзор продвижения'), findsOneWidget);
    expect(find.text('Покупки продвижения'), findsOneWidget);
    expect(find.text('Bike'), findsOneWidget);
    expect(find.text('Car'), findsOneWidget);
    expect(find.text('Покупки продвижения сейчас оплачиваются бонусами.'),
        findsOneWidget);

    final first = tester.getTopLeft(
      find.byKey(const ValueKey('adminPromotionCard-promo-1')),
    );
    final second = tester.getTopLeft(
      find.byKey(const ValueKey('adminPromotionCard-promo-2')),
    );
    expect(second.dx, greaterThan(first.dx));
    expect(second.dy, first.dy);
    expect(tester.takeException(), isNull);
  });

  testWidgets('promotion purchases stay compact in two columns on phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpScreen(tester, _FakeAdminService());

    final firstFinder =
        find.byKey(const ValueKey('adminPromotionCard-promo-1'));
    final secondFinder =
        find.byKey(const ValueKey('adminPromotionCard-promo-2'));
    final first = tester.getRect(firstFinder);
    final second = tester.getRect(secondFinder);

    expect(second.left, greaterThan(first.left));
    expect(second.top, first.top);
    expect(first.width, lessThan(150));
    expect(first.height, lessThan(180));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel promotion success with refresh failure is neutral',
      (tester) async {
    final admin = _FakeAdminService(refreshErrorAfterCancel: true);

    await _pumpScreen(tester, admin);

    final actions = find.byKey(
      const ValueKey('adminPromotionActions-promo-1'),
    );
    await tester.scrollUntilVisible(
      actions,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отключить'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Отменить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(admin.cancelledIds, <String>['promo-1']);
    expect(admin.promotionsCalls, 2);
    expect(find.text('Продвижение отменено'), findsNothing);
    expect(
      find.text('Действие выполнено, но список не удалось обновить'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeAdminService admin,
) async {
  await tester.pumpWidget(
    Provider<AdminService>.value(
      value: admin,
      child: const MaterialApp(
        home: AdminPromotionsScreen(),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

class _FakeAdminService extends AdminService {
  _FakeAdminService({this.refreshErrorAfterCancel = false});

  final bool refreshErrorAfterCancel;
  final List<String> cancelledIds = <String>[];
  int promotionsCalls = 0;
  bool _cancelled = false;
  bool _failNextPromotions = false;

  @override
  Future<Map<String, dynamic>> promotions({
    String? status,
    String? type,
    String? userId,
    String? listingId,
    int? limit,
    String? cursor,
    bool forceRefresh = false,
  }) async {
    promotionsCalls += 1;
    if (_failNextPromotions) {
      _failNextPromotions = false;
      throw Exception('503');
    }
    return <String, dynamic>{
      'items': _cancelled
          ? const <Map<String, dynamic>>[]
          : <Map<String, dynamic>>[
              <String, dynamic>{
                'promotionId': 'promo-1',
                'type': 'showcase',
                'status': 'active',
                'listingId': 'listing-1',
                'listingTitle': 'Bike',
                'listingPrice': 120000,
                'userName': 'Seller',
                'costBonus': 50,
                'timeRemainingSeconds': 3600,
                'impressionsCount': 10,
                'clicksCount': 2,
              },
              <String, dynamic>{
                'promotionId': 'promo-2',
                'type': 'vip',
                'status': 'expired',
                'listingId': 'listing-2',
                'listingTitle': 'Car',
                'listingPrice': 2500000,
                'userName': 'Owner',
                'costBonus': 100,
                'timeRemainingSeconds': 0,
                'impressionsCount': 30,
                'clicksCount': 5,
              },
            ],
    };
  }

  @override
  Future<Map<String, dynamic>> promotionsSummary({
    bool forceRefresh = false,
  }) async {
    return <String, dynamic>{
      'activeShowcaseCount': _cancelled ? 0 : 1,
      'activeBumpCount': 0,
      'activeVipCount': 0,
      'activeTurboCount': 0,
      'totalBonusSpentToday': 150,
      'totalBonusSpentThisMonth': 450,
      'totalShowcaseImpressions': 40,
      'totalShowcaseClicks': 7,
    };
  }

  @override
  Future<Map<String, dynamic>> cancelPromotion(String promotionId) async {
    cancelledIds.add(promotionId);
    _cancelled = true;
    _failNextPromotions = refreshErrorAfterCancel;
    return <String, dynamic>{'promotionId': promotionId};
  }
}
