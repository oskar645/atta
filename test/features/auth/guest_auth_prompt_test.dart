import 'package:atta/src/features/auth/guest_auth_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guest auth sheet has shared compact layout and copy',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(390, 844)),
          child: Scaffold(
            body: GuestAuthSheet(),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(
      find.text('Войдите, чтобы пользоваться всеми возможностями Атта'),
      findsOneWidget,
    );
    expect(find.text('Войти'), findsOneWidget);
    expect(find.text('Уже есть аккаунт? Войти'), findsNothing);
    expect(find.text('ATTA'), findsNothing);
    expect(find.text('Atta'), findsNothing);
    expect(find.text('Атта Маркет'), findsNothing);
    expect(find.text('App Store'), kIsWeb ? findsOneWidget : findsNothing);
    expect(find.text('Google Play'), kIsWeb ? findsOneWidget : findsNothing);

    final sheet = tester.widget<SizedBox>(
      find.byKey(const ValueKey('guest_auth_sheet')),
    );
    expect(sheet.height, 844 * 0.56);
  });
}
