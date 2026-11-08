import 'package:atta/src/features/admin/admin_app_downloads_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows iOS and Android separately and opens all detail periods',
      (tester) async {
    await tester.pumpWidget(_app(_FakeDownloadsAdminService()));
    await tester.pumpAndSettle();

    expect(find.text('Загрузки приложений'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-downloads-ios')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-downloads-android')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-downloads-ios')));
    await tester.pumpAndSettle();

    expect(find.text('Загрузки — iOS'), findsOneWidget);
    expect(find.text('Сегодня'), findsOneWidget);
    expect(find.text('Вчера'), findsOneWidget);
    expect(find.text('За 7 дней'), findsOneWidget);
    expect(find.text('За 30 дней'), findsOneWidget);
    expect(find.text('За всё время'), findsOneWidget);
    expect(find.text('Данные за сегодня ещё не получены'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-downloads-last-updated')),
        findsOneWidget);
  });

  testWidgets('one store without data does not hide the other', (tester) async {
    await tester.pumpWidget(_app(_FakeDownloadsAdminService()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Последние 7 дней: 84'), findsOneWidget);
    expect(find.text('Требуется настройка источника'), findsOneWidget);
  });

  testWidgets('has no overflow on a narrow screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_FakeDownloadsAdminService()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('app-downloads-ios')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Widget _app(AdminService service) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: AdminAppDownloadsSummary(adminService: service),
        ),
      ),
    );

class _FakeDownloadsAdminService extends AdminService {
  @override
  Future<Map<String, dynamic>> appDownloads(
          {bool forceRefresh = false}) async =>
      <String, dynamic>{
        'ios': <String, dynamic>{
          'status': 'ready',
          'metricLabel': 'Первые загрузки',
          'timeZone': 'UTC',
          'today': null,
          'yesterday': 12,
          'last7Days': 84,
          'last30Days': 310,
          'allTime': 1420,
          'latestReportDate': '2026-11-04',
          'lastUpdatedAt': '2026-11-05T08:10:00.000Z',
        },
        'android': <String, dynamic>{
          'status': 'notConfigured',
          'metricLabel': 'Установки пользователями',
          'timeZone': 'America/Los_Angeles',
          'today': null,
          'yesterday': null,
          'last7Days': null,
          'last30Days': null,
          'allTime': null,
          'latestReportDate': null,
          'lastUpdatedAt': null,
        },
      };
}
