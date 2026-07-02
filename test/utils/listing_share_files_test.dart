import 'dart:typed_data';

import 'package:atta/src/services/image_preparation_service.dart';
import 'package:atta/src/utils/listing_share_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('listing share files use only the first available photo', () async {
    final downloadedUrls = <String>[];
    final files = await buildListingShareFiles(
      photoUrls: <String>[
        '',
        'https://cdn.example.com/first.jpg',
        'https://cdn.example.com/second.jpg',
      ],
      downloadPhoto: (url) async {
        downloadedUrls.add(url);
        return Uint8List.fromList(<int>[1, 2, 3]);
      },
      imagePreparationService: _FakeImagePreparationService(),
    );

    expect(downloadedUrls, <String>['https://cdn.example.com/first.jpg']);
    expect(files, hasLength(1));
    expect(await files.single.length(), 3);
  });

  test('listing share files return empty list when photo download fails',
      () async {
    final files = await buildListingShareFiles(
      photoUrls: <String>['https://cdn.example.com/first.jpg'],
      downloadPhoto: (_) async => null,
      imagePreparationService: _FakeImagePreparationService(),
    );

    expect(files, isEmpty);
  });
}

class _FakeImagePreparationService extends ImagePreparationService {
  @override
  Future<PreparedImage> prepareListingShareImageBytes(
    Uint8List bytes, {
    String fileName = 'listing-share.jpg',
  }) async {
    return PreparedImage(
      bytes: bytes,
      fileName: fileName,
      contentType: 'image/jpeg',
      originalBytes: bytes.length,
      compressedBytes: bytes.length,
    );
  }
}
