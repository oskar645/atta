import assert from 'node:assert/strict';
import test from 'node:test';
import { TopBannersService } from './top-banners.service';

const at = new Date('2026-09-26T10:00:00Z');
function banner(id: string, order: number) {
  return { id, title: id, imageUrl: `https://cdn.example/${id}.jpg`, imageBucket: 'feed-ads', imageKey: null,
    targetUrl: '', enabled: true, startAt: new Date('2026-09-01T00:00:00Z'), endAt: new Date('2099-10-01T00:00:00Z'),
    sortOrder: order, impressionCount: 0n, clickCount: 0n, createdAt: at, updatedAt: at, createdById: null };
}

test('cold-start cursor rotates in configured order', async () => {
  const items = [banner('a', 1), banner('b', 2), banner('c', 3)];
  const prisma = { topBanner: { findMany: async () => items } };
  const service = new TopBannersService(prisma as never, {} as never);
  assert.equal((await service.active()).banner?.id, 'a');
  assert.equal((await service.active('a')).banner?.id, 'b');
  assert.equal((await service.active('b')).banner?.id, 'c');
  assert.equal((await service.active('c')).banner?.id, 'a');
});

test('no eligible banner returns safe empty response', async () => {
  const prisma = { topBanner: { findMany: async () => [] } };
  const service = new TopBannersService(prisma as never, {} as never);
  assert.equal((await service.active()).banner, null);
});
