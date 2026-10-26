import 'package:atta/src/features/listings/listing_video_field.dart';
import 'package:atta/src/models/listing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('video URL field keeps the native editable text behavior',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListingVideoField(
            onChanged: (_, __) {},
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('listing_video_url_field')),
    );
    expect(field.keyboardType, TextInputType.url);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.enableInteractiveSelection, isTrue);
    expect(field.contextMenuBuilder, isNotNull);
  });

  testWidgets('video helper title stays visible before and after URL input',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListingVideoField(
            onChanged: (_, __) {},
          ),
        ),
      ),
    );

    final title = find.byKey(const ValueKey('listing_video_helper_title'));
    expect(title, findsOneWidget);
    expect(find.text('Видео с Rutube или VK Видео'), findsOneWidget);
    final titleWidget = tester.widget<Text>(title);
    expect(titleWidget.style?.fontWeight, FontWeight.normal);

    await tester.enterText(
      find.byKey(const ValueKey('listing_video_url_field')),
      'https://vkvideo.ru/clip-235619660_456239017',
    );
    await tester.pump();

    expect(title, findsOneWidget);
    expect(find.text('Видео с Rutube или VK Видео'), findsOneWidget);
  });

  testWidgets('video preview is compact like a photo tile', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListingVideoField(
            initialVideo: const ListingVideo(
              provider: 'vk',
              originalUrl: 'https://vkvideo.ru/clip-1_2',
              videoId: '-1_2',
              playbackUrl: 'https://vk.com/video_ext.php?oid=-1&id=2',
              thumbnailUrl: 'https://example.invalid/preview.jpg',
            ),
            onChanged: (_, __) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const ValueKey('listing_video_preview'))),
      const Size.square(110),
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });
}
