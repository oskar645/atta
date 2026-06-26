import 'package:atta/src/features/listings/listing_archive_flow.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'tapping archive action opens confirmation and cancel does nothing',
      (tester) async {
    final service = _FakeListingsService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => runListingArchiveFlow(
                context,
                listingId: 'listing-1',
                listingsService: service,
              ),
              child: const Text('Снять с публикации'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Снять с публикации'));
    await tester.pumpAndSettle();

    expect(find.text('Снять объявление?'), findsOneWidget);
    expect(find.text('Да, продано'), findsOneWidget);
    expect(find.text('Снять без продажи'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(service.calls, isEmpty);
  });

  testWidgets('tapping sold confirms and calls mark sold', (tester) async {
    final service = _FakeListingsService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => runListingArchiveFlow(
                context,
                listingId: 'listing-1',
                listingsService: service,
              ),
              child: const Text('Снять с публикации'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Снять с публикации'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Да, продано'));
    await tester.pumpAndSettle();

    expect(service.calls.single.status, 'sold');
  });

  testWidgets('tapping archive without sale calls archive', (tester) async {
    final service = _FakeListingsService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => runListingArchiveFlow(
                context,
                listingId: 'listing-1',
                listingsService: service,
              ),
              child: const Text('Снять с публикации'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Снять с публикации'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Снять без продажи'));
    await tester.pumpAndSettle();

    expect(service.calls.single.status, 'archived');
  });
}

class _FakeListingsService extends ListingsService {
  final List<_ArchiveCall> calls = <_ArchiveCall>[];

  @override
  Future<Listing?> archiveListing({
    required String listingId,
    required String status,
    String? note,
  }) async {
    calls.add(_ArchiveCall(listingId: listingId, status: status, note: note));
    return null;
  }
}

class _ArchiveCall {
  const _ArchiveCall({
    required this.listingId,
    required this.status,
    required this.note,
  });

  final String listingId;
  final String status;
  final String? note;
}
