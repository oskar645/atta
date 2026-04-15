import 'package:cached_network_image/cached_network_image.dart';
import 'package:atta/src/features/inbox/chat_screen.dart';
import 'package:atta/src/features/listings/edit_listing_screen.dart';
import 'package:atta/src/features/listings/photo_viewer_screen.dart';
import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/features/reviews/seller_reviews_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:atta/src/widgets/listing_card.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

class ListingDetailScreen extends StatefulWidget {
  final String listingId;
  const ListingDetailScreen({super.key, required this.listingId});

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  bool _viewCounted = false;

  bool _showFullDescription = false;
  bool _showAllSpecs = false;

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('ru', timeago.RuMessages());
  }

  SupabaseClient get _sb => Supabase.instance.client;

  // ✅ имя продавца
  String _displayNameFromUserRow(Map<String, dynamic> u) {
    String pick(dynamic v) => (v ?? '').toString().trim();

    final d1 = pick(u['display_name']);
    if (d1.isNotEmpty) return d1;

    final d2 = pick(u['name']);
    if (d2.isNotEmpty) return d2;

    final d3 = pick(u['displayName']);
    if (d3.isNotEmpty) return d3;

    return 'Пользователь';
  }

  // ✅ аватар продавца
  String _avatarUrlFromUserRow(Map<String, dynamic> u) {
    String pick(dynamic v) => (v ?? '').toString().trim();

    final a1 = pick(u['avatar_url']);
    if (a1.isNotEmpty) return a1;

    final a2 = pick(u['avatarUrl']);
    if (a2.isNotEmpty) return a2;

    final a3 = pick(u['photo_url']);
    if (a3.isNotEmpty) return a3;

    final a4 = pick(u['photoUrl']);
    if (a4.isNotEmpty) return a4;

    return '';
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

  Stream<bool> _streamIsAdmin(String uid) {
    return _sb
        .from('admin_users')
        .stream(primaryKey: ['uid'])
        .eq('uid', uid)
        .map((rows) {
          if (rows.isEmpty) return false;
          final r = rows.first;
          return (r['is_admin'] == true) || (r['isAdmin'] == true);
        });
  }

  Stream<Map<String, dynamic>> _streamSellerProfile(String sellerId) {
    return _sb.from('users').stream(primaryKey: ['id']).eq('id', sellerId).map(
        (rows) => rows.isNotEmpty
            ? Map<String, dynamic>.from(rows.first)
            : <String, dynamic>{});
  }

  Stream<List<Map<String, dynamic>>> _streamSellerReviews(String sellerId) {
    return _sb
        .from('reviews')
        .stream(primaryKey: ['id'])
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Stream<Map<String, dynamic>?> _streamListingRow(String listingId) {
    return _sb
        .from('listings')
        .stream(primaryKey: ['id'])
        .eq('id', listingId)
        .map((rows) =>
            rows.isEmpty ? null : Map<String, dynamic>.from(rows.first));
  }

  Future<void> _openReportDialog({
    required String listingId,
    required String listingOwnerId,
  }) async {
    final me = context.read<AuthService>().currentUser!;

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
      await _sb.from('reports').insert({
        'listing_id': listingId,
        'listing_owner_id': listingOwnerId,
        'reporter_id': me.uid,
        'reason': reason,
        'comment': c.text.trim(),
        'status': 'open',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

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
    String listingId,
    String title, {
    String? photoUrl,
  }) async {
    final shareLink = 'https://atta.app/listing/$listingId';

    final message = 'Посмотри это объявление в ATTA:\n$shareLink';

    try {
      final url = (photoUrl ?? '').trim();
      if (url.isNotEmpty) {
        final res = await http.get(Uri.parse(url));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          await SharePlus.instance.share(
            ShareParams(
              files: [
                XFile.fromData(
                  res.bodyBytes,
                  name: 'listing.jpg',
                  mimeType: 'image/jpeg',
                ),
              ],
              text: message,
              subject: title,
            ),
          );
          return;
        }
      }

      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: title,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _deleteListingAsAdmin({
    required Listing listing,
    required ListingsService listingsSvc,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить объявление'),
        content: const Text(
          'Удалить это объявление для всех пользователей?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Да'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await listingsSvc.archiveListing(
        listingId: listing.id,
        status: 'deleted',
        note: 'Удалено администратором.',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Объявление удалено')),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  List<MapEntry<String, String>> _carSpecsEntries(Listing listing) {
    if (listing.car == null) return [];
    final car = listing.car!;

    final items = <MapEntry<String, String>>[
      MapEntry('Марка', car.brand),
      MapEntry('Модель', car.model),
      if (car.generation.trim().isNotEmpty)
        MapEntry('Поколение', car.generation),
      MapEntry('Год', '${car.year}'),
      MapEntry('Пробег', '${car.mileageKm} км'),
      MapEntry('Кузов', car.bodyType),
      MapEntry('Топливо', car.fuel),
      MapEntry('Двигатель', '${car.engineVolume.toStringAsFixed(1)} л'),
      MapEntry('Мощность', '${car.powerHp} л.с.'),
      MapEntry('Коробка', car.transmission),
      MapEntry('Привод', car.drive),
      MapEntry('Состояние', car.condition),
      MapEntry('Цвет', car.color),
      if (car.owners != null) MapEntry('Владельцев', '${car.owners}'),
      if (car.isCleared != null)
        MapEntry('Растаможен', car.isCleared! ? 'Да' : 'Нет'),
      if ((car.vin ?? '').trim().isNotEmpty) MapEntry('VIN', car.vin!.trim()),
      if ((car.note ?? '').trim().isNotEmpty)
        MapEntry('Примечание', car.note!.trim()),
    ];

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
        border:
            Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
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
        border:
            Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
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
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2))),
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: (!canContact || listing.phone.trim().isEmpty)
                    ? null
                    : () async {
                        final uri = Uri(scheme: 'tel', path: listing.phone);
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
                label: Text(status == 'approved' ? 'Написать' : 'Недоступно'),
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

        return StreamBuilder<Map<String, dynamic>?>(
          stream: _streamListingRow(widget.listingId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            final row = snap.data;
            if (row == null) {
              return Scaffold(
                  appBar: AppBar(),
                  body: const Center(child: Text('Объявление удалено')));
            }

            final listing = Listing.fromMap(row);

            final status = (row['status'] ?? 'approved').toString();
            final rejectionReason =
                (row['rejection_reason'] ?? row['rejectionReason'] ?? '')
                    .toString()
                    .trim();

            final isOwner = listing.ownerId == me.uid;
            final canSee = (status == 'approved') || isOwner || isAdmin;
            final canEdit = isOwner && (status == 'approved' || status == 'rejected');
            if (!canSee) {
              return Scaffold(
                appBar: AppBar(),
                body: const Center(
                    child: Text('Объявление на модерации или недоступно')),
              );
            }

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

            return StreamBuilder<Set<String>>(
              stream: favs.streamFavoriteIds(me.uid),
              builder: (context, favSnap) {
                final isFav = (favSnap.data ?? <String>{}).contains(listing.id);

                return StreamBuilder<Map<String, dynamic>>(
                  stream: _streamSellerProfile(listing.ownerId),
                  builder: (context, sellerSnap) {
                    final u = sellerSnap.data ?? const <String, dynamic>{};
                    final sellerName = _displayNameFromUserRow(u);
                    final sellerAvatar = _avatarUrlFromUserRow(u);

                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: false,
                        title: Text(listing.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        actions: [
                          IconButton(
                            tooltip: 'Поделиться',
                            onPressed: () => _shareAnnouncement(
                              listing.id,
                              listing.title,
                              photoUrl: listing.photoUrls.isEmpty
                                  ? null
                                  : listing.photoUrls.first,
                            ),
                            icon: const Icon(Icons.share_outlined),
                          ),
                          IconButton(
                            onPressed: () => favs.toggleFavorite(
                              uid: me.uid,
                              listingId: listing.id,
                              makeFavorite: !isFav,
                            ),
                            icon: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              color: isFav
                                  ? Colors.red
                                  : Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'edit') {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => EditListingScreen(
                                          listingId: listing.id)),
                                );
                              } else if (v == 'report') {
                                await _openReportDialog(
                                  listingId: listing.id,
                                  listingOwnerId: listing.ownerId,
                                );
                              } else if (v == 'delete_admin') {
                                await _deleteListingAsAdmin(
                                  listing: listing,
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
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800),
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
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
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),

                          _Photos(photoUrls: listing.photoUrls),
                          const SizedBox(height: 14),

                          Text(
                            '${formatPrice(listing.price)} ₽',
                            style: const TextStyle(
                                fontSize: 26, fontWeight: FontWeight.w800),
                          ),

                          if (listing.car != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.speed_outlined,
                                    size: 18,
                                    color:
                                        Theme.of(context).colorScheme.outline),
                                const SizedBox(width: 6),
                                Text(
                                  'Пробег: ${listing.car!.mileageKm} км',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 10),

                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: Theme.of(context).colorScheme.surface,
                              border: Border.all(
                                  color: Theme.of(context)
                                      .dividerColor
                                      .withValues(alpha: 0.18)),
                            ),
                            child: Column(
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 12, 12, 8),
                                  child:
                                      StreamBuilder<List<Map<String, dynamic>>>(
                                    stream:
                                        _streamSellerReviews(listing.ownerId),
                                    builder: (context, rSnap) {
                                      final rows = rSnap.data ??
                                          const <Map<String, dynamic>>[];
                                      double sum = 0;
                                      int cnt = 0;

                                      for (final x in rows) {
                                        final r = x['rating'];
                                        if (r is num) {
                                          sum += r.toDouble();
                                          cnt++;
                                        }
                                      }

                                      final avg =
                                          (cnt == 0) ? 0.0 : (sum / cnt);

                                      return Row(
                                        children: [
                                          const Icon(Icons.star,
                                              size: 18, color: Colors.amber),
                                          const SizedBox(width: 6),
                                          Text(avg.toStringAsFixed(1),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700)),
                                          const SizedBox(width: 6),
                                          Text('($cnt)',
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outline)),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                const Divider(height: 1),
                                ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  leading: Icon(Icons.rate_review_outlined,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                  title: const Text('Отзывы'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => SellerReviewsScreen(
                                          sellerId: listing.ownerId,
                                          sellerName: sellerName,
                                          listingId: listing.id,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
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
                                    onTap: hasAddress
                                        ? () => _openInMaps(address)
                                        : null,
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
                                  if (address.isNotEmpty &&
                                      address != mapLabel) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      address,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            Theme.of(ctx).colorScheme.outline,
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
                                    color:
                                        Theme.of(context).colorScheme.outline),
                                const SizedBox(width: 6),
                                Text(
                                    timeago.format(listing.createdAt,
                                        locale: 'ru'),
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline)),
                                const Spacer(),
                                Icon(Icons.remove_red_eye_outlined,
                                    size: 18,
                                    color:
                                        Theme.of(context).colorScheme.outline),
                                const SizedBox(width: 6),
                                Text('${listing.viewCount}',
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline)),
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
                              child:
                                  Text('Доставка: ${deliveryNames.join(', ')}'),
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline)),
                            ),

                          const SizedBox(height: 12),

                          if (specs.isNotEmpty)
                            _buildCarSpecsSection(context, specs),
                          if (specs.isNotEmpty) const SizedBox(height: 12),

                          _buildDescriptionSection(
                              context, listing.description),

                          const SizedBox(height: 12),

                          // ✅ ПРОДАВЕЦ + АВАТАР
                          InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => SellerPublicProfileScreen(
                                    sellerId: listing.ownerId,
                                    initialSellerName: sellerName,
                                    initialSellerAvatar: sellerAvatar,
                                    initialSellerPhone: listing.phone,
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
                                    color: Theme.of(context)
                                        .dividerColor
                                        .withValues(alpha: 0.18)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Продавец',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16)),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      StreamBuilder<bool>(
                                        stream: presence
                                            .streamIsOnline(listing.ownerId),
                                        builder: (context, onlineSnap) {
                                          final isOnline =
                                              onlineSnap.data == true;
                                          return Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              CircleAvatar(
                                                radius: 22,
                                                backgroundColor: Theme.of(
                                                        context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                                backgroundImage: (sellerAvatar
                                                        .isNotEmpty)
                                                    ? NetworkImage(sellerAvatar)
                                                    : null,
                                                child: (sellerAvatar.isNotEmpty)
                                                    ? null
                                                    : Text(
                                                        _sellerInitial(
                                                            sellerName),
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w900),
                                                      ),
                                              ),
                                              Positioned(
                                                right: -1,
                                                bottom: -1,
                                                child: Container(
                                                  width: 12,
                                                  height: 12,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: isOnline
                                                        ? Colors.green
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .outlineVariant,
                                                    border: Border.all(
                                                      color: Theme.of(context)
                                                          .scaffoldBackgroundColor,
                                                      width: 2,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              sellerName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w800),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              listing.phoneHidden
                                                  ? 'Телефон: скрыт'
                                                  : 'Телефон: ${listing.phone}',
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Открыть профиль продавца',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          _SimilarListingsSection(
                            baseListing: listing,
                            currentUserId: me.uid,
                            listingsSvc: listingsSvc,
                            favs: favs,
                            history: history,
                            reviews: context.read<ReviewsService>(),
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
          },
        );
      },
    );
  }
}

class _SimilarListingsSection extends StatelessWidget {
  final Listing baseListing;
  final String currentUserId;
  final ListingsService listingsSvc;
  final FavoritesService favs;
  final ListingHistoryService history;
  final ReviewsService reviews;

  const _SimilarListingsSection({
    required this.baseListing,
    required this.currentUserId,
    required this.listingsSvc,
    required this.favs,
    required this.history,
    required this.reviews,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Listing>>(
      stream: listingsSvc.streamSimilarListings(baseListing),
      builder: (context, snap) {
        final items = snap.data ?? const <Listing>[];
        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Похожие объявления',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 270,
              child: StreamBuilder<Set<String>>(
                stream: favs.streamFavoriteIds(currentUserId),
                builder: (context, favSnap) {
                  final favIds = favSnap.data ?? const <String>{};
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return SizedBox(
                        width: 190,
                        child: ListingCard(
                          listing: item,
                          isFav: favIds.contains(item.id),
                          isSeen: history.hasViewed(item.id),
                          reviews: reviews,
                          onToggleFav: (makeFav) async {
                            await favs.toggleFavorite(
                              uid: currentUserId,
                              listingId: item.id,
                              makeFavorite: makeFav,
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
                  );
                },
              ),
            ),
          ],
        );
      },
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
                child: CachedNetworkImage(
                  imageUrl: photoUrls[i],
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  placeholder: (_, __) => Container(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined, size: 40),
                  ),
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

