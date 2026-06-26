import 'package:atta/src/features/reviews/seller_reviews_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reviewAuthorAvatarUrl reads author_preview avatar first', () {
    expect(
      reviewAuthorAvatarUrl(<String, dynamic>{
        'author_preview': <String, dynamic>{
          'avatar_url': 'https://cdn.example.com/reviewer.jpg',
        },
        'avatar_url': 'https://cdn.example.com/fallback.jpg',
      }),
      'https://cdn.example.com/reviewer.jpg',
    );
  });

  test('reviewAuthorAvatarUrl falls back to top-level avatar fields', () {
    expect(
      reviewAuthorAvatarUrl(<String, dynamic>{
        'reviewer_avatar_url': 'https://cdn.example.com/top-level.jpg',
      }),
      'https://cdn.example.com/top-level.jpg',
    );
  });
}
