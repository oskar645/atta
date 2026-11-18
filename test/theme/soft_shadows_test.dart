import 'package:atta/src/theme/soft_shadows.dart';
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
}
