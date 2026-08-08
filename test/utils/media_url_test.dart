import 'package:atta/src/utils/media_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolver keeps legacy uploads and proxies S3 urls', () {
    expect(
      resolvePublicMediaUrl('/uploads/avatars/legacy.jpg',
          categoryHint: 'avatars'),
      'https://attamarket.online/uploads/avatars/legacy.jpg',
    );

    expect(
      resolvePublicMediaUrl(
        'https://s3.twcstorage.ru/atta-media-prod/listings/listing-1/photo.jpg',
        categoryHint: 'listings',
      ),
      'https://attamarket.online/media/object?category=listings&key=listings%2Flisting-1%2Fphoto.jpg',
    );
  });

  test('resolver upgrades legacy backend media urls to domain https', () {
    expect(
      resolvePublicMediaUrl(
        'http://5.42.125.179/media/object?category=avatars&key=avatars%2Fuser-1%2Fphoto.jpg',
        categoryHint: 'avatars',
      ),
      'https://attamarket.online/media/object?category=avatars&key=avatars%2Fuser-1%2Fphoto.jpg',
    );

    expect(
      resolvePublicMediaUrl(
        '5.42.125.179/uploads/avatars/legacy.jpg',
        categoryHint: 'avatars',
      ),
      'https://attamarket.online/uploads/avatars/legacy.jpg',
    );
  });

  test('resolver converts file media object urls to backend https urls', () {
    expect(
      resolvePublicMediaUrl(
        'file:///media/object?category=avatars&key=avatars%2Fuser-1%2Fphoto.jpg',
        categoryHint: 'avatars',
      ),
      'https://attamarket.online/media/object?category=avatars&key=avatars%2Fuser-1%2Fphoto.jpg',
    );
  });
}
