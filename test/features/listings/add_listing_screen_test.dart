import 'package:atta/src/features/listings/add_listing_screen.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('create listing screen hides additional section', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ProfileService>.value(value: ProfileService()),
          Provider<ListingsService>.value(value: ListingsService()),
        ],
        child: const MaterialApp(
          home: AddListingScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Дополнительно (необязательно)'), findsNothing);
    expect(find.text('Опубликовать'), findsOneWidget);
  });
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(
        uid: 'user-1',
        phone: '79288888645',
      );
}
