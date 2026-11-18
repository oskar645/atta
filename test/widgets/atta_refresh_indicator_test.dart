import 'dart:async';

import 'package:atta/src/widgets/atta_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses the shared 24px arc and preserves refresh callback',
      (tester) async {
    final refreshCompleter = Completer<void>();
    var refreshCalls = 0;
    final statuses = <RefreshIndicatorStatus?>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttaRefreshIndicator(
            onRefresh: () {
              refreshCalls++;
              return refreshCompleter.future;
            },
            onStatusChange: statuses.add,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 1000)],
            ),
          ),
        ),
      ),
    );

    final arc = find.byKey(const ValueKey('atta-refresh-arc'));
    expect(arc, findsOneWidget);
    expect(tester.getSize(arc), const Size.square(24));
    expect(find.byType(RefreshProgressIndicator), findsNothing);

    final refreshState = tester.state<RefreshIndicatorState>(
      find.byType(RefreshIndicator),
    );
    unawaited(refreshState.show());
    for (var i = 0; i < 10 && refreshCalls == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      statuses,
      contains(RefreshIndicatorStatus.snap),
      reason: 'Observed statuses: $statuses',
    );
    expect(refreshCalls, 1);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
    expect(
      find.ancestor(
        of: arc,
        matching: find.byType(RotationTransition),
      ),
      findsOneWidget,
    );

    refreshCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stays hidden during ordinary scrolling from the first item',
      (tester) async {
    var refreshCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttaRefreshIndicator(
            onRefresh: () async => refreshCalls++,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 1200)],
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(200, 260));
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();

    expect(refreshCalls, 0);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('becomes visible for a real downward pull', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttaRefreshIndicator(
            onRefresh: () async {},
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 1200)],
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(200, 160));
    await gesture.moveBy(const Offset(0, 70));
    await tester.pump();

    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
