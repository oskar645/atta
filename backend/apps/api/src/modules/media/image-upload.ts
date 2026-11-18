const MAX_MULTIPART_FIELDS = 10;

export const IMAGE_UPLOAD_LIMITS = {
  avatar: 2 * 1024 * 1024,
  chat: 2 * 1024 * 1024,
  listing: 8 * 1024 * 1024,
  admin: 5 * 1024 * 1024,
  support: 5 * 1024 * 1024,
} as const;

export function memoryImageUploadOptions(maxFileSize: number) {
  return {
    storage: require('multer').memoryStorage(),
    limits: {
      fileSize: maxFileSize,
      files: 1,
      fields: MAX_MULTIPART_FIELDS,
      parts: MAX_MULTIPART_FIELDS + 2,
      fieldNameSize: 100,
      fieldSize: 64 * 1024,
    },
  };
}

export function detectImageMime(buffer: Buffer) {
  if (
    buffer.length >= 3 &&
    buffer[0] === 0xff &&
    buffer[1] === 0xd8 &&
    buffer[2] === 0xff
  ) {
    return 'image/jpeg';
  }
  if (
    buffer.length >= 8 &&
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47 &&
    buffer[4] === 0x0d &&
    buffer[5] === 0x0a &&
    buffer[6] === 0x1a &&
    buffer[7] === 0x0a
  ) {
    return 'image/png';
  }
  if (
    buffer.length >= 12 &&
    buffer.toString('ascii', 0, 4) === 'RIFF' &&
    buffer.toString('ascii', 8, 12) === 'WEBP'
  ) {
    return 'image/webp';
  }
  if (buffer.length >= 12 && buffer.toString('ascii', 4, 8) === 'ftyp') {
    const brand = buffer.toString('ascii', 8, 12).toLowerCase();
    if (brand.includes('heic') || brand.includes('heix')) {
      return 'image/heic';
    }
    if (brand.includes('heif') || brand.includes('hevx')) {
      return 'image/heif';
    }
  }
  return null;
}
