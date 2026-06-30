import 'package:atta/src/features/wallet/wallet_screen.dart';
import 'package:atta/src/models/wallet.dart';
import 'package:atta/src/models/wallet_transaction.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/wallet_service.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('wallet screen displays bonus balance and daily bonus state',
      (tester) async {
    final walletService = _FakeWalletService();

    await tester.pumpWidget(
      Provider<WalletService>.value(
        value: walletService,
        child: const MaterialApp(home: WalletScreen()),
      ),
    );
    expect(find.byType(SkeletonWalletCard), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('125 бонусов'), findsOneWidget);
    expect(find.text('Ежедневный бонус: +25 бонусов'), findsOneWidget);
    expect(find.text('Сегодняшний бонус уже начислен'), findsOneWidget);
    expect(find.textContaining('рубл'), findsNothing);
  });

  testWidgets('wallet screen shows retry state on error', (tester) async {
    await tester.pumpWidget(
      Provider<WalletService>.value(
        value: _FailingWalletService(),
        child: const MaterialApp(home: WalletScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Кошелёк недоступен'), findsOneWidget);
    expect(
        find.text('Не удалось загрузить кошелёк. Проверьте интернет или VPN.'),
        findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('wallet screen shows preview and opens full history',
      (tester) async {
    final walletService = _FakeWalletService.withTransactions(9);

    await tester.pumpWidget(
      Provider<WalletService>.value(
        value: walletService,
        child: const MaterialApp(home: WalletScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Смотреть все'), findsOneWidget);
    expect(find.text('Начислено 1 бонусов за вход'), findsOneWidget);
    expect(find.text('Начислено 2 бонусов за вход'), findsNothing);
    expect(find.text('Начислено 8 бонусов за вход'), findsNothing);
    expect(find.text('Начислено 9 бонусов за вход'), findsNothing);

    await tester.tap(find.text('Смотреть все'));
    await tester.pumpAndSettle();

    expect(find.text('Все операции'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Начислено 9 бонусов за вход'),
      300,
    );
    await tester.pumpAndSettle();
    expect(find.text('Начислено 9 бонусов за вход'), findsOneWidget);
  });
}

class _FakeWalletService extends WalletService {
  _FakeWalletService() : _transactions = _singleTransaction();

  _FakeWalletService.withTransactions(int count)
      : _transactions = List<WalletTransaction>.generate(
          count,
          (index) => WalletTransaction.fromMap({
            'id': 'tx-${index + 1}',
            'user_id': 'user-1',
            'wallet_id': 'wallet-1',
            'type': 'accrual',
            'amount': index + 1,
            'reason': 'daily_login_bonus',
            'created_at':
                '2026-06-${(19 - index).clamp(10, 19)}T10:00:00.000Z',
          }),
        );

  final List<WalletTransaction> _transactions;

  @override
  Future<Wallet> checkAccrual() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return Wallet.fromMap({
      'balance': 125,
      'maxBalance': 1000,
      'welcomeBonus': 100,
      'dailyBonusAmount': 25,
      'lastDailyBonusAt': '2026-06-19T10:00:00.000Z',
      'canClaimDailyBonus': false,
      'nextDailyBonusAt': '2026-06-20T00:00:00.000Z',
    });
  }

  @override
  Future<List<WalletTransaction>> getTransactions() async {
    return _transactions;
  }
}

List<WalletTransaction> _singleTransaction() {
  return [
    WalletTransaction.fromMap({
      'id': 'tx-1',
      'user_id': 'user-1',
      'wallet_id': 'wallet-1',
      'type': 'accrual',
      'amount': 25,
      'reason': 'daily_login_bonus',
      'created_at': '2026-06-19T10:00:00.000Z',
    }),
  ];
}

class _FailingWalletService extends WalletService {
  @override
  Future<Wallet> checkAccrual() async {
    throw const ApiException(
      'Не удалось загрузить кошелёк. Проверьте интернет или VPN.',
      code: 'timeout',
    );
  }
}
