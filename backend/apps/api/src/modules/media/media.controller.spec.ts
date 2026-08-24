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

test('public object proxy rejects private chat, support and reports media', async () => {
  const storage = {
    readStoredFile: async () => {
      throw new Error('private media should not be read by public proxy');
    },
  };
  const controller = new MediaController(
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    storage as any,
    {} as any,
  );
  const response = {
    setHeader: () => undefined,
    send: () => undefined,
  };

  await assert.rejects(
    () => controller.getPublicObject('support', 'support/ticket-1/photo.jpg', response),
    BadRequestException,
  );
  await assert.rejects(
    () => controller.getPublicObject('chats', 'chats/chat-1/photo.jpg', response),
    BadRequestException,
  );
  await assert.rejects(
    () => controller.getPublicObject('reports', 'reports/report-1/photo.jpg', response),
    BadRequestException,
  );
});

test('public object proxy still allows listing media', async () => {
  let readArgs: unknown[] | undefined;
  const storage = {
    readStoredFile: async (...args: unknown[]) => {
      readArgs = args;
      return Buffer.from([0xff, 0xd8, 0xff]);
    },
  };
  const controller = new MediaController(
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    storage as any,
    {} as any,
  );
  const response = {
    headers: new Map<string, string>(),
    body: null as Buffer | null,
    setHeader(name: string, value: string) {
      this.headers.set(name, value);
    },
    send(body: Buffer) {
      this.body = body;
    },
  };

  await controller.getPublicObject('listings', 'listings/listing-1/photo.jpg', response);

  assert.deepEqual(readArgs, ['listings', 'listings/listing-1/photo.jpg', 's3']);
  assert.equal(response.headers.get('Cache-Control'), 'public, max-age=300');
  assert.deepEqual(response.body, Buffer.from([0xff, 0xd8, 0xff]));
});

test('support media proxy rejects users outside the ticket', async () => {
  const controller = new MediaController(
    {} as any,
    {
      supportMessage: {
        findFirst: async () => null,
      },
    } as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {
      readStoredFile: async () => {
        throw new Error('forbidden user should not read support media');
      },
    } as any,
    {} as any,
  );

  await assert.rejects(
    () =>
      controller.getSupportFileByKey(
        { userId: 'stranger-1', role: 'user' } as any,
        'support/ticket-1/photo.jpg',
        {} as any,
      ),
    {
      message: 'Нет доступа к файлу',
    },
  );
});

test('support media proxy allows ticket owner and stays private-cacheable', async () => {
  const storageBytes = Buffer.from([0x89, 0x50, 0x4e, 0x47]);
  let readArgs: unknown[] | undefined;
  const controller = new MediaController(
    {} as any,
    {
      supportMessage: {
        findFirst: async (args: Record<string, any>) => {
          assert.equal(args.where.ticket.userId, 'user-1');
          assert.deepEqual(args.where.text, {
            contains: 'support/ticket-1/photo.png',
          });
          return {
            id: 'message-1',
          };
        },
      },
    } as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {
      readStoredFile: async (...args: unknown[]) => {
        readArgs = args;
        return storageBytes;
      },
    } as any,
    {} as any,
  );
  const response = {
    headers: new Map<string, string>(),
    body: null as Buffer | null,
    setHeader(name: string, value: string) {
      this.headers.set(name, value);
    },
    send(body: Buffer) {
      this.body = body;
    },
  };

  await controller.getSupportFileByKey(
    { userId: 'user-1', role: 'user' } as any,
    'support/ticket-1/photo.png',
    response,
  );

  assert.deepEqual(readArgs, ['support', 'support/ticket-1/photo.png', 's3']);
  assert.equal(response.headers.get('Cache-Control'), 'private, max-age=300');
  assert.equal(response.headers.get('Content-Type'), 'image/png');
  assert.deepEqual(response.body, storageBytes);
});

test('support media proxy allows admin without ticket membership lookup', async () => {
  let lookupCalled = false;
  let readCalled = false;
  const controller = new MediaController(
    {} as any,
    {
      supportMessage: {
        findFirst: async () => {
          lookupCalled = true;
          return null;
        },
      },
    } as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {
      readStoredFile: async () => {
        readCalled = true;
        return Buffer.from([]);
      },
    } as any,
    {} as any,
  );
  const response = {
    setHeader: () => undefined,
    send: () => undefined,
  };

  await controller.getSupportFileByKey(
    { userId: 'admin-1', role: 'admin' } as any,
    'support/ticket-1/photo.jpg',
    response,
  );

  assert.equal(lookupCalled, false);
  assert.equal(readCalled, true);
});
