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

for (const [category, key] of [
  ['avatars', 'avatars/user-1/photo.png'],
  ['listings', 'listing-photos/legacy.jpg'],
  ['feed-ads', 'misc/ad-1/image.jpg'],
  ['misc', 'misc/notification.jpg'],
]) {
  test(`public namespace remains accessible: ${category}/${key}`, async () => {
    const controller = createController() as any;
    let read = false;
    controller.storageService = { readStoredFile: async () => { read = true; return Buffer.from([]); } };
    await controller.getPublicObject(category, key, { setHeader() {}, send() {} });
    assert.equal(read, true);
  });
}

for (const category of ['avatars', 'listings', 'feed-ads', 'misc', 'videos']) {
  for (const key of [
    'chats/chat-1/photo.jpg', 'chat-images/photo.jpg',
    'support/ticket-1/photo.jpg', 'support-images/photo.jpg',
    'reports/report-1/photo.jpg', 'private/secrets.json', '.env',
    `${category}/../support/secret.jpg`, `${category}//image.jpg`,
    `${category}/%2e%2e/support/secret.jpg`, `${category}%2fsupport/secret.jpg`,
    `${category}/%252e%252e/secret.jpg`, `${category}/image.jpg%00`,
    `${category}/\\..\\support\\secret.jpg`, `/${category}/image.jpg`,
    `bucket/${category}/image.jpg`,
  ]) {
    test(`public proxy rejects substituted or manipulated key: ${category} ${key}`, async () => {
      const controller = createController() as any;
      controller.storageService = { readStoredFile: async () => assert.fail('S3 must not be read') };
      await assert.rejects(() => controller.getPublicObject(category, key, {}), BadRequestException);
    });
  }
}

test('private chat media without authentication never reads storage', async () => {
  const controller = createController();
  await assert.rejects(() => controller.getChatImageByKey('chats/chat-1/photo.jpg', undefined, { headers: {} }, {}),
    { message: 'Access token is required' });
});

test('support proxy rejects namespace manipulation even for admin', async () => {
  const controller = createController();
  for (const key of ['private/secrets.json', 'support/../private/secret', 'support/%2e%2e/secret', 'support-images/%252fsecret']) {
    await assert.rejects(() => controller.getSupportFileByKey({ role: 'admin' } as any, key, {}), BadRequestException);
  }
});

test('deleted account scoped avatar is inaccessible while S3 cleanup is pending', async () => {
  const controller = new MediaController({} as never, {
    user: { findUnique: async () => ({ status: 'DELETED', deletedAt: new Date() }) },
  } as never, {} as never, {} as never, {} as never, {} as never, {} as never, {} as never, {} as never,
  { readStoredFile: async () => { throw new Error('must not read deleted avatar'); } } as never, {} as never);
  await assert.rejects(controller.getPublicObject('avatars', 'avatars/11111111-1111-4111-8111-111111111111/image.jpg', {}), /Файл не найден/);
});

test('active account scoped avatar remains public', async () => {
  let sent = false;
  const controller = new MediaController({} as never, {
    user: { findUnique: async () => ({ status: 'ACTIVE', deletedAt: null }) },
  } as never, {} as never, {} as never, {} as never, {} as never, {} as never, {} as never, {} as never,
  { readStoredFile: async () => Buffer.from('avatar') } as never, {} as never);
  await controller.getPublicObject('avatars', 'avatars/22222222-2222-4222-8222-222222222222/image.jpg', {
    setHeader: () => {}, send: () => { sent = true; },
  });
  assert.equal(sent, true);
});
