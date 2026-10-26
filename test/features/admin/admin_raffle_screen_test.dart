import 'package:atta/src/features/admin/admin_raffle_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeRaffleAdminService extends AdminService {
  _FakeRaffleAdminService(
      {this.empty = false, this.fail = false, this.paged = false});

  final bool empty;
  final bool fail;
  final bool paged;
  final List<String> requestedPrices = [];

  @override
  Future<Map<String, dynamic>> raffleSummary(
      {required String from,
      required String to,
      required String ticketPrice}) async {
    if (fail) throw Exception('Сбой загрузки');
    requestedPrices.add(ticketPrice);
    return {
      'participants': empty ? 0 : 1,
      'tickets': empty ? 0 : 2,
      'amountRub': empty ? 0 : 1200,
      'ticketPriceRub': int.parse(ticketPrice),
    };
  }

  @override
  Future<Map<String, dynamic>> raffleParticipants(
      {required String from,
      required String to,
      required String ticketPrice,
      int limit = 30,
      String? cursor}) async {
    requestedPrices.add(ticketPrice);
    return {
      'items': empty
          ? []
          : [
              {
                'name': cursor == null ? 'Иван Иванов' : 'Адам Алиев',
                'phone': '+79991112233',
                'totalRub': 1200,
                'tickets': 2,
                'remainderRub': 200,
                'firstAt': '2026-10-01',
                'lastAt': '2026-10-02'
              }
            ],
      'nextCursor': paged && cursor == null
          ? '11111111-1111-4111-8111-111111111111'
          : null,
    };
  }
}

void main() {
  Future<void> openScreen(WidgetTester tester, AdminService service) async {
    await tester.pumpWidget(Provider<AdminService>.value(
      value: service,
      child: MaterialApp(
          home: AdminRaffleScreen(
              initialRange: DateTimeRange(
                  start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 2)))),
    ));
  }

  testWidgets('raffle screen loads summary and ticket count for selected dates',
      (tester) async {
    await openScreen(tester, _FakeRaffleAdminService());
    expect(find.text('Цена одного билета, ₽'), findsOneWidget);
    expect(find.text('1 билет = 500 ₽'), findsOneWidget);
    expect(find.text('Дата начала: 01.10.2026'), findsOneWidget);
    expect(find.text('Дата окончания: 02.10.2026'), findsOneWidget);
    expect(find.text('Скачать участников CSV'), findsOneWidget);
    expect(find.text('Скачать билеты для печати CSV'), findsOneWidget);
    await tester.tap(find.text('Показать участников'));
    await tester.pumpAndSettle();

    expect(find.text('Уникальных участников: 1'), findsOneWidget);
    expect(find.text('Цена билета: 500 ₽'), findsOneWidget);
    expect(find.text('Всего билетов: 2'), findsOneWidget);
    expect(find.textContaining('Иван Иванов'), findsOneWidget);
    expect(find.textContaining('остаток 200 ₽'), findsOneWidget);
    await tester.tap(find.text('Дата окончания: 02.10.2026'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('Дата окончания розыгрыша'), findsOneWidget);
    expect(
        tester
            .widget<DatePickerDialog>(find.byType(DatePickerDialog))
            .lastDate
            .year,
        DateTime.now().year + 30);
  });

  testWidgets('raffle screen shows empty state', (tester) async {
    await openScreen(tester, _FakeRaffleAdminService(empty: true));
    await tester.tap(find.text('Показать участников'));
    await tester.pumpAndSettle();
    expect(find.text('Участники не найдены'), findsOneWidget);
  });

  testWidgets('raffle screen shows loading error', (tester) async {
    await openScreen(tester, _FakeRaffleAdminService(fail: true));
    await tester.tap(find.text('Показать участников'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Сбой загрузки'), findsOneWidget);
  });

  testWidgets('raffle screen loads next participant page', (tester) async {
    await openScreen(tester, _FakeRaffleAdminService(paged: true));
    await tester.tap(find.text('Показать участников'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Показать ещё'), 250,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('Показать ещё'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Иван Иванов'), findsOneWidget);
    expect(find.textContaining('Адам Алиев'), findsOneWidget);
  });

  testWidgets(
      'ticket price changes requests and invalid values block calculation',
      (tester) async {
    final admin = _FakeRaffleAdminService();
    await openScreen(tester, admin);
    final field = find.byType(TextField);
    final calculate = find.widgetWithText(FilledButton, 'Показать участников');
    for (final invalid in ['', '0', '-1', '2.5']) {
      await tester.enterText(field, invalid);
      await tester.pump();
      expect(tester.widget<FilledButton>(calculate).onPressed, isNull);
      expect(admin.requestedPrices, isEmpty);
    }
    await tester.enterText(field, '2100');
    await tester.pump();
    expect(tester.widget<FilledButton>(calculate).onPressed, isNotNull);
    expect(find.text('1 билет = 2100 ₽'), findsOneWidget);
    await tester.tap(calculate);
    await tester.pumpAndSettle();
    expect(admin.requestedPrices, ['2100', '2100']);
    expect(find.text('Цена билета: 2100 ₽'), findsOneWidget);
    await tester.enterText(field, '1000');
    await tester.pump();
    expect(find.text('Цена билета: 2100 ₽'), findsNothing);
    await tester.tap(calculate);
    await tester.pumpAndSettle();
    expect(admin.requestedPrices, ['2100', '2100', '1000', '1000']);
  });
}
