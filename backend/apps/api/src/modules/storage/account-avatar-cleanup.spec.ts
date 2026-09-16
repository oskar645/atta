import { test } from 'node:test';
import assert from 'node:assert/strict';
import { StorageService } from './storage.service';
import { env } from '../../config/env';

const A = '11111111-1111-4111-8111-111111111111';
const B = '22222222-2222-4222-8222-222222222222';
function fixture(provider = 's3', shared = false) {
  const deleted: string[] = [];
  const service = new StorageService({ user: { findMany: async () => shared ? [{ avatarUrl: 'shared' }] : [] } } as never,
    {} as never, { getProviderName: () => provider,
      getS3Provider: () => ({ deleteFile: async (_: string, key: string) => { deleted.push(key); } }),
      getLocalProvider: () => ({ deleteFile: async (_: string, key: string) => { deleted.push(key); } }),
    } as never);
  return { service, deleted };
}

test('account avatar cleanup deletes only an owned S3 key, including encoded proxy URLs', async () => {
  const f = fixture(); const key = `avatars/${A}/photo.jpg`;
  await f.service.deleteAccountAvatar(A, `/media/object?category=avatars&key=${encodeURIComponent(key)}`);
  assert.deepEqual(f.deleted, [key]);
});

test('account cleanup never deletes foreign, shared, external or traversal avatar paths', async () => {
  const f = fixture();
  for (const url of [
    `/media/object?category=avatars&key=avatars/${B}/photo.jpg`,
    `/media/object?category=avatars&key=avatars/${A}/../${B}/photo.jpg`,
    `/media/object?category=chats&key=avatars/${A}/photo.jpg`,
    `https://untrusted.example/avatars/${A}/photo.jpg`,
    `https://untrusted.example/media/object?category=avatars&key=avatars/${A}/photo.jpg`,
  ]) await f.service.deleteAccountAvatar(A, url);
  assert.deepEqual(f.deleted, []);
  const shared = fixture('s3', true);
  await shared.service.deleteAccountAvatar(A, `/media/object?category=avatars&key=avatars/${A}/photo.jpg`);
  assert.deepEqual(shared.deleted, []);
});

test('local cleanup strips version query and uses configured local storage only', async () => {
  const f = fixture('local');
  await f.service.deleteAccountAvatar(A, `${env.MEDIA_PUBLIC_BASE_URL}/avatars/photo.jpg?v=old`);
  assert.deepEqual(f.deleted, ['photo.jpg']);
});

test('provider deletion errors propagate so the durable account cleanup can retry', async () => {
  const f = fixture();
  (f.service as any).deleteStoredFile = async () => { throw new Error('provider unavailable'); };
  await assert.rejects(f.service.deleteAccountAvatar(A, `/media/object?category=avatars&key=avatars/${A}/photo.jpg`), /provider unavailable/);
});

test('inactive storage provider does not silently complete physical cleanup', async () => {
  const f = fixture('local');
  await assert.rejects(f.service.deleteAccountAvatar(A, `/media/object?category=avatars&key=avatars/${A}/photo.jpg`), /provider is not active/);
  assert.deepEqual(f.deleted, []);
});

test('encoded avatar reference on B prevents deletion of the shared A object', async () => {
  const key = `avatars/${A}/photo.jpg`;
  const bAvatar = `/media/object?category=avatars&key=${encodeURIComponent(key)}`;
  let deleted = false;
  const service = new StorageService({ user: { findMany: async ({ where }: any) => {
    assert.deepEqual(where.id, { not: A });
    return where.OR.some((clause: any) => clause.avatarUrl && bAvatar.includes(clause.avatarUrl.contains))
      ? [{ avatarUrl: bAvatar }] : [];
  } } } as never, {} as never, { getProviderName: () => 's3',
    getS3Provider: () => ({ deleteFile: async () => { deleted = true; } }),
  } as never);
  await service.deleteAccountAvatar(A, bAvatar);
  assert.equal(deleted, false);
});
