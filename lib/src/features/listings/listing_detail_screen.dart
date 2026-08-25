import 'dart:async';

import 'package:atta/src/features/auth/login_screen.dart';
import 'package:atta/src/features/inbox/chat_screen.dart';
import 'package:atta/src/features/listings/edit_listing_screen.dart';
import 'package:atta/src/features/listings/listing_archive_flow.dart';
import 'package:atta/src/features/listings/photo_viewer_screen.dart';
import 'package:atta/src/features/promotions/listing_stats_screen.dart';
import 'package:atta/src/features/promotions/sell_faster_screen.dart';
import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/features/reviews/seller_reviews_screen.dart';
import 'package:atta/src/features/wallet/wallet_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/deep_link_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/reports_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/wallet_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/utils/listing_share_files.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:atta/src/utils/share_texts.dart';
import 'package:atta/src/utils/vehicle_specs.dart';
import 'package:atta/src/widgets/app_error_view.dart';
import 'package:atta/src/widgets/admin_copy_user_id_button.dart';
import 'package:atta/src/widgets/listing_promotion_badges.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:atta/src/widgets/listing_card.dart';
import 'package:atta/src/widgets/listing_price_row.dart';
import 'package:atta/src/widgets/presence_badge.dart';
import 'package:atta/src/widgets/remote_avatar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:atta/src/services/network_resilience.dart';

class ListingDetailScreen extends StatefulWidget {
  final String listingId;
  final bool openReviewsOnStart;
  final String initialReviewId;

  const ListingDetailScreen({
    super.key,
    required this.listingId,
    this.openReviewsOnStart = false,
    this.initialReviewId = '',
  });

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  bool _viewCounted = false;
  bool _loginRedirectScheduled = false;
  bool _openedInitialReviews = false;
  bool _shareInFlight = false;

  bool _showFullDescription = false;
  bool _showAllSpecs = false;
  Future<Listing?>? _listingFuture;
  Future<dynamic>? _walletFuture;

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('ru', timeago.RuMessages());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listingFuture ??= _loadListingFuture(context.read<ListingsService>());
    _walletFuture ??=
        context.read<WalletService>().maybeCheckAccrualOncePerSession();
    if (widget.openReviewsOnStart && !_openedInitialReviews) {
      _openedInitialReviews = true;
      unawaited(_openInitialReviewsIfNeeded());
    }
  }

  Future<void> _openInitialReviewsIfNeeded() async {
    Listing? listing;
    try {
      listing = await _listingFuture;
    } catch (_) {
      return;
    }
    if (!mounted || listing == null) {
      return;
    }
    final resolvedListing = listing;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SellerReviewsScreen(
            sellerId: resolvedListing.ownerId,
            sellerName: resolvedListing.ownerName,
            listingId: resolvedListing.id,
            initialReviewId: widget.initialReviewId,
          ),
        ),
      );
    });
  }

  String _formatExactTime(DateTime? value) {
    if (value == null) return '';
    try {
      final dt = value.toLocal();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } catch (_) {
      return '';
    }
  }

  String _publishedTimeText(DateTime? value) {
    if (value == null) return '';
    final relative = timeago.format(value, locale: 'ru');
    final exactTime = _formatExactTime(value);
    if (exactTime.isEmpty) return relative;
    return '$relative · $exactTime';
  }

  String _sellerInitial(String name) {
    final t = name.trim();
    if (t.isEmpty) return 'U';
    return t.characters.first.toUpperCase();
  }

  String _deliveryLabel(String key) {
    switch (key) {
      case 'cdek':
        return 'СДЭК';
      case 'ozon':
        return 'Ozon';
      case 'pek':
        return 'ПЭК';
      case 'pickup':
        return 'Самовывоз';
      default:
        return key;
    }
  }

  String _statusTitle(String status) {
    switch (status) {
      case 'pending':
        return 'На модерации';
      case 'approved':
        return 'Одобрено';
      case 'rejected':
        return 'Отклонено';
      default:
        return status.isEmpty ? 'Одобрено' : status;
    }
  }

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'sold':
        return Colors.green;
      case 'deleted':
        return Colors.red;
      case 'archived':
        return Colors.blueGrey;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_top;
      case 'approved':
        return Icons.verified;
      case 'rejected':
        return Icons.block;
      case 'sold':
        return Icons.check_circle_outline;
      case 'deleted':
        return Icons.admin_panel_settings_outlined;
      case 'archived':
        return Icons.archive_outlined;
      default:
        return Icons.info_outline;
    }
  }

  String _promotionTitle(Listing listing) {
    final promotion = listing.primaryActivePromotion;
    if (promotion == null) return '';
    return promotion.title;
  }

  String _cannotPromoteText(String? reason) {
    switch (reason) {
      case 'pending':
        return 'Доступно после модерации';
      case 'archived':
        return 'Снятые с публикации объявления нельзя продвигать';
      case 'deleted':
        return 'Удалённые объявления нельзя продвигать';
      case 'rejected':
        return 'Отклонённые объявления нельзя продвигать';
      case 'sold':
      case 'unpublished':
        return 'Объявление снято с публикации';
      case 'not_owner':
        return 'Продвижение доступно только владельцу';
      default:
        return 'Проверьте статус объявления';
    }
  }

  Stream<bool> _streamIsAdmin(String uid) {
    return context.read<AdminService>().streamIsAdmin(uid);
  }

  Future<Listing?> _loadListingFuture(ListingsService listings) {
    final cached = listings.peekListingById(widget.listingId);
    if (cached != null) {
      return listings
          .refreshListingById(widget.listingId)
          .then<Listing?>((fresh) => fresh ?? cached);
    }
    return listings.getListingById(widget.listingId);
  }

  void _reloadListing() {
    setState(() {
      _listingFuture = _loadListingFuture(context.read<ListingsService>());
    });
  }

  Future<void> _openReportDialog({
    required String listingId,
    required String listingOwnerId,
  }) async {
    final me = context.read<AuthService>().currentUser!;
    final reports = context.read<ReportsService>();

    final reasons = <String>[
      'Запрещённый товар',
      'Мошенничество',
      'Спам / реклама',
      'Оскорбления',
      'Фейк / обман',
      'Другое',
    ];

    String reason = reasons.first;
    final c = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Пожаловаться'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: reason,
              items: reasons
                  .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                  .toList(),
              onChanged: (v) => reason = v ?? reason,
              decoration: const InputDecoration(labelText: 'Причина'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Комментарий (не обязательно)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Отправить')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await reports.reportListing(
        listingId: listingId,
        listingOwnerId: listingOwnerId,
        reporterId: me.uid,
        reason: reason,
        comment: c.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Жалоба отправлена')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _shareAnnouncement(
    String title, {
    required int price,
    required String city,
    required List<String> photoUrls,
  }) async {
    if (_shareInFlight) return;
    _shareInFlight = true;
    final shareText = buildListingShareText(
      listingId: widget.listingId,
      title: title,
      price: price,
      city: city,
    );
    final message = shareText.text;
    if (message == null) {
      if (mounted) {
        showAppSnack(
          context,
          shareText.errorMessage ?? appInstallUrlNotConfiguredMessage,
          isError: true,
        );
      }
      _shareInFlight = false;
      return;
    }

    try {
      List<XFile> files = const <XFile>[];
      try {
        files = await buildListingShareFiles(
          photoUrls: photoUrls,
          downloadPhoto: _downloadSharePhoto,
        );
      } catch (_) {
        files = const <XFile>[];
      }

      await SharePlus.instance.share(
        ShareParams(
          files: files.isEmpty ? null : files,
          text: message,
          subject: 'Объявление в ATTA',
        ),
      );
    } catch (e) {
      if (mounted) {
        showAppSnack(
          context,
          'Не удалось открыть меню отправки. Попробуйте ещё раз.',
          isError: true,
        );
      }
    } finally {
      _shareInFlight = false;
    }
  }

  Future<Uint8List?> _downloadSharePhoto(String url) async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return null;
    }
    return res.bodyBytes;
  }

  Future<void> _deleteListingAsAdmin({
    required Listing listing,
    required AdminService adminService,
    required ListingsService listingsSvc,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить объявление?'),
        content: const Text(
          'Это действие скроет объявление из приложения.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await adminService.deleteListing(
        listing.id,
        reason: 'Удалено администратором.',
        moderationNote: 'Это действие выполнено администратором.',
      );
      final rawListing = response['listing'];
      if (rawListing is Map) {
        final updated = Listing.fromMap(
          rawListing.map((key, value) => MapEntry(key.toString(), value)),
        );
        listingsSvc.applyExternalListingUpdate(updated);
      }

      if (!mounted) return;
      showAppSnack(
        context,
        'Объявление удалено',
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            'Admin delete listing failed listing=${listing.id} error=$e');
      }
      if (!mounted) return;
      showAppSnack(
        context,
        _adminDeleteErrorText(e),
        isError: true,
      );
    }
  }

  List<MapEntry<String, String>> _carSpecsEntries(Listing listing) {
    final items = <MapEntry<String, String>>[
      if ((listing.oemPartNumber ?? '').trim().isNotEmpty)
        MapEntry('Номер детали (OEM)', listing.oemPartNumber!.trim()),
    ];
    final car = listing.car;
    if (car == null) return items;

    items.addAll([
      MapEntry('Марка', car.brand),
      MapEntry('Модель', car.model),
      if (car.generation.trim().isNotEmpty)
        MapEntry('Поколение', car.generation),
      if (car.year != null) MapEntry('Год', '${car.year}'),
      if (car.mileageKm != null) MapEntry('Пробег', '${car.mileageKm} км'),
      if ((car.bodyType ?? '').trim().isNotEmpty)
        MapEntry('Кузов', car.bodyType!.trim()),
      if ((car.fuel ?? '').trim().isNotEmpty)
        MapEntry('Топливо', car.fuel!.trim()),
      if (car.engineVolume != null)
        MapEntry('Двигатель', formatEngineVolume(car.engineVolume)),
      if (car.powerHp != null) MapEntry('Мощность', '${car.powerHp} л.с.'),
      if ((car.transmission ?? '').trim().isNotEmpty)
        MapEntry('Коробка', car.transmission!.trim()),
      if ((car.drive ?? '').trim().isNotEmpty)
        MapEntry('Привод', car.drive!.trim()),
      if ((car.condition ?? '').trim().isNotEmpty)
        MapEntry('Состояние', car.condition!.trim()),
      if ((car.color ?? '').trim().isNotEmpty)
        MapEntry('Цвет', car.color!.trim()),
      if ((car.pts ?? '').trim().isNotEmpty) MapEntry('ПТС', car.pts!.trim()),
      if (car.owners != null) MapEntry('Владельцев', '${car.owners}'),
      if (car.isCleared != null)
        MapEntry('Растаможен', car.isCleared! ? 'Да' : 'Нет'),
      if ((car.vin ?? '').trim().isNotEmpty) MapEntry('VIN', car.vin!.trim()),
      if ((car.note ?? '').trim().isNotEmpty)
        MapEntry('Примечание', car.note!.trim()),
    ]);

    return items;
  }

  Widget _buildDescriptionSection(BuildContext context, String description) {
    final text = description.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    final isLong = text.length > 180;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Описание',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          Text(
            text,
            maxLines: (!_showFullDescription && isLong) ? 4 : null,
            overflow: (!_showFullDescription && isLong)
                ? TextOverflow.ellipsis
                : null,
          ),
          if (isLong) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () =>
                  setState(() => _showFullDescription = !_showFullDescription),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _showFullDescription ? 'Скрыть' : 'Показать полностью',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCarSpecsSection(
      BuildContext context, List<MapEntry<String, String>> specs) {
    if (specs.isEmpty) return const SizedBox.shrink();

    final visible = _showAllSpecs ? specs : specs.take(3).toList();
    final hasMore = specs.length > 3;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Характеристики',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          ...visible.map((e) => _kv(e.key, e.value)),
          if (hasMore) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => _showAllSpecs = !_showAllSpecs),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _showAllSpecs
                      ? 'Скрыть характеристики'
                      : 'Показать все (${specs.length})',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomActions({
    required BuildContext context,
    required bool canContact,
    required String status,
    required Listing listing,
    required String myUid,
    required ChatService chats,
    required String sellerName,
    required String sellerAvatar,
  }) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
              top: BorderSide(
                  color:
                      Theme.of(context).dividerColor.withValues(alpha: 0.2))),
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: (!canContact || listing.phone.trim().isEmpty)
                    ? null
                    : () async {
                        final normalizedPhone =
                            normalizeRuPhoneForApi(listing.phone);
                        final uri = Uri(
                          scheme: 'tel',
                          path: normalizedPhone.isEmpty
                              ? listing.phone.trim()
                              : '+$normalizedPhone',
                        );
                        await launchUrl(uri);
                      },
                icon: const Icon(Icons.call),
                label: Text(status == 'approved' ? 'Позвонить' : 'Недоступно'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: (!canContact || listing.ownerId == myUid)
                    ? null
                    : () async {
                        final chatId = await chats.getOrCreateChat(
                          listingId: listing.id,
                          listingTitle: listing.title,
                          buyerId: myUid,
                          sellerId: listing.ownerId,
                        );

                        if (!context.mounted) return;

                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              chatId: chatId,
                              initialOtherUserName: sellerName,
                              initialOtherUserAvatar: sellerAvatar,
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(
                  listing.ownerId == myUid
                      ? 'Это ваше объявление'
                      : status == 'approved'
                          ? 'Написать'
                          : 'Недоступно',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<AuthService>().currentUser!;
    final favs = context.read<FavoritesService>();
    final chats = context.read<ChatService>();
    final history = context.read<ListingHistoryService>();
    final listingsSvc = context.read<ListingsService>();
    final presence = context.read<PresenceService>();

    return StreamBuilder<bool>(
      stream: _streamIsAdmin(me.uid),
      builder: (context, adminSnap) {
        final isAdmin = adminSnap.data == true;

        return FutureBuilder<Listing?>(
          future: _listingFuture,
          builder: (context, snap) {
            final cachedListing = listingsSvc.peekListingById(widget.listingId);
            final listing = snap.data ?? cachedListing;
            if (snap.hasError && listing == null) {
              final error = snap.error!;
              final auth = context.read<AuthService>();
              if (error is ApiException &&
                  error.isUnauthorized &&
                  !auth.isAuthenticated &&
                  !_loginRedirectScheduled) {
                _loginRedirectScheduled = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen(),
                    ),
                  );
                });
              }
              return Scaffold(
                appBar: AppBar(),
                body: AppErrorView(
                  message: _listingOpenErrorText(error),
                  onRetry: () async {
                    _loginRedirectScheduled = false;
                    _reloadListing();
                  },
                ),
              );
            }
            if (listing == null) {
              return Scaffold(
                appBar: AppBar(),
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: const [
                    SkeletonBox(height: 260, radius: 20),
                    SizedBox(height: 16),
                    SkeletonLine(width: 220, height: 24),
                    SizedBox(height: 12),
                    SkeletonLine(width: 120, height: 28),
                    SizedBox(height: 16),
                    SkeletonLine(height: 14),
                    SizedBox(height: 8),
                    SkeletonLine(height: 14),
                    SizedBox(height: 8),
                    SkeletonLine(width: 180, height: 14),
                    SizedBox(height: 24),
                    SkeletonProfileHeader(),
                    SizedBox(height: 24),
                    SkeletonListingGrid(
                      itemCount: 2,
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                    ),
                  ],
                ),
              );
            }
            final status = listing.status;
            final rejectionReason = listing.rejectionReason.trim();

            final isOwner = listing.ownerId == me.uid;
            final canSee = (status == 'approved') || isOwner || isAdmin;
            final canEdit =
                isOwner && (status == 'approved' || status == 'rejected');
            if (!canSee) {
              return Scaffold(
                appBar: AppBar(),
                body: const Center(
                  child: Text('Объявление не найдено или больше недоступно'),
                ),
              );
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(
                context
                    .read<DeepLinkService>()
                    .clearPendingListingIdIfMatches(widget.listingId),
              );
            });

            final canContact = (status == 'approved') || isOwner || isAdmin;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_viewCounted) return;
              if (status != 'approved') return;
              _viewCounted = true;
              history.markViewed(listing.id);
              if (listing.ownerId != me.uid) {
                listingsSvc.incrementView(listing.id);
              }
            });

            final deliveryNames = listing.delivery.entries
                .where((e) => e.value == true)
                .map((e) => _deliveryLabel(e.key))
                .toList();

            final specs = _carSpecsEntries(listing);

            final sellerName = listing.ownerName.trim().isEmpty
                ? 'Пользователь'
                : listing.ownerName.trim();
            const sellerAvatar = '';

            return Scaffold(
              appBar: AppBar(
                centerTitle: false,
                actions: [
                  IconButton(
                    tooltip: 'Поделиться',
                    onPressed: () => _shareAnnouncement(
                      listing.title,
                      price: listing.price,
                      city: listing.cityShort,
                      photoUrls: listing.photoUrls,
                    ),
                    icon: const Icon(Icons.share_outlined),
                  ),
                  FavoriteToggleButton(
                    favoritesService: favs,
                    userId: me.uid,
                    listingId: listing.id,
                    onError: (error) {
                      if (!context.mounted) return;
                      showAppSnack(
                        context,
                        'Не удалось изменить избранное: $error',
                        isError: true,
                      );
                    },
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  EditListingScreen(listingId: listing.id)),
                        );
                      } else if (v == 'report') {
                        await _openReportDialog(
                          listingId: listing.id,
                          listingOwnerId: listing.ownerId,
                        );
                      } else if (v == 'delete_admin') {
                        await _deleteListingAsAdmin(
                          listing: listing,
                          adminService: context.read<AdminService>(),
                          listingsSvc: listingsSvc,
                        );
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (canEdit)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Редактировать'),
                            ],
                          ),
                        ),
                      if (!isOwner)
                        const PopupMenuItem(
                          value: 'report',
                          child: Row(
                            children: [
                              Icon(Icons.flag_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Пожаловаться'),
                            ],
                          ),
                        ),
                      if (isAdmin)
                        const PopupMenuItem(
                          value: 'delete_admin',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 18),
                              SizedBox(width: 8),
                              Text('Удалить объявление'),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              bottomNavigationBar: _buildBottomActions(
                context: context,
                canContact: canContact,
                status: status,
                listing: listing,
                myUid: me.uid,
                chats: chats,
                sellerName: sellerName,
                sellerAvatar: sellerAvatar,
              ),
              body: ListView(
                controller: _scrollController,
                physics:
                    _listingDetailScrollPhysics(Theme.of(context).platform),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                children: [
                  if (status != 'approved')
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: _statusColor(context, status)
                            .withValues(alpha: 0.12),
                        border: Border.all(
                            color: _statusColor(context, status)
                                .withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          Icon(_statusIcon(status),
                              color: _statusColor(context, status)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_statusTitle(status)}${status == 'pending' ? ' — проверяем объявление' : ''}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (status != 'approved' &&
                      status != 'pending' &&
                      listing.archiveNote.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Text(
                        listing.archiveNote,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  if (status == 'rejected' &&
                      rejectionReason.isNotEmpty &&
                      (isOwner || isAdmin)) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.red.withValues(alpha: 0.08),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        'Причина отклонения: $rejectionReason',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  if (status != 'approved') const SizedBox(height: 12),
                  _Photos(photoUrls: listing.photoUrls),
                  const SizedBox(height: 14),
                  Text(
                    listing.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ListingPriceRow(
                      listing: listing,
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (listing.hasVipPromotion) ...[
                    const SizedBox(height: 8),
                    Text(
                      'VIP-объявление',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: vipBorderColor(context),
                      ),
                    ),
                  ],
                  if (listing.primaryActivePromotion != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.blue.withValues(alpha: 0.08),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Активно: ${_promotionTitle(listing)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (listing.primaryActivePromotion?.endsAt !=
                              null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Действует до: ${_formatExactTime(listing.primaryActivePromotion!.endsAt)} ${listing.primaryActivePromotion!.endsAt!.day.toString().padLeft(2, '0')}.${listing.primaryActivePromotion!.endsAt!.month.toString().padLeft(2, '0')}',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (listing.car?.mileageKm != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.speed_outlined,
                            size: 18,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(width: 6),
                        Text(
                          'Пробег: ${listing.car!.mileageKm} км',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if ((listing.clothesSize ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.straighten_outlined,
                            size: 18,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(width: 6),
                        Text(
                          'Размер: ${listing.clothesSize!.trim()}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (isOwner) ...[
                    FutureBuilder<dynamic>(
                      future: _walletFuture,
                      builder: (context, walletSnap) {
                        final walletService = context.read<WalletService>();
                        final cachedWallet = walletService.cachedWallet;
                        final wallet = walletSnap.data ?? cachedWallet;
                        final balance = wallet?.balance;
                        final canShowSellFaster = listing.status == 'approved';
                        final walletError =
                            walletSnap.hasError && cachedWallet == null;
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Управление объявлением',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (listing.hasShowcasePromotion)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.blue.withValues(alpha: 0.10),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: const Text(
                                        'Витрина',
                                        style: TextStyle(
                                          color: Colors.blue,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: canShowSellFaster
                                    ? FilledButton.icon(
                                        onPressed: () async {
                                          final updated =
                                              await Navigator.of(context)
                                                  .push<bool>(
                                            MaterialPageRoute(
                                              builder: (_) => SellFasterScreen(
                                                listing: listing,
                                              ),
                                            ),
                                          );
                                          if (updated == true && mounted) {
                                            setState(() {
                                              _walletFuture = context
                                                  .read<WalletService>()
                                                  .getWallet();
                                              _listingFuture = context
                                                  .read<ListingsService>()
                                                  .getListingById(
                                                    widget.listingId,
                                                  );
                                            });
                                          }
                                        },
                                        icon: const Icon(Icons.bolt_outlined),
                                        label: const Text('Продать быстрее'),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              if (canShowSellFaster) const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ListingStatsScreen(
                                              listingId: listing.id,
                                              initialFavoriteCount:
                                                  listing.favoriteCount,
                                            ),
                                          ),
                                        );
                                      },
                                      child: const Text('Статистика'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: status == 'approved'
                                          ? () async {
                                              final updated =
                                                  await runListingArchiveFlow(
                                                context,
                                                listingId: listing.id,
                                                listingsService: listingsSvc,
                                              );
                                              if (updated && mounted) {
                                                setState(() {});
                                              }
                                            }
                                          : null,
                                      child: const Text('Снять с публикации'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                balance != null
                                    ? 'Доступно: $balance бонусов'
                                    : walletError
                                        ? 'Не удалось загрузить кошелёк'
                                        : 'Загрузка бонусов...',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (walletError) ...[
                                const SizedBox(height: 6),
                                OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      _walletFuture = context
                                          .read<WalletService>()
                                          .getWallet();
                                    });
                                  },
                                  child: const Text('Повторить'),
                                ),
                              ],
                              if (!listing.canPromote && canShowSellFaster) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _cannotPromoteText(
                                    listing.cannotPromoteReason,
                                  ),
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const WalletScreen(),
                                        ),
                                      );
                                    },
                                    child: const Text('Получить бонусы'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  _SellerReviewsOverviewSection(
                    sellerId: listing.ownerId,
                    sellerName: sellerName,
                    listingId: listing.id,
                    reviewsService: context.read<ReviewsService>(),
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (ctx) {
                      final cityShort = listing.cityShort.trim();
                      final address = listing.cityFull.trim();
                      final hasAddress = address.isNotEmpty;
                      final color = Theme.of(ctx).colorScheme.primary;
                      final mapLabel =
                          cityShort.isNotEmpty ? cityShort : address;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap:
                                hasAddress ? () => _openInMaps(address) : null,
                            borderRadius: BorderRadius.circular(8),
                            child: Text(
                              hasAddress
                                  ? mapLabel
                                  : '\u0413\u043e\u0440\u043e\u0434 \u043d\u0435 \u0443\u043a\u0430\u0437\u0430\u043d',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: hasAddress ? color : null,
                                decoration: hasAddress
                                    ? TextDecoration.underline
                                    : null,
                              ),
                            ),
                          ),
                          if (address.isNotEmpty && address != mapLabel) ...[
                            const SizedBox(height: 4),
                            Text(
                              address,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(ctx).colorScheme.outline,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Theme.of(context).colorScheme.surface,
                      border: Border.all(
                          color: Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.schedule,
                            size: 18,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(width: 6),
                        Text(_publishedTimeText(listing.createdAt),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.outline)),
                        const Spacer(),
                        Icon(Icons.remove_red_eye_outlined,
                            size: 18,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(width: 6),
                        Text('${listing.viewCount}',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.outline)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (deliveryNames.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(
                            color: Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.18)),
                      ),
                      child: Text('Доставка: ${deliveryNames.join(', ')}'),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(
                            color: Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.18)),
                      ),
                      child: Text('Доставка: не указано',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.outline)),
                    ),
                  const SizedBox(height: 12),
                  if (specs.isNotEmpty) _buildCarSpecsSection(context, specs),
                  if (specs.isNotEmpty) const SizedBox(height: 12),
                  _buildDescriptionSection(context, listing.description),
                  const SizedBox(height: 12),
                  _SellerInfoSection(
                    sellerId: listing.ownerId,
                    initialSellerName: sellerName,
                    initialSellerAvatar: sellerAvatar,
                    phone: listing.phone,
                    phoneHidden: listing.phoneHidden,
                    presence: presence,
                    profileService: context.read<ProfileService>(),
                    sellerInitialBuilder: _sellerInitial,
                  ),
                  const SizedBox(height: 12),
                  _SimilarListingsSection(
                    baseListing: listing,
                    currentUserId: me.uid,
                    listingsSvc: listingsSvc,
                    favs: favs,
                    history: history,
                    reviews: context.read<ReviewsService>(),
                    scrollController: _scrollController,
                    platform: Theme.of(context).platform,
                  ),
                  const SizedBox(height: 12),
                  if (listing.ownerId == me.uid)
                    Text(
                      status == 'approved'
                          ? 'Это ваше объявление. Сообщения доступны покупателям.'
                          : 'Это ваше объявление. Сейчас оно: ${_statusTitle(status)}.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

ScrollPhysics? _listingDetailScrollPhysics(TargetPlatform platform) {
  if (platform == TargetPlatform.iOS) {
    return const ClampingScrollPhysics();
  }
  return null;
}

String _adminDeleteErrorText(Object error) {
  if (error is ApiException && error.message.trim().isNotEmpty) {
    return error.message.trim();
  }
  return 'Не удалось удалить объявление. Попробуйте ещё раз.';
}

String _listingOpenErrorText(Object error) {
  if (shouldShowNetworkVpnHint(error)) {
    return kNetworkVpnHintMessage;
  }
  if (error is ApiException) {
    if (error.isUnauthorized) {
      return 'Войдите снова, чтобы открыть это объявление';
    }
    if (error.isNotFound || error.statusCode == 403) {
      return 'Объявление не найдено или больше недоступно';
    }
    if (error.message.trim().isNotEmpty) {
      return error.message.trim();
    }
  }
  return 'Не удалось открыть объявление.';
}

class _SellerReviewsOverviewSection extends StatefulWidget {
  const _SellerReviewsOverviewSection({
    required this.sellerId,
    required this.sellerName,
    required this.listingId,
    required this.reviewsService,
  });

  final String sellerId;
  final String sellerName;
  final String listingId;
  final ReviewsService reviewsService;

  @override
  State<_SellerReviewsOverviewSection> createState() =>
      _SellerReviewsOverviewSectionState();
}

class _SellerReviewsOverviewSectionState
    extends State<_SellerReviewsOverviewSection> {
  List<Map<String, dynamic>> _rows = const <Map<String, dynamic>>[];
  Object? _error;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _rows = widget.reviewsService.peekSellerReviews(widget.sellerId);
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final rows = await widget.reviewsService.refreshSellerReviews(
        widget.sellerId,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.18),
          ),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonLine(width: 90, height: 18),
            SizedBox(height: 14),
            SkeletonLine(width: 140, height: 16),
            SizedBox(height: 14),
            SkeletonLine(height: 48),
          ],
        ),
      );
    }

    if (_error != null && _rows.isEmpty) {
      return _InlineSectionError(
        title: 'Не удалось загрузить отзывы',
        onRetry: _loadReviews,
      );
    }

    double sum = 0;
    var count = 0;
    for (final row in _rows) {
      final rating = row['rating'];
      if (rating is num) {
        sum += rating.toDouble();
        count += 1;
      }
    }
    final average = count == 0 ? 0.0 : (sum / count);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.star, size: 18, color: Colors.amber),
                const SizedBox(width: 6),
                Text(
                  average.toStringAsFixed(1),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                Text(
                  '($count)',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                if (_isLoading) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
          if (_error != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Не удалось обновить отзывы',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadReviews,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 1),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Icon(
              Icons.rate_review_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Отзывы продавца'),
            subtitle:
                count == 0 ? const Text('У продавца пока нет отзывов') : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SellerReviewsScreen(
                    sellerId: widget.sellerId,
                    sellerName: widget.sellerName,
                    listingId: widget.listingId,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SellerInfoSection extends StatefulWidget {
  const _SellerInfoSection({
    required this.sellerId,
    required this.initialSellerName,
    required this.initialSellerAvatar,
    required this.phone,
    required this.phoneHidden,
    required this.presence,
    required this.profileService,
    required this.sellerInitialBuilder,
  });

  final String sellerId;
  final String initialSellerName;
  final String initialSellerAvatar;
  final String phone;
  final bool phoneHidden;
  final PresenceService presence;
  final ProfileService profileService;
  final String Function(String name) sellerInitialBuilder;

  @override
  State<_SellerInfoSection> createState() => _SellerInfoSectionState();
}

class _SellerInfoSectionState extends State<_SellerInfoSection> {
  Map<String, dynamic> _profile = const <String, dynamic>{};
  Object? _error;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profileService.getCachedProfile(widget.sellerId);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile = await widget.profileService.getProfile(widget.sellerId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  String get _sellerName {
    final row = _profile;
    final displayName =
        (row['display_name'] ?? row['name'] ?? '').toString().trim();
    if (displayName.isNotEmpty) return displayName;
    final fallback = widget.initialSellerName.trim();
    return fallback.isEmpty ? 'Пользователь' : fallback;
  }

  String get _sellerAvatar {
    final row = _profile;
    final avatar =
        (row['avatar_url'] ?? row['photo_url'] ?? '').toString().trim();
    if (avatar.isNotEmpty) return avatar;
    return widget.initialSellerAvatar.trim();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SellerPublicProfileScreen(
              sellerId: widget.sellerId,
              initialSellerName: _sellerName,
              initialSellerAvatar: _sellerAvatar,
              initialSellerPhone: widget.phone,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Продавец',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                if (_isLoading) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Не удалось обновить данные продавца',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadProfile,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                StreamBuilder<bool>(
                  stream: widget.presence.streamIsOnline(widget.sellerId),
                  builder: (context, onlineSnap) {
                    final isOnline = onlineSnap.data == true;
                    return PresenceBadge(
                      isOnline: isOnline,
                      child: RemoteAvatar(
                        imageUrl: _sellerAvatar,
                        fallbackText: widget.sellerInitialBuilder(_sellerName),
                        radius: 22,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _sellerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          AdminCopyUserIdButton(userId: widget.sellerId),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.phoneHidden
                            ? 'Телефон: скрыт'
                            : 'Телефон: ${formatRussianPhone(widget.phone)}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Открыть профиль продавца',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimilarListingsSection extends StatefulWidget {
  final Listing baseListing;
  final String currentUserId;
  final ListingsService listingsSvc;
  final FavoritesService favs;
  final ListingHistoryService history;
  final ReviewsService reviews;
  final ScrollController scrollController;
  final TargetPlatform platform;

  const _SimilarListingsSection({
    required this.baseListing,
    required this.currentUserId,
    required this.listingsSvc,
    required this.favs,
    required this.history,
    required this.reviews,
    required this.scrollController,
    required this.platform,
  });

  @override
  State<_SimilarListingsSection> createState() =>
      _SimilarListingsSectionState();
}

class _SimilarListingsSectionState extends State<_SimilarListingsSection> {
  final GlobalKey _sectionKey = GlobalKey();

  List<Listing> _items = const <Listing>[];
  Object? _error;
  bool _isLoading = false;
  bool _preserveEmptyExtentAtBottom = false;
  bool _wasAtBottomWhenLoadingStarted = false;
  double _preservedEmptyExtent = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_releasePreservedExtentAfterScrollUp);
    _loadSimilar();
  }

  @override
  void dispose() {
    widget.scrollController
        .removeListener(_releasePreservedExtentAfterScrollUp);
    super.dispose();
  }

  Future<void> _loadSimilar() async {
    if (_isLoading) return;
    _wasAtBottomWhenLoadingStarted = _isIosDetailBottomEdge();
    _debugLogBottomState('setState loading');
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await widget.listingsSvc.getSimilarListings(
        widget.baseListing,
      );
      if (!mounted) return;
      final preserveEmptyExtent =
          items.isEmpty && _wasAtBottomWhenLoadingStarted;
      final currentHeight = _sectionKey.currentContext?.size?.height ?? 300;
      _debugLogBottomState('setState success count=${items.length}');
      setState(() {
        _items = items;
        _isLoading = false;
        _preserveEmptyExtentAtBottom = preserveEmptyExtent;
        _preservedEmptyExtent =
            preserveEmptyExtent ? currentHeight : _preservedEmptyExtent;
      });
      _debugLogAfterLayout('after success');
    } catch (error) {
      if (!mounted) return;
      _debugLogBottomState('setState error');
      setState(() {
        _error = error;
        _isLoading = false;
        _preserveEmptyExtentAtBottom = false;
      });
      _debugLogAfterLayout('after error');
    }
  }

  bool _isIosDetailBottomEdge() {
    if (widget.platform != TargetPlatform.iOS) {
      return false;
    }
    final position = _scrollPositionOrNull();
    if (position == null) return false;
    return position.pixels >= position.maxScrollExtent - 0.5 ||
        position.extentAfter <= 0.5;
  }

  void _releasePreservedExtentAfterScrollUp() {
    if (!_preserveEmptyExtentAtBottom) {
      return;
    }
    final position = _scrollPositionOrNull();
    if (position == null || position.extentAfter <= 24) {
      return;
    }
    setState(() {
      _preserveEmptyExtentAtBottom = false;
    });
    _debugLogAfterLayout('released preserved empty extent');
  }

  ScrollPosition? _scrollPositionOrNull() {
    if (!mounted || !widget.scrollController.hasClients) {
      return null;
    }
    return widget.scrollController.position;
  }

  void _debugLogBottomState(String reason) {
    assert(() {
      final mediaQueryElement =
          context.getElementForInheritedWidgetOfExactType<MediaQuery>();
      final mediaQuery = mediaQueryElement?.widget is MediaQuery
          ? mediaQueryElement!.widget as MediaQuery
          : null;
      final position = _scrollPositionOrNull();
      final height = _sectionKey.currentContext?.size?.height;
      debugPrint(
        'ATTA listing detail bottom: $reason '
        'pixels=${position?.pixels.toStringAsFixed(1)} '
        'max=${position?.maxScrollExtent.toStringAsFixed(1)} '
        'after=${position?.extentAfter.toStringAsFixed(1)} '
        'safeBottom=${mediaQuery?.data.padding.bottom.toStringAsFixed(1)} '
        'viewBottom=${mediaQuery?.data.viewPadding.bottom.toStringAsFixed(1)} '
        'similarHeight=${height?.toStringAsFixed(1)} '
        'similarCount=${_items.length} '
        'loading=$_isLoading '
        'preserveEmpty=$_preserveEmptyExtentAtBottom',
      );
      return true;
    }());
  }

  void _debugLogAfterLayout(String reason) {
    assert(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _debugLogBottomState(reason);
      });
      return true;
    }());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _items.isEmpty) {
      return Column(
        key: _sectionKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Похожие объявления',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 270,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 2,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, __) => Container(
                width: 190,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 120, radius: 12),
                    SizedBox(height: 12),
                    SkeletonLine(width: 120, height: 14),
                    SizedBox(height: 8),
                    SkeletonLine(width: 90, height: 18),
                    SizedBox(height: 8),
                    SkeletonLine(width: 60, height: 12),
                    SizedBox(height: 8),
                    SkeletonLine(width: 80, height: 12),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_error != null && _items.isEmpty) {
      return KeyedSubtree(
        key: _sectionKey,
        child: _InlineSectionError(
          title: 'Не удалось загрузить похожие объявления',
          onRetry: _loadSimilar,
        ),
      );
    }

    if (_items.isEmpty) {
      if (_preserveEmptyExtentAtBottom && _preservedEmptyExtent > 0) {
        return SizedBox(
          key: _sectionKey,
          height: _preservedEmptyExtent,
        );
      }
      return KeyedSubtree(
        key: _sectionKey,
        child: const SizedBox.shrink(),
      );
    }

    return Column(
      key: _sectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Похожие объявления',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Не удалось обновить похожие объявления',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
              TextButton(
                onPressed: _loadSimilar,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ] else
          const SizedBox(height: 10),
        SizedBox(
          height: 270,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = _items[index];
              return SizedBox(
                width: 190,
                child: FavoriteListingCard(
                  listing: item,
                  favoritesService: widget.favs,
                  userId: widget.currentUserId,
                  isSeen: widget.history.hasViewed(item.id),
                  reviews: widget.reviews,
                  onError: (error) {
                    if (!context.mounted) return;
                    showAppSnack(
                      context,
                      'Не удалось изменить избранное: $error',
                      isError: true,
                    );
                  },
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ListingDetailScreen(listingId: item.id),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _InlineSectionError extends StatelessWidget {
  const _InlineSectionError({
    required this.title,
    required this.onRetry,
  });

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}

Future<void> _openInMaps(String address) async {
  final query = Uri.encodeComponent(address.trim());
  if (query.isEmpty) return;

  final geo = Uri.parse('geo:0,0?q=$query');
  if (await canLaunchUrl(geo)) {
    await launchUrl(geo, mode: LaunchMode.externalApplication);
    return;
  }

  final google =
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
  if (await canLaunchUrl(google)) {
    await launchUrl(google, mode: LaunchMode.externalApplication);
    return;
  }

  final yandex = Uri.parse('https://yandex.ru/maps/?text=$query');
  if (await canLaunchUrl(yandex)) {
    await launchUrl(yandex, mode: LaunchMode.externalApplication);
    return;
  }

  final osm = Uri.parse('https://www.openstreetmap.org/search?query=$query');
  await launchUrl(osm, mode: LaunchMode.externalApplication);
}

Widget _kv(String k, String v) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
            width: 120,
            child:
                Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(width: 10),
        Expanded(child: Text(v)),
      ],
    ),
  );
}

class _Photos extends StatefulWidget {
  final List<String> photoUrls;
  const _Photos({required this.photoUrls});

  @override
  State<_Photos> createState() => _PhotosState();
}

class _PhotosState extends State<_Photos> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final photoUrls = widget.photoUrls;

    if (photoUrls.isEmpty) {
      return Container(
        height: 260,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: const Center(
            child: Icon(Icons.image_not_supported_outlined, size: 48)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: photoUrls.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PhotoViewerScreen(
                          photoUrls: photoUrls, initialIndex: i),
                    ),
                  );
                },
                child: MediaPreviewBox(
                  imageUrl: photoUrls[i],
                  categoryHint: 'listings',
                  borderRadius: 0,
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_page + 1}/${photoUrls.length}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
