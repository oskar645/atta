import 'dart:async';

import 'package:atta/src/features/listings/my_listings_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('my listings first load shows skeleton then empty state',
      (tester) async {
    final listingsService = _DelayedListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    expect(find.byType(SkeletonAdminModerationCard), findsWidgets);

    await tester.pumpAndSettle();

    expect(find.text('Нет активных объявлений'), findsOneWidget);
  });

  testWidgets('moderation archived deleted and sold tabs keep skeleton flow',
      (tester) async {
    final listingsService = _DelayedListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    expect(find.byType(SkeletonAdminModerationCard), findsWidgets);

    await tester.tap(find.text('На модерации'));
    await tester.pump();
    expect(find.byType(SkeletonAdminModerationCard), findsWidgets);

    await tester.tap(find.text('Архивные'));
    await tester.pump();
    expect(find.byType(SkeletonAdminModerationCard), findsWidgets);

    await tester.ensureVisible(find.text('Удалённые'));
    await tester.tap(find.text('Удалённые'));
    await tester.pump();
    expect(find.byType(SkeletonAdminModerationCard), findsWidgets);

    await tester.ensureVisible(find.text('Проданные'));
    await tester.tap(find.text('Проданные'));
    await tester.pumpAndSettle();
    expect(find.text('Нет проданных объявлений'), findsOneWidget);
  });

  testWidgets('active listing keeps sell faster button enabled',
      (tester) async {
    final listingsService = _ListingsWithItemService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Продать быстрее'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Продать быстрее'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('non-active listing hides sell faster button', (tester) async {
    final listingsService = _ListingsWithPendingItemService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    await tester.tap(find.text('На модерации'));
    await tester.pumpAndSettle();

    expect(find.text('Продать быстрее'), findsNothing);
  });

  testWidgets('archived listing disappears from active tab immediately',
      (tester) async {
    final listingsService = _ReactiveListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Велосипед'), findsOneWidget);

    await listingsService.archiveCurrent();
    await tester.pump();

    expect(find.text('Велосипед'), findsNothing);
    expect(find.text('Нет активных объявлений'), findsOneWidget);
  });

  testWidgets(
      'pending listing moves to active tab immediately after moderation update',
      (tester) async {
    final listingsService = _ModerationReactiveListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    await tester.tap(find.text('На модерации'));
    await tester.pumpAndSettle();
    expect(find.text('Самокат'), findsOneWidget);

    await listingsService.approveCurrent();
    await tester.pump();

    expect(find.text('Самокат'), findsNothing);

    await tester.tap(find.text('Активные'));
    await tester.pumpAndSettle();
    expect(find.text('Самокат'), findsOneWidget);
  });
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'user-1');
}

class _DelayedListingsService extends ListingsService {
  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return const <Listing>[];
  }
}

class _ListingsWithItemService extends ListingsService {
  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
  }) async {
    if (!statuses.contains('approved')) {
      return const <Listing>[];
    }
    return <Listing>[
      Listing.fromMap(<String, dynamic>{
        'id': 'listing-1',
        'owner_id': 'user-1',
        'owner_email': 'user@example.com',
        'owner_name': 'User',
        'title': 'Велосипед',
        'description': 'Описание',
        'category': 'Транспорт',
        'subcategory': 'Велосипеды',
        'price': 10000,
        'phone': '',
        'phone_hidden': false,
        'city': 'Москва',
        'delivery': <String, dynamic>{},
        'photo_urls': const <String>[],
        'view_count': 0,
        'status': 'approved',
        'rejection_reason': '',
        'can_promote': false,
        'cannot_promote_reason': 'Объявление пока на модерации.',
        'created_at': '2026-06-20T10:00:00.000Z',
      }),
    ];
  }
}

class _ListingsWithPendingItemService extends ListingsService {
  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
  }) async {
    if (!statuses.contains('pending')) {
      return const <Listing>[];
    }
    return <Listing>[
      Listing.fromMap(<String, dynamic>{
        'id': 'listing-2',
        'owner_id': 'user-1',
        'owner_email': 'user@example.com',
        'owner_name': 'User',
        'title': 'Самокат',
        'description': 'Описание',
        'category': 'Транспорт',
        'subcategory': 'Самокаты',
        'price': 7000,
        'phone': '',
        'phone_hidden': false,
        'city': 'Москва',
        'delivery': <String, dynamic>{},
        'photo_urls': const <String>[],
        'view_count': 0,
        'status': 'pending',
        'rejection_reason': '',
        'can_promote': false,
        'created_at': '2026-06-20T10:00:00.000Z',
      }),
    ];
  }
}

class _ReactiveListingsService extends ListingsService {
  final List<Listing> _active = <Listing>[
    Listing.fromMap(<String, dynamic>{
      'id': 'listing-1',
      'owner_id': 'user-1',
      'owner_email': 'user@example.com',
      'owner_name': 'User',
      'title': 'Велосипед',
      'description': 'Описание',
      'category': 'Транспорт',
      'subcategory': 'Велосипеды',
      'price': 10000,
      'phone': '',
      'phone_hidden': false,
      'city': 'Москва',
      'delivery': <String, dynamic>{},
      'photo_urls': const <String>[],
      'view_count': 0,
      'status': 'approved',
      'rejection_reason': '',
      'can_promote': false,
      'cannot_promote_reason': '',
      'created_at': '2026-06-20T10:00:00.000Z',
    }),
  ];

  final StreamController<void> _refreshes = StreamController<void>.broadcast();

  @override
  Stream<void> get refreshes => _refreshes.stream;

  @override
  List<Listing> peekMyListingsByStatuses({
    required Set<String> statuses,
  }) {
    return _active.where((item) => statuses.contains(item.status)).toList();
  }

  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
  }) async {
    return peekMyListingsByStatuses(statuses: statuses);
  }

  Future<void> archiveCurrent() async {
    _active.clear();
    _refreshes.add(null);
  }
}

class _ModerationReactiveListingsService extends ListingsService {
  final List<Listing> _items = <Listing>[
    Listing.fromMap(<String, dynamic>{
      'id': 'listing-2',
      'owner_id': 'user-1',
      'owner_email': 'user@example.com',
      'owner_name': 'User',
      'title': 'Самокат',
      'description': 'Описание',
      'category': 'Транспорт',
      'subcategory': 'Самокаты',
      'price': 7000,
      'phone': '',
      'phone_hidden': false,
      'city': 'Москва',
      'delivery': <String, dynamic>{},
      'photo_urls': const <String>[],
      'view_count': 0,
      'status': 'pending',
      'rejection_reason': '',
      'can_promote': false,
      'created_at': '2026-06-20T10:00:00.000Z',
    }),
  ];

  final StreamController<void> _refreshes = StreamController<void>.broadcast();

  @override
  Stream<void> get refreshes => _refreshes.stream;

  @override
  List<Listing> peekMyListingsByStatuses({
    required Set<String> statuses,
  }) {
    return _items.where((item) => statuses.contains(item.status)).toList();
  }

  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
  }) async {
    return peekMyListingsByStatuses(statuses: statuses);
  }

  Future<void> approveCurrent() async {
    _items[0] = Listing.fromMap(<String, dynamic>{
      ..._items[0].toMap(),
      'status': 'approved',
    });
    _refreshes.add(null);
  }
}
