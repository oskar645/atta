import 'package:atta/src/features/admin/admin_raffle_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeRaffleAdminService extends AdminService {
  _FakeRaffleAdminService(
      {this.empty = false, this.fail = false, this.paged = false});

  final bool empty;
  final bool fail;
  final bool paged;
  final List<String> requestedPrices = [];
  final List<String?> requestedTicketSearches = [];

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

  @override
  Future<Map<String, dynamic>> raffleTickets(
      {required String from,
      required String to,
      required String ticketPrice,
      int limit = 50,
      String? cursor,
      String? search}) async {
    requestedTicketSearches.add(search);
    return {
      'items': empty
          ? []
          : [
              {
                'ticketNumber': cursor == null ? '1' : '51',
                'name': 'Иван Иванов',
                'phone': '+79991112233',
              },
              {
                'ticketNumber': cursor == null ? '2' : '52',
                'name': 'Иван Иванов',
                'phone': '+79991112233',
              },
            ],
      'nextCursor': paged && cursor == null ? '50' : null,
    };
  }
}

class _LargeRaffleAdminService extends _FakeRaffleAdminService {
  final List<String?> requestedCursors = <String?>[];

  @override
  Future<Map<String, dynamic>> raffleSummary(
      {required String from,
      required String to,
      required String ticketPrice}) async {
    return {
      'participants': 1,
      'tickets': 600,
      'amountRub': 300000,
      'ticketPriceRub': int.parse(ticketPrice),
    };
  }

  @override
  Future<Map<String, dynamic>> raffleTickets(
      {required String from,
      required String to,
      required String ticketPrice,
      int limit = 50,
      String? cursor,
      String? search}) async {
    requestedCursors.add(cursor);
    final first = int.parse(cursor ?? '0') + 1;
    final last = (first + limit - 1).clamp(first, 600);
    return {
      'items': [
        for (var number = first; number <= last; number++)
          {
            'ticketNumber': '$number',
            'name': 'Участник',
            'phone': '+79990000000',
          },
      ],
      'nextCursor': last < 600 ? '$last' : null,
    };
  }
}

void main() {
  Future<void> openScreen(WidgetTester tester, AdminService service) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    expect(find.text('Дата начала'), findsOneWidget);
    expect(find.text('01.10.2026'), findsOneWidget);
    expect(find.text('Дата окончания'), findsOneWidget);
    expect(find.text('02.10.2026'), findsOneWidget);
    await tester.tap(find.text('Показать участников'));
    await tester.pumpAndSettle();

    expect(find.text('Участники'), findsWidgets);
    expect(find.text('Всего билетов'), findsOneWidget);
    expect(find.text('Сумма'), findsOneWidget);
    expect(find.text('Скачать список'), findsOneWidget);
    expect(find.text('Печать PDF'), findsOneWidget);
    expect(find.text('Копировать'), findsOneWidget);
    expect(find.text('Поделиться'), findsOneWidget);
    expect(find.textContaining('Иван Иванов'), findsOneWidget);
    expect(find.textContaining('остаток 200 ₽'), findsOneWidget);
    await tester.tap(find.text('02.10.2026'));
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
    await tester.enterText(field, '1000');
    await tester.pump();
    expect(find.text('Всего билетов'), findsNothing);
    await tester.tap(calculate);
    await tester.pumpAndSettle();
    expect(admin.requestedPrices, ['2100', '2100', '1000', '1000']);
  });

  testWidgets(
      'ticket view shows every ticket and searches without accumulating pages',
      (tester) async {
    final admin = _FakeRaffleAdminService(paged: true);
    await openScreen(tester, admin);
    await tester.tap(find.text('Показать участников'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Все билеты'),
      300,
      scrollable: find
          .descendant(
              of: find.byType(ListView), matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.text('Все билеты'));
    await tester.pumpAndSettle();

    expect(find.text('Билет №1'), findsOneWidget);
    expect(find.text('Билет №2'), findsOneWidget);
    expect(find.text('Поиск по имени, телефону или № билета'), findsOneWidget);
    await tester.tap(find.text('Дальше'));
    await tester.pumpAndSettle();
    expect(find.text('Билет №51'), findsOneWidget);
    expect(find.text('Билет №1'), findsNothing);
    await tester.enterText(
        find.widgetWithText(TextField, 'Поиск по имени, телефону или № билета'),
        '#2');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(admin.requestedTicketSearches.last, '#2');
  });

  testWidgets(
      'copy range copies all 500 tickets without dialog lifecycle error',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final admin = _LargeRaffleAdminService();
    await openScreen(tester, admin);
    await tester.tap(find.text('Показать участников'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Копировать диапазон'),
      300,
      scrollable: find
          .descendant(
              of: find.byType(ListView), matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.text('Копировать диапазон'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'По билет'), '500');
    await tester.tap(find.widgetWithText(FilledButton, 'Копировать'));
    await tester.pump(const Duration(seconds: 1));

    expect(admin.requestedCursors, <String?>['0', '100', '200', '300', '400']);
    expect(find.text('Скопировано билетов: 500'), findsOneWidget);
  });
}
