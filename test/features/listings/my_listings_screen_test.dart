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

  testWidgets('ordinary my listing uses white cool-shadow surface without rim',
      (tester) async {
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

    final decorations = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>();
    expect(
      decorations.any((decoration) =>
          decoration.boxShadow?.length == 3 &&
          decoration.boxShadow?.first.color == const Color(0x30547CA5)),
      isTrue,
    );

    final listingMaterial = tester.widget<Material>(
      find.byKey(const ValueKey('my_listing_surface:listing-1')),
    );
    final listingShape = listingMaterial.shape! as RoundedRectangleBorder;
    expect(listingMaterial.color, Colors.white);
    expect(listingMaterial.clipBehavior, Clip.antiAlias);
    expect(listingShape.side, BorderSide.none);
  });

  testWidgets('three tabs show real grouped counts and status badges',
      (tester) async {
    final listingsService = _GroupedListingsService();

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

    expect(find.text('На модерации'), findsNothing);
    expect(find.text('Отклонённые'), findsNothing);
    expect(find.text('Проданные'), findsNothing);
    expect(find.text('Удалённые'), findsNothing);
    expect(find.text('Активные'), findsOneWidget);
    expect(find.text('Ждут действия'), findsOneWidget);
    expect(find.text('Архив'), findsOneWidget);
    final activeCounter = find.byKey(
      const ValueKey('my_listings_tab_count:Активные'),
    );
    expect(activeCounter, findsOneWidget);
    expect(tester.widget<Text>(activeCounter).data, '2');
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isFalse);
    expect(find.text('На проверке'), findsOneWidget);

    await tester.tap(find.text('Ждут действия'));
    await tester.pumpAndSettle();
    expect(find.text('Требуется действие'), findsOneWidget);
    expect(find.text('Исправьте описание'), findsOneWidget);
    expect(find.text('Опубликовать снова'), findsOneWidget);

    await tester.tap(find.text('Архив'));
    await tester.pumpAndSettle();
    expect(find.text('Продано'), findsOneWidget);
    expect(find.text('Снято'), findsOneWidget);
    expect(find.text('Удалено модератором'), findsOneWidget);
  });

  testWidgets('fixed tabs fit compact widths and large text without scrolling',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final textScale in [1.0, 1.5, 2.0]) {
        await tester.binding.setSurfaceSize(Size(width, 800));
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<AuthService>.value(value: _FakeAuthService()),
              Provider<FollowService>.value(value: _FakeFollowService()),
              Provider<ListingsService>.value(
                value: _GroupedListingsService(),
              ),
            ],
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 800),
                  textScaler: TextScaler.linear(textScale),
                ),
                child: const MyListingsScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final tabBar = tester.widget<TabBar>(find.byType(TabBar));
        expect(tabBar.isScrollable, isFalse);
        expect(find.text('Активные'), findsOneWidget);
        expect(find.text('Ждут действия'), findsOneWidget);
        expect(find.text('Архив'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('create listing button is available on every tab',
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

    expect(find.text('Разместить объявление'), findsOneWidget);

    await tester.tap(find.text('Ждут действия'));
    await tester.pumpAndSettle();
    expect(find.text('Разместить объявление'), findsOneWidget);

    await tester.ensureVisible(find.text('Архив'));
    await tester.tap(find.text('Архив'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Разместить объявление'), findsOneWidget);
  });

  testWidgets('create listing button hides down and shows on upward scroll',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 520));
    final listingsService = _LongListingsService();

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

    expect(find.text('Разместить объявление'), findsOneWidget);

    await tester.drag(find.byType(ListView).last, const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 260));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('my_listings_create_button_opacity')),
          )
          .opacity,
      0,
    );

    await tester.drag(find.byType(ListView).last, const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 260));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('my_listings_create_button_opacity')),
          )
          .opacity,
      1,
    );
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

  testWidgets('action and archive tabs keep skeleton flow', (tester) async {
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

    await tester.tap(find.text('Ждут действия'));
    await tester.pump();
    expect(find.byType(SkeletonMyListingTile), findsWidgets);

    await tester.tap(find.text('Архив'));
    await tester.pumpAndSettle();
    expect(find.text('Нет архивных объявлений'), findsOneWidget);
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

    await tester.tap(find.text('Ждут действия'));
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

  testWidgets('active listing uses plain green status and white card surface',
      (tester) async {
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

    final statusFinder =
        find.byKey(const ValueKey('my_listing_status:listing-1'));
    expect(statusFinder, findsOneWidget);
    expect(tester.widget(statusFinder), isA<Text>());
    expect(tester.widget<Text>(statusFinder).style?.color,
        const Color(0xFF16713A));

    final surface = tester.widget<Material>(
      find.byKey(const ValueKey('my_listing_surface:listing-1')),
    );
    expect(surface.color, Colors.white);
  });

  testWidgets('bottom actions keep full text at compact and wide widths',
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
      expect(editLabel.softWrap, isFalse);
      expect(editLabel.overflow, isNull);
      expect(archiveLabel.maxLines, 1);
      expect(archiveLabel.softWrap, isFalse);
      expect(archiveLabel.overflow, isNull);
      expect(editLabel.style?.fontSize, 13);
      expect(archiveLabel.style?.fontSize, 13);
      expect(
          tester.getSize(bottomButtons.at(0)).height, greaterThanOrEqualTo(46));
      expect(
          tester.getSize(bottomButtons.at(1)).height, greaterThanOrEqualTo(46));
      final firstCenter = tester.getCenter(bottomButtons.at(0));
      final secondCenter = tester.getCenter(bottomButtons.at(1));
      expect(secondCenter.dy, firstCenter.dy);
      expect(firstCenter.dx, lessThan(secondCenter.dx));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('self-archived listing can be edited and published again',
      (tester) async {
    final listingsService = _ListingsWithStatusItemService(
      listing: _listing(
        id: 'archived-1',
        title: 'Архивное объявление',
        status: 'archived',
      ),
    );

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

    await tester.tap(find.text('Архив'));
    await tester.pumpAndSettle();

    expect(find.text('Архивное объявление'), findsOneWidget);
    expect(find.text('Редактировать'), findsOneWidget);
    expect(find.text('Опубликовать снова'), findsOneWidget);
    expect(find.text('Снять с публикации'), findsNothing);

    final editButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Редактировать'),
    );
    final resubmitButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Опубликовать снова'),
    );
    expect(editButton.onPressed, isNotNull);
    expect(resubmitButton.onPressed, isNotNull);

    await tester.tap(find.text('Опубликовать снова'));
    await tester.pumpAndSettle();

    expect(listingsService.resubmitRequests, 1);
    expect(find.text('Объявление отправлено на модерацию'), findsOneWidget);
    expect(find.text('Архивное объявление'), findsNothing);

    await tester.tap(find.text('Активные'));
    await tester.pumpAndSettle();

    expect(find.text('Архивное объявление'), findsOneWidget);
    expect(find.text('На проверке'), findsOneWidget);
  });

  testWidgets('resubmit ignores repeated tap and does not show false success',
      (tester) async {
    final listingsService = _FailingResubmitListingsService(
      listing: _listing(
        id: 'rejected-error',
        title: 'Объявление с ошибкой',
        status: 'rejected',
        rejectionReason: 'Исправьте описание',
      ),
    );

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
    await tester.tap(find.text('Ждут действия'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Опубликовать снова'));
    await tester.tap(find.text('Опубликовать снова'));
    await tester.pumpAndSettle();

    expect(listingsService.resubmitRequests, 1);
    expect(find.text('Объявление отправлено на модерацию'), findsNothing);
    expect(
      find.text(
        'Не удалось отправить объявление. Проверьте данные и попробуйте снова.',
      ),
      findsOneWidget,
    );
    expect(find.text('Объявление с ошибкой'), findsOneWidget);
    expect(find.text('Требуется действие'), findsOneWidget);
  });

  testWidgets(
      'self-archived listing with unnormalized status still shows owner actions',
      (tester) async {
    final listingsService = _ListingsWithStatusItemService(
      listing: _listing(
        id: 'archived-unnormalized',
        title: 'Архив со статусом из API',
        status: ' archived ',
      ),
    );

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

    await tester.tap(find.text('Архив'));
    await tester.pumpAndSettle();

    expect(find.text('Архив со статусом из API'), findsOneWidget);
    expect(find.text('Снято'), findsOneWidget);
    expect(find.text('Редактировать'), findsOneWidget);
    expect(find.text('Опубликовать снова'), findsOneWidget);
  });

  testWidgets(
      'admin archived listing does not show publish again in archive tab',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
          Provider<ListingsService>.value(
            value: _ListingsWithStatusItemService(
              listing: _listing(
                id: 'admin-archived-1',
                title: 'Архив модератора',
                status: 'archived',
                moderatedBy: 'admin-1',
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Архив'));
    await tester.pumpAndSettle();

    expect(find.text('Архив модератора'), findsOneWidget);
    expect(find.text('Опубликовать снова'), findsNothing);
    expect(find.text('Снять с публикации'), findsNothing);
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

    await tester.pumpAndSettle();
    expect(find.text('Самокат'), findsOneWidget);

    await listingsService.approveCurrent();
    await tester.pump();

    expect(find.text('Самокат'), findsOneWidget);
    expect(find.text('Активно'), findsOneWidget);
  });

  testWidgets('my listings load more appends pages and keeps tabs independent',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 520));
    final listingsService = _PagedMyListingsService();

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

    expect(listingsService.requestsFor('approved'), <String?>[null]);
    expect(find.text('active-0'), findsOneWidget);
    expect(find.text('active-5'), findsNothing);

    await tester.drag(find.byType(ListView).last, const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(listingsService.requestsFor('approved'), <String?>[null, 'a2']);
    expect(find.text('active-5'), findsOneWidget);

    await tester.drag(find.byType(ListView).last, const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(
      listingsService.requestsFor('approved'),
      <String?>[null, 'a2', 'a3'],
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(
      listingsService.requestsFor('approved'),
      <String?>[null, 'a2', 'a3'],
    );
    await tester.tap(find.text('Ждут действия'));
    await tester.pumpAndSettle();
    expect(listingsService.requestsFor('rejected'), <String?>[null]);
    expect(find.text('active-0'), findsNothing);
  });

  testWidgets('short my listings page automatically loads the next page',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 900));
    final listingsService = _ShortPagedMyListingsService();

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

    expect(listingsService.requests, <String?>[null, 'short-2']);
    expect(find.text('Короткая страница 1'), findsOneWidget);
    expect(find.text('Короткая страница 2'), findsOneWidget);
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

class _LongListingsService extends ListingsService {
  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
    bool forceRefresh = false,
  }) async {
    if (!statuses.contains('approved')) {
      return const <Listing>[];
    }
    return List<Listing>.generate(
      18,
      (index) => _listing(
        id: 'long-$index',
        title: 'long-$index',
        status: 'approved',
      ),
    );
  }
}

class _ListingsWithStatusItemService extends ListingsService {
  _ListingsWithStatusItemService({required this.listing});

  Listing listing;
  int resubmitRequests = 0;
  final StreamController<void> _refreshes = StreamController<void>.broadcast();

  @override
  Stream<void> get refreshes => _refreshes.stream;

  @override
  List<Listing> peekMyListingsByStatuses({
    required Set<String> statuses,
  }) {
    return statuses.contains(listing.normalizedStatus)
        ? <Listing>[listing]
        : <Listing>[];
  }

  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
    bool forceRefresh = false,
  }) async {
    return statuses.contains(listing.normalizedStatus)
        ? <Listing>[listing]
        : <Listing>[];
  }

  @override
  Future<Listing?> resubmitListing({required String listingId}) async {
    resubmitRequests += 1;
    listing = Listing.fromMap(<String, dynamic>{
      ...listing.toMap(),
      'status': 'pending',
      'moderated_by': null,
    });
    _refreshes.add(null);
    return listing;
  }
}

class _GroupedListingsService extends ListingsService {
  final List<Listing> _items = <Listing>[
    _listing(id: 'approved', title: 'Активное', status: 'approved'),
    _listing(id: 'pending', title: 'Проверяемое', status: 'pending'),
    _listing(
      id: 'rejected',
      title: 'На доработке',
      status: 'rejected',
      rejectionReason: 'Исправьте описание',
    ),
    _listing(id: 'sold', title: 'Проданное', status: 'sold'),
    _listing(id: 'archived', title: 'Снятое', status: 'archived'),
    _listing(
      id: 'admin-archived',
      title: 'Удалённое модератором',
      status: 'archived',
      moderatedBy: 'admin-1',
      rejectionReason: 'Нарушение правил',
    ),
  ];

  @override
  Future<List<Listing>> refreshMyListings(String uid) async => _items;

  @override
  List<Listing> peekMyListingsByStatuses({required Set<String> statuses}) {
    return _items
        .where((item) => statuses.contains(item.normalizedStatus))
        .toList();
  }

  @override
  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
    bool forceRefresh = false,
  }) async {
    return peekMyListingsByStatuses(statuses: statuses);
  }
}

class _FailingResubmitListingsService extends _ListingsWithStatusItemService {
  _FailingResubmitListingsService({required super.listing});

  @override
  Future<Listing?> resubmitListing({required String listingId}) async {
    resubmitRequests += 1;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    throw Exception('resubmit failed');
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

class _PagedMyListingsService extends ListingsService {
  final Map<String, List<String?>> requests = <String, List<String?>>{};

  List<String?> requestsFor(String status) => requests[status] ?? <String?>[];

  @override
  Future<MyListingsPage> getMyListingsPageByStatuses(
    String uid, {
    required Set<String> statuses,
    int limit = 20,
    String? cursor,
    bool forceRefresh = false,
  }) async {
    final status = statuses.contains('rejected')
        ? 'rejected'
        : statuses.contains('archived')
            ? 'archived'
            : 'approved';
    requests.putIfAbsent(status, () => <String?>[]).add(cursor);
    if (status == 'rejected') {
      return const MyListingsPage(items: <Listing>[], hasMore: false);
    }
    if (cursor == null) {
      return MyListingsPage(
        items: List<Listing>.generate(
          5,
          (index) => _listing(
            id: 'active-$index',
            title: 'active-$index',
            status: 'approved',
          ),
        ),
        hasMore: true,
        nextCursor: 'a2',
      );
    }
    if (cursor == 'a2') {
      return MyListingsPage(
        items: <Listing>[
          _listing(id: 'active-4', title: 'active-4', status: 'approved'),
          ...List<Listing>.generate(
            5,
            (index) => _listing(
              id: 'active-${index + 5}',
              title: 'active-${index + 5}',
              status: 'approved',
            ),
          ),
        ],
        hasMore: true,
        nextCursor: 'a3',
      );
    }
    return MyListingsPage(
      items: <Listing>[
        _listing(id: 'active-9', title: 'active-9', status: 'approved'),
      ],
      hasMore: false,
    );
  }
}

class _ShortPagedMyListingsService extends ListingsService {
  final List<String?> requests = <String?>[];

  @override
  Future<MyListingsPage> getMyListingsPageByStatuses(
    String uid, {
    required Set<String> statuses,
    int limit = 20,
    String? cursor,
    bool forceRefresh = false,
  }) async {
    if (!statuses.contains('approved')) {
      return const MyListingsPage(items: <Listing>[], hasMore: false);
    }
    requests.add(cursor);
    if (cursor == null) {
      return MyListingsPage(
        items: <Listing>[
          _listing(
            id: 'short-1',
            title: 'Короткая страница 1',
            status: 'approved',
          ),
        ],
        hasMore: true,
        nextCursor: 'short-2',
      );
    }
    return MyListingsPage(
      items: <Listing>[
        _listing(
          id: 'short-2',
          title: 'Короткая страница 2',
          status: 'approved',
        ),
      ],
      hasMore: false,
    );
  }
}

Listing _listing({
  required String id,
  required String title,
  required String status,
  String ownerId = 'user-1',
  String? moderatedBy,
  String rejectionReason = '',
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
    'rejection_reason': rejectionReason,
    'moderated_by': moderatedBy,
    'can_promote': false,
    'created_at': '2026-06-20T10:00:00.000Z',
  });
}
