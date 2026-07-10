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
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Дополнительно (необязательно)'), findsNothing);
    expect(find.text('Опубликовать'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Пробег (необязательно)',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration?.labelText == 'Кузов (необязательно)',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration?.labelText == 'Топливо (необязательно)',
      ),
      findsOneWidget,
    );
    expect(find.text('Объём двигателя (необязательно)'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration?.labelText == 'Коробка (необязательно)',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration?.labelText == 'Привод (необязательно)',
      ),
      findsOneWidget,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration?.labelText == 'Состояние (необязательно)',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration?.labelText == 'Цвет (необязательно)',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration?.labelText == 'ПТС (необязательно)',
      ),
      findsOneWidget,
    );
  });
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(
        uid: 'user-1',
        phone: '79288888645',
      );
}
