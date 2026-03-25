import 'package:cached_network_image/cached_network_image.dart';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthService>().currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Нужно войти')),
      );
    }

    final favs = context.read<FavoritesService>();
    final listings = context.read<ListingsService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Избранное')),
      body: StreamBuilder<Set<String>>(
        stream: favs.streamFavoriteIds(user.uid),
        builder: (context, favSnap) {
          final idsSet = favSnap.data ?? <String>{};
          final ids = idsSet.toList();

          if (ids.isEmpty) return const Center(child: Text('Пусто'));

          // ✅ Берём ленту и фильтруем по избранному
          return StreamBuilder<List<Listing>>(
            stream: listings.streamListings(category: 'Все', search: ''),
            builder: (context, listSnap) {
              if (!listSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final all = listSnap.data ?? <Listing>[];

              // только те, что реально есть в базе и доступны (approved в streamListings)
              final favListings = all.where((l) => idsSet.contains(l.id)).toList();

              // ✅ если какие-то id не нашлись (например, удалили объявление) — убираем из избранного
              final foundIds = favListings.map((e) => e.id).toSet();
              final missingIds = idsSet.difference(foundIds);
              if (missingIds.isNotEmpty) {
                // не await — чтобы не блокировать build
                for (final id in missingIds) {
                  favs.toggleFavorite(uid: user.uid, listingId: id, makeFavorite: false);
                }
              }

              if (favListings.isEmpty) {
                return const Center(child: Text('Нет доступных объявлений'));
              }

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: favListings.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final l = favListings[i];
                  final photo = l.photoUrls.isNotEmpty ? l.photoUrls.first : null;

                  return ListTile(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ListingDetailScreen(listingId: l.id),
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    tileColor: Theme.of(context).colorScheme.surfaceContainerLowest,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 56,
                        height: 56,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: photo == null
                            ? const Icon(Icons.image_not_supported_outlined)
                            : CachedNetworkImage(
                                imageUrl: photo,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    title: Text(
                      l.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${l.price} ₽ • ${l.category}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.favorite),
                      onPressed: () => favs.toggleFavorite(
                        uid: user.uid,
                        listingId: l.id,
                        makeFavorite: false,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
