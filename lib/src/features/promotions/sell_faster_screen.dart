import 'package:atta/src/models/active_promotion.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/models/promotion_plan.dart';
import 'package:atta/src/models/wallet.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/network_resilience.dart';
import 'package:atta/src/services/promotions_service.dart';
import 'package:atta/src/services/wallet_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:atta/src/features/wallet/wallet_screen.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SellFasterScreen extends StatefulWidget {
  const SellFasterScreen({
    super.key,
    required this.listing,
  });

  final Listing listing;

  @override
  State<SellFasterScreen> createState() => _SellFasterScreenState();
}

class _SellFasterScreenState extends State<SellFasterScreen> {
  late Future<_SellFasterData> _future;
  String? _activatingPlanType;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_SellFasterData> _load() async {
    final walletService = context.read<WalletService>();
    final promotionsService = context.read<PromotionsService>();
    Wallet? wallet;
    String? walletErrorText;
    try {
      wallet = await walletService.getWallet();
    } catch (error) {
      walletErrorText = _walletErrorText(error);
    }
    final results = await Future.wait([
      promotionsService.getPlans(),
      promotionsService.getListingPromotionState(widget.listing.id),
    ]);
    final plans = results[0] as List<PromotionPlan>;
    final promotionState = results[1] as ListingPromotionState;
    return _SellFasterData(
      wallet: wallet,
      plans: plans,
      activePromotions: promotionState.activePromotions,
      canPromote: promotionState.canPromote,
      cannotPromoteReason: promotionState.cannotPromoteReason,
      walletErrorText: walletErrorText,
    );
  }

  Future<void> _openWallet() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WalletScreen()),
    );
    if (!mounted) return;
    _reload();
  }

  Future<void> _showInsufficientBonuses(PromotionPlan plan) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Недостаточно бонусов',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Для тарифа "${plan.title}" нужно ${plan.costBonus} бонусов.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _openWallet();
                  },
                  child: const Text('Получить бонусы'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onPlanPressed(
    PromotionPlan plan,
    _SellFasterData data,
  ) async {
    final active = _findPromotion(plan.type, data.activePromotions);
    if (active != null || _activatingPlanType != null) {
      return;
    }
    if (!data.canPromote) {
      showAppSnack(
        context,
        data.cannotPromoteReason?.trim().isNotEmpty == true
            ? data.cannotPromoteReason!
            : 'Это объявление сейчас нельзя продвигать.',
        isError: true,
      );
      return;
    }

    final wallet = data.wallet;
    if (wallet != null && wallet.balance < plan.costBonus) {
      await _showInsufficientBonuses(plan);
      return;
    }

    await _activatePlan(plan, wallet);
  }

  Future<void> _activatePlan(
    PromotionPlan plan,
    Wallet? wallet,
  ) async {
    final promotionsService = context.read<PromotionsService>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => _PromotionConfirmSheet(
        listing: widget.listing,
        plan: plan,
        wallet: wallet,
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      if (kDebugMode) {
        debugPrint(
          'SellFaster activate start listingId=${widget.listing.id} planId=${plan.type} planPrice=${plan.costBonus} walletBalance=${wallet?.balance ?? 'unknown'}',
        );
      }
      setState(() {
        _activatingPlanType = plan.type;
      });
      final response =
          await promotionsService.promoteListing(widget.listing.id, plan.type);
      final promotedListingRaw = response['listing'];
      final promotedListing = promotedListingRaw is Map
          ? Listing.fromMap(
              promotedListingRaw.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : null;
      if (mounted) {
        context
            .read<ListingsService>()
            .refreshFeedAfterPromotion(listing: promotedListing);
      }
      if (kDebugMode) {
        debugPrint(
          'SellFaster activate success listingId=${widget.listing.id} planId=${plan.type} response=$response',
        );
      }
      final nextFuture = _load();
      if (mounted) {
        setState(() {
          _future = nextFuture;
        });
      }
      final nextState = await nextFuture;
      if (!mounted) return;
      final activated = _findPromotion(plan.type, nextState.activePromotions);
      if (activated == null) {
        throw const ApiException(
          'Продвижение применилось на сервере, но экран ещё не обновился. Попробуйте открыть его ещё раз.',
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_promotionSuccessText(response)),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (kDebugMode) {
        if (e is ApiException) {
          debugPrint(
            'SellFaster activate failed listingId=${widget.listing.id} planId=${plan.type} status=${e.statusCode} body=${e.details}',
          );
        } else {
          debugPrint(
            'SellFaster activate failed listingId=${widget.listing.id} planId=${plan.type} error=$e',
          );
        }
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(_promotionErrorText(e, plan))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _activatingPlanType = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Продать быстрее'),
        centerTitle: false,
      ),
      body: FutureBuilder<_SellFasterData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _sellFasterLoadError(snapshot.error!),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                SkeletonWalletCard(),
                SizedBox(height: 16),
                SkeletonAdminModerationCard(),
                SkeletonAdminModerationCard(),
                SkeletonAdminModerationCard(),
              ],
            );
          }

          final data = snapshot.data!;
          final balance = data.wallet?.balance;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                balance == null
                    ? 'Баланс временно недоступен'
                    : 'Баланс: $balance бонусов',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              if (data.walletErrorText?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  data.walletErrorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: _reload,
                    child: const Text('Повторить'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ...data.plans.map((plan) {
                final active = _findPromotion(plan.type, data.activePromotions);
                final enoughBalance =
                    balance == null || balance >= plan.costBonus;
                final isLoading = _activatingPlanType == plan.type;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  Colors.blue.withValues(alpha: 0.10),
                              child: Icon(
                                _iconForType(plan.type),
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                plan.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              '${plan.costBonus} бонусов',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(plan.description),
                        const SizedBox(height: 8),
                        Text(
                            'Длительность: ${_durationLabel(plan.durationHours)}'),
                        if (active != null && active.endsAt != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Активно до ${_formatDateTime(active.endsAt!)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: active == null && !isLoading
                                ? () => _onPlanPressed(plan, data)
                                : null,
                            child: isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    active != null
                                        ? 'Уже подключено'
                                        : !data.canPromote
                                            ? 'Подключить'
                                            : !enoughBalance
                                                ? 'Подключить'
                                                : 'Подключить',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              const Text(
                'Тарифы видны всегда, а списание происходит только после подтверждения backend.',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SellFasterData {
  const _SellFasterData({
    required this.wallet,
    required this.plans,
    required this.activePromotions,
    required this.canPromote,
    required this.cannotPromoteReason,
    this.walletErrorText,
  });

  final Wallet? wallet;
  final List<PromotionPlan> plans;
  final List<ActivePromotion> activePromotions;
  final bool canPromote;
  final String? cannotPromoteReason;
  final String? walletErrorText;
}

class _PromotionConfirmSheet extends StatelessWidget {
  const _PromotionConfirmSheet({
    required this.listing,
    required this.plan,
    required this.wallet,
  });

  final Listing listing;
  final PromotionPlan plan;
  final Wallet? wallet;

  @override
  Widget build(BuildContext context) {
    final photo = listing.firstPhotoUrl;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.type == 'showcase'
                  ? 'Добавить в Витрину ATTA?'
                  : 'Подключить ${plan.title}?',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(plan.description),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 68,
                      height: 68,
                      child: photo == null
                          ? Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: const Icon(Icons.image_outlined),
                            )
                          : CachedNetworkImage(
                              imageUrl: photo,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          listing.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text('${formatPrice(listing.price)} ₽'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Стоимость: ${plan.costBonus} бонусов'),
            const SizedBox(height: 4),
            Text(
              wallet == null
                  ? 'Баланс временно недоступен'
                  : 'Ваш баланс: ${wallet!.balance} бонусов',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Подключить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

ActivePromotion? _findPromotion(
  String type,
  List<ActivePromotion> activePromotions,
) {
  for (final promotion in activePromotions) {
    if (promotion.type == type) return promotion;
  }
  return null;
}

IconData _iconForType(String type) {
  switch (type) {
    case 'showcase':
      return Icons.auto_awesome_outlined;
    case 'bump':
      return Icons.vertical_align_top_rounded;
    case 'vip':
      return Icons.workspace_premium_outlined;
    case 'turbo':
      return Icons.local_fire_department_outlined;
    default:
      return Icons.bolt_outlined;
  }
}

String _durationLabel(int durationHours) {
  switch (durationHours) {
    case 24:
      return '24 часа';
    case 48:
      return '2 дня';
    case 96:
      return '4 дня';
    default:
      return '$durationHours часов';
  }
}

String _promotionErrorText(Object error, PromotionPlan plan) {
  if (error is ApiException) {
    if (error.isTimeout || error.isNetworkError) {
      return kNetworkVpnHintMessage;
    }
    if (error.statusCode == 500 || error.statusCode == 503) {
      return 'Сервис продвижения временно недоступен. Попробуйте позже.';
    }
    final message = error.message.trim();
    if (message.isNotEmpty) {
      final mapped = _promotionErrorTextFromString(message, plan);
      if (mapped != 'Не удалось подключить продвижение.') {
        return mapped;
      }
      return message;
    }
  }
  final errorText = error.toString();
  return _promotionErrorTextFromString(errorText, plan);
}

String _promotionErrorTextFromString(String error, PromotionPlan plan) {
  final normalized = error.toLowerCase();
  if (normalized.contains('timeout') || normalized.contains('network')) {
    return kNetworkVpnHintMessage;
  }
  if (error.trim().endsWith('.')) {
    return error.trim();
  }
  if (error.contains('Недостаточно бонусов')) {
    return 'Недостаточно бонусов';
  }
  if (error.contains('модерации')) {
    return 'Объявление пока на модерации.';
  }
  if (error.contains('Архивные объявления')) {
    return 'Архивные объявления нельзя продвигать.';
  }
  if (error.contains('Удалённые объявления')) {
    return 'Удалённые объявления нельзя продвигать.';
  }
  if (error.contains('Отклонённые объявления')) {
    return 'Отклонённые объявления нельзя продвигать.';
  }
  if (error.contains('Проданное объявление')) {
    return 'Проданное объявление нельзя продвигать.';
  }
  if (error.contains('только владельцу')) {
    return 'Продвижение доступно только владельцу объявления.';
  }
  if (error.contains('pending')) {
    return 'Объявление ещё на модерации.';
  }
  if (error.contains('archived')) {
    return 'Снятые с публикации объявления нельзя продвигать.';
  }
  if (error.contains('deleted')) {
    return 'Удалённые объявления нельзя продвигать.';
  }
  if (error.contains('rejected')) {
    return 'Отклонённые объявления нельзя продвигать.';
  }
  if (error.contains('not_owner')) {
    return 'Продвижение доступно только владельцу.';
  }
  if (error.contains('уже активна') || error.contains('уже активно')) {
    return '${plan.title} уже активно.';
  }
  if (error.contains('unpublished') || error.contains('sold')) {
    return 'Объявление снято с публикации.';
  }
  return 'Не удалось подключить продвижение.';
}

String _promotionSuccessText(Map<String, dynamic> response) {
  final message = (response['message'] ?? '').toString().toLowerCase();
  if (message.contains('уже')) {
    return 'Уже активно';
  }
  return 'Продвижение подключено';
}

String _sellFasterLoadError(Object error) {
  if (error is ApiException) {
    if (error.isTimeout || error.isNetworkError) {
      return kNetworkVpnHintMessage;
    }
    if (error.message.trim().isNotEmpty) {
      return error.message.trim();
    }
  }
  return shouldShowNetworkVpnHint(error)
      ? kNetworkVpnHintMessage
      : 'Не удалось загрузить планы продвижения.';
}

String _walletErrorText(Object error) {
  if (error is ApiException) {
    if (error.isTimeout || error.isNetworkError) {
      return 'Не удалось загрузить кошелёк. Повторите попытку.';
    }
    if (error.isUnauthorized) {
      return 'Требуется повторный вход в аккаунт.';
    }
    if (error.message.trim().isNotEmpty) {
      return error.message.trim();
    }
  }
  return shouldShowNetworkVpnHint(error)
      ? kNetworkVpnHintMessage
      : 'Не удалось загрузить кошелёк. Повторите попытку.';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$dd.$mm, $hh:$min';
}
