import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/models/showcase_item.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:flutter/material.dart';

class ShowcasePreviewScreen extends StatelessWidget {
  const ShowcasePreviewScreen({
    super.key,
    required this.item,
  });

  final ShowcaseItem item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Витрина ATTA'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: _ShowcaseImage(photoUrl: item.firstPhotoUrl),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Витрина ATTA',
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            item.title.isEmpty ? 'Объявление недоступно' : item.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            '${formatPrice(item.price)} ₽',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.location_on_outlined,
            text: item.city.isEmpty ? 'Город не указан' : item.city,
          ),
          _InfoRow(
            icon: Icons.person_outline,
            text: item.sellerName.isEmpty ? 'Продавец' : item.sellerName,
          ),
          if (item.sellerRating != null)
            _InfoRow(
              icon: Icons.star_rounded,
              text:
                  'Рейтинг продавца: ${item.sellerRating!.toStringAsFixed(1)}',
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: item.listingId.trim().isEmpty
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ListingDetailScreen(listingId: item.listingId),
                      ),
                    );
                  },
            child: const Text('Открыть объявление'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ShowcaseImage extends StatelessWidget {
  const _ShowcaseImage({required this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return MediaPreviewBox(
      imageUrl: photoUrl?.trim() ?? '',
      categoryHint: 'listings',
      borderRadius: 0,
      emptyLabel: 'Фото недоступно',
      errorLabel: 'Фото недоступно',
      placeholderLabel: 'Загрузка фото...',
    );
  }
}
