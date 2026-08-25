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

    await tester.pumpWidget(_wrap(adminService));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Регистрации'));
    await tester.pumpAndSettle();

    expect(find.text('Всего пользователей'), findsOneWidget);
    expect(find.text('За этот месяц'), findsOneWidget);
    expect(find.text('Август'), findsOneWidget);
    expect(find.text('Июль'), findsOneWidget);
    expect(find.text('Июнь'), findsOneWidget);
    expect(find.text('143'), findsWidgets);
    expect(find.text('0'), findsOneWidget);
    expect(adminService.registrationStatsCalls, 1);

    await tester.tap(find.text('${DateTime.now().year}').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${DateTime.now().year - 1}').last);
    await tester.pumpAndSettle();

    expect(adminService.requestedYears.last, DateTime.now().year - 1);
    expect(find.text('Май'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
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
    final currentYear = DateTime.now().year;
    if (year == currentYear - 1) {
      return <String, dynamic>{
        'year': currentYear - 1,
        'available_years': <int>[currentYear - 1, currentYear],
        'total_users': 327,
        'current_month_count': 143,
        'months': <Map<String, dynamic>>[
          <String, dynamic>{'month': 5, 'count': 12},
        ],
      };
    }
    return <String, dynamic>{
      'year': currentYear,
      'available_years': <int>[currentYear - 1, currentYear],
      'total_users': 327,
      'current_month_count': 143,
      'months': <Map<String, dynamic>>[
        <String, dynamic>{'month': 8, 'count': 143},
        <String, dynamic>{'month': 7, 'count': 0},
        <String, dynamic>{'month': 6, 'count': 54},
      ],
    };
  }
}
