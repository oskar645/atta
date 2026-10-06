import 'package:atta/src/utils/listing_link_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts listing id from shared ATTA text', () {
    expect(
      extractListingIdFromMessage(
        'Посмотри объявление в ATTA:\n\nФара\n'
        'https://attamarket.online/listing/listing-42',
      ),
      'listing-42',
    );
  });

  test('supports www and custom app listing links', () {
    expect(
      extractListingIdFromMessage(
        'https://www.attamarket.online/listing/abc-123?from=chat',
      ),
      'abc-123',
    );
    expect(
      extractListingIdFromMessage('atta://listing/abc-456'),
      'abc-456',
    );
  });

  test('ignores foreign and incomplete links', () {
    expect(
      extractListingIdFromMessage(
        'https://example.com/listing/listing-42',
      ),
      isNull,
    );
    expect(
      extractListingIdFromMessage('https://attamarket.online/listing/'),
      isNull,
    );
  });
}
