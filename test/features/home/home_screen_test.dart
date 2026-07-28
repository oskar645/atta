import 'dart:async';

import 'package:atta/src/app.dart';
import 'package:atta/src/features/home/home_screen.dart';
import 'package:atta/src/features/showcase/showcase_all_screen.dart';
import 'package:atta/src/features/showcase/showcase_preview_screen.dart';
import 'package:atta/src/constants/categories.dart';
import 'package:atta/src/models/showcase_item.dart';
import 'package:atta/src/models/feed_ad.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/feed_ads_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/showcase_service.dart';
import 'package:atta/src/widgets/feed_ad_banner.dart';
import 'package:atta/src/widgets/listing_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'home feed loads next page near bottom and does not duplicate showcase or listings',
    (tester) async {
      final showcase = _FakeShowcaseService();
      final listings = _FakeListingsService(
        onGetListingsPage: (request) async {
          if (request.cursor == null) {
            return ListingsFeedPage(
              items: List<Listing>.generate(
                20,
                (index) => _listing(
                  id: 'listing-$index',
                  title: index == 19 ? 'Дубль' : 'Товар $index',
                ),
              ),
              hasMore: true,
              nextCursor: 'cursor-1',
            );
          }
          return ListingsFeedPage(
            items: <Listing>[
              _listing(id: 'listing-19', title: 'Дубль'),
              for (var index = 20; index <= 28; index++)
                _listing(id: 'listing-$index', title: 'Товар $index'),
            ],
            hasMore: false,
            nextCursor: null,
          );
        },
      );

      await tester.pumpWidget(
        _buildHomeTestApp(
          listings: listings,
          showcase: showcase,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(listings.requests.length, 1);

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -8000),
        20000,
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(listings.requests.length, 2);
      expect(listings.requests.last.cursor, 'cursor-1');
      expect(showcase.homeShowcaseCalls, 1);
      expect(find.text('Дубль'), findsNothing);
      expect(find.text('Больше объявлений нет'), findsNothing);
    },
  );

  testWidgets(
    'home feed does not start repeated loadMore while page request is in flight',
    (tester) async {
      final secondPageCompleter = Completer<ListingsFeedPage>();
      final listings = _FakeListingsService(
        onGetListingsPage: (request) async {
          if (request.cursor == null) {
            return ListingsFeedPage(
              items: List<Listing>.generate(
                20,
                (index) => _listing(
                  id: 'listing-$index',
                  title: 'Товар $index',
                ),
              ),
              hasMore: true,
              nextCursor: 'cursor-1',
            );
          }
          return secondPageCompleter.future;
        },
      );

      await tester.pumpWidget(_buildHomeTestApp(listings: listings));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -8000),
        20000,
      );
      await tester.pump();
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -1200),
        12000,
      );
      await tester.pump();

      expect(listings.requests.length, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      secondPageCompleter.complete(
        ListingsFeedPage(
          items: <Listing>[
            _listing(id: 'listing-20', title: 'Товар 20'),
          ],
          hasMore: false,
          nextCursor: null,
        ),
      );

      await tester.pumpAndSettle();

      expect(listings.requests.length, 2);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'home showcase cards are slightly smaller with partial third card on iPhone',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildHomeTestApp(
          listings: _FakeListingsService(
            onGetListingsPage: (request) async => ListingsFeedPage(
              items: List<Listing>.generate(
                4,
                (index) => _listing(
                  id: 'listing-$index',
                  title: 'Товар $index',
                ),
              ),
              hasMore: false,
              nextCursor: null,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      final first =
          tester.getRect(find.byKey(const ValueKey('home_showcase_card:0')));
      final second =
          tester.getRect(find.byKey(const ValueKey('home_showcase_card:1')));
      final third =
          tester.getRect(find.byKey(const ValueKey('home_showcase_card:2')));

      expect(first.width, greaterThanOrEqualTo(120));
      expect(first.width, lessThanOrEqualTo(126));
      expect(second.left, greaterThan(first.left));
      expect(third.left, lessThan(390));
      expect(third.right, greaterThan(390));
    },
  );

  testWidgets(
    'home showcase horizontal list scrolls to more cards',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildHomeTestApp(
          listings: _FakeListingsService(
            onGetListingsPage: (request) async => ListingsFeedPage(
              items: <Listing>[
                _listing(id: 'listing-1', title: 'Товар 1'),
              ],
              hasMore: false,
              nextCursor: null,
            ),
          ),
          showcase: _FakeShowcaseService(
            items: List<ShowcaseItem>.generate(
              5,
              (index) => _showcaseItem(
                promotionId: 'promo-${index + 1}',
                listingId: 'listing-${index + 1}',
                title: 'Витрина $index',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Витрина 3'), findsNothing);

      await tester.drag(
        find.byKey(const ValueKey('home_showcase_card:1')),
        const Offset(-180, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Витрина 3'), findsOneWidget);
    },
  );

  testWidgets(
    'showcase all opens listing directly instead of preview',
    (tester) async {
      ShowcaseItem? openedItem;

      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ShowcaseService>.value(
            value: _FakeShowcaseService(),
            child: ShowcaseAllScreen(
              onOpenListing: (context, item) async {
                openedItem = item;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Витрина').first);
      await tester.pumpAndSettle();

      expect(openedItem?.listingId, 'listing-showcase');
      expect(find.text('Открыть объявление'), findsNothing);
    },
  );

  testWidgets(
    'showcase all uses full shared categories list with horizontal filters',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ShowcaseService>.value(
            value: _FakeShowcaseService(
              items: <ShowcaseItem>[
                _showcaseItem(
                  promotionId: 'promo-auto',
                  listingId: 'listing-auto',
                  title: 'Авто витрина',
                  category: 'Авто',
                ),
                _showcaseItem(
                  promotionId: 'promo-job',
                  listingId: 'listing-job',
                  title: 'Работа витрина',
                  category: 'Работа',
                ),
              ],
            ),
            child: const ShowcaseAllScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Все'), findsOneWidget);
      expect(find.text(kCategories[1]), findsOneWidget);
      final filtersListView =
          tester.widget<ListView>(find.byType(ListView).first);
      expect(filtersListView.scrollDirection, Axis.horizontal);
      expect(filtersListView.semanticChildCount, kCategories.length);

      await tester.drag(find.byType(ListView).first, const Offset(-600, 0));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Работа'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();

      expect(find.text('Работа витрина'), findsOneWidget);
      expect(find.text('Авто витрина'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Все'),
        -120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Все'));
      await tester.pumpAndSettle();

      expect(find.text('Работа витрина'), findsOneWidget);
      expect(find.text('Авто витрина'), findsOneWidget);
    },
  );

  testWidgets(
    'home showcase pull to refresh triggers showcase refresh',
    (tester) async {
      final showcase = _FakeShowcaseService(
        onGetHomeShowcase: (callCount) async => <ShowcaseItem>[
          _showcaseItem(
            promotionId: 'promo-$callCount',
            listingId: 'listing-$callCount',
            title: callCount == 1 ? 'Первая витрина' : 'Обновленная витрина',
          ),
        ],
      );

      await tester.pumpWidget(
        _buildHomeTestApp(
          listings: _FakeListingsService(
            onGetListingsPage: (request) async => ListingsFeedPage(
              items: <Listing>[
                _listing(id: 'listing-1', title: 'Товар 1'),
              ],
              hasMore: false,
              nextCursor: null,
            ),
          ),
          showcase: showcase,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(showcase.homeShowcaseCalls, 1);
      expect(find.text('Первая витрина'), findsOneWidget);

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 800),
        1200,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(showcase.homeShowcaseCalls, 2);
      expect(find.text('Обновленная витрина'), findsOneWidget);
      expect(find.text('Товар 1'), findsOneWidget);
      expect(find.byType(ListingCard), findsOneWidget);
    },
  );

  testWidgets(
    'home showcase refresh keeps previous cards visible while loading new data',
    (tester) async {
      final refreshCompleter = Completer<List<ShowcaseItem>>();
      final showcase = _FakeShowcaseService(
        onGetHomeShowcase: (callCount) {
          if (callCount == 1) {
            return Future<List<ShowcaseItem>>.value(
              <ShowcaseItem>[
                _showcaseItem(
                  promotionId: 'promo-1',
                  listingId: 'listing-1',
                  title: 'Старая витрина',
                ),
              ],
            );
          }
          return refreshCompleter.future;
        },
      );

      await tester.pumpWidget(
        _buildHomeTestApp(
          listings: _FakeListingsService(
            onGetListingsPage: (request) async => ListingsFeedPage(
              items: <Listing>[
                _listing(id: 'listing-1', title: 'Товар 1'),
              ],
              hasMore: false,
              nextCursor: null,
            ),
          ),
          showcase: showcase,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 800),
        1200,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Старая витрина'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('home_showcase_card:0')), findsOneWidget);

      refreshCompleter.complete(
        <ShowcaseItem>[
          _showcaseItem(
            promotionId: 'promo-2',
            listingId: 'listing-2',
            title: 'Новая витрина',
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Новая витрина'), findsOneWidget);
    },
  );

  testWidgets(
    'showcase all button still opens showcase screen',
    (tester) async {
      await tester.pumpWidget(
        _buildHomeTestApp(
          listings: _FakeListingsService(
            onGetListingsPage: (request) async => ListingsFeedPage(
              items: <Listing>[
                _listing(id: 'listing-1', title: 'Товар 1'),
              ],
              hasMore: false,
              nextCursor: null,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Смотреть все'));
      await tester.pumpAndSettle();

      expect(find.byType(ShowcaseAllScreen), findsOneWidget);
    },
  );

  testWidgets(
    'home showcase card tap behavior is unchanged',
    (tester) async {
      await tester.pumpWidget(
        _buildHomeTestApp(
          listings: _FakeListingsService(
            onGetListingsPage: (request) async => ListingsFeedPage(
              items: <Listing>[
                _listing(id: 'listing-1', title: 'Товар 1'),
              ],
              hasMore: false,
              nextCursor: null,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home_showcase_card:0')));
      await tester.pumpAndSettle();

      expect(find.byType(ShowcasePreviewScreen), findsOneWidget);
      expect(find.byType(ShowcaseAllScreen), findsNothing);
    },
  );

  testWidgets(
    'home feed keeps category and search on loadMore',
    (tester) async {
      final listings = _FakeListingsService(
        onGetListingsPage: (request) async {
          if (request.category == 'Электроника' &&
              request.search == 'ноут' &&
              request.cursor == null) {
            return ListingsFeedPage(
              items: List<Listing>.generate(
                20,
                (index) => _listing(
                  id: 'electronics-$index',
                  title: 'Ноутбук $index',
                  category: 'Электроника',
                ),
              ),
              hasMore: true,
              nextCursor: 'filtered-1',
            );
          }

          if (request.category == 'Электроника' &&
              request.search == 'ноут' &&
              request.cursor == 'filtered-1') {
            return ListingsFeedPage(
              items: List<Listing>.generate(
                5,
                (index) => _listing(
                  id: 'tail-$index',
                  title: 'Хвост $index',
                  category: 'Электроника',
                ),
              ),
              hasMore: false,
              nextCursor: null,
            );
          }

          return ListingsFeedPage(
            items: List<Listing>.generate(
              20,
              (index) => _listing(
                id: 'default-$index',
                title: 'Лента $index',
              ),
            ),
            hasMore: false,
            nextCursor: null,
          );
        },
      );

      await tester.pumpWidget(_buildHomeTestApp(listings: listings));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Электроника'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ноут');
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -8000),
        20000,
      );
      await tester.pump();
      await tester.pumpAndSettle();

      final loadMoreRequest = listings.requests.last;
      expect(loadMoreRequest.category, 'Электроника');
      expect(loadMoreRequest.search, 'ноут');
      expect(loadMoreRequest.cursor, 'filtered-1');
    },
  );

  testWidgets(
    'favorite toggle updates card without listings reload',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final listings = _FakeListingsService(
        onGetListingsPage: (request) async => ListingsFeedPage(
          items: <Listing>[
            _listing(id: 'listing-1', title: 'Товар 1'),
          ],
          hasMore: false,
          nextCursor: null,
        ),
      );
      final favorites = _FakeFavoritesService();

      await tester.pumpWidget(
        _buildHomeTestApp(
          listings: listings,
          favorites: favorites,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(listings.requests.length, 1);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      final favoriteButton = find.descendant(
        of: find.byType(ListingCard),
        matching: find.byType(IconButton),
      );
      await tester.ensureVisible(favoriteButton.first);
      await tester.tap(favoriteButton.first);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(favorites.toggleCalls, 1);
      expect(listings.requests.length, 1);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    },
  );

  testWidgets(
    'home feed does not call loadMore when hasMore is false',
    (tester) async {
      final listings = _FakeListingsService(
        onGetListingsPage: (request) async => ListingsFeedPage(
          items: List<Listing>.generate(
            20,
            (index) => _listing(
              id: 'listing-$index',
              title: 'Товар $index',
            ),
          ),
          hasMore: false,
          nextCursor: null,
        ),
      );

      await tester.pumpWidget(_buildHomeTestApp(listings: listings));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -8000),
        20000,
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(listings.requests.length, 1);
      expect(find.text('Больше объявлений нет'), findsNothing);
    },
  );

  testWidgets(
    'home feed pull to refresh resets pagination and refreshes first page',
    (tester) async {
      var firstPageCallCount = 0;
      final listings = _FakeListingsService(
        onGetListingsPage: (request) async {
          if (request.cursor == null) {
            firstPageCallCount += 1;
            return ListingsFeedPage(
              items: <Listing>[
                _listing(
                  id: firstPageCallCount == 1 ? 'listing-1' : 'listing-1b',
                  title:
                      firstPageCallCount == 1 ? 'Первая версия' : 'Обновлено',
                ),
              ],
              hasMore: true,
              nextCursor: 'cursor-1',
            );
          }
          return ListingsFeedPage(
            items: <Listing>[
              _listing(id: 'listing-2', title: 'Хвост'),
            ],
            hasMore: false,
            nextCursor: null,
          );
        },
      );

      await tester.pumpWidget(_buildHomeTestApp(listings: listings));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -8000),
        20000,
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(listings.requests.length, 2);
      expect(listings.requests.last.cursor, 'cursor-1');

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 8000),
        20000,
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 600),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(
        listings.requests.where((request) => request.cursor == null).length,
        greaterThanOrEqualTo(2),
      );
      expect(find.text('Обновлено'), findsOneWidget);
      expect(find.text('Первая версия'), findsNothing);
    },
  );

  testWidgets('home top promo banner is hidden when there is no active ad',
      (tester) async {
    final listings = _FakeListingsService(
      onGetListingsPage: (_) async => ListingsFeedPage(
        items: <Listing>[
          _listing(id: 'listing-1', title: 'Первая карточка'),
        ],
        hasMore: false,
      ),
    );

    await tester.pumpWidget(
      _buildHomeTestApp(
        listings: listings,
        feedAds: _FakeFeedAdsService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FeedAdBanner), findsNothing);
  });

  testWidgets('home active promo banner renders above listing grid',
      (tester) async {
    final listings = _FakeListingsService(
      onGetListingsPage: (_) async => ListingsFeedPage(
        items: <Listing>[
          _listing(id: 'listing-1', title: 'Первая карточка'),
          _listing(id: 'listing-2', title: 'Вторая карточка'),
        ],
        hasMore: false,
      ),
    );
    final feedAds = _FakeFeedAdsService(
      ad: FeedAd.fromMap(
        const <String, dynamic>{
          'id': 'ad-1',
          'title': 'Промо баннер',
          'image_url': 'https://example.com/ad.jpg',
          'target_url': 'https://example.com',
          'is_active': true,
          'placement': 'home',
          'created_at': '2026-07-03T10:00:00.000Z',
        },
      ),
    );

    await tester.pumpWidget(
      _buildHomeTestApp(
        listings: listings,
        feedAds: feedAds,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FeedAdBanner), findsOneWidget);
    final bannerTopLeft = tester.getTopLeft(find.byType(FeedAdBanner));
    final showcaseTopLeft = tester.getTopLeft(find.text('Витрина'));
    expect(bannerTopLeft.dy, lessThan(showcaseTopLeft.dy));
  });

  testWidgets(
    'home screen does not render feed ad skeleton when no active ad exists',
    (tester) async {
      final listings = _FakeListingsService(
        onGetListingsPage: (_) async => ListingsFeedPage(
          items: <Listing>[
            _listing(id: 'listing-1', title: 'Первая карточка'),
          ],
          hasMore: false,
        ),
      );

      await tester.pumpWidget(
        _buildHomeTestApp(
          listings: listings,
          feedAds: _DelayedFeedAdsService(),
        ),
      );
      await tester.pump();

      expect(find.byType(FeedAdBanner), findsNothing);
      expect(find.text('Витрина'), findsOneWidget);
    },
  );

  testWidgets(
    'showcase position is stable when feed ads loading finishes empty',
    (tester) async {
      final listings = _FakeListingsService(
        onGetListingsPage: (_) async => ListingsFeedPage(
          items: <Listing>[
            _listing(id: 'listing-1', title: 'Первая карточка'),
          ],
          hasMore: false,
        ),
      );
      final feedAds = _DelayedFeedAdsService();

      await tester.pumpWidget(
        _buildHomeTestApp(
          listings: listings,
          feedAds: feedAds,
        ),
      );
      await tester.pump();

      final showcaseBefore = tester.getTopLeft(find.text('Витрина'));

      feedAds.emit(null);
      await tester.pumpAndSettle();

      final showcaseAfter = tester.getTopLeft(find.text('Витрина'));
      expect(showcaseAfter.dy, showcaseBefore.dy);
      expect(find.byType(FeedAdBanner), findsNothing);
    },
  );

  testWidgets(
    'pull to refresh does not show empty banner placeholder',
    (tester) async {
      final listings = _FakeListingsService(
        onGetListingsPage: (_) async => ListingsFeedPage(
          items: <Listing>[
            _listing(id: 'listing-1', title: 'Первая карточка'),
          ],
          hasMore: false,
        ),
      );

      await tester.pumpWidget(
        _buildHomeTestApp(
          listings: listings,
          feedAds: _DelayedFeedAdsService(),
        ),
      );
      await tester.pumpAndSettle();

      final showcaseBefore = tester.getTopLeft(find.text('Витрина'));

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(FeedAdBanner), findsNothing);
      final showcaseAfterRefresh = tester.getTopLeft(find.text('Витрина'));
      expect(showcaseAfterRefresh.dy, showcaseBefore.dy);
    },
  );

  testWidgets(
    'weak network error in feed ads does not add empty block above showcase',
    (tester) async {
      final listings = _FakeListingsService(
        onGetListingsPage: (_) async => ListingsFeedPage(
          items: <Listing>[
            _listing(id: 'listing-1', title: 'Первая карточка'),
          ],
          hasMore: false,
        ),
      );

      await tester.pumpWidget(
        _buildHomeTestApp(
          listings: listings,
          feedAds: _ErrorFeedAdsService(),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(FeedAdBanner), findsNothing);
      expect(find.text('Витрина'), findsOneWidget);
    },
  );
}

Widget _buildHomeTestApp({
  required _FakeListingsService listings,
  _FakeShowcaseService? showcase,
  FeedAdsService? feedAds,
  _FakeFavoritesService? favorites,
}) {
  return MultiProvider(
    providers: [
      Provider<AuthService>.value(value: _FakeAuthService()),
      Provider<ListingsService>.value(value: listings),
      Provider<FavoritesService>.value(
        value: favorites ?? _FakeFavoritesService(),
      ),
      Provider<FeedAdsService>.value(value: feedAds ?? _FakeFeedAdsService()),
      Provider<ShowcaseService>.value(
          value: showcase ?? _FakeShowcaseService()),
      Provider<ReviewsService>.value(value: _FakeReviewsService()),
      Provider<NotificationsService>.value(value: _FakeNotificationsService()),
      ChangeNotifierProvider<ListingHistoryService>.value(
        value: ListingHistoryService(),
      ),
    ],
    child: MaterialApp(
      navigatorObservers: <NavigatorObserver>[attaRouteObserver],
      home: const HomeScreen(),
    ),
  );
}

class _PageRequest {
  const _PageRequest({
    required this.category,
    required this.search,
    required this.filters,
    required this.limit,
    required this.cursor,
  });

  final String category;
  final String search;
  final ListingFeedFilters? filters;
  final int limit;
  final String? cursor;
}

class _FakeListingsService extends ListingsService {
  _FakeListingsService({
    required this.onGetListingsPage,
  });

  final Future<ListingsFeedPage> Function(_PageRequest request)
      onGetListingsPage;
  final List<_PageRequest> requests = <_PageRequest>[];

  @override
  Future<ListingsFeedPage> getListingsPage({
    required String category,
    required String search,
    ListingFeedFilters? filters,
    int limit = 20,
    String? cursor,
  }) {
    final request = _PageRequest(
      category: category,
      search: search,
      filters: filters,
      limit: limit,
      cursor: cursor,
    );
    requests.add(request);
    return onGetListingsPage(request);
  }
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'user-1');
}

class _FakeFavoritesService extends FavoritesService {
  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();
  final Set<String> _favoriteIds = <String>{};
  int toggleCalls = 0;

  @override
  Stream<Set<String>> streamFavoriteIds(String uid) async* {
    yield Set<String>.from(_favoriteIds);
    yield* _controller.stream;
  }

  @override
  bool isFavorite(String uid, String listingId) {
    return _favoriteIds.contains(listingId);
  }

  @override
  Stream<bool> streamIsFavorite(String uid, String listingId) async* {
    yield isFavorite(uid, listingId);
    yield* _controller.stream.map((ids) => ids.contains(listingId));
  }

  @override
  Future<void> toggleFavorite({
    required String uid,
    required String listingId,
    required bool makeFavorite,
  }) async {
    toggleCalls += 1;
    if (makeFavorite) {
      _favoriteIds.add(listingId);
    } else {
      _favoriteIds.remove(listingId);
    }
    _controller.add(Set<String>.from(_favoriteIds));
  }
}

class _FakeFeedAdsService extends FeedAdsService {
  _FakeFeedAdsService({this.ad});

  final FeedAd? ad;

  @override
  Stream<FeedAd?> streamActiveAd({String placement = 'home'}) {
    return Stream<FeedAd?>.value(ad);
  }

  @override
  Future<void> recordImpression(String adId) async {}

  @override
  Future<void> recordClick(String adId) async {}
}

class _DelayedFeedAdsService extends FeedAdsService {
  _DelayedFeedAdsService();
  final StreamController<FeedAd?> _controller =
      StreamController<FeedAd?>.broadcast();

  @override
  Stream<FeedAd?> streamActiveAd({String placement = 'home'}) {
    return _controller.stream;
  }

  void emit(FeedAd? ad) {
    _controller.add(ad);
  }

  @override
  Future<void> recordImpression(String adId) async {}

  @override
  Future<void> recordClick(String adId) async {}
}

class _ErrorFeedAdsService extends FeedAdsService {
  @override
  Stream<FeedAd?> streamActiveAd({String placement = 'home'}) async* {
    throw Exception('feed ads failed');
  }

  @override
  Future<void> recordImpression(String adId) async {}

  @override
  Future<void> recordClick(String adId) async {}
}

class _FakeShowcaseService extends ShowcaseService {
  _FakeShowcaseService({
    List<ShowcaseItem>? items,
    this.onGetHomeShowcase,
  }) : _items = items ??
            <ShowcaseItem>[
              for (var index = 0; index < 3; index++)
                _showcaseItem(
                  promotionId: 'promo-${index + 1}',
                  listingId: index == 0 ? 'listing-showcase' : 'listing-$index',
                  title: index == 0 ? 'Витрина' : 'Витрина $index',
                ),
            ];

  int homeShowcaseCalls = 0;
  final Future<List<ShowcaseItem>> Function(int callCount)? onGetHomeShowcase;
  final List<ShowcaseItem> _items;

  @override
  Future<List<ShowcaseItem>> getShowcase() async {
    return List<ShowcaseItem>.from(_items);
  }

  @override
  Future<List<ShowcaseItem>> getHomeShowcase() async {
    homeShowcaseCalls += 1;
    if (onGetHomeShowcase != null) {
      return onGetHomeShowcase!(homeShowcaseCalls);
    }
    return List<ShowcaseItem>.from(_items);
  }

  @override
  Future<void> recordImpression(String promotionId) async {}

  @override
  Future<void> recordClick(String promotionId) async {}
}

class _FakeReviewsService extends ReviewsService {
  @override
  Stream<Map<String, dynamic>> streamSellerRating(String sellerId) {
    return Stream<Map<String, dynamic>>.value(
      const <String, dynamic>{'avg': 0.0, 'count': 0},
    );
  }
}

class _FakeNotificationsService extends NotificationsService {
  @override
  Stream<int> streamUnreadBadgeCount(String userId) {
    return Stream<int>.value(0);
  }
}

Listing _listing({
  required String id,
  required String title,
  String category = 'Все',
}) {
  return Listing.fromMap(<String, dynamic>{
    'id': id,
    'owner_id': 'user-1',
    'owner_email': 'user@example.com',
    'owner_name': 'User',
    'title': title,
    'description': 'Описание',
    'category': category,
    'subcategory': 'Телефоны',
    'price': 1000,
    'phone': '+79990000000',
    'phone_hidden': false,
    'city': 'Москва',
    'delivery': const <String, dynamic>{'pickup': true},
    'photo_urls': const <String>[],
    'view_count': 0,
    'status': 'approved',
    'rejection_reason': '',
    'can_promote': false,
    'created_at': '2026-07-01T10:00:00.000Z',
    'published_at': '2026-07-01T10:00:00.000Z',
  });
}

ShowcaseItem _showcaseItem({
  required String promotionId,
  required String listingId,
  required String title,
  String category = 'Электроника',
  DateTime? startsAt,
}) {
  return ShowcaseItem.fromMap(<String, dynamic>{
    'promotion_id': promotionId,
    'listing_id': listingId,
    'title': title,
    'price': 1500,
    'city': 'Москва',
    'seller_id': 'seller-1',
    'seller_name': 'Seller',
    'category': category,
    'starts_at': startsAt?.toIso8601String(),
    'impressions_count': 0,
    'clicks_count': 0,
  });
}
