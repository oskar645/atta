import 'dart:typed_data';

import 'package:atta/src/services/image_preparation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('prepareListingShareImageBytes downsizes image to share-safe bounds',
      () async {
    final source = img.Image(width: 1600, height: 1200);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x % 255, y % 255, (x + y) % 255);
      }
    }

    final originalBytes = Uint8List.fromList(img.encodePng(source));
    final prepared =
        await ImagePreparationService().prepareListingShareImageBytes(
      originalBytes,
      fileName: 'source.png',
    );
    final decoded = img.decodeImage(prepared.bytes);

    expect(decoded, isNotNull);
    expect(decoded!.width, lessThanOrEqualTo(800));
    expect(decoded.height, lessThanOrEqualTo(800));
    expect(prepared.contentType, 'image/jpeg');
    expect(prepared.fileName, 'listing_share.jpg');
  });
}
