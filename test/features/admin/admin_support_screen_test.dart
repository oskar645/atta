import 'dart:async';

import 'package:atta/src/features/admin/admin_support_screen.dart';
import 'package:atta/src/services/support_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('admin support long press delete hides thread from list',
      (tester) async {
    final support = _FakeSupportService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SupportService>.value(value: support),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AdminSupportTab()),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Старое обращение'), findsOneWidget);

    await tester.longPress(find.text('Старое обращение'));
    await tester.pump();
    expect(
      find.text('Удалить переписку из списка поддержки?'),
      findsOneWidget,
    );

    await tester.tap(find.text('Удалить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Старое обращение'), findsNothing);
    expect(support.hiddenTicketIds, <String>['ticket-1']);
  });
}

class _FakeSupportService extends SupportService {
  final List<Map<String, dynamic>> _tickets = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'ticket-1',
      'uid': 'user-1',
      'name': 'Пользователь',
      'last_message': 'Старое обращение',
      'updated_at': '2026-07-02T10:00:00.000Z',
      'unread_for_admin': false,
    },
  ];
  final List<String> hiddenTicketIds = <String>[];
  final StreamController<List<Map<String, dynamic>>> _controller =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  @override
  Stream<List<Map<String, dynamic>>> streamTicketsForAdmin() async* {
    yield List<Map<String, dynamic>>.from(_tickets);
    yield* _controller.stream;
  }

  @override
  Future<void> hideAdminTicket({
    required String ticketId,
    required String updatedAt,
  }) async {
    hiddenTicketIds.add(ticketId);
    _tickets.removeWhere(
      (item) => (item['id'] ?? '').toString().trim() == ticketId,
    );
    _controller.add(List<Map<String, dynamic>>.from(_tickets));
  }
}
