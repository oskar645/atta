import 'package:atta/src/models/listing_stats.dart';
import 'package:atta/src/services/promotions_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ListingStatsScreen extends StatefulWidget {
  const ListingStatsScreen({
    super.key,
    required this.listingId,
    this.initialFavoriteCount = 0,
  });

  final String listingId;
  final int initialFavoriteCount;

  @override
  State<ListingStatsScreen> createState() => _ListingStatsScreenState();
}

class _ListingStatsScreenState extends State<ListingStatsScreen> {
  late Future<ListingStats> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<PromotionsService>().getListingStats(
          widget.listingId,
          initialFavoriteCount: widget.initialFavoriteCount,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика'),
        centerTitle: false,
      ),
      body: FutureBuilder<ListingStats>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final stats = snapshot.data!;
          final empty = stats.views == 0 &&
              stats.favorites == 0 &&
              stats.showcaseImpressions == 0 &&
              stats.showcaseClicks == 0 &&
              stats.activePromotions.isEmpty;

          if (empty) {
            return const Center(child: Text('Статистика пока пустая'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatTile(title: 'Просмотры', value: '${stats.views}'),
              _StatTile(
                title: 'Добавили в избранное',
                value: '${stats.favorites}',
              ),
              _StatTile(
                title: 'Показы в Витрине',
                value: '${stats.showcaseImpressions}',
              ),
              _StatTile(
                title: 'Клики из Витрины',
                value: '${stats.showcaseClicks}',
              ),
              const SizedBox(height: 16),
              const Text(
                'Активные продвижения',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (stats.activePromotions.isEmpty)
                const Text('Активных продвижений нет')
              else
                ...stats.activePromotions.map(
                  (promotion) => Card(
                    child: ListTile(
                      title: Text(promotion.title),
                      subtitle: Text(
                        promotion.endsAt == null
                            ? 'Активно'
                            : 'Активно до ${_formatDateTime(promotion.endsAt!)}',
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$dd.$mm, $hh:$min';
}
