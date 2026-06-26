import 'package:atta/src/utils/media_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolver keeps legacy uploads and proxies S3 urls', () {
    expect(
      resolvePublicMediaUrl('/uploads/avatars/legacy.jpg', categoryHint: 'avatars'),
      'http://5.42.125.179/uploads/avatars/legacy.jpg',
    );

    expect(
      resolvePublicMediaUrl(
        'https://s3.twcstorage.ru/atta-media-prod/listings/listing-1/photo.jpg',
        categoryHint: 'listings',
      ),
      'http://5.42.125.179/media/object?category=listings&key=listings%2Flisting-1%2Fphoto.jpg',
    );
  });

  test('resolver does not proxy backend urls over backend urls', () {
    expect(
      resolvePublicMediaUrl(
        'http://5.42.125.179/media/object?category=avatars&key=avatars%2Fuser-1%2Fphoto.jpg',
        categoryHint: 'avatars',
      ),
      'http://5.42.125.179/media/object?category=avatars&key=avatars%2Fuser-1%2Fphoto.jpg',
    );
  });
}
