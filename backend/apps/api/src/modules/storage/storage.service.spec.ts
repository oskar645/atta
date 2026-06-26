import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { test } from 'node:test';

import { ServiceUnavailableException } from '@nestjs/common';

import { env } from '../../config/env';
import { AppController } from '../../app.controller';
import { normalizeStoredMediaUrl } from '../../common/serializers';
import { LocalStorageProvider } from './local-storage.provider';
import { MediaStorageService } from './media-storage.service';
import { S3StorageProvider } from './s3-storage.provider';
import { StorageService } from './storage.service';

test('local storage still works when STORAGE_DRIVER=local', async () => {
  const previousDriver = env.STORAGE_DRIVER;
  const previousProvider = env.STORAGE_PROVIDER;
  const previousUploadsDir = env.LOCAL_UPLOADS_DIR;
  const previousBaseUrl = env.MEDIA_PUBLIC_BASE_URL;
  const root = await mkdtemp(join(tmpdir(), 'atta-local-storage-'));

  env.STORAGE_DRIVER = 'local';
  env.STORAGE_PROVIDER = 'local';
  env.LOCAL_UPLOADS_DIR = root;
  env.MEDIA_PUBLIC_BASE_URL = 'https://atta.local/uploads';

  try {
    const provider = new LocalStorageProvider();
    const saved = await provider.saveFile({
      buffer: Buffer.from('hello'),
      category: 'avatars',
      contentType: 'image/png',
      originalName: 'avatar.png',
    });

    assert.equal(saved.provider, 'local');
    assert.match(saved.url, /\/uploads\/avatars\//);
    const bytes = await readFile(join(root, 'avatars', saved.key));
    assert.equal(bytes.toString(), 'hello');
  } finally {
    env.STORAGE_DRIVER = previousDriver;
    env.STORAGE_PROVIDER = previousProvider;
    env.LOCAL_UPLOADS_DIR = previousUploadsDir;
    env.MEDIA_PUBLIC_BASE_URL = previousBaseUrl;
    await rm(root, { recursive: true, force: true });
  }
});

test('S3 provider builds correct key and url', async () => {
  const uploads: Array<Record<string, string>> = [];
  const provider = new S3StorageProvider({
    buildMediaUrl: ({ category, key }: { category: string; key: string }) =>
      `https://cdn.example.com/${category}/${key}`,
    deleteObject: async () => undefined,
    getBucketName: () => 'atta-media-prod',
    getHealthStatus: async () => ({ status: 's3_ok' as const }),
    isConfigured: () => true,
    readObject: async () => Buffer.from(''),
    uploadObject: async (payload: Record<string, string | Buffer>) => {
      uploads.push({
        bucket: String(payload.bucket),
        key: String(payload.key),
      });
    },
  } as never);

  const avatar = await provider.saveFile({
    buffer: Buffer.from('avatar'),
    category: 'avatars',
    contentType: 'image/jpeg',
    context: { userId: 'user-1' },
    originalName: 'avatar.jpg',
  });
  const listing = await provider.saveFile({
    buffer: Buffer.from('listing'),
    category: 'listings',
    contentType: 'image/png',
    context: { listingId: 'listing-1' },
    originalName: 'photo.png',
  });

  assert.match(uploads[0].key, /^avatars\/user-1\/.+\.jpg$/);
  assert.match(uploads[1].key, /^listings\/listing-1\/.+\.png$/);
  assert.match(avatar.url, /^https:\/\/cdn\.example\.com\/avatars\//);
  assert.match(listing.url, /^https:\/\/cdn\.example\.com\/listings\//);
});

test('old /uploads url remains unchanged', () => {
  const storage = new StorageService(
    {} as never,
    {} as never,
    {
      getLocalProvider: () => new LocalStorageProvider(),
      getProvider: () => new LocalStorageProvider(),
      getProviderName: () => 'local',
      getS3Provider: () => ({}) as never,
    } as never,
  );

  const key = storage.extractLocalKey(
    'avatars',
    'https://atta.local/uploads/avatars/legacy.jpg',
  );

  assert.equal(key, 'legacy.jpg');
});

test('normalizeStoredMediaUrl converts S3 url into backend proxy without duplicate bucket', () => {
  const normalized = normalizeStoredMediaUrl(
    'https://s3.twcstorage.ru/atta-media-prod/atta-media-prod/avatars/user-1/new.jpg',
    {
      category: 'avatars',
      providerHint: 's3',
    },
  );

  assert.equal(
    normalized,
    '/media/object?category=avatars&key=avatars%2Fuser-1%2Fnew.jpg',
  );
});

test('failed S3 upload returns Russian error', async () => {
  const storage = new StorageService(
    {} as never,
    {} as never,
    {
      getLocalProvider: () => new LocalStorageProvider(),
      getProvider: () => ({
        buildPublicUrl: () => '',
        deleteFile: async () => undefined,
        ensureReady: async () => undefined,
        getHealth: async () => ({ status: 's3_error' as const }),
        getName: () => 's3' as const,
        readFile: async () => Buffer.from(''),
        saveFile: async () => {
          throw new Error('boom');
        },
      }),
      getProviderName: () => 's3',
      getS3Provider: () => ({}) as never,
    } as never,
  );

  await assert.rejects(
    storage.saveUploadedFile({
      buffer: Buffer.from('x'),
      category: 'avatars',
      contentType: 'image/png',
      originalName: 'x.png',
    }),
    (error: unknown) =>
      error instanceof ServiceUnavailableException &&
      error.message === 'Не удалось загрузить файл. Попробуйте позже.',
  );
});

test('health dependencies returns s3_ok and s3_error', async () => {
  const controllerOk = new AppController(
    { $queryRaw: async () => 1 } as never,
    { ping: async () => 'PONG' } as never,
    { getHealthStatus: async () => ({ status: 's3_ok' as const }) } as never,
  );
  const controllerError = new AppController(
    { $queryRaw: async () => 1 } as never,
    { ping: async () => 'PONG' } as never,
    {
      getHealthStatus: async () => ({
        status: 's3_error' as const,
        message: 'S3 недоступен.',
      }),
    } as never,
  );

  const ok = await controllerOk.getDependenciesHealth();
  const error = await controllerError.getDependenciesHealth();

  assert.equal(ok.storage, 's3_ok');
  assert.equal(ok.storage_message, null);
  assert.equal(error.storage, 's3_error');
  assert.equal(error.storage_message, 'S3 недоступен.');
});
