import 'package:atta/src/features/support/support_screen.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/support_service.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('support screen shows skeleton while loading ticket',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ProfileService>.value(value: _FakeProfileService()),
          Provider<SupportService>.value(value: _DelayedSupportService()),
        ],
        child: const MaterialApp(home: SupportScreen()),
      ),
    );

    expect(find.byType(SkeletonMessageBubble), findsWidgets);

    await tester.pumpAndSettle();

    expect(find.text('Пока нет сообщений. Напишите нам, и мы поможем.'),
        findsOneWidget);
  });

  testWidgets('outgoing support text stays readable in dark theme',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ProfileService>.value(value: _FakeProfileService()),
          Provider<SupportService>.value(value: _LoadedSupportService()),
        ],
        child: MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: ThemeMode.dark,
          home: const SupportScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final textWidget = tester.widget<Text>(find.text('тест'));
    expect(textWidget.style?.color, const Color(0xFF17212F));
  });
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'user-1');
}

class _DelayedSupportService extends SupportService {
  @override
  Future<String?> getOrCreateMyTicketId({required String uid}) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return null;
  }
}

class _FakeProfileService extends ProfileService {}

class _LoadedSupportService extends SupportService {
  @override
  Future<String?> getOrCreateMyTicketId({required String uid}) async {
    return 'ticket-1';
  }

  @override
  List<Map<String, dynamic>> peekMessages(String ticketId) {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'msg-1',
        'ticket_id': ticketId,
        'sender': 'user',
        'text': 'тест',
        'created_at': '2026-06-26T09:00:00.000Z',
      },
    ];
  }

  @override
  Stream<List<Map<String, dynamic>>> streamMessages(String ticketId) async* {
    yield peekMessages(ticketId);
  }
}
