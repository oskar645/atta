import 'package:atta/src/models/listing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy subcategory payload is normalized for display', () {
    final listing = Listing.fromMap({
      'id': 'listing-old',
      'category': 'Недвижимость',
      'subcategory': 'Квартира',
    });
    expect(listing.subcategory, 'Квартиры');
  });

  test('listing parses valid coordinates from backend payload', () {
    final listing = Listing.fromMap({
      'id': 'listing-1',
      'latitude': '43.3178000',
      'longitude': 45.6949,
    });

    expect(listing.latitude, 43.3178);
    expect(listing.longitude, 45.6949);
    expect(listing.hasCoordinates, isTrue);
    expect(listing.toMap()['latitude'], 43.3178);
  });

  test('listing rejects out-of-range coordinates for map use', () {
    final listing = Listing.fromMap({
      'id': 'listing-1',
      'latitude': 95,
      'longitude': 45,
    });

    expect(listing.hasCoordinates, isFalse);
  });
}
