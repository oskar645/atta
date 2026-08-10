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
  Future<Map<String, dynamic>> wallets({
    bool forceRefresh = false,
    int? limit,
    String? cursor,
  }) async {
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
    int? limit,
    String? cursor,
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

  @override
  Future<Map<String, dynamic>> referralSummary({
    String? period,
    String? from,
    String? to,
    bool forceRefresh = false,
  }) async {
    return <String, dynamic>{
      'newRegistrationsByInvite': 1,
      'rewardedReferralBonuses': 1,
      'referralPointsAwarded': 50,
      'unfinishedInvites': 0,
      'rewardFailures': 0,
      'pointsPurchased': 0,
      'pointsSpent': 0,
      'dailyBonusesAwarded': 0,
    };
  }

  @override
  Future<Map<String, dynamic>> referrals({
    String? period,
    String? from,
    String? to,
    String? search,
    String? userId,
    int? limit,
    String? cursor,
    bool forceRefresh = false,
  }) async {
    return <String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'inviter': <String, dynamic>{
            'id': 'user-1',
            'name': 'Seller',
          },
          'referralCode': 'USER1',
          'referralPoints': 50,
          'invitations': const <Map<String, dynamic>>[],
        },
      ],
      'hasMore': false,
      'nextCursor': null,
    };
  }
}
