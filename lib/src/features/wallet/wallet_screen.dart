import 'dart:async';

import 'package:atta/src/models/wallet.dart';
import 'package:atta/src/models/wallet_transaction.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/network_resilience.dart';
import 'package:atta/src/services/wallet_service.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void _debugWalletScreenLog(String message) {
  assert(() {
    debugPrint(message);
    return true;
  }());
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with WidgetsBindingObserver {
  static const Duration _resumeRefreshCooldown = Duration(seconds: 5);
  late Future<_WalletBundle> _future;
  DateTime? _lastRefreshAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final walletService = context.read<WalletService>();
    if (walletService.cachedWallet != null) {
      _debugWalletScreenLog(
        'Wallet cached balance shown balance=${walletService.cachedWallet!.balance}',
      );
    }
    _future = _load(walletService, forceRefresh: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_refreshBackgroundIfNeeded());
  }

  Future<_WalletBundle> _load(
    WalletService walletService, {
    required bool forceRefresh,
  }) async {
    final cachedWallet = walletService.cachedWallet;
    if (cachedWallet != null) {
      _debugWalletScreenLog(
        'Wallet cached balance shown balance=${cachedWallet.balance}',
      );
    }
    _debugWalletScreenLog('Wallet refresh start');
    try {
      final wallet =
          await walletService.checkAccrual(forceRefresh: forceRefresh);
      final transactions =
          await walletService.getTransactions(forceRefresh: forceRefresh);
      _lastRefreshAt = DateTime.now();
      _debugWalletScreenLog('Wallet refresh success balance=${wallet.balance}');
      return _WalletBundle(
        wallet: wallet,
        transactions: transactions,
      );
    } catch (error) {
      _debugWalletScreenLog('Wallet refresh error message=$error');
      if (cachedWallet != null) {
        return _WalletBundle(
          wallet: cachedWallet,
          transactions: walletService.cachedTransactions,
          transactionsErrorText: _walletTransactionsErrorText(error),
        );
      }
      rethrow;
    } finally {
      _debugWalletScreenLog('Wallet finally loading=false');
    }
  }

  Future<void> _refreshBackgroundIfNeeded() async {
    final lastRefreshAt = _lastRefreshAt;
    if (lastRefreshAt != null &&
        DateTime.now().difference(lastRefreshAt) < _resumeRefreshCooldown) {
      return;
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    final walletService = context.read<WalletService>();
    final future = _load(walletService, forceRefresh: true);
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ATTA Кошелёк'),
        centerTitle: false,
      ),
      body: FutureBuilder<_WalletBundle>(
        future: _future,
        initialData: _initialBundle(context.read<WalletService>()),
        builder: (context, snapshot) {
          if (snapshot.hasError && !snapshot.hasData) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Баланс',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(height: 10),
                      Text(_walletErrorText(snapshot.error!)),
                    ],
                  ),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                SkeletonWalletCard(),
                SizedBox(height: 20),
                SkeletonLine(width: 160, height: 18),
                SizedBox(height: 12),
                SkeletonSupportTicketRow(),
                SkeletonSupportTicketRow(),
                SkeletonSupportTicketRow(),
              ],
            );
          }

          final bundle = snapshot.data!;
          final refreshing = snapshot.connectionState != ConnectionState.done;
          final previewTransactions = _walletPreviewItems(bundle.transactions);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Баланс',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${bundle.wallet.balance} бонусов',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (refreshing) ...[
                        const SizedBox(height: 8),
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                      const SizedBox(height: 10),
                      const Text(
                        'Бонусы для продвижения',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Welcome-бонус: ${bundle.wallet.welcomeBonus} бонусов',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ежедневный бонус: +${bundle.wallet.dailyBonusAmount} бонусов',
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Приглашение друга: получите 100 бонусов, когда приглашённый пользователь зарегистрируется в ATTA.',
                      ),
                      const SizedBox(height: 4),
                      Text('Максимум: ${bundle.wallet.maxBalance} бонусов'),
                      if (bundle.wallet.lastDailyBonusAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Последний бонус за вход: ${_formatDateTime(bundle.wallet.lastDailyBonusAt!)}',
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        bundle.wallet.canClaimDailyBonus
                            ? 'Сегодняшний бонус ещё доступен'
                            : 'Сегодняшний бонус уже начислен',
                      ),
                      if (bundle.wallet.nextDailyBonusAt != null &&
                          !bundle.wallet.canClaimDailyBonus) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Следующий бонус: ${_formatDateTime(bundle.wallet.nextDailyBonusAt!)}',
                        ),
                      ],
                    ],
                  ),
                ),
                if (snapshot.hasError) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(_walletErrorText(snapshot.error!)),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'История операций',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (bundle.transactions.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _WalletTransactionsAllScreen(
                                transactions: bundle.transactions,
                              ),
                            ),
                          );
                        },
                        child: const Text('Смотреть все'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (bundle.transactionsErrorText != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bundle.transactionsErrorText!),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (bundle.transactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('Операций пока нет'),
                  )
                else
                  ...previewTransactions.map(
                    (transaction) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        title: Text(_transactionTitle(transaction)),
                        subtitle: Text(_formatDateTime(transaction.createdAt)),
                        trailing: Text(
                          '${transaction.type == 'spend' ? '-' : '+'}${transaction.amount}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: transaction.type == 'spend'
                                ? Colors.red
                                : Colors.green,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

_WalletBundle? _initialBundle(WalletService walletService) {
  final wallet = walletService.cachedWallet;
  if (wallet == null) {
    return null;
  }
  return _WalletBundle(
    wallet: wallet,
    transactions: walletService.cachedTransactions,
  );
}

String _walletErrorText(Object error) {
  if (error is ApiException) {
    if (error.isUnauthorized) {
      return 'Не удалось обновить кошелёк. Попробуйте позже.';
    }
    if (error.isTimeout || error.isNetworkError) {
      return 'Не удалось обновить кошелёк. Попробуйте позже.';
    }
    if (error.message.trim().isNotEmpty) {
      return 'Не удалось обновить кошелёк. Попробуйте позже.';
    }
  }
  return shouldShowNetworkVpnHint(error)
      ? 'Не удалось обновить кошелёк. Попробуйте позже.'
      : 'Не удалось загрузить кошелёк. Попробуйте позже.';
}

String _walletTransactionsErrorText(Object error) {
  if (error is ApiException) {
    if (error.isUnauthorized) {
      return 'Не удалось обновить кошелёк. Попробуйте позже.';
    }
    if (error.isTimeout || error.isNetworkError) {
      return 'Не удалось обновить кошелёк. Попробуйте позже.';
    }
    if (error.message.trim().isNotEmpty) {
      return 'Не удалось обновить кошелёк. Попробуйте позже.';
    }
  }
  return shouldShowNetworkVpnHint(error)
      ? 'Не удалось обновить кошелёк. Попробуйте позже.'
      : 'Не удалось обновить кошелёк. Попробуйте позже.';
}

class _WalletBundle {
  const _WalletBundle({
    required this.wallet,
    required this.transactions,
    this.transactionsErrorText,
  });

  final Wallet wallet;
  final List<WalletTransaction> transactions;
  final String? transactionsErrorText;
}

const int _walletPreviewLimit = 1;

List<WalletTransaction> _walletPreviewItems(List<WalletTransaction> items) {
  if (items.length <= _walletPreviewLimit) {
    return items;
  }
  return items.take(_walletPreviewLimit).toList(growable: false);
}

String _transactionTitle(WalletTransaction transaction) {
  final metadata = transaction.metadata;
  final customTitle =
      (metadata?['description'] ?? metadata?['title'] ?? '').toString().trim();
  if (customTitle.isNotEmpty) {
    return customTitle;
  }
  switch (transaction.reason) {
    case 'welcome_bonus':
      return 'Начислено ${transaction.amount} бонусов';
    case 'recurring_bonus':
      return 'Начислено ${transaction.amount} бонусов';
    case 'daily_login_bonus':
      return 'Начислено ${transaction.amount} бонусов за вход';
    case 'referral_inviter_bonus':
      return 'Бонус за приглашение друга';
    case 'promotion_showcase':
      return 'Списано ${transaction.amount} бонусов за Витрину ATTA';
    case 'promotion_bump':
      return 'Списано ${transaction.amount} бонусов за поднятие';
    case 'promotion_vip':
      return 'Списано ${transaction.amount} бонусов за VIP';
    case 'promotion_turbo':
      return 'Списано ${transaction.amount} бонусов за Турбо';
    default:
      return 'Операция на ${transaction.amount} бонусов';
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final yyyy = local.year.toString();
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$dd.$mm.$yyyy, $hh:$min';
}

class _WalletTransactionsAllScreen extends StatelessWidget {
  const _WalletTransactionsAllScreen({
    required this.transactions,
  });

  final List<WalletTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Все операции'),
        centerTitle: false,
      ),
      body: transactions.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Операций пока нет'),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                final transaction = transactions[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(_transactionTitle(transaction)),
                    subtitle: Text(_formatDateTime(transaction.createdAt)),
                    trailing: Text(
                      '${transaction.type == 'spend' ? '-' : '+'}${transaction.amount}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: transaction.type == 'spend'
                            ? Colors.red
                            : Colors.green,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
