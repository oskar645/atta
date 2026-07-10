import 'dart:async';

import 'package:atta/src/features/admin/admin_reports_screen.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/reports_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('support composer dialog can open and close without assertion',
      (tester) async {
    final reports = _FakeReportsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ReportsService>.value(value: reports),
        ],
        child: const MaterialApp(home: AdminReportsScreen()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Написать автору жалобы'));
    await tester.pumpAndSettle();

    expect(find.text('Сообщение в поддержку'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('decision dialog can open and close without disposed controller',
      (tester) async {
    final reports = _FakeReportsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ReportsService>.value(value: reports),
        ],
        child: const MaterialApp(home: AdminReportsScreen()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Нарушений нет'));
    await tester.pumpAndSettle();

    expect(find.text('Отправить уведомление'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('report card hides technical ids from main ui', (tester) async {
    final reports = _FakeReportsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ReportsService>.value(value: reports),
        ],
        child: const MaterialApp(home: AdminReportsScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Жалоба на объявление'), findsOneWidget);
    expect(find.textContaining('report-1'), findsNothing);
    expect(find.textContaining('listing-1'), findsNothing);
    expect(find.textContaining('user-1'), findsNothing);
    expect(find.textContaining('user-2'), findsNothing);
    expect(find.text('Профиль автора жалобы'), findsOneWidget);
    expect(find.text('Профиль второй стороны'), findsOneWidget);
  });

  testWidgets('warning template is editable and does not include ids',
      (tester) async {
    final reports = _FakeReportsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ReportsService>.value(value: reports),
        ],
        child: const MaterialApp(home: AdminReportsScreen()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Отправить предупреждение'));
    await tester.pumpAndSettle();

    expect(find.text('Сообщение в поддержку'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    final controller = field.controller!;
    expect(controller.text, isNot(contains('report-1')));
    expect(controller.text, isNot(contains('listing-1')));
    expect(controller.text, isNot(contains('user-1')));
    expect(controller.text, isNot(contains('user-2')));
    expect(controller.text, isNot(contains('Заявитель')));

    await tester.enterText(
        find.byType(TextField), '${controller.text}\n\nP.S.');
    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();

    expect(reports.contactCalls, 1);
    expect(reports.lastMessage, contains('P.S.'));
  });
}

class _FakeReportsService extends ReportsService {
  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'report-1',
      'status': 'open',
      'reason': 'Спам',
      'comment': 'Лишний текст',
      'reporter_id': 'user-1',
      'reporter_name': 'Заявитель',
      'reported_user_id': 'user-2',
      'reported_user_name': 'Продавец',
      'listing_id': 'listing-1',
      'listing_title': 'Объявление',
      'listing_seller_name': 'Продавец',
      'created_at': '2026-07-03T10:00:00.000Z',
    },
  ];
  int contactCalls = 0;
  String lastMessage = '';

  @override
  List<Map<String, dynamic>> peekAllReports() =>
      List<Map<String, dynamic>>.from(
        _items,
      );

  @override
  Stream<List<Map<String, dynamic>>> streamOpenReports() async* {
    yield List<Map<String, dynamic>>.from(_items);
  }

  @override
  Stream<List<Map<String, dynamic>>> streamProcessedReports() async* {
    yield const <Map<String, dynamic>>[];
  }

  @override
  Future<Map<String, dynamic>> contactUserViaSupport({
    required String userId,
    required String name,
    required String subject,
    required String message,
  }) async {
    contactCalls += 1;
    lastMessage = message;
    return <String, dynamic>{'ok': true};
  }
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(
        uid: 'admin-1',
        email: 'admin@example.com',
        displayName: 'Admin',
        isAdmin: true,
      );
}
