import 'package:atta/src/widgets/seller_level_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact seller level badge uses separate centered label lines',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SellerLevelBadge(level: 'bronze'),
        ),
      ),
    );

    expect(find.text('Бронзовый\nпродавец'), findsNothing);
    expect(find.text('Бронзовый'), findsOneWidget);
    expect(find.text('продавец'), findsOneWidget);

    final firstLine = tester.widget<Text>(find.text('Бронзовый'));
    expect(firstLine.maxLines, 1);
    expect(firstLine.softWrap, isFalse);
    expect(firstLine.textAlign, TextAlign.center);
    expect(firstLine.style?.fontSize, inInclusiveRange(8, 11));
    expect(firstLine.style?.fontWeight, FontWeight.w400);
    expect(firstLine.style?.height, 1.05);

    final badgeBox = tester.renderObject<RenderBox>(
      find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.width == 52,
      ),
    );
    expect(badgeBox.size.width, 52);
  });

  testWidgets('large seller level badge adapts image and text in range',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SellerLevelBadge(
            level: 'gold',
            size: SellerLevelBadgeSize.large,
          ),
        ),
      ),
    );

    expect(find.text('Золотой\nпродавец'), findsNothing);
    expect(find.text('Золотой'), findsOneWidget);
    expect(find.text('продавец'), findsOneWidget);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, inInclusiveRange(28, 32));
    expect(image.height, inInclusiveRange(28, 32));

    final firstLine = tester.widget<Text>(find.text('Золотой'));
    expect(firstLine.style?.fontSize, inInclusiveRange(10, 12));

    final badgeBox = tester.renderObject<RenderBox>(
      find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.width == 64,
      ),
    );
    expect(badgeBox.size.width, 64);
  });

  for (final width in <double>[320, 360, 390, 414]) {
    testWidgets(
        'compact seller level badge has no overflow at ${width.toInt()}',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 220));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 220),
              textScaler: const TextScaler.linear(1.6),
            ),
            child: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 42,
                  child: SellerLevelBadge(level: 'silver'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Серебряный'), findsOneWidget);
      expect(find.text('продавец'), findsOneWidget);
    });

    testWidgets('large seller level badge has no overflow at ${width.toInt()}',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 260));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 260),
              textScaler: const TextScaler.linear(1.6),
            ),
            child: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 52,
                  child: SellerLevelBadge(
                    level: 'gold',
                    size: SellerLevelBadgeSize.large,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Золотой'), findsOneWidget);
      expect(find.text('продавец'), findsOneWidget);
    });
  }
}
