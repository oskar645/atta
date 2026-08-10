import 'dart:async';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/wallet_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/wallet_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('wallet accrue check runs at most once per active session', () async {
    final firstApi = _FakeWalletApi();
    final firstService = WalletService(api: firstApi);
    firstService.activateSession('user-1');

    await firstService.maybeCheckAccrualOncePerSession();
    await firstService.maybeCheckAccrualOncePerSession();

    expect(firstApi.checkAccrualCalls, 1);

    final secondApi = _FakeWalletApi();
    final secondService = WalletService(api: secondApi);
    secondService.activateSession('user-1');

    await secondService.maybeCheckAccrualOncePerSession();

    expect(secondApi.checkAccrualCalls, 1);
    expect(secondApi.getWalletCalls, 0);
  });

  test('wallet refresh uses single-flight', () async {
    final api = _FakeWalletApi();
    final service = WalletService(api: api);
    service.activateSession('user-1');

    final completer = Completer<Map<String, dynamic>>();
    api.checkAccrualHandler = () => completer.future;

    final first = service.checkAccrual(forceRefresh: true);
    final second = service.checkAccrual(forceRefresh: true);

    expect(api.checkAccrualCalls, 1);

    completer.complete(_walletMap(balance: 225));

    final wallets = await Future.wait([first, second]);
    expect(wallets[0].balance, 225);
    expect(wallets[1].balance, 225);
  });

  test('accrual snack amount comes from backend response', () async {
    final api = _FakeWalletApi();
    final service = WalletService(api: api);
    service.activateSession('user-1');
    api.checkAccrualHandler = () async => <String, dynamic>{
          'awarded': true,
          'amount': 15,
          'wallet': _walletMap(balance: 115),
        };

    await service.checkAccrual(forceRefresh: true);

    expect(service.lastAccrualAwarded, isTrue);
    expect(service.lastAccrualAmount, 15);
  });

  test('network error does not clear old balance', () async {
    final api = _FakeWalletApi();
    final service = WalletService(api: api);
    service.activateSession('user-1');

    await service.getWallet();
    expect(service.cachedWallet?.balance, 10);

    api.checkAccrualHandler = () async => throw const ApiException(
          'Проверьте интернет-соединение и попробуйте снова.',
          code: 'timeout',
        );

    await expectLater(
      service.checkAccrual(forceRefresh: true),
      throwsA(isA<ApiException>()),
    );
    expect(service.cachedWallet?.balance, 10);
  });

  test('wallet cache is separated by currentUserId', () async {
    final api = _FakeWalletApi();
    final service = WalletService(api: api);

    service.activateSession('user-1');
    api.checkAccrualHandler = () async => _walletMap(balance: 111);
    await service.checkAccrual(forceRefresh: true);
    expect(service.cachedWallet?.balance, 111);

    service.activateSession('user-2');
    api.checkAccrualHandler = () async => _walletMap(balance: 222);
    await service.checkAccrual(forceRefresh: true);
    expect(service.cachedWallet?.balance, 222);

    service.activateSession('user-1');
    expect(service.cachedWallet?.balance, 111);
  });

  test('local phone date is not used to skip daily check-in', () async {
    final api = _FakeWalletApi();
    final service = WalletService(api: api);
    service.activateSession('user-1');

    final wallet = await service.maybeCheckAccrualOncePerSession();

    expect(api.checkAccrualCalls, 1);
    expect(api.getWalletCalls, 0);
    expect(wallet?.balance, 10);
  });

  test('pending top up status stays local until user closes it', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'wallet_pending_yookassa_payment_id': 'payment-1',
    });
    final api = _FakeWalletApi();
    api.paymentStatusHandler = () async => <String, dynamic>{
          'paymentId': 'payment-1',
          'status': 'pending',
          'pointsAmount': 100,
          'credited': false,
        };
    final service = WalletService(api: api);

    final result = await service.checkPendingTopUpStatus();
    expect(result?.status, WalletTopUpStatus.pending);
    expect(api.paymentStatusCalls, 1);

    await service.checkPendingTopUpStatus();
    expect(api.paymentStatusCalls, 2);

    await service.clearPendingTopUp();
    expect(await service.checkPendingTopUpStatus(), isNull);
  });

  test('succeeded top up refreshes wallet and transactions from backend',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'wallet_pending_yookassa_payment_id': 'payment-1',
    });
    final api = _FakeWalletApi();
    api.getWalletHandler = () async => _walletMap(balance: 325);
    api.getTransactionsHandler = () async => <String, dynamic>{
          'wallet': _walletMap(balance: 325),
          'items': <Map<String, dynamic>>[
            {
              'id': 'tx-purchase-1',
              'user_id': 'user-1',
              'wallet_id': 'wallet-1',
              'type': 'accrual',
              'amount': 100,
              'reason': 'points_purchase',
              'created_at': '2026-08-02T10:00:00.000Z',
            },
          ],
        };
    api.paymentStatusHandler = () async => <String, dynamic>{
          'paymentId': 'payment-1',
          'status': 'succeeded',
          'pointsAmount': 100,
          'credited': true,
          'balance': 325,
        };
    final service = WalletService(api: api);
    service.activateSession('user-1');

    final result = await service.checkPendingTopUpStatus();

    expect(result?.status, WalletTopUpStatus.succeeded);
    expect(service.cachedWallet?.balance, 325);
    expect(service.cachedTransactions.single.reason, 'points_purchase');
    expect(api.getWalletCalls, 1);
    expect(api.getTransactionsCalls, 1);
    expect(await service.checkPendingTopUpStatus(), isNull);
  });

  test('top up status check uses single-flight per payment id', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'wallet_pending_yookassa_payment_id': 'payment-1',
    });
    final api = _FakeWalletApi();
    final completer = Completer<Map<String, dynamic>>();
    api.paymentStatusHandler = () => completer.future;
    final service = WalletService(api: api);

    final first = service.checkPendingTopUpStatus();
    final second = service.checkPendingTopUpStatus();
    await Future<void>.delayed(Duration.zero);
    expect(api.paymentStatusCalls, 1);

    completer.complete(<String, dynamic>{
      'paymentId': 'payment-1',
      'status': 'pending',
      'pointsAmount': 100,
      'credited': false,
    });

    final results = await Future.wait([first, second]);
    expect(results[0]?.status, WalletTopUpStatus.pending);
    expect(results[1]?.status, WalletTopUpStatus.pending);
  });
}

Map<String, dynamic> _walletMap({required int balance}) {
  return <String, dynamic>{
    'balance': balance,
    'max_balance': null,
    'welcome_bonus': 500,
    'daily_bonus_amount': 15,
    'can_claim_daily_bonus': false,
    'days_until_next_accrual': 0,
    'seconds_until_next_accrual': 0,
  };
}

class _FakeWalletApi extends WalletApi {
  _FakeWalletApi() : super(ApiClient(tokenStorage: TokenStorage()));

  int checkAccrualCalls = 0;
  int getWalletCalls = 0;
  int getTransactionsCalls = 0;
  int paymentStatusCalls = 0;
  Future<Map<String, dynamic>> Function()? checkAccrualHandler;
  Future<Map<String, dynamic>> Function()? getWalletHandler;
  Future<Map<String, dynamic>> Function()? getTransactionsHandler;
  Future<Map<String, dynamic>> Function()? paymentStatusHandler;

  @override
  Future<Map<String, dynamic>> getWallet() async {
    getWalletCalls += 1;
    final handler = getWalletHandler;
    if (handler != null) {
      return handler();
    }
    return _walletMap(balance: 10);
  }

  @override
  Future<Map<String, dynamic>> getTransactions() async {
    getTransactionsCalls += 1;
    final handler = getTransactionsHandler;
    if (handler != null) {
      return handler();
    }
    return <String, dynamic>{
      'wallet': _walletMap(balance: 10),
      'items': const <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> checkAccrual() async {
    checkAccrualCalls += 1;
    final handler = checkAccrualHandler;
    if (handler != null) {
      return handler();
    }
    return <String, dynamic>{
      'wallet': _walletMap(balance: 10),
    };
  }

  @override
  Future<Map<String, dynamic>> getPaymentStatus(String paymentId) async {
    paymentStatusCalls += 1;
    final handler = paymentStatusHandler;
    if (handler != null) {
      return handler();
    }
    return <String, dynamic>{
      'paymentId': paymentId,
      'status': 'pending',
      'pointsAmount': 100,
      'credited': false,
    };
  }
}
