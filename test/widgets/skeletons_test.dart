import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('core skeleton widgets render without layout jumps',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SkeletonBox(width: 100, height: 40),
              SkeletonLine(width: 80),
              SkeletonCircle(size: 32),
              Expanded(child: SkeletonListingGrid(itemCount: 2)),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(SkeletonBox), findsWidgets);
    expect(find.byType(SkeletonLine), findsWidgets);
    expect(find.byType(SkeletonCircle), findsWidgets);
    expect(find.byType(SkeletonListingCard), findsNWidgets(2));
  });
}
