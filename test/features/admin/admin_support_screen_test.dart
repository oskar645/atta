import 'dart:async';

import 'package:atta/src/features/admin/admin_support_screen.dart';
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
import 'package:atta/src/services/support_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('admin support long press delete hides thread from list',
      (tester) async {
    final support = _FakeSupportService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SupportService>.value(value: support),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AdminSupportTab()),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Старое обращение'), findsOneWidget);

    await tester.longPress(find.text('Старое обращение'));
    await tester.pump();
    expect(
      find.text('Удалить переписку из списка поддержки?'),
      findsOneWidget,
    );

    await tester.tap(find.text('Удалить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Старое обращение'), findsNothing);
    expect(support.hiddenTicketIds, <String>['ticket-1']);
  });

  testWidgets('admin ticket header opens profile only once on rapid taps',
      (tester) async {
    final profile = _FakeProfileService(
      completer: Completer<Map<String, dynamic>>(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SupportService>.value(value: _FakeSupportService()),
          Provider<ProfileService>.value(value: profile),
          Provider<ReviewsService>.value(value: _FakeReviewsService()),
          Provider<ListingsService>.value(value: _FakeListingsService()),
          Provider<ChatService>.value(value: _FakeChatService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
          Provider<PresenceService>.value(value: _FakePresenceService()),
          Provider<AdminService>.value(value: _FakeAdminService()),
          Provider<AuthService>.value(value: _FakeAuthService()),
        ],
        child: const MaterialApp(
          home: AdminTicketScreen(
            ticketId: 'ticket-1',
            titleName: 'Пользователь',
            userUid: 'user-1',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.text('Пользователь'));
    await tester.tap(find.text('Пользователь'));
    await tester.pump();

    profile.completer.complete(<String, dynamic>{
      'id': 'user-1',
      'display_name': 'Пользователь',
    });
    await tester.pumpAndSettle();

    expect(find.byType(SellerPublicProfileScreen), findsOneWidget);
  });

  testWidgets('admin ticket header shows russian error when user missing',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SupportService>.value(value: _FakeSupportService()),
          Provider<ProfileService>.value(value: _FakeProfileService()),
        ],
        child: const MaterialApp(
          home: AdminTicketScreen(
            ticketId: 'ticket-1',
            titleName: 'Пользователь',
            userUid: '',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.text('Пользователь'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text(
        'Не удалось открыть профиль пользователя',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('admin support uses fallback user_id field to open profile',
      (tester) async {
    final profile = _FakeProfileService(
      completer: Completer<Map<String, dynamic>>()
        ..complete(<String, dynamic>{
          'id': 'user-42',
          'display_name': 'Emir',
        }),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SupportService>.value(
            value: _FakeSupportService(
              tickets: <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'ticket-1',
                  'user_id': 'user-42',
                  'name': 'Emir',
                  'last_message': 'Здравствуйте',
                  'updated_at': '2026-07-02T10:00:00.000Z',
                  'unread_for_admin': false,
                },
              ],
            ),
          ),
          Provider<ProfileService>.value(value: profile),
          Provider<ReviewsService>.value(value: _FakeReviewsService()),
          Provider<ListingsService>.value(value: _FakeListingsService()),
          Provider<ChatService>.value(value: _FakeChatService()),
          Provider<FollowService>.value(value: _FakeFollowService()),
          Provider<PresenceService>.value(value: _FakePresenceService()),
          Provider<AdminService>.value(value: _FakeAdminService()),
          Provider<AuthService>.value(value: _FakeAuthService()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AdminSupportTab()),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.byTooltip('Профиль пользователя'));
    await tester.pumpAndSettle();

    expect(profile.calls, 1);
    expect(find.byType(SellerPublicProfileScreen), findsOneWidget);
  });

  testWidgets('admin ticket header shows unavailable profile message',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SupportService>.value(value: _FakeSupportService()),
          Provider<ProfileService>.value(value: _FakeProfileService()),
        ],
        child: const MaterialApp(
          home: AdminTicketScreen(
            ticketId: 'ticket-1',
            titleName: 'Пользователь',
            userUid: 'user-404',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.text('Пользователь'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.text(
        'Профиль пользователя недоступен',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });
}

class _FakeSupportService extends SupportService {
  _FakeSupportService({List<Map<String, dynamic>>? tickets})
      : _tickets = tickets ??
            <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'ticket-1',
                'uid': 'user-1',
                'name': 'Пользователь',
                'last_message': 'Старое обращение',
                'updated_at': '2026-07-02T10:00:00.000Z',
                'unread_for_admin': false,
              },
            ];

  final List<Map<String, dynamic>> _tickets;
  final List<String> hiddenTicketIds = <String>[];
  final StreamController<List<Map<String, dynamic>>> _controller =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  @override
  Stream<List<Map<String, dynamic>>> streamTicketsForAdmin() async* {
    yield List<Map<String, dynamic>>.from(_tickets);
    yield* _controller.stream;
  }

  @override
  Stream<List<Map<String, dynamic>>> streamAdminMessages(
      String ticketId) async* {
    yield <Map<String, dynamic>>[
      <String, dynamic>{
        'sender': 'user',
        'text': 'Здравствуйте',
        'created_at': '2026-07-02T10:00:00.000Z',
      },
    ];
  }

  @override
  Future<void> hideAdminTicket({
    required String ticketId,
    required String updatedAt,
  }) async {
    hiddenTicketIds.add(ticketId);
    _tickets.removeWhere(
      (item) => (item['id'] ?? '').toString().trim() == ticketId,
    );
    _controller.add(List<Map<String, dynamic>>.from(_tickets));
  }

  @override
  Future<void> markReadByAdmin(String ticketId) async {}
}

class _FakeProfileService extends ProfileService {
  _FakeProfileService({Completer<Map<String, dynamic>>? completer})
      : completer = completer ?? Completer<Map<String, dynamic>>() {
    if (completer == null && !this.completer.isCompleted) {
      this.completer.complete(<String, dynamic>{});
    }
  }

  final Completer<Map<String, dynamic>> completer;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> getProfile(String uid) {
    calls += 1;
    return completer.future;
  }

  @override
  Stream<Map<String, dynamic>> streamProfile(
    String uid, {
    Map<String, dynamic>? seed,
  }) async* {
    yield await getProfile(uid);
  }
}

class _FakeListingsService extends ListingsService {
  @override
  Stream<List<Listing>> streamListingsByOwnerAll(String ownerId) async* {
    yield const <Listing>[];
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

class _FakeReviewsService extends ReviewsService {
  @override
  Stream<Map<String, dynamic>> streamSellerRating(String sellerId) async* {
    yield const <String, dynamic>{'avg': 0.0, 'count': 0};
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

class _FakeAdminService extends AdminService {}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'admin-1');
}
