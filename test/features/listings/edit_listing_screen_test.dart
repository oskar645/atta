import 'package:atta/src/features/listings/edit_listing_screen.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('edit listing screen shows optional transport labels',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _FakeAuthService()),
          Provider<ListingsService>.value(value: _FakeListingsService()),
        ],
        child: const MaterialApp(
          home: EditListingScreen(listingId: 'listing-1'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();

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
            widget.decoration.labelText == 'Кузов (необязательно)',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Топливо (необязательно)',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText ==
                'Объём двигателя (необязательно), например: 2.2 или 300 куб. см',
      ),
      findsOneWidget,
    );
  });
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'user-1');
}

class _FakeListingsService extends ListingsService {
  @override
  Future<Listing?> getListingById(String id) async {
    return Listing.fromMap(<String, dynamic>{
      'id': id,
      'owner_id': 'user-1',
      'title': 'Toyota Camry',
      'description': 'Описание',
      'category': 'Авто',
      'subcategory': 'Легковые автомобили',
      'price': 1500000,
      'phone': '+79990000000',
      'phone_hidden': false,
      'city': 'Москва',
      'delivery': <String, dynamic>{'pickup': true},
      'photo_urls': const <String>[],
      'car': <String, dynamic>{
        'brand': 'Toyota',
        'model': 'Camry',
        'generation': 'XV70',
      },
    });
  }
}
