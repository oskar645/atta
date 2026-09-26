import 'dart:async';

import 'package:atta/src/features/admin/admin_marketplace_analytics_screens.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('zero-result analytics appends cursor pages without duplicates',
      (tester) async {
    final admin = _Admin();
    await _pump(tester, admin);
    expect(find.text('Запрос 0'), findsOneWidget);

    await tester.fling(find.byType(ListView), const Offset(0, -4000), 10000);
    await tester.pumpAndSettle();

    expect(admin.cursors, contains('page-2'));
    expect(find.text('Запрос 34'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale period response cannot overwrite the latest response',
      (tester) async {
    final admin = _Admin(delayMonth: true);
    await _pump(tester, admin, settle: false);
    await tester.tap(find.text('7 дней'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('Свежий период'), findsOneWidget);

    admin.month.complete(_page(['Устаревший период'], hasMore: false));
    await tester.pumpAndSettle();
    expect(find.text('Свежий период'), findsOneWidget);
    expect(find.text('Устаревший период'), findsNothing);
  });
}

Future<void> _pump(WidgetTester tester, _Admin admin,
    {bool settle = true}) async {
  await tester.pumpWidget(Provider<AdminService>.value(
    value: admin,
    child: const MaterialApp(home: AdminZeroResultSearchesScreen()),
  ));
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}

Map<String, dynamic> _page(List<String> queries, {required bool hasMore}) => {
      'items': [
        for (final query in queries)
          {
            'query': query,
            'normalized_query': query.toLowerCase(),
            'count': 1,
            'last_searched_at': '2026-09-26T10:00:00.000Z'
          }
      ],
      'has_more': hasMore,
      'next_cursor': hasMore ? 'page-2' : null,
    };

class _Admin extends AdminService {
  _Admin({this.delayMonth = false});
  final bool delayMonth;
  final month = Completer<Map<String, dynamic>>();
  final cursors = <String?>[];

  @override
  Future<Map<String, dynamic>> zeroResultSearches(
      {String period = 'month',
      String search = '',
      int limit = 30,
      String? cursor}) {
    cursors.add(cursor);
    if (delayMonth && period == 'month') return month.future;
    if (period == '7d') {
      return Future.value(_page(['Свежий период'], hasMore: false));
    }
    if (cursor == 'page-2') {
      return Future.value(_page(
          ['Запрос 29', ...List.generate(5, (i) => 'Запрос ${30 + i}')],
          hasMore: false));
    }
    return Future.value(
        _page(List.generate(30, (i) => 'Запрос $i'), hasMore: true));
  }
}
