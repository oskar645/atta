import 'dart:async';

import 'package:atta/src/features/admin/admin_users_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('users tab keeps existing list and does not load stats on open',
      (tester) async {
    final adminService = _FakeAdminService();

    await tester.pumpWidget(_wrap(adminService));
    await tester.pumpAndSettle();

    expect(find.text('Пользователь ATTA'), findsOneWidget);
    expect(find.text('Телефон: +7 999 111 22 33'), findsOneWidget);
    expect(adminService.usersCalls, 1);
    expect(adminService.registrationStatsCalls, 0);
  });

  testWidgets('registration stats tab shows months and changes year',
      (tester) async {
    final adminService = _FakeAdminService();
    final currentMonth = _moscowNow().month;

    await tester.pumpWidget(_wrap(adminService));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Регистрации'));
    await tester.pumpAndSettle();

    expect(find.text('Всего пользователей'), findsOneWidget);
    expect(find.text('Сегодня'), findsOneWidget);
    expect(find.text('В этом месяце'), findsOneWidget);
    expect(find.text('Лучший месяц'), findsOneWidget);
    expect(find.text('Динамика за год'), findsOneWidget);
    expect(find.text('Июнь · 54'), findsOneWidget);
    expect(find.byKey(const ValueKey('registration-total-users-card')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('registration-today-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('registration-current-month-card')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('registration-best-month-card')),
        findsOneWidget);
    for (var month = 1; month <= 12; month += 1) {
      expect(
        find.byKey(ValueKey('registration-month-bar-$month')),
        findsOneWidget,
      );
    }
    final selectedMonthSummary = tester.widget<Text>(
      find.byKey(const ValueKey('registration-selected-month-summary')),
    );
    expect(selectedMonthSummary.data, contains(_monthName(currentMonth)));
    final currentMonthBar = find.byKey(
      ValueKey('registration-month-bar-$currentMonth'),
    );
    final currentMonthFill = tester.widget<AnimatedContainer>(
      find.descendant(
        of: currentMonthBar,
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect((currentMonthFill.decoration as BoxDecoration).color,
        const Color(0xFF0B6BFF));
    expect(find.textContaining('+12% к'), findsOneWidget);
    expect(adminService.registrationStatsCalls, 1);

    await tester.tap(find.text('${_moscowNow().year}').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${_moscowNow().year - 1}').last);
    await tester.pumpAndSettle();

    expect(adminService.requestedYears.last, _moscowNow().year - 1);
    expect(find.text('Май · 12'), findsOneWidget);
  });

  testWidgets('registration stats handles selected month comparison and zeros',
      (tester) async {
    final adminService = _FakeAdminService();

    await tester.pumpWidget(_wrap(adminService));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Регистрации'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('registration-month-bar-3')));
    await tester.pumpAndSettle();

    expect(find.text('Март — 0 регистраций'), findsOneWidget);
    expect(
        find.text('В предыдущем месяце регистраций не было'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('registration-month-bar-5')));
    await tester.pumpAndSettle();

    expect(find.text('Май — 30 регистраций'), findsOneWidget);
    expect(find.text('−25% к апрелю'), findsOneWidget);
  });

  testWidgets('registration stats avoids overflow on a narrow phone',
      (tester) async {
    final originalOnError = FlutterError.onError;
    final details = <FlutterErrorDetails>[];
    FlutterError.onError = details.add;
    addTearDown(() => FlutterError.onError = originalOnError);
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final adminService = _FakeAdminService();

    await tester.pumpWidget(_wrap(adminService));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Регистрации'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('registration-month-bar-12')),
        findsOneWidget);
    expect(
      details
          .where((detail) => detail.exceptionAsString().contains('overflowed'))
          .toList(),
      isEmpty,
    );
  });

  testWidgets('registration stats handles loading and error states',
      (tester) async {
    final completer = Completer<Map<String, dynamic>>();
    final adminService = _FakeAdminService(statsCompleter: completer);

    await tester.pumpWidget(_wrap(adminService));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Регистрации'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.completeError(Exception('network'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Не удалось загрузить регистрации'),
        findsOneWidget);
    final switcher = tester.getRect(find.byType(SegmentedButton<bool>));
    await tester.tapAt(Offset(
      switcher.left + switcher.width * 0.25,
      switcher.center.dy,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Пользователь ATTA'), findsOneWidget);
  });
}

Widget _wrap(AdminService adminService) {
  return MultiProvider(
    providers: [
      Provider<AdminService>.value(value: adminService),
      Provider<AuthService>.value(value: AuthService()),
    ],
    child: const MaterialApp(home: AdminUsersScreen()),
  );
}

class _FakeAdminService extends AdminService {
  _FakeAdminService({this.statsCompleter});

  final Completer<Map<String, dynamic>>? statsCompleter;
  int usersCalls = 0;
  int registrationStatsCalls = 0;
  final List<int?> requestedYears = <int?>[];

  @override
  Future<Map<String, dynamic>> users({
    bool forceRefresh = false,
    int? limit,
    String? cursor,
    String? search,
  }) async {
    usersCalls += 1;
    return <String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'user-1',
          'display_name': 'Пользователь ATTA',
          'phone': '79991112233',
          'created_at': '2026-08-01T10:00:00.000Z',
          'status': 'active',
        },
      ],
      'hasMore': false,
      'nextCursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> userRegistrationStats({
    int? year,
    bool forceRefresh = false,
  }) async {
    registrationStatsCalls += 1;
    requestedYears.add(year);
    if (statsCompleter != null) {
      return statsCompleter!.future;
    }
    final currentYear = _moscowNow().year;
    final currentMonth = _moscowNow().month;
    final previousMonth = currentMonth == 1 ? 12 : currentMonth - 1;
    final stats = <int, int>{
      2: 0,
      3: 0,
      4: 40,
      5: 30,
      6: 54,
      previousMonth: 25,
      currentMonth: 28,
    };
    if (year == currentYear - 1) {
      return <String, dynamic>{
        'year': currentYear - 1,
        'available_years': <int>[currentYear - 1, currentYear],
        'total_users': 327,
        'todayCount': 7,
        'current_month_count': 28,
        'months': <Map<String, dynamic>>[
          <String, dynamic>{'month': 5, 'count': 12},
        ],
      };
    }
    return <String, dynamic>{
      'year': currentYear,
      'available_years': <int>[currentYear - 1, currentYear],
      'total_users': 327,
      'todayCount': 7,
      'current_month_count': 28,
      'months': stats.entries
          .map(
            (entry) => <String, dynamic>{
              'month': entry.key,
              'count': entry.value,
            },
          )
          .toList(growable: false),
    };
  }
}

String _monthName(int month) {
  const names = <int, String>{
    1: 'Январь',
    2: 'Февраль',
    3: 'Март',
    4: 'Апрель',
    5: 'Май',
    6: 'Июнь',
    7: 'Июль',
    8: 'Август',
    9: 'Сентябрь',
    10: 'Октябрь',
    11: 'Ноябрь',
    12: 'Декабрь',
  };
  return names[month] ?? '$month';
}

DateTime _moscowNow() {
  return DateTime.now().toUtc().add(const Duration(hours: 3));
}
