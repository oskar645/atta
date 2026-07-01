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
      await tester.tap(find.byKey(const ValueKey('admin-moderation-item:listing-pending')));
      await tester.pumpAndSettle();

      expect(find.text('Проверка объявления'), findsOneWidget);
      expect(find.text('Описание'), findsOneWidget);
      expect(find.text('Продавец'), findsOneWidget);
      expect(find.textContaining('Подробное описание объявления'), findsOneWidget);
      expect(find.textContaining('Телефон'), findsOneWidget);
      expect(find.textContaining('+79990000000'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Дополнительные поля'), 300);
      await tester.pumpAndSettle();
      expect(find.text('Дополнительные поля'), findsOneWidget);
      expect(find.textContaining('Марка'), findsOneWidget);
      expect(find.textContaining('BMW'), findsOneWidget);
      expect(find.text('Одобрить ✅'), findsOneWidget);
      expect(find.text('Отклонить ❌'), findsOneWidget);
    },
  );
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
  @override
  Stream<bool> streamIsAdmin(String uid) => Stream<bool>.value(true);

  @override
  Stream<int> streamPendingModerationCount() => Stream<int>.value(1);

  @override
  Stream<int> streamUnreadSupportForAdminCount() => Stream<int>.value(0);

  @override
  Stream<int> streamOpenReportsCount() => Stream<int>.value(0);

  @override
  Future<Map<String, dynamic>> dashboardStats({bool forceRefresh = false}) async {
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
    if (status == 'all') {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return <String, dynamic>{
        'items': <Map<String, dynamic>>[
          _listingMap(id: 'listing-all', title: 'All listing'),
        ],
      };
    }

    return <String, dynamic>{
      'items': <Map<String, dynamic>>[
        _listingMap(id: 'listing-pending', title: 'Pending listing'),
      ],
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
