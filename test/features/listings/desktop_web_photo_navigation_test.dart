import 'package:atta/src/features/listings/desktop_web_photo_navigation.dart';
import 'package:atta/src/features/listings/photo_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop arrows are hidden for a single photo', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DesktopWebPhotoNavigation(
          enabledOverride: true,
          currentIndex: 0,
          photoCount: 1,
          onPrevious: _noop,
          onNext: _noop,
          child: ColoredBox(color: Colors.black),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('photo_previous')), findsNothing);
    expect(find.byKey(const ValueKey('photo_next')), findsNothing);
  });

  testWidgets('desktop arrows navigate forward and backward', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _NavigationHarness()));

    expect(find.text('0'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo_previous')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('photo_next')));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo_previous')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo_next')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('full screen starts at requested photo and stays open navigating',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PhotoViewerScreen(
          photoUrls: ['/tmp/photo-1', '/tmp/photo-2', '/tmp/photo-3'],
          initialIndex: 1,
          desktopWebNavigationOverride: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('2/3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('photo_next')));
    await tester.pumpAndSettle();
    expect(find.text('3/3'), findsOneWidget);
    expect(find.byType(PhotoViewerScreen), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
  });
}

void _noop() {}

class _NavigationHarness extends StatefulWidget {
  const _NavigationHarness();

  @override
  State<_NavigationHarness> createState() => _NavigationHarnessState();
}

class _NavigationHarnessState extends State<_NavigationHarness> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return DesktopWebPhotoNavigation(
      enabledOverride: true,
      currentIndex: index,
      photoCount: 3,
      onPrevious: () => setState(() => index--),
      onNext: () => setState(() => index++),
      child: Center(child: Text('$index')),
    );
  }
}
