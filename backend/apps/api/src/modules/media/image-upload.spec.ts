import { Readable } from 'node:stream';
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { detectImageMime, IMAGE_UPLOAD_LIMITS, memoryImageUploadOptions } from './image-upload';

const multer = require('multer');

test('upload limits preserve every existing route size and multipart bounds', () => {
  assert.deepEqual(IMAGE_UPLOAD_LIMITS, {
    avatar: 2 * 1024 * 1024,
    chat: 2 * 1024 * 1024,
    listing: 8 * 1024 * 1024,
    admin: 5 * 1024 * 1024,
    support: 5 * 1024 * 1024,
  });
  assert.deepEqual(memoryImageUploadOptions(123).limits, {
    fileSize: 123,
    files: 1,
    fields: 10,
    parts: 12,
    fieldNameSize: 100,
    fieldSize: 64 * 1024,
  });
});

function multipartBody(
  boundary: string,
  file: Buffer,
  fields: Array<[string, string]> = [],
) {
  const chunks: Buffer[] = [];
  for (const [name, value] of fields) {
    chunks.push(Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n${value}\r\n`,
    ));
  }
  chunks.push(Buffer.from(
    `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="photo.jpg"\r\nContent-Type: image/jpeg\r\n\r\n`,
  ));
  chunks.push(file, Buffer.from(`\r\n--${boundary}--\r\n`));
  return Buffer.concat(chunks);
}

async function parseMultipart(body: Buffer, boundary: string, maxFileSize: number) {
  const request = Readable.from(body) as Readable & Record<string, any>;
  request.headers = {
    'content-length': String(body.length),
    'content-type': `multipart/form-data; boundary=${boundary}`,
  };
  request.method = 'POST';
  request.url = '/media/test';

  await new Promise<void>((resolve, reject) => {
    multer(memoryImageUploadOptions(maxFileSize)).single('file')(
      request,
      {} as any,
      (error: unknown) => error ? reject(error) : resolve(),
    );
  });
  return request;
}

test('multipart accepts one valid file within the configured limit', async () => {
  const boundary = 'atta-valid-upload';
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xdb]);
  const request = await parseMultipart(multipartBody(boundary, jpeg), boundary, jpeg.length);

  assert.equal(request.file.size, jpeg.length);
  assert.deepEqual(request.file.buffer, jpeg);
  assert.equal(detectImageMime(request.file.buffer), 'image/jpeg');
});

test('multipart rejects a file before buffering beyond the configured limit', async () => {
  const boundary = 'atta-oversized-upload';
  await assert.rejects(
    () => parseMultipart(multipartBody(boundary, Buffer.alloc(9, 1)), boundary, 8),
    (error: any) => error?.code === 'LIMIT_FILE_SIZE',
  );
});

test('multipart rejects excessive fields and malformed input', async () => {
  const boundary = 'atta-field-limit';
  const fields = Array.from({ length: 11 }, (_, index) => [`field${index}`, 'x'] as [string, string]);
  await assert.rejects(
    () => parseMultipart(multipartBody(boundary, Buffer.from([0xff]), fields), boundary, 1024),
    (error: any) => error?.code === 'LIMIT_FIELD_COUNT' || error?.code === 'LIMIT_PART_COUNT',
  );

  const malformedBoundary = 'atta-malformed-upload';
  const malformed = Buffer.from(
    `--${malformedBoundary}\r\nContent-Disposition: form-data; name="file"; filename="x.jpg"\r\nContent-Type: image/jpeg\r\n\r\nunfinished`,
  );
  await assert.rejects(
    () => parseMultipart(malformed, malformedBoundary, 1024),
    /Unexpected end of form/,
  );
});
