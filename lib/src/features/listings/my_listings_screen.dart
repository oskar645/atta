import 'package:cached_network_image/cached_network_image.dart';
import 'package:atta/src/features/favorites/favorites_screen.dart';
import 'package:atta/src/features/listings/add_listing_screen.dart';
import 'package:atta/src/features/listings/edit_listing_screen.dart';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final svc = context.read<ListingsService>();
    final uid = auth.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои объявления'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Активные'),
            Tab(text: 'На модерации'),
            Tab(text: 'Удалённые'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite_border),
            tooltip: 'Избранное',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FavoritesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.blue, size: 28),
            tooltip: 'Добавить',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddListingScreen()),
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _ListingsTab(
            stream: svc.streamMyListingsByStatuses(
              uid,
              statuses: {'approved'},
            ),
          ),
          _ListingsTab(
            stream: svc.streamMyListingsByStatuses(
              uid,
              statuses: {'pending'},
            ),
          ),
          _ListingsTab(
            stream: svc.streamMyListingsByStatuses(
              uid,
              statuses: {'deleted', 'archived', 'rejected', 'sold'},
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingsTab extends StatelessWidget {
  final Stream<List<Listing>> stream;
  const _ListingsTab({required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Listing>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return const Center(child: Text('Пока нет объявлений'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _MyListingTile(listing: items[i]),
        );
      },
    );
  }
}

class _MyListingTile extends StatelessWidget {
  final Listing listing;
  const _MyListingTile({required this.listing});

  @override
  Widget build(BuildContext context) {
    final svc = context.read<ListingsService>();
    final photo = listing.photoUrls.isNotEmpty ? listing.photoUrls.first : null;
    final isArchived = listing.isArchivedStatus;
    final canEdit = listing.canOwnerEdit && listing.status != 'deleted' && listing.status != 'sold';
    final archiveNote = listing.archiveNote.trim();

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ListingDetailScreen(listingId: listing.id),
        ),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Ink(
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
              child: Container(
                width: 92,
                height: 92,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: photo == null
                    ? const Icon(Icons.image_not_supported_outlined)
                    : CachedNetworkImage(
                        imageUrl: photo,
                        fit: BoxFit.cover,
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
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${listing.price} ₽',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text('Просмотров: ${listing.viewCount}'),
                  const SizedBox(height: 4),
                  Text(
                    'Статус: ${_statusLabel(listing.status)}',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                  if (archiveNote.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      archiveNote,
                      maxLines: 3,
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
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Редактировать',
              onPressed: canEdit
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EditListingScreen(listingId: listing.id),
                        ),
                      );
                    }
                  : null,
            ),
            IconButton(
              icon: Icon(
                isArchived ? Icons.inventory_2_outlined : Icons.archive_outlined,
                color: isArchived ? null : Colors.red,
              ),
              tooltip: isArchived ? 'В архиве' : 'В архив',
              onPressed: isArchived
                  ? null
                  : () async {
                      final decision = await showDialog<_ArchiveDecision>(
                        context: context,
                        builder: (ctx) => const _ArchiveListingDialog(),
                      );

                      if (decision == null) return;

                      await svc.archiveListing(
                        listingId: listing.id,
                        status: decision.status,
                        note: decision.note,
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(decision.successMessage)),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'Активно';
      case 'pending':
        return 'На модерации';
      case 'rejected':
        return 'Нужно исправить';
      case 'sold':
        return 'Продано';
      case 'deleted':
        return 'Удалено админом';
      case 'archived':
        return 'В архиве';
      default:
        return status;
    }
  }
}

class _ArchiveDecision {
  final String status;
  final String note;
  final String successMessage;

  const _ArchiveDecision({
    required this.status,
    required this.note,
    required this.successMessage,
  });
}

class _ArchiveListingDialog extends StatefulWidget {
  const _ArchiveListingDialog();

  @override
  State<_ArchiveListingDialog> createState() => _ArchiveListingDialogState();
}

class _ArchiveListingDialogState extends State<_ArchiveListingDialog> {
  static const List<_ArchiveDecision> _options = [
    _ArchiveDecision(
      status: 'sold',
      note: 'Продано через ATTA.',
      successMessage: 'Объявление перенесено в архив как проданное',
    ),
    _ArchiveDecision(
      status: 'sold',
      note: 'Продано в другом месте.',
      successMessage: 'Объявление перенесено в архив как проданное',
    ),
    _ArchiveDecision(
      status: 'archived',
      note: 'Снято владельцем с публикации.',
      successMessage: 'Объявление перенесено в архив',
    ),
  ];

  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Перенести в архив'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Что произошло с объявлением?'),
            const SizedBox(height: 10),
            for (var i = 0; i < _options.length; i++)
              RadioListTile<int>(
                value: i,
                groupValue: _selectedIndex,
                contentPadding: EdgeInsets.zero,
                title: Text(_labelFor(_options[i])),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedIndex = value);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _options[_selectedIndex]),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  String _labelFor(_ArchiveDecision decision) {
    switch (decision.note) {
      case 'Продано через ATTA.':
        return 'Продано в приложении';
      case 'Продано в другом месте.':
        return 'Продано в другом месте';
      default:
        return 'Снять с продажи';
    }
  }
}
