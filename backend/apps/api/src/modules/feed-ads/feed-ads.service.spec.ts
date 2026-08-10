import { test } from 'node:test';
import assert from 'node:assert/strict';

import { FeedAdPlacement } from '@prisma/client';

import { FeedAdsService } from './feed-ads.service';

const authUser = {
  userId: 'admin-1',
  sessionId: 'session-1',
  role: 'admin' as const,
};

function feedAd(overrides?: Record<string, unknown>) {
  const createdAt = new Date('2026-08-10T10:00:00.000Z');
  return {
    id: 'feed-ad-1',
    title: 'Промо',
    imageUrl: 'https://cdn.example.com/feed-ad.png',
    imageBucket: 'feed-ads',
    imageKey: 'feed-ad-1/feed-ad.png',
    targetUrl: 'https://example.com',
    durationDays: 1,
    isActive: false,
    placement: FeedAdPlacement.HOME,
    createdById: authUser.userId,
    createdAt,
    activatedAt: null,
    expiresAt: null,
    updatedAt: createdAt,
    impressionCount: BigInt(0),
    clickCount: BigInt(0),
    ...overrides,
  };
}

function createService(overrides?: {
  findUnique?: (args?: Record<string, unknown>) => Promise<unknown>;
  findFirst?: (args?: Record<string, unknown>) => Promise<unknown>;
  create?: (args: Record<string, unknown>) => Promise<unknown>;
  update?: (args: Record<string, unknown>) => Promise<unknown>;
  updateMany?: (args: Record<string, unknown>) => Promise<unknown>;
}) {
  const prisma = {
    feedAd: {
      findUnique: overrides?.findUnique ?? (async () => feedAd()),
      findFirst: overrides?.findFirst ?? (async () => null),
      findMany: async () => [],
      create:
        overrides?.create ??
        (async (args: Record<string, unknown>) =>
          feedAd(args['data'] as Record<string, unknown>)),
      update:
        overrides?.update ??
        (async (args: Record<string, unknown>) =>
          feedAd(args['data'] as Record<string, unknown>)),
      updateMany: overrides?.updateMany ?? (async () => ({ count: 1 })),
      delete: async () => feedAd(),
    },
  };

  const storage = {
    deleteFeedAdImage: async () => undefined,
    saveUploadedFile: async () => ({
      bucket: 'feed-ads',
      key: 'feed-ad-1/feed-ad.png',
      url: 'https://cdn.example.com/feed-ad.png',
    }),
  };

  return new FeedAdsService(prisma as never, storage as never);
}

test('feed ad creation keeps new ads inactive until manual activation', async () => {
  let createArgs: Record<string, unknown> | undefined;
  const service = createService({
    create: async (args) => {
      createArgs = args;
      return feedAd(args['data'] as Record<string, unknown>);
    },
  });

  const result = await service.create(authUser, {
    title: 'Промо',
    image_url: 'https://cdn.example.com/feed-ad.png',
    target_url: 'https://example.com',
    duration_days: 10,
  });

  const data = createArgs?.['data'] as Record<string, unknown>;
  assert.equal(data['isActive'], false);
  assert.equal(result.ad.is_active, false);
});

test('activation calls updateMany, activates requested ad and preserves day durations as 24h blocks', async () => {
  for (const durationDays of [1, 2, 5, 10, 15, 20, 30]) {
    let disabledPreviousAds = false;
    let updateData: Record<string, unknown> | undefined;
    const service = createService({
      findUnique: async () => feedAd({ durationDays }),
      updateMany: async () => {
        disabledPreviousAds = true;
        return { count: 1 };
      },
      update: async (args) => {
        updateData = args['data'] as Record<string, unknown>;
        return feedAd(updateData);
      },
    });

    const result = await service.activate('feed-ad-1');
    const activatedAt = updateData?.['activatedAt'] as Date;
    const expiresAt = updateData?.['expiresAt'] as Date;

    assert.equal(disabledPreviousAds, true);
    assert.equal(updateData?.['isActive'], true);
    assert.equal(
      expiresAt.getTime() - activatedAt.getTime(),
      durationDays * 86400000,
    );
    assert.equal(result.ad.is_active, true);
  }
});

test('active feed ad query excludes expired ads', async () => {
  let findFirstArgs: Record<string, unknown> | undefined;
  const service = createService({
    findFirst: async (args) => {
      findFirstArgs = args;
      return null;
    },
  });

  const result = await service.getActive('home');
  const where = findFirstArgs?.['where'] as Record<string, unknown>;
  const clauses = where['OR'] as Array<{ expiresAt: unknown }>;

  assert.equal(where['isActive'], true);
  assert.equal(clauses[0].expiresAt, null);
  assert.ok((clauses[1].expiresAt as { gt: unknown }).gt instanceof Date);
  assert.equal(result.ad, null);
});
