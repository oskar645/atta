import 'dart:async';

import 'package:atta/src/features/listings/my_listings_screen.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/follow_service.dart';
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
          Provider<FollowService>.value(value: _FakeFollowService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    expect(find.byType(SkeletonMyListingTile), findsWidgets);

    await tester.pumpAndSettle();

    expect(find.text('Нет активных объявлений'), findsOneWidget);
  });

  testWidgets('my listings loads active items automatically without pull',
      (tester) async {
    final listingsService = _ListingsWithItemService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    expect(find.text('Нет активных объявлений'), findsNothing);

    await tester.pumpAndSettle();

    expect(find.text('Велосипед'), findsOneWidget);
    expect(find.text('Нет активных объявлений'), findsNothing);
  });

  testWidgets('my listings load error clears skeleton and shows retry',
      (tester) async {
    final listingsService = _FailingListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    expect(find.byType(SkeletonMyListingTile), findsWidgets);

    await tester.pumpAndSettle();

    expect(find.byType(SkeletonMyListingTile), findsNothing);
    expect(
      find.text('Не удалось загрузить объявления. Попробуйте снова.'),
      findsOneWidget,
    );
  });

  testWidgets('my listings retry after timeout loads fresh items',
      (tester) async {
    final listingsService = _TimeoutThenSuccessListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    await tester.pumpAndSettle();
    expect(
      find.text('Не удалось загрузить объявления. Попробуйте снова.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Повторить').first);
    await tester.pumpAndSettle();

    expect(find.text('Велосипед'), findsOneWidget);
    expect(
      find.text('Не удалось загрузить объявления. Попробуйте снова.'),
      findsNothing,
    );
    expect(listingsService.calls, 2);
  });

  testWidgets('my listings refresh keeps old list until response',
      (tester) async {
    final listingsService = _RefreshKeepsOldListService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Старое объявление'), findsOneWidget);

    final scrollable = find.byType(RefreshIndicator);
    await tester.drag(scrollable, const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Старое объявление'), findsOneWidget);
    expect(find.text('Нет активных объявлений'), findsNothing);

    listingsService.completeRefresh();
    await tester.pumpAndSettle();

    expect(find.text('Новое объявление'), findsOneWidget);
    expect(find.text('Старое объявление'), findsNothing);
  });

  testWidgets(
      'my listings shows cached items immediately and refreshes in background',
      (tester) async {
    final listingsService = _CachedRefreshOnOpenListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    expect(find.text('Старое объявление'), findsOneWidget);
    expect(find.byType(SkeletonMyListingTile), findsNothing);

    listingsService.completeRefresh();
    await tester.pumpAndSettle();

    expect(find.text('Новое объявление'), findsOneWidget);
    expect(find.text('Старое объявление'), findsNothing);
    expect(listingsService.forceRefreshCalls, 1);
  });

  testWidgets('network error does not clear old my listings data',
      (tester) async {
    final listingsService = _RefreshErrorKeepsOldListService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Старое объявление'), findsOneWidget);

    await tester.drag(find.byType(RefreshIndicator), const Offset(0, 300));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Старое объявление'), findsOneWidget);
    expect(find.text('Нет активных объявлений'), findsNothing);
    expect(
      find.text('Не удалось обновить объявления. Попробуйте ещё раз.'),
      findsOneWidget,
    );
  });

  testWidgets('delayed retry-style load does not show false empty state',
      (tester) async {
    final listingsService = _RetryLikeDelayedListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    expect(find.byType(SkeletonMyListingTile), findsWidgets);
    expect(find.text('Нет активных объявлений'), findsNothing);

    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(SkeletonMyListingTile), findsWidgets);
    expect(find.text('Нет активных объявлений'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('Велосипед'), findsOneWidget);
  });

  testWidgets('moderation archived deleted and sold tabs keep skeleton flow',
      (tester) async {
    final listingsService = _DelayedListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    expect(find.byType(SkeletonMyListingTile), findsWidgets);

    await tester.tap(find.text('На модерации'));
    await tester.pump();
    expect(find.byType(SkeletonMyListingTile), findsWidgets);

    await tester.tap(find.text('Архивные'));
    await tester.pump();
    expect(find.byType(SkeletonMyListingTile), findsWidgets);

    await tester.ensureVisible(find.text('Удалённые'));
    await tester.tap(find.text('Удалённые'));
    await tester.pump();
    expect(find.byType(SkeletonMyListingTile), findsWidgets);

    await tester.ensureVisible(find.text('Проданные'));
    await tester.tap(find.text('Проданные'));
    await tester.pumpAndSettle();
    expect(find.text('Нет проданных объявлений'), findsOneWidget);
  });

  testWidgets('switching tabs during first load does not show blank screen',
      (tester) async {
    final listingsService = _DelayedListingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    await tester.tap(find.text('На модерации'));
    await tester.pump();
    expect(find.byType(SkeletonMyListingTile), findsWidgets);

    await tester.tap(find.text('Активные'));
    await tester.pump();
    expect(find.byType(SkeletonMyListingTile), findsWidgets);

    await tester.pump(const Duration(milliseconds: 140));
    await tester.pumpAndSettle();
  });

  testWidgets('active listing keeps sell faster button enabled',
      (tester) async {
    final listingsService = _ListingsWithItemService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
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
    expect(find.text('Снять с публикации'), findsOneWidget);
    expect(find.text('В архив'), findsNothing);
    final bottomButtons = find.byType(OutlinedButton);
    expect(bottomButtons, findsNWidgets(2));
    expect(
      tester.getSize(bottomButtons.at(0)).height,
      tester.getSize(bottomButtons.at(1)).height,
    );
  });

  testWidgets('bottom actions stay single-line at compact and wide widths',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AuthService>.value(value: _FakeAuthService()),
            Provider<FollowService>.value(value: _FakeFollowService()),
            Provider<ListingsService>.value(value: _ListingsWithItemService()),
          ],
          child: const MaterialApp(home: MyListingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final editLabel = tester.widget<Text>(find.text('Редактировать'));
      final archiveLabel = tester.widget<Text>(find.text('Снять с публикации'));
      final bottomButtons = find.byType(OutlinedButton);

      expect(editLabel.maxLines, 1);
      expect(editLabel.overflow, TextOverflow.ellipsis);
      expect(archiveLabel.maxLines, 1);
      expect(archiveLabel.overflow, TextOverflow.ellipsis);
      expect(
        tester.getSize(bottomButtons.at(0)).height,
        tester.getSize(bottomButtons.at(1)).height,
      );
      if (width < 430) {
        expect(editLabel.style?.fontSize, 12);
        expect(archiveLabel.style?.fontSize, 11);
      } else {
        expect(editLabel.style?.fontSize, 14);
        expect(archiveLabel.style?.fontSize, 12);
      }
    }
  });

  testWidgets('active listing shows favorite count near views', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 800));
    final listingsService = _ListingsWithFavoriteCountService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<FollowService>.value(
            value: _FakeFollowService(followersCount: 3),
          ),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Просмотров: 7'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('my_listing_favorite_count:listing-3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('my_listing_followers_icon:listing-3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('my_listing_followers_count:listing-3')),
      findsOneWidget,
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    final viewsRect = tester.getRect(find.text('Просмотров: 7'));
    final favoriteIconRect = tester.getRect(
      find.byKey(const ValueKey('my_listing_favorite_icon:listing-3')),
    );
    final favoriteCountRect = tester.getRect(
      find.byKey(const ValueKey('my_listing_favorite_count:listing-3')),
    );
    final followersIconRect = tester.getRect(
      find.byKey(const ValueKey('my_listing_followers_icon:listing-3')),
    );
    final followersCountRect = tester.getRect(
      find.byKey(const ValueKey('my_listing_followers_count:listing-3')),
    );

    expect(favoriteIconRect.left - viewsRect.right, lessThanOrEqualTo(8));
    expect(
        followersIconRect.left - favoriteCountRect.right, lessThanOrEqualTo(8));
    expect(favoriteCountRect.right, lessThanOrEqualTo(320));
    expect(followersCountRect.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  for (final entry in <String, int>{
    'zero followers': 0,
    'one follower': 1,
    'several followers': 7,
  }.entries) {
    testWidgets('active listing shows ${entry.key} as person icon and count',
        (tester) async {
      final listingsService = _ListingsWithFavoriteCountService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AuthService>.value(value: _FakeAuthService()),
            Provider<FollowService>.value(
              value: _FakeFollowService(followersCount: entry.value),
            ),
            Provider<ListingsService>.value(value: listingsService),
          ],
          child: const MaterialApp(home: MyListingsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('my_listing_followers_icon:listing-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('my_listing_followers_count:listing-3')),
        findsOneWidget,
      );
      expect(find.text('${entry.value}'), findsOneWidget);
      expect(find.text('Просмотров: 7'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('my_listing_favorite_count:listing-3')),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget);
    });
  }

  testWidgets('non-active tabs do not show favorite count', (tester) async {
    final listingsService = _ListingsWithPendingFavoriteCountService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
          Provider<ListingsService>.value(value: listingsService),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );

    await tester.tap(find.text('На модерации'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('my_listing_favorite_count:listing-4')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('my_listing_followers_count:listing-4')),
      findsNothing,
    );
  });

  testWidgets('non-active listing hides sell faster button', (tester) async {
    final listingsService = _ListingsWithPendingItemService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
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
          Provider<FollowService>.value(value: _FakeFollowService()),
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
          Provider<FollowService>.value(value: _FakeFollowService()),
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

class _FakeFollowService extends FollowService {
  _FakeFollowService({this.followersCount = 0});

  final int followersCount;

  @override
  Stream<int> streamFollowersCount(String sellerId) {
    return Stream<int>.value(followersCount);
  }
}

class _DelayedListingsService extends ListingsService {
  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
    bool forceRefresh = false,
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
    bool forceRefresh = false,
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

class _FailingListingsService extends ListingsService {
  @override
  List<Listing> peekMyListingsByStatuses({
    required Set<String> statuses,
  }) {
    return const <Listing>[];
  }

  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
    bool forceRefresh = false,
  }) async {
    throw Exception('my listings failed');
  }
}

class _TimeoutThenSuccessListingsService extends ListingsService {
  int calls = 0;
  Object? _lastError;

  @override
  Object? lastMyListingsErrorForUser(String uid) => _lastError;

  @override
  List<Listing> peekMyListingsByStatuses({
    required Set<String> statuses,
  }) {
    return const <Listing>[];
  }

  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
    bool forceRefresh = false,
  }) async {
    if (!statuses.contains('approved')) {
      return const <Listing>[];
    }
    calls += 1;
    if (calls == 1) {
      _lastError = TimeoutException('Future not completed');
      return const <Listing>[];
    }
    _lastError = null;
    return <Listing>[
      _listing(
        id: 'listing-retry',
        title: 'Велосипед',
        status: 'approved',
      ),
    ];
  }
}

class _RefreshKeepsOldListService extends ListingsService {
  final Completer<List<Listing>> _refreshCompleter = Completer<List<Listing>>();

  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
    bool forceRefresh = false,
  }) {
    if (!statuses.contains('approved')) {
      return Future<List<Listing>>.value(const <Listing>[]);
    }
    if (forceRefresh) {
      return _refreshCompleter.future;
    }
    return Future<List<Listing>>.value(
      <Listing>[
        _listing(
          id: 'listing-old',
          title: 'Старое объявление',
          status: 'approved',
        ),
      ],
    );
  }

  void completeRefresh() {
    _refreshCompleter.complete(
      <Listing>[
        _listing(
          id: 'listing-new',
          title: 'Новое объявление',
          status: 'approved',
        ),
      ],
    );
  }
}

class _RefreshErrorKeepsOldListService extends ListingsService {
  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
    bool forceRefresh = false,
  }) async {
    if (!statuses.contains('approved')) {
      return const <Listing>[];
    }
    if (forceRefresh) {
      throw const ApiException('network');
    }
    return <Listing>[
      _listing(
        id: 'listing-old',
        title: 'Старое объявление',
        status: 'approved',
      ),
    ];
  }
}

class _CachedRefreshOnOpenListingsService extends ListingsService {
  final Completer<List<Listing>> _refreshCompleter = Completer<List<Listing>>();
  int forceRefreshCalls = 0;

  @override
  List<Listing> peekMyListingsByStatuses({
    required Set<String> statuses,
  }) {
    if (!statuses.contains('approved')) {
      return const <Listing>[];
    }
    return <Listing>[
      _listing(
        id: 'listing-old',
        title: 'Старое объявление',
        status: 'approved',
      ),
    ];
  }

  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
    bool forceRefresh = false,
  }) {
    if (!statuses.contains('approved')) {
      return Future<List<Listing>>.value(const <Listing>[]);
    }
    if (forceRefresh) {
      forceRefreshCalls += 1;
      return _refreshCompleter.future;
    }
    return Future<List<Listing>>.value(peekMyListingsByStatuses(
      statuses: statuses,
    ));
  }

  void completeRefresh() {
    _refreshCompleter.complete(
      <Listing>[
        _listing(
          id: 'listing-new',
          title: 'Новое объявление',
          status: 'approved',
        ),
      ],
    );
  }
}

class _RetryLikeDelayedListingsService extends ListingsService {
  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
    bool forceRefresh = false,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (!statuses.contains('approved')) {
      return const <Listing>[];
    }
    return <Listing>[
      _listing(
        id: 'listing-1',
        title: 'Велосипед',
        status: 'approved',
      ),
    ];
  }
}

class _ListingsWithPendingItemService extends ListingsService {
  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
    bool forceRefresh = false,
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

class _ListingsWithFavoriteCountService extends ListingsService {
  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
    bool forceRefresh = false,
  }) async {
    if (!statuses.contains('approved')) {
      return const <Listing>[];
    }
    return <Listing>[
      Listing.fromMap(<String, dynamic>{
        'id': 'listing-3',
        'owner_id': 'user-1',
        'owner_email': 'user@example.com',
        'owner_name': 'User',
        'title': 'Телефон',
        'description': 'Описание',
        'category': 'Электроника',
        'subcategory': 'Смартфоны',
        'price': 50000,
        'phone': '',
        'phone_hidden': false,
        'city': 'Москва',
        'delivery': <String, dynamic>{},
        'photo_urls': const <String>[],
        'view_count': 7,
        'favorites_count': 2,
        'status': 'approved',
        'rejection_reason': '',
        'can_promote': false,
        'created_at': '2026-06-20T10:00:00.000Z',
      }),
    ];
  }
}

class _ListingsWithPendingFavoriteCountService extends ListingsService {
  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
    bool forceRefresh = false,
  }) async {
    if (!statuses.contains('pending')) {
      return const <Listing>[];
    }
    return <Listing>[
      Listing.fromMap(<String, dynamic>{
        'id': 'listing-4',
        'owner_id': 'user-1',
        'owner_email': 'user@example.com',
        'owner_name': 'User',
        'title': 'Ноутбук',
        'description': 'Описание',
        'category': 'Электроника',
        'subcategory': 'Ноутбуки',
        'price': 70000,
        'phone': '',
        'phone_hidden': false,
        'city': 'Москва',
        'delivery': <String, dynamic>{},
        'photo_urls': const <String>[],
        'view_count': 4,
        'favorites_count': 9,
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
    bool forceRefresh = false,
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
    bool forceRefresh = false,
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

Listing _listing({
  required String id,
  required String title,
  required String status,
  String ownerId = 'user-1',
}) {
  return Listing.fromMap(<String, dynamic>{
    'id': id,
    'owner_id': ownerId,
    'owner_email': 'user@example.com',
    'owner_name': 'User',
    'title': title,
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
    'status': status,
    'rejection_reason': '',
    'can_promote': false,
    'created_at': '2026-06-20T10:00:00.000Z',
  });
}
