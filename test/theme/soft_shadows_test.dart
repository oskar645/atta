import 'package:atta/src/app.dart';
import 'package:atta/src/theme/soft_shadows.dart';
import 'package:atta/src/widgets/standard_search_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('soft shadows stay subtle and adapt to theme brightness',
      (tester) async {
    Future<List<BoxShadow>> shadowsFor(Brightness brightness) async {
      late List<BoxShadow> result;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Theme(
            data: ThemeData(brightness: brightness),
            child: Builder(
              builder: (context) {
                result = attaSoftShadows(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return result;
    }

    final light = await shadowsFor(Brightness.light);
    final dark = await shadowsFor(Brightness.dark);

    expect(light, hasLength(2));
    expect(dark, hasLength(2));
    expect(light.first.blurRadius, 10);
    expect(light.first.offset, const Offset(0, 2));
    expect(light.last.blurRadius, 24);
    expect(light.last.spreadRadius, -2);
    expect(light.last.offset, const Offset(0, 8));
    expect(light.first.color.a, lessThan(dark.first.color.a));
    expect(dark.last.color.a, lessThan(dark.first.color.a));
  });

  test('ATTA dark theme uses black surfaces throughout', () {
    final theme = buildAttaDarkTheme();
    final scheme = theme.colorScheme;

    expect(theme.scaffoldBackgroundColor, Colors.black);
    expect(theme.canvasColor, Colors.black);
    expect(theme.appBarTheme.backgroundColor, Colors.black);
    expect(theme.cardTheme.color, Colors.black);
    expect(theme.dialogTheme.backgroundColor, Colors.black);
    expect(theme.bottomSheetTheme.backgroundColor, Colors.black);
    expect(scheme.surface, Colors.black);
    expect(scheme.surfaceContainerLowest, Colors.black);
    expect(scheme.surfaceContainerLow, Colors.black);
    expect(scheme.surfaceContainer, Colors.black);
    expect(scheme.surfaceContainerHigh, Colors.black);
    expect(scheme.surfaceContainerHighest, Colors.black);
  });

  testWidgets('cool surfaces use the approved three-layer shadow in dark mode',
      (tester) async {
    late List<BoxShadow> shadows;
    await tester.pumpWidget(
      MaterialApp(
        darkTheme: buildAttaDarkTheme(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) {
            shadows = attaCoolSoftCardShadows(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(shadows, hasLength(3));
    expect(shadows[0].color, const Color(0x3D7CA1C7));
    expect(shadows[0].blurRadius, 3);
    expect(shadows[0].offset, Offset.zero);
    expect(shadows[1].color, const Color(0x247CA1C7));
    expect(shadows[2].color, const Color(0x127CA1C7));
  });

  testWidgets('standard search is black with three-layer shadow in dark mode',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        darkTheme: buildAttaDarkTheme(),
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: Center(
            child: StandardSearchSurface(
              child: SizedBox(width: 200, height: 44),
            ),
          ),
        ),
      ),
    );

    final decorations = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(
      decorations.any(
        (decoration) =>
            decoration.boxShadow?.length == 3 &&
            decoration.boxShadow?.first.color == const Color(0x3D7CA1C7),
      ),
      isTrue,
    );
    expect(
      tester
          .widgetList<Material>(find.byType(Material))
          .any((material) => material.color == Colors.black),
      isTrue,
    );
  });
}
