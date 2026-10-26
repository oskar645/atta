import 'package:atta/src/models/listing.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _baseListing() => {
      'id': 'video-listing',
      'owner_id': 'u1',
      'owner_name': 'User',
      'title': 'Title',
      'description': 'Desc',
      'category': 'Авто',
      'subcategory': 'Легковые',
      'price': 100,
      'phone': '79281234567',
      'city': 'Гудермес',
      'delivery': const <String, dynamic>{},
      'photo_urls': const <String>[],
      'status': 'approved',
      'created_at': '2026-06-18T12:00:00.000Z',
    };

void main() {
  test('listing maps photo_items from backend response', () {
    final listing = Listing.fromMap({
      'id': 'l1',
      'owner_id': 'u1',
      'owner_email': '',
      'owner_name': 'User',
      'title': 'Title',
      'description': 'Desc',
      'category': 'Авто',
      'subcategory': 'Легковые',
      'price': 100,
      'phone': '79281234567',
      'phone_hidden': false,
      'city': 'Гудермес',
      'delivery': const <String, dynamic>{},
      'photo_urls': const ['https://a'],
      'photo_items': const [
        {
          'id': 'p1',
          'url': 'https://a',
          'sort_order': 0,
        },
      ],
      'status': 'approved',
      'rejection_reason': '',
      'created_at': '2026-06-18T12:00:00.000Z',
    });

    expect(listing.photoItems, hasLength(1));
    expect(listing.photoItems.first.id, 'p1');
    expect(listing.photoItems.first.url, 'https://a');
    expect(listing.firstPhotoUrl, 'https://a');
    expect(listing.imageUrl, 'https://a');
  });

  test('listing falls back to photos array when photo_urls is empty', () {
    final listing = Listing.fromMap({
      'id': 'l2',
      'owner_id': 'u1',
      'owner_email': '',
      'owner_name': 'User',
      'title': 'Title',
      'description': 'Desc',
      'category': 'Авто',
      'subcategory': 'Легковые',
      'price': 100,
      'phone': '79281234567',
      'phone_hidden': false,
      'city': 'Гудермес',
      'delivery': const <String, dynamic>{},
      'photos': const [
        {
          'id': 'p2',
          'public_url': 'https://b',
          'sort_order': 0,
        },
      ],
      'status': 'approved',
      'rejection_reason': '',
      'created_at': '2026-06-18T12:00:00.000Z',
    });

    expect(listing.firstPhotoUrl, 'https://b');
    expect(listing.photoUrls.first, 'https://b');
  });

  test('listing video is optional and maps provider metadata', () {
    final withoutVideo = Listing.fromMap(_baseListing());
    expect(withoutVideo.video, isNull);

    final withVideo = Listing.fromMap({
      ..._baseListing(),
      'video': {
        'provider': 'rutube',
        'originalUrl': 'https://rutube.ru/video/abc/',
        'videoId': 'abc',
        'playbackUrl': 'https://rutube.ru/play/embed/abc',
        'thumbnailUrl': 'https://pic.rutube.ru/abc.jpg',
      },
    });
    expect(withVideo.video?.provider, 'rutube');
    expect(withVideo.video?.thumbnailUrl, 'https://pic.rutube.ru/abc.jpg');
  });
}
