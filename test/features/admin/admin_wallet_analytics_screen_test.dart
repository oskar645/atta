import 'package:atta/src/features/admin/admin_wallet_analytics_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('admin wallet analytics screen renders', (tester) async {
    await tester.pumpWidget(
      Provider<AdminService>.value(
        value: _FakeAdminWalletService(),
        child: const MaterialApp(
          home: AdminWalletAnalyticsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Кошельки и бонусы'), findsOneWidget);
    expect(find.text('Бонусная активность'), findsOneWidget);
    expect(find.text('Seller'), findsWidgets);
  });
}

class _FakeAdminWalletService extends AdminService {
  @override
  Future<Map<String, dynamic>> wallets({bool forceRefresh = false}) async {
    return <String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'userName': 'Seller',
          'userPhone': '+79990000000',
          'bonusBalance': 120,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> walletTransactions({
    String? type,
    String? reason,
    String? userId,
    bool forceRefresh = false,
  }) async {
    return <String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'userName': 'Seller',
          'reason': 'promotion_showcase',
          'amount': 50,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> bonusAnalytics({
    String? period,
    bool forceRefresh = false,
  }) async {
    return <String, dynamic>{
      'totalBonusAccrued': 25,
      'totalBonusSpent': 50,
      'spentByReason': <String, dynamic>{
        'promotion_showcase': 50,
        'promotion_bump': 0,
        'promotion_vip': 0,
        'promotion_turbo': 0,
      },
    };
  }
}
