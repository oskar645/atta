import 'package:atta/src/theme/soft_shadows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('soft shadows stay subtle and adapt to theme brightness',
      (tester) async {
    Future<BoxShadow> shadowFor(Brightness brightness) async {
      late BoxShadow result;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Theme(
            data: ThemeData(brightness: brightness),
            child: Builder(
              builder: (context) {
                result = attaSoftShadows(context).single;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return result;
    }

    final light = await shadowFor(Brightness.light);
    final dark = await shadowFor(Brightness.dark);

    expect(light.blurRadius, 8);
    expect(light.spreadRadius, -1);
    expect(light.offset, const Offset(0, 2));
    expect(light.color.a, lessThan(dark.color.a));
    expect(dark.color.a, lessThan(0.2));
  });
}
