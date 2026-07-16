import 'dart:async';

import 'package:atta/src/features/admin/admin_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/saved_search_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
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
          child: const MaterialApp(home: AdminScreen()),
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
          child: const MaterialApp(home: AdminScreen()),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Модерация'));
      await tester.pumpAndSettle();

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
          child: const MaterialApp(home: AdminScreen()),
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
          child: const MaterialApp(home: AdminScreen()),
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
          child: const MaterialApp(home: AdminScreen()),
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
      expect(find.textContaining('Телефон'), findsOneWidget);
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
        child: const MaterialApp(home: AdminScreen()),
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
        child: const MaterialApp(home: AdminScreen()),
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
        child: const MaterialApp(home: AdminScreen()),
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
  final List<String> approvedIds = <String>[];
  final List<String> rejectedIds = <String>[];
  final List<String> markedSections = <String>[];
  bool _showPending = true;
  int listingsCalls = 0;
  int isAdminStreamCalls = 0;
  int pendingModerationStreamCalls = 0;
  int unreadSupportStreamCalls = 0;
  int openReportsStreamCalls = 0;
  int _moderationBadgeCount = 2;
  int _supportBadgeCount = 0;
  int _reportsBadgeCount = 1;
  final StreamController<int> _moderationBadges =
      StreamController<int>.broadcast();
  final StreamController<int> _supportBadges =
      StreamController<int>.broadcast();
  final StreamController<int> _reportsBadges =
      StreamController<int>.broadcast();

  _FakeAdminService() {
    _moderationBadges.add(2);
    _supportBadges.add(0);
    _reportsBadges.add(1);
  }

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
      },
      'daily': <String, dynamic>{
        'listings': <Map<String, dynamic>>[
          <String, dynamic>{'listings_new': 1},
        ],
      },
    };
  }

  @override
  Future<int> pendingModerationCount({bool forceRefresh = false}) async => 1;

  @override
  Future<Map<String, dynamic>> listings({
    String? status,
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
