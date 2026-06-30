import { test } from 'node:test';
import assert from 'node:assert/strict';

import { BadRequestException } from '@nestjs/common';

import { MediaController } from './media.controller';

function createController() {
  return new MediaController(
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
  );
}

test('media controller rejects non-image upload', () => {
  const controller = createController() as any;

  assert.throws(
    () =>
      controller.requireImage(
        {
          buffer: Buffer.from('not-an-image'),
          mimetype: 'text/plain',
          size: 12,
          originalname: 'payload.txt',
        },
        1024,
      ),
    (error: unknown) =>
      error instanceof BadRequestException &&
      error.message === 'Поддерживаются JPG, PNG, WEBP и HEIC/HEIF',
  );
});

