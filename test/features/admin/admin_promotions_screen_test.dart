import 'package:atta/src/features/admin/admin_promotions_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('admin promotions screen renders', (tester) async {
    await tester.pumpWidget(
      Provider<AdminService>.value(
        value: _FakeAdminService(),
        child: const MaterialApp(
          home: AdminPromotionsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Продвижения'), findsOneWidget);
    expect(find.text('Bike'), findsOneWidget);
    expect(
        find.text(
            'Платежи пока не подключены. Сейчас учитываются только бонусы.'),
        findsOneWidget);
  });
}

class _FakeAdminService extends AdminService {
  @override
  Future<Map<String, dynamic>> promotions({
    String? status,
    String? type,
    String? userId,
    String? listingId,
    bool forceRefresh = false,
  }) async {
    return <String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'promotionId': 'promo-1',
          'type': 'showcase',
          'status': 'active',
          'listingId': 'listing-1',
          'listingTitle': 'Bike',
          'userName': 'Seller',
          'costBonus': 50,
          'timeRemainingSeconds': 3600,
          'impressionsCount': 10,
          'clicksCount': 2,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> promotionsSummary({
    bool forceRefresh = false,
  }) async {
    return <String, dynamic>{
      'activeShowcaseCount': 1,
      'activeBumpCount': 0,
      'activeVipCount': 0,
      'activeTurboCount': 0,
    };
  }

  @override
  Future<Map<String, dynamic>> cancelPromotion(String promotionId) async {
    return <String, dynamic>{'promotionId': promotionId};
  }
}
