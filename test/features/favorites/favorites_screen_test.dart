import 'dart:async';

import 'package:atta/src/features/favorites/favorites_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/saved_search_service.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('favorites first load skeleton', (tester) async {
    await tester.pumpWidget(_wrapFavorites());

    expect(find.byType(SkeletonAdminModerationCard), findsWidgets);
  });
}

Widget _wrapFavorites() {
  return MultiProvider(
    providers: [
      Provider<AuthService>.value(value: _FakeAuthService()),
      Provider<FavoritesService>.value(value: _FakeFavoritesService()),
      Provider<FollowService>.value(value: _FakeFollowService()),
      Provider<ListingsService>.value(value: _DelayedListingsService()),
      Provider<NotificationsService>.value(value: _FakeNotificationsService()),
      Provider<SavedSearchService>.value(value: _FakeSavedSearchService()),
      ChangeNotifierProvider<ListingHistoryService>.value(
        value: ListingHistoryService(),
      ),
      Provider<ReviewsService>.value(value: _FakeReviewsService()),
    ],
    child: const MaterialApp(home: FavoritesScreen()),
  );
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'user-1');
}

class _FakeFavoritesService extends FavoritesService {
  final Set<String> _ids = <String>{'listing-1'};
  final Completer<Set<String>> _loadCompleter = Completer<Set<String>>();

  @override
  Set<String> peekFavoriteIds(String uid) => Set<String>.from(_ids);

  @override
  Future<Set<String>> getFavoriteIds(String uid) async {
    return _loadCompleter.future;
  }

  @override
  Future<Set<String>> refreshFavoriteIds(String uid) async {
    return _loadCompleter.future;
  }

  @override
  Stream<Set<String>> streamFavoriteIds(String uid) async* {
    yield Set<String>.from(_ids);
  }
}

class _FakeFollowService extends FollowService {
  final Completer<List<FollowedSeller>> _loadCompleter =
      Completer<List<FollowedSeller>>();

  @override
  List<FollowedSeller> peekFollowedSellers(String followerId) {
    return const <FollowedSeller>[];
  }

  @override
  Future<List<FollowedSeller>> getFollowedSellers(String followerId) async {
    return _loadCompleter.future;
  }

  @override
  Future<List<FollowedSeller>> refreshFollowedSellers(String followerId) async {
    return _loadCompleter.future;
  }
}

class _DelayedListingsService extends ListingsService {
  final Completer<List<Listing>> _loadCompleter = Completer<List<Listing>>();

  @override
  List<Listing> peekListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) {
    return const <Listing>[];
  }

  @override
  Future<List<Listing>> getListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) async {
    return _loadCompleter.future;
  }
}

class _FakeNotificationsService extends NotificationsService {
  @override
  Stream<int> streamUnreadSavedSearchCount(String userId) {
    return Stream<int>.value(0);
  }
}

class _FakeSavedSearchService extends SavedSearchService {
  final Completer<List<SavedSearch>> _loadCompleter =
      Completer<List<SavedSearch>>();

  @override
  List<SavedSearch> peekSavedSearches(String userId) => const <SavedSearch>[];

  @override
  Future<List<SavedSearch>> getSavedSearches(String userId) async {
    return _loadCompleter.future;
  }

  @override
  Future<List<SavedSearch>> refreshSavedSearches(String userId) async {
    return _loadCompleter.future;
  }
}

class _FakeReviewsService extends ReviewsService {}
