import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminWalletAnalyticsScreen extends StatefulWidget {
  const AdminWalletAnalyticsScreen({super.key});

  @override
  State<AdminWalletAnalyticsScreen> createState() =>
      _AdminWalletAnalyticsScreenState();
}

class _AdminWalletAnalyticsScreenState
    extends State<AdminWalletAnalyticsScreen> {
  late Future<_AdminWalletAnalyticsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_AdminWalletAnalyticsData> _load() async {
    final admin = context.read<AdminService>();
    final walletsResponse = await admin.wallets();
    final transactionsResponse = await admin.walletTransactions();
    final analyticsResponse = await admin.bonusAnalytics();
    return _AdminWalletAnalyticsData(
      wallets: _extractItems(walletsResponse),
      transactions: _extractItems(transactionsResponse),
      analytics: Map<String, dynamic>.from(analyticsResponse),
    );
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Кошельки и бонусы')),
      body: FutureBuilder<_AdminWalletAnalyticsData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _AdminWalletStateView(
              message:
                  'Не удалось загрузить бонусную активность.\n${snap.error}',
              onRetry: _refresh,
            );
          }

          final data = snap.data!;
          final spentByReason = Map<String, dynamic>.from(
              data.analytics['spentByReason'] as Map? ?? const {});
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  'Бонусная активность',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Реальные платежи не подключены. Сейчас учитываются только бонусы.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _WalletSummaryCard(
                      title: 'Начислено',
                      value: '${data.analytics['totalBonusAccrued'] ?? 0}',
                    ),
                    _WalletSummaryCard(
                      title: 'Списано',
                      value: '${data.analytics['totalBonusSpent'] ?? 0}',
                    ),
                    _WalletSummaryCard(
                      title: 'Витрина',
                      value: '${spentByReason['promotion_showcase'] ?? 0}',
                    ),
                    _WalletSummaryCard(
                      title: 'Поднятие',
                      value: '${spentByReason['promotion_bump'] ?? 0}',
                    ),
                    _WalletSummaryCard(
                      title: 'VIP',
                      value: '${spentByReason['promotion_vip'] ?? 0}',
                    ),
                    _WalletSummaryCard(
                      title: 'Турбо',
                      value: '${spentByReason['promotion_turbo'] ?? 0}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Кошельки',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...data.wallets.take(5).map(
                      (wallet) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text((wallet['userName'] ?? 'Пользователь')
                              .toString()),
                          subtitle:
                              Text((wallet['userPhone'] ?? '').toString()),
                          trailing: Text('${wallet['bonusBalance'] ?? 0}'),
                        ),
                      ),
                    ),
                const SizedBox(height: 8),
                Text(
                  'Последние операции',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...data.transactions.take(8).map(
                      (item) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text((item['reason'] ?? '').toString()),
                          subtitle: Text((item['userName'] ?? '').toString()),
                          trailing: Text(
                            '${item['amount'] ?? 0}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
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

class _AdminWalletAnalyticsData {
  const _AdminWalletAnalyticsData({
    required this.wallets,
    required this.transactions,
    required this.analytics,
  });

  final List<Map<String, dynamic>> wallets;
  final List<Map<String, dynamic>> transactions;
  final Map<String, dynamic> analytics;
}

class _WalletSummaryCard extends StatelessWidget {
  const _WalletSummaryCard({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminWalletStateView extends StatelessWidget {
  const _AdminWalletStateView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
