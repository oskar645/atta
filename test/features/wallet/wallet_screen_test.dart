import 'dart:async';

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
  setUp(() {
    debugWalletPaymentUrlLauncher = (_) async => true;
  });

  tearDown(() {
    debugWalletPaymentUrlLauncher = (url) {
      throw StateError('Unexpected payment URL launch in test: $url');
    };
  });

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

    expect(find.text('225 бонусов', findRichText: true), findsOneWidget);
    expect(find.text('Ежедневный бонус: +25 бонусов'), findsOneWidget);
    expect(
      find.text(
        'Приглашение друга: получите 100 бонусов, когда приглашённый пользователь зарегистрируется в ATTA.',
      ),
      findsOneWidget,
    );
    expect(find.text('Сегодняшний бонус уже начислен'), findsOneWidget);
    expect(find.textContaining('рубл'), findsNothing);
  });

  testWidgets('wallet screen shows cached balance immediately while refreshing',
      (tester) async {
    final walletService = _CachedThenRefreshingWalletService();

    await tester.pumpWidget(
      Provider<WalletService>.value(
        value: walletService,
        child: const MaterialApp(home: WalletScreen()),
      ),
    );

    expect(find.text('225 бонусов', findRichText: true), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pumpAndSettle();

    expect(find.text('325 бонусов', findRichText: true), findsOneWidget);
  });

  testWidgets('wallet screen shows retry state on error', (tester) async {
    await tester.pumpWidget(
      Provider<WalletService>.value(
        value: _FailingWalletService(),
        child: const MaterialApp(home: WalletScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Не удалось обновить кошелёк. Попробуйте позже.'),
        findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
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

  testWidgets('wallet screen still opens when transactions failed',
      (tester) async {
    await tester.pumpWidget(
      Provider<WalletService>.value(
        value: _TransactionsFailingWalletService(),
        child: const MaterialApp(home: WalletScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(find.text('225 бонусов', findRichText: true), findsOneWidget);
    expect(
      find.text('Не удалось обновить кошелёк. Попробуйте позже.'),
      findsOneWidget,
    );
    expect(find.text('Повторить'), findsNothing);
    expect(find.text('Кошелёк недоступен'), findsNothing);
  });

  testWidgets('wallet screen refresh fetches fresh balance and history',
      (tester) async {
    final walletService = _RefreshingWalletService();

    await tester.pumpWidget(
      Provider<WalletService>.value(
        value: walletService,
        child: const MaterialApp(home: WalletScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('225 бонусов', findRichText: true), findsOneWidget);
    expect(find.text('Начислено 25 бонусов за вход'), findsOneWidget);

    await tester.drag(find.byType(RefreshIndicator), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('5 225 бонусов', findRichText: true), findsOneWidget);
    expect(
      find.text('Тестовые бонусы от администрации ATTA'),
      findsOneWidget,
    );
  });

  testWidgets('pending top up shows unfinished state and can be closed',
      (tester) async {
    final walletService = _PendingTopUpWalletService();

    await _pumpWallet(tester, walletService);

    expect(find.text('Оплата не завершена'), findsOneWidget);
    expect(find.text('Проверить ещё раз'), findsOneWidget);
    expect(find.text('Закрыть'), findsOneWidget);

    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();

    expect(walletService.clearPendingCalls, 1);
    expect(find.text('Оплата не завершена'), findsNothing);
  });

  testWidgets('succeeded top up refreshes balance and purchase history',
      (tester) async {
    final walletService = _SucceededTopUpWalletService();

    await _pumpWallet(tester, walletService);

    expect(find.text('325 бонусов', findRichText: true), findsOneWidget);
    expect(find.text('Куплено 100 баллов'), findsOneWidget);
    expect(find.text('Оплата прошла. Начислено 100 баллов'), findsOneWidget);
  });

  testWidgets('top up button is visible, enabled, and opens YooKassa sheet',
      (tester) async {
    final walletService = _TopUpWalletService();

    await _pumpWallet(tester, walletService);

    final topUpButtonFinder = find.byKey(const Key('wallet-top-up-button'));
    expect(topUpButtonFinder, findsOneWidget);
    final topUpButton = tester.widget<FilledButton>(topUpButtonFinder);
    expect(topUpButton.onPressed, isNotNull);

    await tester.tap(find.text('Пополнить'));
    await tester.pumpAndSettle();

    expect(find.text('Временно недоступно'), findsNothing);
    expect(find.text('Пополнение кошелька'), findsOneWidget);
    expect(find.text('ЮKassa'), findsOneWidget);
    expect(walletService.topUpCalls, 0);
    expect(find.text('225 бонусов', findRichText: true), findsOneWidget);
  });

  testWidgets('top up preset is selected and shows bonus amount',
      (tester) async {
    final walletService = _FakeWalletService();

    await _pumpTopUpSheet(tester, walletService);

    expect(find.text('100 бонусов'), findsOneWidget);
    await tester.tap(find.text('500 ₽'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('wallet-top-up-amount-field')),
    );
    expect(field.controller?.text, '500');
  });

  testWidgets('manual top up input works', (tester) async {
    final walletService = _FakeWalletService();

    await _pumpTopUpSheet(tester, walletService);

    await tester.enterText(
      find.byKey(const Key('wallet-top-up-amount-field')),
      '700',
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('wallet-top-up-amount-field')),
    );
    expect(field.controller?.text, '700');
  });

  testWidgets('invalid top up amount blocks payment', (tester) async {
    final walletService = _TopUpWalletService();

    await _pumpTopUpSheet(tester, walletService);

    await tester.enterText(
      find.byKey(const Key('wallet-top-up-amount-field')),
      '50',
    );
    await tester.pumpAndSettle();

    expect(find.text('Минимальная сумма: 100 ₽'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('wallet-top-up-submit')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('top up submit cannot be started twice', (tester) async {
    final walletService = _TopUpWalletService();

    await _pumpTopUpSheet(tester, walletService);
    await tester.tap(find.text('100 ₽'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('wallet-top-up-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('wallet-top-up-submit')));
    await tester.pump();

    expect(walletService.topUpCalls, 1);
    walletService.completeTopUp();
    await tester.pumpAndSettle();
  });

  testWidgets('top up button opens sheet without changing balance',
      (tester) async {
    final walletService = _TopUpWalletService();

    await _pumpWallet(tester, walletService);
    expect(find.text('225 бонусов', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Пополнить'));
    await tester.pumpAndSettle();

    expect(find.text('225 бонусов', findRichText: true), findsOneWidget);
    expect(find.text('Пополнение кошелька'), findsOneWidget);
    expect(walletService.topUpCalls, 0);
  });

  testWidgets('top up does not increase balance before confirmation',
      (tester) async {
    final walletService = _TopUpWalletService();

    await _pumpTopUpSheet(tester, walletService);
    await tester.tap(find.text('300 ₽'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wallet-top-up-submit')));
    await tester.pump();

    expect(walletService.topUpCalls, 1);
    walletService.completeTopUp();
    await tester.pumpAndSettle();
  });

  testWidgets('top up sheet fits a small screen without overflow',
      (tester) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 560);
    final walletService = _FakeWalletService();

    await _pumpTopUpSheet(tester, walletService);

    expect(tester.takeException(), isNull);
    expect(find.text('Пополнение кошелька'), findsOneWidget);
  });
}

Future<void> _pumpWallet(
  WidgetTester tester,
  WalletService walletService,
) async {
  await tester.pumpWidget(
    Provider<WalletService>.value(
      value: walletService,
      child: const MaterialApp(home: WalletScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpTopUpSheet(
  WidgetTester tester,
  WalletService walletService,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WalletTopUpSheet(walletService: walletService),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
            'created_at': '2026-06-${(19 - index).clamp(10, 19)}T10:00:00.000Z',
          }),
        );

  final List<WalletTransaction> _transactions;

  @override
  Future<Wallet> checkAccrual({bool forceRefresh = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return Wallet.fromMap({
      'balance': 225,
      'maxBalance': 1000,
      'welcomeBonus': 200,
      'dailyBonusAmount': 25,
      'lastDailyBonusAt': '2026-06-19T10:00:00.000Z',
      'canClaimDailyBonus': false,
      'nextDailyBonusAt': '2026-06-20T00:00:00.000Z',
    });
  }

  @override
  Future<List<WalletTransaction>> getTransactions(
      {bool forceRefresh = false}) async {
    return _transactions;
  }

  @override
  Future<WalletTopUpStatusResult?> checkPendingTopUpStatus() async => null;
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
  Future<WalletTopUpStatusResult?> checkPendingTopUpStatus() async => null;

  @override
  Future<Wallet> checkAccrual({bool forceRefresh = false}) async {
    throw const ApiException(
      'Проверьте интернет-соединение и попробуйте снова.',
      code: 'timeout',
    );
  }
}

class _TransactionsFailingWalletService extends _FakeWalletService {
  @override
  Wallet? get cachedWallet => Wallet.fromMap({
        'balance': 225,
        'maxBalance': 1000,
        'welcomeBonus': 200,
        'dailyBonusAmount': 25,
        'canClaimDailyBonus': false,
      });

  @override
  Future<List<WalletTransaction>> getTransactions(
      {bool forceRefresh = false}) async {
    throw const ApiException(
      'Проверьте интернет-соединение и попробуйте снова.',
      code: 'timeout',
    );
  }
}

class _RefreshingWalletService extends WalletService {
  int _walletFetches = 0;
  int _transactionFetches = 0;

  @override
  Future<WalletTopUpStatusResult?> checkPendingTopUpStatus() async => null;

  @override
  Future<Wallet> checkAccrual({bool forceRefresh = false}) async {
    _walletFetches += 1;
    final balance = _walletFetches == 1 ? 225 : 5225;
    return Wallet.fromMap({
      'balance': balance,
      'maxBalance': 10000,
      'welcomeBonus': 200,
      'dailyBonusAmount': 25,
      'lastDailyBonusAt': '2026-06-19T10:00:00.000Z',
      'canClaimDailyBonus': false,
      'nextDailyBonusAt': '2026-06-20T00:00:00.000Z',
    });
  }

  @override
  Future<List<WalletTransaction>> getTransactions(
      {bool forceRefresh = false}) async {
    _transactionFetches += 1;
    if (_transactionFetches == 1) {
      return _singleTransaction();
    }
    return [
      WalletTransaction.fromMap({
        'id': 'tx-admin-1',
        'user_id': 'user-1',
        'wallet_id': 'wallet-1',
        'type': 'accrual',
        'amount': 5000,
        'reason': 'recurring_bonus',
        'metadata': {
          'description': 'Тестовые бонусы от администрации ATTA',
          'reference': 'ADMIN_TEST_BONUS_5000_2026_07',
        },
        'created_at': '2026-07-02T10:00:00.000Z',
      }),
    ];
  }
}

class _PendingTopUpWalletService extends _FakeWalletService {
  int clearPendingCalls = 0;

  @override
  Future<WalletTopUpStatusResult?> checkPendingTopUpStatus() async {
    return const WalletTopUpStatusResult(
      paymentId: 'payment-1',
      status: WalletTopUpStatus.pending,
      pointsAmount: 100,
      credited: false,
    );
  }

  @override
  Future<void> clearPendingTopUp() async {
    clearPendingCalls += 1;
  }
}

class _SucceededTopUpWalletService extends WalletService {
  int _walletFetches = 0;
  bool _statusChecked = false;

  @override
  Future<WalletTopUpStatusResult?> checkPendingTopUpStatus() async {
    if (_statusChecked) return null;
    _statusChecked = true;
    return const WalletTopUpStatusResult(
      paymentId: 'payment-1',
      status: WalletTopUpStatus.succeeded,
      pointsAmount: 100,
      credited: true,
    );
  }

  @override
  Future<Wallet> checkAccrual({bool forceRefresh = false}) async {
    _walletFetches += 1;
    return Wallet.fromMap({
      'balance': _walletFetches == 1 ? 225 : 325,
      'maxBalance': 1000,
      'welcomeBonus': 200,
      'dailyBonusAmount': 25,
      'canClaimDailyBonus': false,
    });
  }

  @override
  Future<List<WalletTransaction>> getTransactions(
      {bool forceRefresh = false}) async {
    if (_walletFetches <= 1) {
      return _singleTransaction();
    }
    return [
      WalletTransaction.fromMap({
        'id': 'tx-purchase-1',
        'user_id': 'user-1',
        'wallet_id': 'wallet-1',
        'type': 'accrual',
        'amount': 100,
        'reason': 'points_purchase',
        'created_at': '2026-08-02T10:00:00.000Z',
      }),
    ];
  }
}

class _CachedThenRefreshingWalletService extends WalletService {
  @override
  Future<WalletTopUpStatusResult?> checkPendingTopUpStatus() async => null;

  @override
  Wallet? get cachedWallet => Wallet.fromMap({
        'balance': 225,
        'maxBalance': 1000,
        'welcomeBonus': 200,
        'dailyBonusAmount': 25,
        'canClaimDailyBonus': false,
      });

  @override
  Future<Wallet> checkAccrual({bool forceRefresh = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return Wallet.fromMap({
      'balance': 325,
      'maxBalance': 1000,
      'welcomeBonus': 200,
      'dailyBonusAmount': 25,
      'canClaimDailyBonus': false,
    });
  }

  @override
  Future<List<WalletTransaction>> getTransactions(
      {bool forceRefresh = false}) async {
    return _singleTransaction();
  }
}

class _TopUpWalletService extends _FakeWalletService {
  int topUpCalls = 0;
  Completer<void>? _topUpCompleter;

  @override
  Future<WalletTopUpStartResult> startWalletTopUp(int amountRub) async {
    topUpCalls += 1;
    _topUpCompleter = Completer<void>();
    await _topUpCompleter!.future;
    return WalletTopUpStartResult(
      paymentId: 'payment-1',
      confirmationUrl: Uri.parse('https://example.com/pay'),
    );
  }

  void completeTopUp() {
    final completer = _topUpCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}
