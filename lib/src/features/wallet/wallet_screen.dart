import 'dart:async';

import 'package:atta/src/models/wallet.dart';
import 'package:atta/src/models/wallet_transaction.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/network_resilience.dart';
import 'package:atta/src/services/wallet_service.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

void _debugWalletScreenLog(String message) {
  assert(() {
    debugPrint(message);
    return true;
  }());
}

typedef WalletPaymentUrlLauncher = Future<bool> Function(Uri url);

Future<bool> _launchWalletPaymentUrl(Uri url) {
  return launchUrl(url, mode: LaunchMode.externalApplication);
}

WalletPaymentUrlLauncher debugWalletPaymentUrlLauncher =
    _launchWalletPaymentUrl;

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with WidgetsBindingObserver {
  static const Duration _resumeRefreshCooldown = Duration(seconds: 5);
  static const bool _topUpEnabled = true;
  late Future<_WalletBundle> _future;
  DateTime? _lastRefreshAt;
  bool _checkingTopUp = false;
  String? _topUpStatusText;
  bool _topUpCanClose = false;

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
    unawaited(_checkPendingTopUpStatus());
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
    await _checkPendingTopUpStatus();
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

  Future<void> _checkPendingTopUpStatus() async {
    if (_checkingTopUp) return;
    setState(() {
      _checkingTopUp = true;
      _topUpCanClose = false;
      _topUpStatusText = 'Проверяем оплату...';
    });
    try {
      final result =
          await context.read<WalletService>().checkPendingTopUpStatus();
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _topUpStatusText = null;
          _topUpCanClose = false;
        });
        return;
      }
      switch (result.status) {
        case WalletTopUpStatus.succeeded:
          setState(() {
            _topUpStatusText = null;
            _topUpCanClose = false;
          });
          await _refresh();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Оплата прошла. Начислено ${_formatInt(result.pointsAmount)} баллов',
              ),
            ),
          );
          break;
        case WalletTopUpStatus.canceled:
          setState(() {
            _topUpStatusText = null;
            _topUpCanClose = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Оплата не завершена')),
          );
          break;
        case WalletTopUpStatus.pending:
          setState(() {
            _topUpStatusText = 'Оплата не завершена';
            _topUpCanClose = true;
          });
          break;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _topUpStatusText = 'Не удалось проверить оплату. Попробуйте ещё раз.';
        _topUpCanClose = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _checkingTopUp = false;
        });
      }
    }
  }

  Future<void> _closePendingTopUpNotice() async {
    await context.read<WalletService>().clearPendingTopUp();
    if (!mounted) return;
    setState(() {
      _topUpStatusText = null;
      _topUpCanClose = false;
    });
  }

  Future<void> _openTopUpSheet() async {
    await showWalletTopUpSheet(
      context,
      onPaymentStarted: _checkPendingTopUpStatus,
    );
  }

  void _showTopUpUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Временно недоступно')),
    );
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
                if (_topUpStatusText != null) ...[
                  _TopUpStatusBanner(
                    text: _topUpStatusText!,
                    checking: _checkingTopUp,
                    onCheck: _checkPendingTopUpStatus,
                    onClose: _topUpCanClose ? _closePendingTopUpNotice : null,
                  ),
                  const SizedBox(height: 12),
                ],
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: RichText(
                                maxLines: 1,
                                text: TextSpan(
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  children: [
                                    TextSpan(
                                      text:
                                          '${_formatInt(bundle.wallet.balance)} ',
                                      style: const TextStyle(fontSize: 30),
                                    ),
                                    const TextSpan(
                                      text: 'бонусов',
                                      style: TextStyle(fontSize: 24),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: _topUpEnabled ? null : _showTopUpUnavailable,
                            child: FilledButton(
                              key: const Key('wallet-top-up-button'),
                              onPressed: _topUpEnabled ? _openTopUpSheet : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                disabledForegroundColor: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text('Пополнить'),
                            ),
                          ),
                        ],
                      ),
                      if (bundle.wallet.maxBalance > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Максимум: ${_formatInt(bundle.wallet.maxBalance)} бонусов',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
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

Future<void> showWalletTopUpSheet(
  BuildContext context, {
  WalletService? walletService,
  VoidCallback? onPaymentStarted,
}) async {
  final service = walletService ?? context.read<WalletService>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => WalletTopUpSheet(
      walletService: service,
      onPaymentStarted: onPaymentStarted,
    ),
  );
}

class WalletTopUpSheet extends StatefulWidget {
  const WalletTopUpSheet({
    super.key,
    required this.walletService,
    this.onPaymentStarted,
  });

  final WalletService walletService;
  final VoidCallback? onPaymentStarted;

  @override
  State<WalletTopUpSheet> createState() => _WalletTopUpSheetState();
}

class _WalletTopUpSheetState extends State<WalletTopUpSheet> {
  static const int _minAmount = 100;
  static const int _maxAmount = 150000;
  static const List<int> _presetAmounts = <int>[100, 300, 500, 1000, 1500];

  final TextEditingController _amountController = TextEditingController();
  int? _selectedPreset;
  bool _submitting = false;
  String? _errorText;

  int? get _amount {
    final text = _amountController.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  bool get _canSubmit => !_submitting && _validateAmount(_amount) == null;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _selectPreset(int amount) {
    setState(() {
      _selectedPreset = amount;
      _amountController.text = amount.toString();
      _errorText = null;
    });
  }

  void _handleManualInput(String value) {
    final amount = int.tryParse(value.trim());
    setState(() {
      if (_selectedPreset != null && _selectedPreset != amount) {
        _selectedPreset = null;
      }
      _errorText = _validateAmount(amount);
    });
  }

  String? _validateAmount(int? amount) {
    if (amount == null) {
      return 'Введите сумму пополнения';
    }
    if (amount < _minAmount) {
      return 'Минимальная сумма: $_minAmount ₽';
    }
    if (amount > _maxAmount) {
      return 'Максимальная сумма: ${_formatInt(_maxAmount)} ₽';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final amount = _amount;
    final validationError = _validateAmount(amount);
    if (validationError != null) {
      setState(() {
        _errorText = validationError;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      final result = await widget.walletService.startWalletTopUp(amount!);
      final opened =
          await debugWalletPaymentUrlLauncher(result.confirmationUrl);
      if (!mounted) return;
      if (!opened) {
        setState(() {
          _errorText = 'Не удалось открыть страницу оплаты.';
        });
        return;
      }
      widget.onPaymentStarted?.call();
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Не удалось начать оплату. Попробуйте позже.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Пополнение кошелька',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 22),
                TextField(
                  key: const Key('wallet-top-up-amount-field'),
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: _handleManualInput,
                  decoration: InputDecoration(
                    hintText: 'Введите сумму',
                    suffixText: '₽',
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    errorText: _errorText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final amount in _presetAmounts)
                      _TopUpPresetChip(
                        amount: amount,
                        selected: _selectedPreset == amount,
                        onPressed: () => _selectPreset(amount),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const _PaymentMethodTile(),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('wallet-top-up-submit'),
                  onPressed: _canSubmit ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: scheme.surfaceContainerHighest,
                    disabledForegroundColor: scheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Перейти к оплате',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopUpStatusBanner extends StatelessWidget {
  const _TopUpStatusBanner({
    required this.text,
    required this.checking,
    required this.onCheck,
    this.onClose,
  });

  final String text;
  final bool checking;
  final VoidCallback onCheck;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: checking
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : const Icon(Icons.payments_rounded, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (onClose != null || !checking) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: checking ? null : onCheck,
                    child: const Text('Проверить ещё раз'),
                  ),
                  if (onClose != null)
                    TextButton(
                      onPressed: checking ? null : onClose,
                      child: const Text('Закрыть'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TopUpPresetChip extends StatelessWidget {
  const _TopUpPresetChip({
    required this.amount,
    required this.selected,
    required this.onPressed,
  });

  final int amount;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = selected ? Colors.blue : scheme.outlineVariant;
    final textColor = selected ? Colors.blue : scheme.onSurface;

    return SizedBox(
      width: 104,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: textColor,
          backgroundColor:
              selected ? Colors.blue.withValues(alpha: 0.08) : scheme.surface,
          side: BorderSide(color: borderColor, width: selected ? 1.6 : 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_formatInt(amount)} ₽',
              maxLines: 1,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${_formatInt(amount)} бонусов',
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                color: selected ? Colors.blue : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blue, width: 1.4),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.credit_card_rounded, color: Colors.blue),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ЮKassa',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text('Банковская карта, СБП'),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: Colors.blue),
        ],
      ),
    );
  }
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
    case 'signup_bonus':
    case 'welcome_bonus':
      return 'Начислено ${transaction.amount} бонусов';
    case 'recurring_bonus':
      return 'Начислено ${transaction.amount} бонусов';
    case 'daily_login_bonus':
      return 'Начислено ${transaction.amount} бонусов за вход';
    case 'referral_inviter_bonus':
      return 'Бонус за приглашение друга';
    case 'points_purchase':
      return 'Куплено ${transaction.amount} баллов';
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

String _formatInt(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i += 1) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(' ');
    }
  }
  return buffer.toString();
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
