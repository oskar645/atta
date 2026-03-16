import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/listing.dart';
import '../services/reviews_service.dart';
import '../utils/price_formatter.dart';

class ListingCard extends StatelessWidget {
  final Listing listing;

  /// true если в избранном
  final bool isFav;
  final bool isSeen;

  /// открыть объявление
  final VoidCallback onOpen;

  /// нажали сердечко (передаём: сделать избранным или убрать)
  final ValueChanged<bool> onToggleFav;

  /// сервис отзывов
  final ReviewsService reviews;

  const ListingCard({
    super.key,
    required this.listing,
    required this.isFav,
    required this.isSeen,
    required this.onOpen,
    required this.onToggleFav,
    required this.reviews,
  });

  /// ✅ На карточке показываем только последнюю часть адреса:
  /// "Чеченская республика, Гудермесский район, село Шуани" -> "Шуани"
  /// "Москва" -> "Москва"
  /// "г. Грозный" -> "Грозный"
  String _shortCity(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';

    // если разделено запятыми — берём последнюю часть
    if (s.contains(',')) {
      s = s.split(',').last.trim();
    }

    // если разделено тире/дефисом — иногда тоже удобно брать последнюю часть
    // (оставим мягко: только если это не "Ростов-на-Дону" и т.п. — поэтому не трогаем дефисы)

    // убрать частые префиксы
    s = s
        .replaceAll(RegExp(r'^(г\.|город)\s+', caseSensitive: false), '')
        .replaceAll(RegExp(r'^(с\.|село)\s+', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'^(п\.|пос\.|поселок|посёлок)\s+', caseSensitive: false),
            '')
        .trim();

    // если последняя часть получилась пустая — вернём исходное
    return s.isEmpty ? raw.trim() : s;
  }

  @override
  Widget build(BuildContext context) {
    final photo = listing.photoUrls.isNotEmpty ? listing.photoUrls.first : null;

    final cityRaw = listing.city.trim();
    final cityShort = cityRaw.isEmpty ? '' : _shortCity(cityRaw);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// PHOTO
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: photo == null || photo.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.image_not_supported_outlined,
                                      size: 34,
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Нет фото',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: photo,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => const Center(
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                                errorWidget: (_, __, ___) => Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.broken_image_outlined,
                                        size: 34,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Ошибка загрузки',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      if (isSeen)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(0),
                            ),
                            child: const Text(
                              'Просмотрено',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w400,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              /// INFO
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// title + fav
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              listing.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                height: 1.05,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            height: 28,
                            width: 28,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                  width: 28, height: 28),
                              onPressed: () => onToggleFav(!isFav),
                              icon: Icon(
                                isFav ? Icons.favorite : Icons.favorite_border,
                                color: isFav
                                    ? Colors.red
                                    : Theme.of(context).colorScheme.outline,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      /// price
                      Text(
                        '${formatPrice(listing.price)} ₽',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),

                      const SizedBox(height: 4),

                      /// rating seller
                      StreamBuilder<Map<String, dynamic>>(
                        stream: reviews.streamSellerRating(listing.ownerId),
                        builder: (context, rSnap) {
                          final avg =
                              (rSnap.data?['avg'] as num?)?.toDouble() ?? 0.0;
                          final cnt =
                              (rSnap.data?['count'] as num?)?.toInt() ?? 0;

                          return Row(
                            children: [
                              const Icon(Icons.star,
                                  size: 14, color: Colors.amber),
                              const SizedBox(width: 4),
                              Text(avg.toStringAsFixed(1),
                                  style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 4),
                              Text(
                                '($cnt)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 4),

                      /// ✅ city (теперь коротко, как ты просил)
                      Text(
                        cityRaw.isEmpty ? 'Город не указан' : cityShort,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
