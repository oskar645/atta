import 'package:atta/src/features/admin/admin_listings_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('deleted listing uses permanent delete action', (tester) async {
    final service = _FakeAdminListingsService(status: 'deleted');
    await tester.pumpWidget(_app(service, initialStatus: 'deleted'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Действия'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить навсегда'), findsOneWidget);

    await tester.tap(find.text('Удалить навсегда'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить объявление навсегда?'), findsOneWidget);
    expect(find.textContaining('безвозвратно удалено'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Удалить навсегда'));
    await tester.pumpAndSettle();
    expect(service.permanentlyDeletedIds, ['listing-1']);
    expect(service.softDeletedIds, isEmpty);
  });

  testWidgets('non-deleted listing keeps existing soft delete action',
      (tester) async {
    final service = _FakeAdminListingsService(status: 'approved');
    await tester.pumpWidget(_app(service, initialStatus: 'approved'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Действия'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить'), findsOneWidget);
    expect(find.text('Удалить навсегда'), findsNothing);
  });
}

Widget _app(
  AdminService service, {
  required String initialStatus,
}) {
  return Provider<AdminService>.value(
    value: service,
    child: MaterialApp(
      home: AdminListingsScreen(initialStatus: initialStatus),
    ),
  );
}

class _FakeAdminListingsService extends AdminService {
  _FakeAdminListingsService({required this.status});

  final String status;
  final List<String> permanentlyDeletedIds = [];
  final List<String> softDeletedIds = [];

  @override
  Future<Map<String, dynamic>> filteredListings({
    String? status,
    String? period,
    String? search,
    int? limit,
    String? cursor,
  }) async {
    return {
      'items': [
        {
          'id': 'listing-1',
          'title': 'Тестовое объявление',
          'price': 1000,
          'owner_name': 'Продавец',
          'status': this.status,
          'created_at': '2026-11-01T10:00:00.000Z',
          if (this.status == 'deleted')
            'deleted_at': '2026-11-02T10:00:00.000Z',
        },
      ],
      'total': 1,
      'nextCursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> permanentlyDeleteListing(
    String listingId,
  ) async {
    permanentlyDeletedIds.add(listingId);
    return {'deleted': true, 'id': listingId};
  }

  @override
  Future<Map<String, dynamic>> deleteListing(
    String listingId, {
    String? reason,
    String? moderationNote,
    bool wasPending = false,
  }) async {
    softDeletedIds.add(listingId);
    return {
      'listing': {'id': listingId, 'status': 'deleted'}
    };
  }
}
