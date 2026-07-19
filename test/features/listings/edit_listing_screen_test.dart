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

    expect(find.text('Параметры авто'), findsOneWidget);
    expect(find.text('Необязательно'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Пробег (необязательно)',
      ),
      findsNothing,
    );

    await tester.tap(find.text('Параметры авто'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            _decorationHasLabel(widget.decoration, 'Пробег (необязательно)'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            _decorationHasLabel(widget.decoration, 'Кузов (необязательно)'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            _decorationHasLabel(widget.decoration, 'Топливо (необязательно)'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            _decorationHasLabel(
              widget.decoration,
              'Объём двигателя (необязательно)',
            ),
      ),
      findsOneWidget,
    );
  });
}

bool _decorationHasLabel(InputDecoration? decoration, String expected) {
  final actual = decoration?.labelText ?? _labelWidgetText(decoration?.label);
  return _normalizeLabel(actual) == _normalizeLabel(expected);
}

String _labelWidgetText(Widget? widget) {
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText() ?? '';
  }
  return '';
}

String _normalizeLabel(String? text) {
  return (text ?? '').replaceAll(RegExp(r'[\s()]'), '').toLowerCase();
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
