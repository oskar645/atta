import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:atta/src/services/api/api_exception.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';

class PreparedImage {
  const PreparedImage({
    required this.bytes,
    required this.fileName,
    required this.contentType,
    required this.originalBytes,
    required this.compressedBytes,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
  final int originalBytes;
  final int compressedBytes;
}

class ImagePreparationService {
  static const int chatMaxBytes = 2 * 1024 * 1024;
  static const int listingMaxBytes = 5 * 1024 * 1024;
  static const int avatarMaxBytes = 2 * 1024 * 1024;
  static const Set<String> _supportedMimeTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif',
  };
  static const Set<String> _supportedExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
  };

  Future<PreparedImage> prepareChatImage(File file) {
    return _prepareImageFile(
      file,
      maxBytes: chatMaxBytes,
      maxDimension: 1600,
      minQuality: 75,
      maxQuality: 85,
      squareCrop: false,
      tooLargeMessage: 'Файл слишком большой. Выберите другое фото.',
      debugLabel: 'chat',
    );
  }

  Future<PreparedImage> prepareListingImage(File file) {
    return _prepareImageFile(
      file,
      maxBytes: listingMaxBytes,
      maxDimension: 2560,
      minQuality: 80,
      maxQuality: 88,
      squareCrop: false,
      tooLargeMessage: 'Файл слишком большой. Выберите фото меньшего размера.',
      debugLabel: 'listing',
    );
  }

  Future<PreparedImage> prepareAvatar(File file) {
    return _prepareImageFile(
      file,
      maxBytes: avatarMaxBytes,
      maxDimension: 1200,
      minQuality: 78,
      maxQuality: 86,
      squareCrop: true,
      tooLargeMessage: 'Файл слишком большой. Выберите другое фото.',
      debugLabel: 'avatar',
    );
  }

  Future<PreparedImage> prepareAvatarBytes(
    Uint8List bytes, {
    String fileName = 'avatar.jpg',
  }) {
    return _prepareImageBytes(
      bytes,
      fileName: fileName,
      maxBytes: avatarMaxBytes,
      maxDimension: 1200,
      minQuality: 78,
      maxQuality: 86,
      squareCrop: true,
      tooLargeMessage: 'Фото слишком большое. Попробуйте выбрать другое фото.',
      debugLabel: 'avatar',
    );
  }

  Future<PreparedImage> _prepareImageFile(
    File file, {
    required int maxBytes,
    required int maxDimension,
    required int minQuality,
    required int maxQuality,
    required bool squareCrop,
    required String tooLargeMessage,
    required String debugLabel,
  }) async {
    final originalBytes = await file.readAsBytes();
    return _prepareImageBytes(
      originalBytes,
      fileName: file.path.split(Platform.pathSeparator).last,
      maxBytes: maxBytes,
      maxDimension: maxDimension,
      minQuality: minQuality,
      maxQuality: maxQuality,
      squareCrop: squareCrop,
      tooLargeMessage: tooLargeMessage,
      debugLabel: debugLabel,
    );
  }

  Future<PreparedImage> _prepareImageBytes(
    Uint8List originalBytes, {
    required String fileName,
    required int maxBytes,
    required int maxDimension,
    required int minQuality,
    required int maxQuality,
    required bool squareCrop,
    required String tooLargeMessage,
    required String debugLabel,
  }) async {
    final extension = _detectExtension(fileName, originalBytes);
    final mimeType = lookupMimeType(
          fileName,
          headerBytes: originalBytes.take(16).toList(),
        )?.toLowerCase() ??
        '';
    if (!_supportedExtensions.contains(extension) &&
        !_supportedMimeTypes.contains(mimeType)) {
      throw const ApiException(
        'Поддерживаются только JPEG, PNG, WEBP и HEIC/HEIF фото.',
      );
    }
    img.Image? decoded;
    try {
      decoded = img.decodeImage(originalBytes);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      if (extension == 'heic' || extension == 'heif') {
        throw const ApiException(
          'Формат HEIC пока не поддерживается на этом устройстве. Пересохраните фото как JPEG или PNG и попробуйте ещё раз.',
        );
      }
      throw const ApiException(
        'Не удалось обработать изображение. Выберите настоящее фото в JPEG, PNG или WEBP.',
      );
    }

    var working = squareCrop ? _squareCrop(decoded) : decoded;
    working = _resizeIfNeeded(working, maxDimension);

    Uint8List bestBytes = Uint8List.fromList(
      img.encodeJpg(working, quality: maxQuality),
    );

    if (bestBytes.length > maxBytes) {
      for (var quality = maxQuality - 4;
          quality >= minQuality && bestBytes.length > maxBytes;
          quality -= 4) {
        bestBytes =
            Uint8List.fromList(img.encodeJpg(working, quality: quality));
      }
    }

    var resizeDimension = maxDimension;
    while (bestBytes.length > maxBytes && resizeDimension > 960) {
      resizeDimension = math.max(960, resizeDimension - 240);
      working = _resizeIfNeeded(
        squareCrop ? _squareCrop(decoded) : decoded,
        resizeDimension,
      );
      bestBytes = Uint8List.fromList(
        img.encodeJpg(working, quality: minQuality),
      );
    }

    if (kDebugMode) {
      debugPrint(
        'Image prepare [$debugLabel]: before=${originalBytes.length} after=${bestBytes.length}',
      );
    }

    if (bestBytes.length > maxBytes) {
      throw ApiException(
        tooLargeMessage,
        statusCode: 413,
        code: 'payload_too_large',
      );
    }

    return PreparedImage(
      bytes: bestBytes,
      fileName: '$debugLabel.jpg',
      contentType: 'image/jpeg',
      originalBytes: originalBytes.length,
      compressedBytes: bestBytes.length,
    );
  }

  img.Image _resizeIfNeeded(img.Image source, int maxDimension) {
    if (source.width <= maxDimension && source.height <= maxDimension) {
      return source;
    }
    if (source.width >= source.height) {
      return img.copyResize(source, width: maxDimension);
    }
    return img.copyResize(source, height: maxDimension);
  }

  img.Image _squareCrop(img.Image source) {
    final size = math.min(source.width, source.height);
    final x = ((source.width - size) / 2).round();
    final y = ((source.height - size) / 2).round();
    return img.copyCrop(source, x: x, y: y, width: size, height: size);
  }

  String _detectExtension(String fileName, Uint8List bytes) {
    final sanitized = fileName.trim().toLowerCase();
    final dot = sanitized.lastIndexOf('.');
    if (dot != -1 && dot + 1 < sanitized.length) {
      return sanitized.substring(dot + 1);
    }
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
      if (brand.contains('heic') || brand.contains('heix')) return 'heic';
      if (brand.contains('heif') || brand.contains('hevx')) return 'heif';
    }
    return '';
  }
}
