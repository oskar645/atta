import 'package:atta/src/models/listing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Listing parses camelCase sellerLevel', () {
    expect(Listing.fromMap(_listing({'sellerLevel': 'bronze'})).sellerLevel,
        'bronze');
  });

  test('Listing parses snake_case seller_level', () {
    expect(Listing.fromMap(_listing({'seller_level': 'silver'})).sellerLevel,
        'silver');
  });
}

Map<String, dynamic> _listing(Map<String, dynamic> level) => <String, dynamic>{
      'id': 'listing-1',
      'owner_id': 'seller-1',
      'title': 'Listing',
      'description': '',
      'category': 'Другое',
      'price': 100,
      'created_at': '2026-09-23T00:00:00.000Z',
      'updated_at': '2026-09-23T00:00:00.000Z',
      ...level,
    };
