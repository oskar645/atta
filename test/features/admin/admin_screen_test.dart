import 'dart:async';

import 'package:atta/src/features/admin/admin_screen.dart';
import 'package:atta/src/features/listings/photo_viewer_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/saved_search_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  test('dashboard scheduler refreshes at Moscow midnight before interval', () {
    expect(
      adminDashboardRefreshDelay(
        DateTime.utc(2026, 12, 31, 20, 59),
      ),
      const Duration(minutes: 1),
    );
    expect(
      adminDashboardRefreshDelay(
        DateTime.utc(2026, 12, 31, 20, 50),
      ),
      const Duration(minutes: 5),
    );
  });

  testWidgets('dashboard refreshes backend and usage after app resume',
      (tester) async {
    final adminService = _FakeAdminService();
    var usageCalls = 0;
    Future<Map<String, dynamic>> loadUsage() async {
      usageCalls += 1;
      return _loadUsageAnalytics();
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<AdminService>.value(value: adminService),
          Provider<NotificationsService>.value(
              value: _FakeNotificationsService()),
          Provider<SavedSearchService>.value(value: _FakeSavedSearchService()),
        ],
        child: MaterialApp(
          home: AdminScreen(usageAnalyticsLoad: loadUsage),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(adminService.dashboardStatsCalls, 1);
    expect(usageCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(adminService.dashboardStatsCalls, 2);
    expect(adminService.lastDashboardForceRefresh, isTrue);
    expect(usageCalls, 2);
  });

  testWidgets('dashboard periodically refreshes all centralized data',
      (tester) async {
    final adminService = _FakeAdminService();
    var usageCalls = 0;
    Future<Map<String, dynamic>> loadUsage() async {
      usageCalls += 1;
      return _loadUsageAnalytics();
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<AdminService>.value(value: adminService),
          Provider<NotificationsService>.value(
              value: _FakeNotificationsService()),
          Provider<SavedSearchService>.value(value: _FakeSavedSearchService()),
        ],
        child: MaterialApp(
          home: AdminScreen(usageAnalyticsLoad: loadUsage),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();

    expect(adminService.dashboardStatsCalls, 2);
    expect(usageCalls, 2);
  });

  testWidgets('dashboard coalesces realtime scopes and disposes listeners',
      (tester) async {
    final adminService = _FakeAdminService();
    final socket = _FakeDashboardSocketService();
    var usageCalls = 0;
    Future<Map<String, dynamic>> loadUsage() async {
      usageCalls += 1;
      return _loadUsageAnalytics();
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<AdminService>.value(value: adminService),
          Provider<ChatSocketService>.value(value: socket),
          Provider<NotificationsService>.value(
              value: _FakeNotificationsService()),
          Provider<SavedSearchService>.value(value: _FakeSavedSearchService()),
        ],
        child: MaterialApp(
          home: AdminScreen(usageAnalyticsLoad: loadUsage),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(socket.subscribeAnalyticsCalls, 1);
    expect(socket.hasEventListener, isTrue);
    socket.emitEvent('presence.changed');
    socket.emitEvent('presence.changed');
    socket.emitEvent('admin.dashboard.changed', <String, dynamic>{
      'scopes': <String>['listings', 'searches'],
    });
    socket.emitEvent('analytics_updated');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(adminService.dashboardMetricsCalls, 1);
    expect(adminService.lastDashboardMetricScopes,
        containsAll(<String>['presence', 'listings', 'searches']));
    expect(usageCalls, 2);
    expect(find.text('7'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(socket.hasEventListener, isFalse);
    expect(socket.hasConnectionListener, isFalse);
    await socket.close();
  });

  testWidgets('socket reconnect performs one full reconciliation refresh',
      (tester) async {
    final adminService = _FakeAdminService();
    final socket = _FakeDashboardSocketService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<AdminService>.value(value: adminService),
          Provider<ChatSocketService>.value(value: socket),
          Provider<NotificationsService>.value(
              value: _FakeNotificationsService()),
          Provider<SavedSearchService>.value(value: _FakeSavedSearchService()),
        ],
        child: const MaterialApp(
          home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
        ),
      ),
    );
    await tester.pumpAndSettle();
    socket.emitConnection(false);
    socket.emitConnection(true);
    await tester.pumpAndSettle();

    expect(adminService.dashboardStatsCalls, 2);
    expect(adminService.lastDashboardForceRefresh, isTrue);
    expect(socket.subscribeAnalyticsCalls, 2);
    await socket.close();
  });

  testWidgets('Moscow midnight queues refresh behind an in-flight request',
      (tester) async {
    final adminService = _FakeAdminService();
    final secondRefresh = Completer<Map<String, dynamic>>();
    var now = DateTime.utc(2026, 12, 31, 20, 59, 50);
    adminService.dashboardStatsHandler = (forceRefresh) {
      if (adminService.dashboardStatsCalls == 2) return secondRefresh.future;
      return Future<Map<String, dynamic>>.value(
        adminService.dashboardResponse(),
      );
    };
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<AdminService>.value(value: adminService),
          Provider<NotificationsService>.value(
              value: _FakeNotificationsService()),
          Provider<SavedSearchService>.value(value: _FakeSavedSearchService()),
        ],
        child: MaterialApp(
          home: AdminScreen(
            usageAnalyticsLoad: _loadUsageAnalytics,
            dashboardNow: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(adminService.dashboardStatsCalls, 2);
    now = DateTime.utc(2026, 12, 31, 21);
    await tester.pump(const Duration(seconds: 10));
    secondRefresh.complete(adminService.dashboardResponse());
    await tester.pumpAndSettle();

    expect(adminService.dashboardStatsCalls, 3);
  });

  testWidgets('dashboard loads once and keeps platform analytics last',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<AdminService>.value(value: _FakeAdminService()),
          Provider<NotificationsService>.value(
              value: _FakeNotificationsService()),
          Provider<SavedSearchService>.value(value: _FakeSavedSearchService()),
        ],
        child: const MaterialApp(
          home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Пользователей'), findsOneWidget);
    expect(find.text('Платформы'), findsOneWidget);
    final usersY = tester.getTopLeft(find.text('Пользователей')).dy;
    final platformsY = tester.getTopLeft(find.text('Платформы')).dy;
    expect(usersY, lessThan(platformsY));

    await tester.tap(find.text('Платформы'));
    await tester.pumpAndSettle();
    expect(find.text('Активные пользователи'), findsOneWidget);
    expect(find.text('Регистрации'), findsOneWidget);
    expect(find.text('iPhone'), findsNWidgets(2));
    expect(find.text('Android'), findsNWidgets(2));
    expect(find.text('Web'), findsNWidgets(2));
    expect(find.text('Версии приложения'), findsOneWidget);
  });

  testWidgets('app downloads is immediately before technical server status',
      (tester) async {
    tester.view.physicalSize = const Size(900, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<AdminService>.value(value: _FakeAdminService()),
          Provider<NotificationsService>.value(
              value: _FakeNotificationsService()),
          Provider<SavedSearchService>.value(value: _FakeSavedSearchService()),
        ],
        child: const MaterialApp(
          home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Загрузки приложений'), findsOneWidget);
    expect(find.text('Состояние сервера'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Загрузки приложений')).dy,
      lessThan(tester.getTopLeft(find.text('Состояние сервера')).dy),
    );
  });

  testWidgets('pulling dashboard down refreshes every dashboard block',
      (tester) async {
    final adminService = _FakeAdminService();
    var usageCalls = 0;
    Future<Map<String, dynamic>> loadUsage() async {
      usageCalls += 1;
      return _loadUsageAnalytics();
    }

    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<AdminService>.value(value: adminService),
          Provider<NotificationsService>.value(
              value: _FakeNotificationsService()),
          Provider<SavedSearchService>.value(value: _FakeSavedSearchService()),
        ],
        child: MaterialApp(
          home: AdminScreen(usageAnalyticsLoad: loadUsage),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(adminService.dashboardStatsCalls, 1);
    expect(usageCalls, 1);
    expect(adminService.appDownloadsCalls, 1);

    await tester.drag(find.byType(ListView).first, const Offset(0, 500));
    await tester.pumpAndSettle();

    expect(adminService.dashboardStatsCalls, 2);
    expect(adminService.lastDashboardForceRefresh, isTrue);
    expect(usageCalls, 2);
    expect(adminService.appDownloadsCalls, 2);
  });

  testWidgets(
    'dashboard shows points purchases card and opens purchases screen',
    (tester) async {
      final adminService = _FakeAdminService();
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AuthService>.value(value: _FakeAuthService()),
            Provider<AdminService>.value(value: adminService),
            Provider<NotificationsService>.value(
              value: _FakeNotificationsService(),
            ),
            Provider<SavedSearchService>.value(
              value: _FakeSavedSearchService(),
            ),
          ],
          child: const MaterialApp(
            home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Покупки баллов'), findsOneWidget);
      expect(find.text('1250 ₽'), findsOneWidget);
      expect(find.text('500 баллов • 2 покупок'), findsOneWidget);

      await tester.tap(find.text('Покупки баллов'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminScreen), findsNothing);
      expect(find.text('Покупки баллов'), findsWidgets);
    },
  );

  testWidgets('dashboard keeps revenue and promotion as compact entry cards',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<AdminService>.value(value: _FakeAdminService()),
          Provider<NotificationsService>.value(
              value: _FakeNotificationsService()),
          Provider<SavedSearchService>.value(value: _FakeSavedSearchService()),
        ],
        child: const MaterialApp(
          home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('adminRevenueCard')), findsOneWidget);
    expect(find.text('Выручка'), findsOneWidget);
    expect(find.byKey(const Key('adminPromotionsCard')), findsOneWidget);
    expect(find.text('Продвижение'), findsOneWidget);
    expect(find.text('Продвижения сегодня'), findsNothing);
    expect(find.text('8 400 ₽'), findsNothing);
    expect(find.text('420 баллов'), findsNothing);
    expect(find.text('Пользователей'), findsOneWidget);

    await tester.tap(find.text('Выручка'));
    await tester.pumpAndSettle();
    expect(find.text('Покупки баллов'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Продвижение'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Продвижение'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('payments and promotions realtime update only targeted blocks',
      (tester) async {
    final adminService = _FakeAdminService();
    final socket = _FakeDashboardSocketService();
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<AdminService>.value(value: adminService),
          Provider<ChatSocketService>.value(value: socket),
          Provider<NotificationsService>.value(
              value: _FakeNotificationsService()),
          Provider<SavedSearchService>.value(value: _FakeSavedSearchService()),
        ],
        child: const MaterialApp(
          home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
        ),
      ),
    );
    await tester.pumpAndSettle();

    socket.emitEvent('admin.dashboard.changed', <String, dynamic>{
      'scopes': <String>['payments', 'promotions'],
    });
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(adminService.dashboardStatsCalls, 1);
    expect(adminService.dashboardMetricsCalls, 1);
    expect(adminService.lastDashboardMetricScopes,
        containsAll(<String>['payments', 'promotions']));
    expect(find.text('9 999 ₽'), findsNothing);
    expect(find.text('777 баллов'), findsNothing);
    expect(find.text('Выручка'), findsOneWidget);
    expect(find.text('Продвижение'), findsOneWidget);
    expect(find.text('Пользователей'), findsOneWidget);
    await socket.close();
  });

  testWidgets('compact financial entries fit a small screen', (tester) async {
    final adminService = _FakeAdminService();
    adminService.dashboardStatsHandler = (_) async {
      final response = adminService.dashboardResponse();
      final stats = response['stats'] as Map<String, dynamic>;
      stats['revenue'] = <String, dynamic>{
        'todayRub': 1234567890.25,
        'days7Rub': 9876543210,
        'days30Rub': 123456789012,
      };
      stats['promotionsToday'] = <String, dynamic>{
        'byType': <String, dynamic>{
          'bump': 1234567,
          'vip': 2345678,
          'showcase': 3456789,
          'turbo': 4567890,
        },
        'total': 11604924,
        'pointsSpent': 987654321,
      };
      return response;
    };
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<AdminService>.value(value: adminService),
          Provider<NotificationsService>.value(
              value: _FakeNotificationsService()),
          Provider<SavedSearchService>.value(value: _FakeSavedSearchService()),
        ],
        child: const MaterialApp(
          home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();

    expect(find.text('Выручка'), findsOneWidget);
    expect(find.text('1 234 567 890,25 ₽'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.text('Продвижение'), findsOneWidget);
    expect(find.text('987 654 321 баллов'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'moderation keeps current list visible while status refresh is loading',
    (tester) async {
      final adminService = _FakeAdminService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AuthService>.value(value: _FakeAuthService()),
            Provider<AdminService>.value(value: adminService),
            Provider<NotificationsService>.value(
              value: _FakeNotificationsService(),
            ),
            Provider<SavedSearchService>.value(
              value: _FakeSavedSearchService(),
            ),
          ],
          child: const MaterialApp(
            home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Модерация'));
      await tester.pumpAndSettle();

      expect(find.text('Pending listing'), findsOneWidget);

      await tester.tap(find.text('Все'));
      await tester.pump();

      expect(find.text('Pending listing'), findsOneWidget);
      expect(
        find.byKey(const Key('admin_moderation_inline_spinner')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('All listing'), findsOneWidget);
      expect(find.text('Pending listing'), findsNothing);
      expect(
        find.byKey(const Key('admin_moderation_inline_spinner')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'moderation loads listings on open and does not auto-refresh in background',
    (tester) async {
      final adminService = _FakeAdminService(includeModerationDiff: true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AuthService>.value(value: _FakeAuthService()),
            Provider<AdminService>.value(value: adminService),
            Provider<NotificationsService>.value(
              value: _FakeNotificationsService(),
            ),
            Provider<SavedSearchService>.value(
              value: _FakeSavedSearchService(),
            ),
          ],
          child: const MaterialApp(
            home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Модерация'));
      await tester.pumpAndSettle();
      expect(find.text('Изменено'), findsOneWidget);

      final callsAfterOpen = adminService.listingsCalls;
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();

      expect(callsAfterOpen, greaterThanOrEqualTo(1));
      expect(adminService.listingsCalls, callsAfterOpen);
    },
  );

  testWidgets(
    'admin header streams are not recreated on rebuild',
    (tester) async {
      final adminService = _FakeAdminService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AuthService>.value(value: _FakeAuthService()),
            Provider<AdminService>.value(value: adminService),
            Provider<NotificationsService>.value(
              value: _FakeNotificationsService(),
            ),
            Provider<SavedSearchService>.value(
              value: _FakeSavedSearchService(),
            ),
          ],
          child: const MaterialApp(
            home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final isAdminCallsAfterFirstBuild = adminService.isAdminStreamCalls;
      final pendingCallsAfterFirstBuild =
          adminService.pendingModerationStreamCalls;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AuthService>.value(value: _FakeAuthService()),
            Provider<AdminService>.value(value: adminService),
            Provider<NotificationsService>.value(
              value: _FakeNotificationsService(),
            ),
            Provider<SavedSearchService>.value(
              value: _FakeSavedSearchService(),
            ),
          ],
          child: const MaterialApp(
            home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(adminService.isAdminStreamCalls, isAdminCallsAfterFirstBuild);
      expect(
        adminService.pendingModerationStreamCalls,
        pendingCallsAfterFirstBuild,
      );
    },
  );

  testWidgets(
    'moderation listing opens detailed preview with description and extra fields',
    (tester) async {
      final adminService = _FakeAdminService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AuthService>.value(value: _FakeAuthService()),
            Provider<AdminService>.value(value: adminService),
            Provider<NotificationsService>.value(
              value: _FakeNotificationsService(),
            ),
            Provider<SavedSearchService>.value(
              value: _FakeSavedSearchService(),
            ),
          ],
          child: const MaterialApp(
            home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Модерация'));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey('admin-moderation-item:listing-pending')));
      await tester.pumpAndSettle();

      expect(find.text('Проверка объявления'), findsOneWidget);
      expect(find.text('Описание'), findsOneWidget);
      expect(find.text('Продавец'), findsOneWidget);
      expect(
          find.textContaining('Подробное описание объявления'), findsOneWidget);
      expect(find.text('Телефон'), findsOneWidget);
      expect(find.textContaining('+7 999 000 00 00'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Дополнительные поля'), 300);
      await tester.pumpAndSettle();
      expect(find.text('Дополнительные поля'), findsOneWidget);
      expect(find.textContaining('Марка'), findsOneWidget);
      expect(find.textContaining('BMW'), findsOneWidget);
      expect(find.text('Одобрить ✅'), findsOneWidget);
      expect(find.text('Отклонить ❌'), findsOneWidget);
    },
  );

  testWidgets('moderation photo opens existing full screen viewer',
      (tester) async {
    await tester.pumpWidget(_buildModerationReviewApp(<String, dynamic>{
      ..._moderationListingFixture(),
      'photo_urls': <String>[
        '/media/object?category=listings&key=listings%2Fphoto-1.jpg',
        '/media/object?category=listings&key=listings%2Fphoto-2.jpg',
      ],
    }));
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('admin_moderation_photo_0')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PhotoViewerScreen), findsOneWidget);
    final viewer = tester.widget<PhotoViewerScreen>(
      find.byType(PhotoViewerScreen),
    );
    expect(viewer.photoUrls, hasLength(2));
    expect(viewer.photoUrls.first, startsWith('http'));
    expect(viewer.photoUrls.first, contains('category=listings'));
    expect(viewer.initialIndex, 0);
  });

  testWidgets('moderation keeps technical ids compact and copyable',
      (tester) async {
    await tester.pumpWidget(_buildModerationReviewApp(<String, dynamic>{
      ..._moderationListingFixture(),
      'id': 'ca5a2cbf-dfe7-41a7-8101-123456789abc',
      'moderated_by': 'a1b2c3d4-e5f6-47a8-9012-abcdef123456',
      'owner': <String, dynamic>{
        'id': 'seller-1',
        'large_internal_value': List<String>.filled(20, 'internal').join('-'),
      },
    }));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('admin_moderation_technical_data')),
      300,
    );
    await tester.tap(
      find.byKey(const ValueKey('admin_moderation_technical_data')),
    );
    await tester.pumpAndSettle();

    expect(find.text('ID объявления'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin_moderation_copy:listing_id')),
      findsOneWidget,
    );
    expect(find.textContaining('large_internal_value'), findsNothing);
  });

  testWidgets('moderation video is visible and opens playback url',
      (tester) async {
    final previousLauncher = UrlLauncherPlatform.instance;
    final launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);

    await tester.pumpWidget(_buildModerationReviewApp(<String, dynamic>{
      ..._moderationListingFixture(),
      'video': <String, dynamic>{
        'provider': 'rutube',
        'originalUrl': 'https://rutube.example/original',
        'videoId': 'video-1',
        'playbackUrl': 'https://rutube.example/watch/video-1',
        'thumbnailUrl': 'https://example.com/video-thumb.jpg',
      },
    }));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('admin_moderation_video')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('admin_moderation_video')),
    );
    await tester.pump();

    expect(
      launcher.launchedUrls,
      contains('https://rutube.example/watch/video-1'),
    );
  });

  testWidgets('moderation changes show real before and after values in green',
      (tester) async {
    await tester.pumpWidget(_buildModerationReviewApp(<String, dynamic>{
      ..._moderationListingFixture(),
      'price': 450000,
      'phone_hidden': true,
      'car': <String, dynamic>{'brand': 'BMW', 'model': 'X5'},
      'moderation_diff': <String, dynamic>{
        'changed': <Map<String, dynamic>>[
          <String, dynamic>{
            'field': 'price',
            'label': 'Цена',
            'before': 500000,
            'after': 450000,
          },
          <String, dynamic>{
            'field': 'phone_hidden',
            'label': 'Телефон скрыт',
            'before': false,
            'after': true,
          },
          <String, dynamic>{
            'field': 'car',
            'label': 'Характеристики',
            'before': <String, dynamic>{'brand': 'BMW', 'model': 'X3'},
            'after': <String, dynamic>{'brand': 'BMW', 'model': 'X5'},
          },
        ],
      },
    }));
    await tester.pumpAndSettle();

    final priceChange = find.byKey(
      const ValueKey('admin_moderation_change:price'),
    );
    expect(priceChange, findsOneWidget);
    expect(
      find.descendant(of: priceChange, matching: find.text('Было: 500000 ₽')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: priceChange, matching: find.text('Стало: 450000 ₽')),
      findsOneWidget,
    );
    final priceContainer = tester.widget<Container>(priceChange);
    final decoration = priceContainer.decoration! as BoxDecoration;
    expect(decoration.border, isNotNull);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('admin_moderation_change:phone_hidden')),
      300,
    );
    expect(
      find.byKey(const ValueKey('admin_moderation_change:phone_hidden')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('admin_moderation_change:car')),
      300,
    );
    expect(
      find.byKey(const ValueKey('admin_moderation_change:car')),
      findsOneWidget,
    );
  });

  testWidgets('moderation detail keeps all existing administrative actions',
      (tester) async {
    await tester.pumpWidget(
      _buildModerationReviewApp(_moderationListingFixture()),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Одобрить ✅'), 500);
    expect(find.text('Одобрить ✅'), findsOneWidget);
    expect(find.text('Отклонить ❌'), findsOneWidget);
    expect(find.text('Удалить полностью'), findsOneWidget);
    expect(find.text('Заблокировать пользователя'), findsOneWidget);
  });

  testWidgets('moderation approve removes item immediately', (tester) async {
    final adminService = _FakeAdminService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<AdminService>.value(value: adminService),
          Provider<NotificationsService>.value(
            value: _FakeNotificationsService(),
          ),
          Provider<SavedSearchService>.value(
            value: _FakeSavedSearchService(),
          ),
        ],
        child: const MaterialApp(
          home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Модерация'));
    await tester.pumpAndSettle();
    expect(find.text('Pending listing'), findsOneWidget);

    await tester.tap(find.text('Одобрить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Pending listing'), findsNothing);
    expect(adminService.approvedIds, <String>['listing-pending']);
  });

  testWidgets('moderation reject removes item immediately', (tester) async {
    final adminService = _FakeAdminService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<AdminService>.value(value: adminService),
          Provider<NotificationsService>.value(
            value: _FakeNotificationsService(),
          ),
          Provider<SavedSearchService>.value(
            value: _FakeSavedSearchService(),
          ),
        ],
        child: const MaterialApp(
          home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Модерация'));
    await tester.pumpAndSettle();
    expect(find.text('Pending listing'), findsOneWidget);

    await tester.tap(find.text('Отклонить'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Нарушение правил');
    await tester.tap(find.text('Отклонить').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Pending listing'), findsNothing);
    expect(adminService.rejectedIds, <String>['listing-pending']);
  });

  testWidgets('opening one admin section clears only its badge',
      (tester) async {
    final adminService = _FakeAdminService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<AdminService>.value(value: adminService),
          Provider<NotificationsService>.value(
            value: _FakeNotificationsService(),
          ),
          Provider<SavedSearchService>.value(
            value: _FakeSavedSearchService(),
          ),
        ],
        child: const MaterialApp(
          home: AdminScreen(usageAnalyticsLoad: _loadUsageAnalytics),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('admin-tab-badge:Модерация')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('admin-tab-badge:Жалобы')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Модерация'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('admin-tab-badge:Модерация')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('admin-tab-badge:Жалобы')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
        adminService.markedSections, contains(AdminService.moderationSection));
    expect(
      adminService.markedSections,
      isNot(contains(AdminService.reportsSection)),
    );
  });
}

Future<Map<String, dynamic>> _loadUsageAnalytics() async => <String, dynamic>{
      'periods': <String, dynamic>{
        'today': <String, dynamic>{
          'guests': 2,
          'guestOpens': 3,
          'registeredOpens': 4,
          'totalOpens': 7,
          'messages': 5,
          'activeChats': 1,
        },
      },
      'platforms': <String, dynamic>{
        for (final period in <String>['today', 'week', 'month', 'all'])
          period: <String, dynamic>{
            'active': <String, dynamic>{'ios': 1, 'android': 2, 'web': 3},
            'registrations': <String, dynamic>{
              'ios': 4,
              'android': 5,
              'web': 6,
              'unknown': 0,
            },
            'versions': <Map<String, dynamic>>[],
          },
      },
    };

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(
        uid: 'admin-1',
        email: 'admin@example.com',
        displayName: 'Admin',
        isAdmin: true,
      );
}

class _FakeAdminService extends AdminService {
  _FakeAdminService({this.includeModerationDiff = false}) {
    _moderationBadges.add(2);
    _supportBadges.add(0);
    _reportsBadges.add(1);
  }

  final bool includeModerationDiff;
  final List<String> approvedIds = <String>[];
  final List<String> rejectedIds = <String>[];
  final List<String> markedSections = <String>[];
  bool _showPending = true;
  int listingsCalls = 0;
  int isAdminStreamCalls = 0;
  int pendingModerationStreamCalls = 0;
  int unreadSupportStreamCalls = 0;
  int openReportsStreamCalls = 0;
  int dashboardStatsCalls = 0;
  int dashboardMetricsCalls = 0;
  int appDownloadsCalls = 0;
  Set<String> lastDashboardMetricScopes = <String>{};
  Future<Map<String, dynamic>> Function(bool forceRefresh)?
      dashboardStatsHandler;
  bool lastDashboardForceRefresh = false;
  int _moderationBadgeCount = 2;
  int _supportBadgeCount = 0;
  int _reportsBadgeCount = 1;
  final StreamController<int> _moderationBadges =
      StreamController<int>.broadcast();
  final StreamController<int> _supportBadges =
      StreamController<int>.broadcast();
  final StreamController<int> _reportsBadges =
      StreamController<int>.broadcast();

  @override
  void bindAdminUser(String uid) {}

  @override
  Stream<bool> streamIsAdmin(String uid) {
    isAdminStreamCalls += 1;
    return Stream<bool>.value(true);
  }

  @override
  Stream<int> streamPendingModerationCount() {
    pendingModerationStreamCalls += 1;
    return Stream<int>.multi((controller) {
      controller.add(_moderationBadgeCount);
      final sub = _moderationBadges.stream.listen(controller.add);
      controller.onCancel = () async => sub.cancel();
    });
  }

  @override
  Stream<int> streamUnreadSupportForAdminCount() {
    unreadSupportStreamCalls += 1;
    return Stream<int>.multi((controller) {
      controller.add(_supportBadgeCount);
      final sub = _supportBadges.stream.listen(controller.add);
      controller.onCancel = () async => sub.cancel();
    });
  }

  @override
  Stream<int> streamOpenReportsCount() {
    openReportsStreamCalls += 1;
    return Stream<int>.multi((controller) {
      controller.add(_reportsBadgeCount);
      final sub = _reportsBadges.stream.listen(controller.add);
      controller.onCancel = () async => sub.cancel();
    });
  }

  @override
  Future<void> markSectionSeen(String section) async {
    markedSections.add(section);
    switch (section) {
      case AdminService.moderationSection:
        _moderationBadgeCount = 0;
        _moderationBadges.add(0);
        break;
      case AdminService.supportSection:
        _supportBadgeCount = 0;
        _supportBadges.add(0);
        break;
      case AdminService.reportsSection:
        _reportsBadgeCount = 0;
        _reportsBadges.add(0);
        break;
    }
  }

  @override
  Future<Map<String, dynamic>> dashboardStats(
      {bool forceRefresh = false}) async {
    dashboardStatsCalls += 1;
    lastDashboardForceRefresh = forceRefresh;
    final handler = dashboardStatsHandler;
    if (handler != null) return handler(forceRefresh);
    return dashboardResponse();
  }

  @override
  Future<Map<String, dynamic>> appDownloads({bool forceRefresh = false}) async {
    appDownloadsCalls += 1;
    return <String, dynamic>{
      'ios': <String, dynamic>{
        'status': 'ready',
        'metricLabel': 'Первые загрузки',
        'timeZone': 'UTC',
        'today': 12,
        'yesterday': 10,
        'last7Days': 70,
        'last30Days': 300,
        'allTime': 1400,
        'latestReportDate': '2026-11-05',
        'lastUpdatedAt': '2026-11-05T08:10:00.000Z',
      },
      'android': <String, dynamic>{
        'status': 'ready',
        'metricLabel': 'Установки пользователями',
        'timeZone': 'America/Los_Angeles',
        'today': null,
        'yesterday': 15,
        'last7Days': 96,
        'last30Days': 355,
        'allTime': 1670,
        'latestReportDate': '2026-11-04',
        'lastUpdatedAt': '2026-11-05T09:00:00.000Z',
      },
    };
  }

  Map<String, dynamic> dashboardResponse() {
    return <String, dynamic>{
      'stats': <String, dynamic>{
        'users': 1,
        'onlineUsers': 1,
        'listings': 1,
        'activeListings': 1,
        'sold': 0,
        'sales30d': 0,
        'spentPoints30d': 415,
        'pendingModeration': 1,
        'supportTickets': 0,
        'reportsOpen': 0,
        'activeAds': 0,
        'pointsPurchasesMonth': <String, dynamic>{
          'totalAmountRub': 1250,
          'totalPoints': 500,
          'purchasesCount': 2,
        },
        'revenue': <String, dynamic>{
          'todayRub': 1250,
          'days7Rub': 8400,
          'days30Rub': 29100.25,
        },
        'promotionsToday': <String, dynamic>{
          'byType': <String, dynamic>{
            'bump': 8,
            'vip': 2,
            'showcase': 1,
            'turbo': 0,
          },
          'total': 11,
          'pointsSpent': 420,
        },
      },
      'daily': <String, dynamic>{
        'listings': <Map<String, dynamic>>[
          <String, dynamic>{'listings_new': 1},
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> dashboardMetrics(Set<String> scopes) async {
    dashboardMetricsCalls += 1;
    lastDashboardMetricScopes = Set<String>.from(scopes);
    return <String, dynamic>{
      'scopes': scopes.toList(),
      'stats': <String, dynamic>{
        if (scopes.contains('presence')) 'onlineUsers': 7,
        if (scopes.contains('listings')) 'listings': 3,
        if (scopes.contains('searches')) 'allSearches': 9,
        if (scopes.contains('payments'))
          'revenue': <String, dynamic>{
            'todayRub': 9999,
            'days7Rub': 12000,
            'days30Rub': 45000,
          },
        if (scopes.contains('promotions'))
          'promotionsToday': <String, dynamic>{
            'byType': <String, dynamic>{
              'bump': 9,
              'vip': 3,
              'showcase': 2,
              'turbo': 1,
            },
            'total': 15,
            'pointsSpent': 777,
          },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> pointsPurchasesSummary({
    String? from,
    String? to,
    String? search,
    bool forceRefresh = false,
  }) async {
    return <String, dynamic>{
      'summary': <String, dynamic>{
        'totalAmountRub': 1250,
        'totalPoints': 500,
        'purchasesCount': 2,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> pointsPurchases({
    String? from,
    String? to,
    String? search,
    int? limit,
    String? cursor,
    bool forceRefresh = false,
  }) async {
    return <String, dynamic>{
      'items': <Map<String, dynamic>>[],
      'hasMore': false,
      'nextCursor': null,
    };
  }

  @override
  Future<int> pendingModerationCount({bool forceRefresh = false}) async => 1;

  @override
  Future<Map<String, dynamic>> listings({
    String? status,
    int? limit,
    String? cursor,
    bool forceRefresh = false,
  }) async {
    listingsCalls += 1;
    if (status == 'all') {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return <String, dynamic>{
        'items': <Map<String, dynamic>>[
          _listingMap(id: 'listing-all', title: 'All listing'),
        ],
      };
    }

    return <String, dynamic>{
      'items': _showPending
          ? <Map<String, dynamic>>[
              if (includeModerationDiff)
                <String, dynamic>{
                  ..._listingMap(
                      id: 'listing-pending', title: 'Pending listing'),
                  'moderation_diff': <String, dynamic>{
                    'changed': <Map<String, dynamic>>[
                      <String, dynamic>{
                        'field': 'price',
                        'before': 500000,
                        'after': 450000,
                      },
                    ],
                  },
                }
              else
                _listingMap(id: 'listing-pending', title: 'Pending listing'),
            ]
          : const <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> approveListing(String listingId) async {
    approvedIds.add(listingId);
    _showPending = false;
    return <String, dynamic>{
      'listing': _listingMap(id: listingId, title: 'Pending listing')
    };
  }

  @override
  Future<Map<String, dynamic>> rejectListing(
    String listingId, {
    String? reason,
    String? moderationNote,
  }) async {
    rejectedIds.add(listingId);
    _showPending = false;
    return <String, dynamic>{
      'listing': _listingMap(id: listingId, title: 'Pending listing')
    };
  }

  Map<String, dynamic> _listingMap({
    required String id,
    required String title,
  }) {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'price': 1000,
      'city': 'Москва',
      'category': 'Транспорт',
      'subcategory': 'Легковые',
      'description': 'Подробное описание объявления для модерации.',
      'phone': '+79990000000',
      'brand': 'BMW',
      'condition': 'Б/у',
      'owner_name': 'Seller',
      'status': 'pending',
      'created_at': '2026-07-01T10:00:00.000Z',
    };
  }
}

class _FakeNotificationsService extends NotificationsService {}

class _FakeSavedSearchService extends SavedSearchService {}

Widget _buildModerationReviewApp(Map<String, dynamic> listing) {
  return MultiProvider(
    providers: [
      Provider<AuthService>.value(value: _FakeAuthService()),
      Provider<AdminService>.value(value: _FakeAdminService()),
      Provider<NotificationsService>.value(
        value: _FakeNotificationsService(),
      ),
    ],
    child: MaterialApp(
      home: AdminListingReviewScreen(
        listingId: (listing['id'] ?? '').toString(),
        listingData: listing,
      ),
    ),
  );
}

Map<String, dynamic> _moderationListingFixture() => <String, dynamic>{
      'id': 'listing-review',
      'title': 'BMW X5',
      'price': 500000,
      'city': 'Москва',
      'address': 'ул. Тестовая, 1',
      'category': 'Авто',
      'subcategory': 'Легковые',
      'description': 'Описание объявления для проверки.',
      'phone': '+79990000000',
      'phone_hidden': false,
      'owner_id': 'seller-1',
      'owner_name': 'Seller',
      'status': 'pending',
      'created_at': '2026-07-01T10:00:00.000Z',
      'delivery': <String, dynamic>{'pickup': true},
      'photo_urls': const <String>[],
    };

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = <String>[];

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDashboardSocketService extends ChatSocketService {
  final StreamController<ChatSocketEvent> _eventController =
      StreamController<ChatSocketEvent>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  int subscribeAnalyticsCalls = 0;

  @override
  Stream<ChatSocketEvent> get events => _eventController.stream;

  @override
  Stream<bool> get connectionChanges => _connectionController.stream;

  @override
  void subscribeAnalytics() {
    subscribeAnalyticsCalls += 1;
  }

  bool get hasEventListener => _eventController.hasListener;
  bool get hasConnectionListener => _connectionController.hasListener;

  void emitEvent(String name, [Map<String, dynamic>? payload]) {
    _eventController.add(ChatSocketEvent(name, payload ?? <String, dynamic>{}));
  }

  void emitConnection(bool connected) => _connectionController.add(connected);

  Future<void> close() async {
    await _eventController.close();
    await _connectionController.close();
  }
}
