import 'dart:typed_data';

import 'package:atta/src/services/image_preparation_service.dart';
import 'package:share_plus/share_plus.dart';

typedef ListingSharePhotoDownloader = Future<Uint8List?> Function(String url);

Future<List<XFile>> buildListingShareFiles({
  required List<String> photoUrls,
  required ListingSharePhotoDownloader downloadPhoto,
  ImagePreparationService? imagePreparationService,
}) async {
  String? selectedUrl;
  for (final photoUrl in photoUrls) {
    final normalized = photoUrl.trim();
    if (normalized.isNotEmpty) {
      selectedUrl = normalized;
      break;
    }
  }

  if (selectedUrl == null) {
    return const <XFile>[];
  }

  final originalBytes = await downloadPhoto(selectedUrl);
  if (originalBytes == null || originalBytes.isEmpty) {
    return const <XFile>[];
  }

  final prepared = await (imagePreparationService ?? ImagePreparationService())
      .prepareListingShareImageBytes(
    originalBytes,
    fileName: 'listing-share.jpg',
  );

  return <XFile>[
    XFile.fromData(
      prepared.bytes,
      name: prepared.fileName,
      mimeType: prepared.contentType,
    ),
  ];
}
