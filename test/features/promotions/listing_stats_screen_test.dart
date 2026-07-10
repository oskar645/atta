import 'package:atta/src/features/promotions/listing_stats_screen.dart';
import 'package:atta/src/models/listing_stats.dart';
import 'package:atta/src/services/promotions_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('owner stats hide messages and calls and show favorites',
      (tester) async {
    await tester.pumpWidget(
      Provider<PromotionsService>.value(
        value: _FakePromotionsService(),
        child: const MaterialApp(
          home: ListingStatsScreen(
            listingId: 'listing-1',
            initialFavoriteCount: 2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Просмотры'), findsOneWidget);
    expect(find.text('Добавили в избранное'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Сообщения'), findsNothing);
    expect(find.text('Звонки'), findsNothing);
  });
}

class _FakePromotionsService extends PromotionsService {
  @override
  Future<ListingStats> getListingStats(
    String listingId, {
    int initialFavoriteCount = 0,
  }) async {
    return ListingStats(
      views: 12,
      favorites: initialFavoriteCount,
      messages: 5,
      calls: 3,
      showcaseImpressions: 0,
      showcaseClicks: 0,
      activePromotions: const [],
    );
  }
}
