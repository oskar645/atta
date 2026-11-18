import 'package:atta/src/features/listings/real_estate_map_screen.dart';
import 'package:atta/src/models/map_listing.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('first map render waits for MapController readiness',
      (tester) async {
    final listings = _FakeListingsService(const [
      MapListing(
        id: 'home-1',
        title: 'Дом на карте',
        price: 2500000,
        city: 'Грозный',
        address: 'ул. Мира, 1',
        latitude: 43.31,
        longitude: 45.69,
        photoUrl: '/media/object?category=listings&key=listings/home-1.jpg',
      ),
    ]);

    await tester.pumpWidget(_mapApp(listings));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(listings.mapRequests, 1);
    expect(listings.lastWest, lessThan(46.0943477));
    expect(listings.lastEast, greaterThan(46.0943477));
    expect(listings.lastSouth, lessThan(43.3472172));
    expect(listings.lastNorth, greaterThan(43.3472172));
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Дом на карте'), findsOneWidget);
  });

  testWidgets('clusters react to zoom and map gestures can reload area',
      (tester) async {
    final listings = _FakeListingsService(const [
      MapListing(
        id: 'home-1',
        title: 'Дом 1',
        price: 1000000,
        city: 'Грозный',
        address: 'Адрес 1',
        latitude: 43.31,
        longitude: 45.90,
      ),
      MapListing(
        id: 'home-2',
        title: 'Дом 2',
        price: 2000000,
        city: 'Грозный',
        address: 'Адрес 2',
        latitude: 43.33,
        longitude: 45.90,
      ),
    ]);

    await tester.pumpWidget(_mapApp(listings));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsNothing);
    expect(find.byIcon(Icons.home_rounded), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    await tester.drag(find.byType(FlutterMap), const Offset(-120, 30));
    await tester.pumpAndSettle();
    expect(find.text('Искать в этой области'), findsOneWidget);
    await tester.tap(find.text('Искать в этой области'));
    await tester.pumpAndSettle();
    expect(listings.mapRequests, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('listings at the exact same address open as choices immediately',
      (tester) async {
    final listings = _FakeListingsService(const [
      MapListing(
        id: 'same-1',
        title: 'Первый дом',
        price: 1000000,
        city: 'Гудермес',
        address: 'Гудермес',
        latitude: 43.3530186,
        longitude: 46.1049578,
      ),
      MapListing(
        id: 'same-2',
        title: 'Второй дом',
        price: 2000000,
        city: 'Гудермес',
        address: 'Гудермес',
        latitude: 43.3530186,
        longitude: 46.1049578,
      ),
    ]);

    await tester.pumpWidget(_mapApp(listings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();

    expect(find.text('Первый дом'), findsOneWidget);
    expect(find.text('Второй дом'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('map search and zoom controls use compact sizes', (tester) async {
    await tester.pumpWidget(_mapApp(_FakeListingsService(const [])));
    await tester.pumpAndSettle();

    expect(
        tester.getSize(find.byKey(const Key('real-estate-map-search'))).height,
        44);
    expect(
        tester.getSize(find.byIcon(Icons.add)).height, lessThanOrEqualTo(34));
    expect(tester.getSize(find.byIcon(Icons.remove)).height,
        lessThanOrEqualTo(34));
  });

  testWidgets('map can be closed and opened again safely', (tester) async {
    final listings = _FakeListingsService(const []);
    await tester.pumpWidget(
      Provider<ListingsService>.value(
        value: listings,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const RealEstateMapScreen(
                        filters: ListingFeedFilters(
                          category: 'Недвижимость',
                          search: '',
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Открыть карту'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть карту'));
    await tester.pumpAndSettle();
    expect(listings.mapRequests, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть карту'));
    await tester.pumpAndSettle();

    expect(listings.mapRequests, 2);
    expect(tester.takeException(), isNull);
  });
}

Widget _mapApp(_FakeListingsService listings) =>
    Provider<ListingsService>.value(
      value: listings,
      child: const MaterialApp(
        home: RealEstateMapScreen(
          filters: ListingFeedFilters(
            category: 'Недвижимость',
            search: '',
          ),
        ),
      ),
    );

class _FakeListingsService extends ListingsService {
  _FakeListingsService(this.items);

  final List<MapListing> items;
  int mapRequests = 0;
  double? lastNorth;
  double? lastSouth;
  double? lastEast;
  double? lastWest;

  @override
  Future<List<MapListing>> getRealEstateMapListings({
    required double north,
    required double south,
    required double east,
    required double west,
    required ListingFeedFilters filters,
  }) async {
    mapRequests++;
    lastNorth = north;
    lastSouth = south;
    lastEast = east;
    lastWest = west;
    return items;
  }
}
