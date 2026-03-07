import 'package:cached_network_image/cached_network_image.dart';
import 'package:chestore2/src/features/inbox/chat_screen.dart';
import 'package:chestore2/src/features/listings/listing_detail_screen.dart';
import 'package:chestore2/src/features/reviews/seller_reviews_screen.dart';
import 'package:chestore2/src/models/listing.dart';
import 'package:chestore2/src/services/auth_service.dart';
import 'package:chestore2/src/services/chat_service.dart';
import 'package:chestore2/src/services/listings_service.dart';
import 'package:chestore2/src/services/presence_service.dart';
import 'package:chestore2/src/services/profile_service.dart';
import 'package:chestore2/src/services/reviews_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SellerPublicProfileScreen extends StatefulWidget {
  final String sellerId;

  const SellerPublicProfileScreen({
    super.key,
    required this.sellerId,
  });

  @override
  State<SellerPublicProfileScreen> createState() => _SellerPublicProfileScreenState();
}

class _SellerPublicProfileScreenState extends State<SellerPublicProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  String _pickName(Map<String, dynamic> u) {
    String pick(dynamic v) => (v ?? '').toString().trim();
    final dn = pick(u['display_name']);
    if (dn.isNotEmpty) return dn;
    final name = pick(u['name']);
    if (name.isNotEmpty) return name;
    return 'Пользователь';
  }

  String _pickPhoto(Map<String, dynamic> u) {
    String pick(dynamic v) => (v ?? '').toString().trim();
    final p1 = pick(u['avatar_url']);
    if (p1.isNotEmpty) return p1;
    final p2 = pick(u['photo_url']);
    if (p2.isNotEmpty) return p2;
    return '';
  }

  String _pickPhone(Map<String, dynamic> u) {
    return (u['phone'] ?? '').toString().trim();
  }

  Future<void> _openChat({
    required BuildContext context,
    required ListingsService listingsSvc,
    required ChatService chats,
    required String myUid,
    required String sellerId,
  }) async {
    try {
      final listing = await listingsSvc.getLatestApprovedListingByOwner(sellerId);
      if (listing == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('У продавца пока нет объявлений')),
        );
        return;
      }

      final chatId = await chats.getOrCreateChat(
        listingId: listing.id,
        listingTitle: listing.title,
        buyerId: myUid,
        sellerId: sellerId,
      );

      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.read<ProfileService>();
    final reviews = context.read<ReviewsService>();
    final listingsSvc = context.read<ListingsService>();
    final chats = context.read<ChatService>();
    final presence = context.read<PresenceService>();
    final me = context.read<AuthService>().currentUser;

    final myUid = me?.uid ?? '';
    final isMe = myUid.isNotEmpty && myUid == widget.sellerId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль продавца'),
        centerTitle: false,
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Активные'),
            Tab(text: 'Архив'),
          ],
        ),
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: profile.streamProfile(widget.sellerId),
        builder: (context, pSnap) {
          if (pSnap.connectionState == ConnectionState.waiting && !pSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final u = pSnap.data ?? const <String, dynamic>{};
          final sellerName = _pickName(u);
          final photoUrl = _pickPhoto(u);
          final phone = _pickPhone(u);

          final canCall = phone.isNotEmpty && !isMe;
          final canWrite = myUid.isNotEmpty && !isMe;

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Theme.of(context).colorScheme.surface,
                  border:
                      Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.18)),
                ),
                child: Row(
                  children: [
                    StreamBuilder<bool>(
                      stream: presence.streamIsOnline(widget.sellerId),
                      builder: (context, onlineSnap) {
                        final isOnline = onlineSnap.data == true;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _Avatar(photoUrl: photoUrl, fallbackText: sellerName),
                            Positioned(
                              right: -1,
                              bottom: -1,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isOnline
                                      ? Colors.green
                                      : Theme.of(context).colorScheme.outlineVariant,
                                  border: Border.all(
                                    color: Theme.of(context).scaffoldBackgroundColor,
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sellerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          StreamBuilder<Map<String, dynamic>>(
                            stream: reviews.streamSellerRating(widget.sellerId),
                            builder: (_, rSnap) {
                              final m = rSnap.data ?? const {'avg': 0.0, 'count': 0};
                              final avg = (m['avg'] as num?)?.toDouble() ?? 0.0;
                              final cnt = (m['count'] as num?)?.toInt() ?? 0;
                              return Row(
                                children: [
                                  const Icon(Icons.star, size: 18, color: Colors.amber),
                                  const SizedBox(width: 6),
                                  Text(
                                    avg.toStringAsFixed(1),
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '($cnt)',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.outline,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canCall
                          ? () async {
                              final uri = Uri(scheme: 'tel', path: phone);
                              await launchUrl(uri);
                            }
                          : null,
                      icon: const Icon(Icons.call),
                      label: Text(canCall ? 'Позвонить' : 'Телефон скрыт'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: canWrite
                          ? () => _openChat(
                                context: context,
                                listingsSvc: listingsSvc,
                                chats: chats,
                                myUid: myUid,
                                sellerId: widget.sellerId,
                              )
                          : null,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Написать'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                leading: Icon(
                  Icons.rate_review_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Отзывы'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SellerReviewsScreen(
                        sellerId: widget.sellerId,
                        sellerName: sellerName,
                        listingId: '',
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 560,
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _SellerListingsGrid(
                      stream: listingsSvc.streamListingsByOwnerAll(widget.sellerId).map(
                            (items) => items.where((x) => x.status == 'approved').toList(),
                          ),
                      isArchive: false,
                    ),
                    _SellerListingsGrid(
                      stream: listingsSvc.streamListingsByOwnerAll(widget.sellerId).map(
                            (items) => items
                                .where((x) =>
                                    x.status == 'deleted' ||
                                    x.status == 'archived' ||
                                    x.status == 'rejected')
                                .toList(),
                          ),
                      isArchive: true,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final String fallbackText;

  const _Avatar({this.photoUrl, required this.fallbackText});

  @override
  Widget build(BuildContext context) {
    final t = fallbackText.trim();
    final letter = t.isEmpty ? 'U' : t[0].toUpperCase();

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: ClipOval(
        child: (photoUrl == null || photoUrl!.isEmpty)
            ? Center(
                child: Text(
                  letter,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              )
            : Image.network(photoUrl!, fit: BoxFit.cover),
      ),
    );
  }
}

class _SellerListingsGrid extends StatelessWidget {
  final Stream<List<Listing>> stream;
  final bool isArchive;
  const _SellerListingsGrid({required this.stream, required this.isArchive});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Listing>>(
      stream: stream,
      builder: (context, lSnap) {
        if (lSnap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Ошибка объявлений: ${lSnap.error}'),
          );
        }
        if (lSnap.connectionState == ConnectionState.waiting && !lSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = lSnap.data ?? const <Listing>[];
        if (items.isEmpty) {
          return Center(
            child: Text(
              isArchive ? 'Архив пуст' : 'Пока нет объявлений',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          );
        }

        final grid = GridView.builder(
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.78,
          ),
          itemBuilder: (_, i) => _ListingCard(
            listing: items[i],
            isArchive: isArchive,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ListingDetailScreen(listingId: items[i].id),
                ),
              );
            },
          ),
        );

        if (!isArchive) return grid;

        return Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Text(
                'Архив: история объявлений продавца (продано, снято, отклонено).',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(child: grid),
          ],
        );
      },
    );
  }
}

class _ListingCard extends StatelessWidget {
  final Listing listing;
  final VoidCallback onTap;
  final bool isArchive;

  const _ListingCard({
    required this.listing,
    required this.onTap,
    required this.isArchive,
  });

  String _statusLabel(String status) {
    switch (status) {
      case 'sold':
        return 'Продано';
      case 'rejected':
        return 'Отклонено';
      case 'deleted':
      case 'archived':
        return 'Снято';
      default:
        return 'Снято';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'sold':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'deleted':
      case 'archived':
        return Colors.grey;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  String? _archiveNote(Listing listing) {
    if (listing.status == 'rejected' && listing.rejectionReason.trim().isNotEmpty) {
      return listing.rejectionReason.trim();
    }
    if (listing.status == 'sold') return 'Объявление отмечено как проданное';
    if (listing.status == 'deleted' || listing.status == 'archived') {
      return 'Объявление снято с публикации';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final photo = listing.photoUrls.isNotEmpty ? listing.photoUrls.first : '';
    final statusText = _statusLabel(listing.status);
    final statusColor = _statusColor(listing.status);
    final archiveNote = isArchive ? _archiveNote(listing) : null;
    final image = (photo.isEmpty)
        ? Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(child: Icon(Icons.image_outlined)),
          )
        : CachedNetworkImage(
            imageUrl: photo,
            fit: BoxFit.cover,
            width: double.infinity,
            placeholder: (_, __) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
            errorWidget: (_, __, ___) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined),
            ),
          );

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: isArchive ? null : onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (isArchive)
                      ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                        child: Opacity(opacity: 0.78, child: image),
                      )
                    else
                      image,
                    if (isArchive)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isArchive) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: statusColor.withValues(alpha: 0.14),
                        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    listing.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${listing.price} ₽',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (archiveNote != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      archiveNote,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
