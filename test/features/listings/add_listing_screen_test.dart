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
      _textFieldWithLabel('Пробег (необязательно)'),
      findsOneWidget,
    );
    expect(
      _dropdownWithLabel('Кузов (необязательно)'),
      findsOneWidget,
    );
    expect(
      _dropdownWithLabel('Топливо (необязательно)'),
      findsOneWidget,
    );
    expect(_textWithOptionalLabel('Объём двигателя (необязательно)'),
        findsOneWidget);
    expect(
      _dropdownWithLabel('Коробка (необязательно)'),
      findsOneWidget,
    );
    expect(
      _dropdownWithLabel('Привод (необязательно)'),
      findsOneWidget,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(
      _dropdownWithLabel('Состояние (необязательно)'),
      findsOneWidget,
    );
    expect(
      _dropdownWithLabel('Цвет (необязательно)'),
      findsOneWidget,
    );
    expect(
      _dropdownWithLabel('ПТС (необязательно)'),
      findsOneWidget,
    );
  });
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is TextField && _decorationHasLabel(widget.decoration, label),
  );
}

Finder _dropdownWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        _decorationHasLabel(widget.decoration, label),
  );
}

Finder _textWithOptionalLabel(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        _normalizeLabel(widget.data ?? widget.textSpan?.toPlainText()) ==
            _normalizeLabel(label),
  );
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
  AuthUser? get currentUser => const AuthUser(
        uid: 'user-1',
        phone: '79288888645',
      );
}
