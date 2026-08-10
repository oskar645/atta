import 'dart:async';

import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('profile active listings show skeleton on first load',
      (tester) async {
    final listings = _FakeSellerListingsService();
    listings.firstLoadCompleter = Completer<List<Listing>>();

    await tester.pumpWidget(_buildApp(listings: listings));
    await tester.pump();

    expect(find.byType(SkeletonListingCard), findsWidgets);
  });

  testWidgets('profile refresh keeps previous listings visible',
      (tester) async {
    final listings = _FakeSellerListingsService(
      initialItems: <Listing>[
        _listing('listing-1', 'Старое объявление'),
      ],
    );

    await tester.pumpWidget(_buildApp(listings: listings));
    await tester.pumpAndSettle();

    expect(find.text('Старое объявление'), findsOneWidget);

    listings.refreshCompleter = Completer<List<Listing>>();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
    await tester.pump();

    expect(find.text('Старое объявление'), findsOneWidget);
    expect(find.byType(SkeletonListingCard), findsNothing);

    listings.refreshCompleter!.complete(<Listing>[
      _listing('listing-1', 'Старое объявление'),
      _listing('listing-2', 'Новое объявление'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Новое объявление'), findsOneWidget);
  });

  testWidgets('admin can copy seller userId from public profile',
      (tester) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final data = Map<String, dynamic>.from(call.arguments as Map);
          clipboardText = data['text'] as String?;
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': clipboardText};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _buildApp(
        listings: _FakeSellerListingsService(),
        auth: _FakeAuthService(isAdmin: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('admin_copy_user_id_button')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('admin_copy_user_id_button')));
    await tester.pump();

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboard?.text, 'seller-1');
    expect(find.text('ID скопирован'), findsOneWidget);
  });

  testWidgets('regular user does not see seller userId copy button',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        listings: _FakeSellerListingsService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('admin_copy_user_id_button')), findsNothing);
  });

  testWidgets('empty seller userId does not show copy button', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        listings: _FakeSellerListingsService(),
        auth: _FakeAuthService(isAdmin: true),
        sellerId: '',
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('admin_copy_user_id_button')), findsNothing);
    expect(find.text('Продавец'), findsOneWidget);
  });
}

Widget _buildApp({
  required _FakeSellerListingsService listings,
  _FakeAuthService? auth,
  String sellerId = 'seller-1',
}) {
  return MultiProvider(
    providers: [
      Provider<ProfileService>.value(value: _FakeProfileService()),
      Provider<ReviewsService>.value(value: _FakeReviewsService()),
      Provider<ListingsService>.value(value: listings),
      Provider<ChatService>.value(value: _FakeChatService()),
      Provider<FollowService>.value(value: _FakeFollowService()),
      Provider<PresenceService>.value(value: _FakePresenceService()),
      Provider<AdminService>.value(value: _FakeAdminService()),
      Provider<AuthService>.value(value: auth ?? _FakeAuthService()),
    ],
    child: MaterialApp(
      home: SellerPublicProfileScreen(
        sellerId: sellerId,
        initialSellerName: 'Продавец',
      ),
    ),
  );
}

class _FakeSellerListingsService extends ListingsService {
  _FakeSellerListingsService({
    List<Listing> initialItems = const <Listing>[],
  }) : _items = List<Listing>.from(initialItems);

  List<Listing> _items;
  Completer<List<Listing>>? firstLoadCompleter;
  Completer<List<Listing>>? refreshCompleter;

  @override
  List<Listing> peekListingsByOwner(String ownerId) {
    return List<Listing>.from(_items);
  }

  @override
  Future<List<Listing>> getListingsByOwnerAll(String ownerId) async {
    if (firstLoadCompleter != null) {
      final items = await firstLoadCompleter!.future;
      _items = List<Listing>.from(items);
      return List<Listing>.from(_items);
    }
    return List<Listing>.from(_items);
  }

  @override
  Future<List<Listing>> refreshListingsByOwner(String ownerId) async {
    if (refreshCompleter != null) {
      final items = await refreshCompleter!.future;
      final deduped = <String, Listing>{
        for (final item in items) item.id: item
      };
      _items = deduped.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      refreshCompleter = null;
      return List<Listing>.from(_items);
    }
    return List<Listing>.from(_items);
  }
}

class _FakeProfileService extends ProfileService {
  @override
  Future<Map<String, dynamic>> getProfile(
    String uid, {
    bool forceRefresh = false,
  }) async {
    return <String, dynamic>{
      'id': uid,
      'display_name': 'Продавец',
      'avatar_url': '',
      'phone': '+79990000000',
    };
  }

  @override
  Stream<Map<String, dynamic>> streamProfile(
    String uid, {
    Map<String, dynamic>? seed,
  }) async* {
    yield <String, dynamic>{
      'id': uid,
      'display_name': 'Продавец',
      'avatar_url': '',
      'phone': '+79990000000',
    };
  }
}

class _FakeReviewsService extends ReviewsService {
  @override
  Future<List<Map<String, dynamic>>> refreshSellerReviews(
      String sellerId) async {
    return const <Map<String, dynamic>>[];
  }

  @override
  Stream<Map<String, dynamic>> streamSellerRating(String sellerId) async* {
    yield const <String, dynamic>{'avg': 0.0, 'count': 0};
  }
}

class _FakeChatService extends ChatService {}

class _FakeFollowService extends FollowService {
  @override
  Stream<bool> streamIsFollowing({
    required String followerId,
    required String sellerId,
  }) async* {
    yield false;
  }
}

class _FakePresenceService extends PresenceService {
  @override
  Stream<bool> streamIsOnline(
    String uid, {
    Duration staleAfter = const Duration(minutes: 2),
  }) async* {
    yield false;
  }
}

class _FakeAdminService extends AdminService {
  @override
  Stream<bool> streamIsAdmin(String uid) {
    return Stream<bool>.value(false);
  }
}

class _FakeAuthService extends AuthService {
  _FakeAuthService({this.isAdmin = false});

  final bool isAdmin;

  @override
  AuthUser? get currentUser => AuthUser(uid: 'viewer-1', isAdmin: isAdmin);
}

Listing _listing(String id, String title) {
  return Listing.fromMap(<String, dynamic>{
    'id': id,
    'owner_id': 'seller-1',
    'owner_email': 'seller@example.com',
    'owner_name': 'Продавец',
    'title': title,
    'description': 'Описание',
    'category': 'Электроника',
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
    'created_at': id == 'listing-2'
        ? '2026-07-02T10:00:00.000Z'
        : '2026-07-01T10:00:00.000Z',
    'published_at': id == 'listing-2'
        ? '2026-07-02T10:00:00.000Z'
        : '2026-07-01T10:00:00.000Z',
  });
}
