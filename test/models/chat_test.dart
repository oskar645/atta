import 'package:atta/src/models/chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat uses first listing photo from preview fallbacks', () {
    final chat = Chat.fromMap(<String, dynamic>{
      'id': 'chat-1',
      'listing_id': 'listing-1',
      'buyer_id': 'buyer-1',
      'seller_id': 'seller-1',
      'created_at': '2026-06-27T10:00:00.000Z',
      'updated_at': '2026-06-27T10:00:00.000Z',
      'listing_preview': <String, dynamic>{
        'title': 'Exeed',
        'photo_items': <Map<String, dynamic>>[
          <String, dynamic>{'url': 'https://cdn.example.com/exeed.jpg'},
        ],
      },
    });

    expect(chat.listingTitle, 'Exeed');
    expect(chat.listingPhotoUrl, 'https://cdn.example.com/exeed.jpg');
  });
}
