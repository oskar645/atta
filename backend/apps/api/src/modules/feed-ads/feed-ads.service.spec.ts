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
  findMany?: (args?: Record<string, unknown>) => Promise<unknown[]>;
  create?: (args: Record<string, unknown>) => Promise<unknown>;
  update?: (args: Record<string, unknown>) => Promise<unknown>;
  updateMany?: (args: Record<string, unknown>) => Promise<unknown>;
  count?: (args?: Record<string, unknown>) => Promise<number>;
}) {
  const prisma = {
    feedAd: {
      findUnique: overrides?.findUnique ?? (async () => feedAd()),
      findFirst: overrides?.findFirst ?? (async () => null),
      findMany: overrides?.findMany ?? (async () => []),
      create:
        overrides?.create ??
        (async (args: Record<string, unknown>) =>
          feedAd(args['data'] as Record<string, unknown>)),
      update:
        overrides?.update ??
        (async (args: Record<string, unknown>) =>
          feedAd(args['data'] as Record<string, unknown>)),
      updateMany: overrides?.updateMany ?? (async () => ({ count: 1 })),
      count: overrides?.count ?? (async () => 0),
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

  return new FeedAdsService(prisma as never, storage as never, {
    debounce: async () => true,
  } as never);
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

test('feed ad creation accepts empty target url and trims instagram links', async () => {
  const createdTargetUrls: unknown[] = [];
  const service = createService({
    create: async (args) => {
      const data = args['data'] as Record<string, unknown>;
      createdTargetUrls.push(data['targetUrl']);
      return feedAd(data);
    },
  });

  const emptyResult = await service.create(authUser, {
    title: 'Промо без ссылки',
    image_url: 'https://cdn.example.com/feed-ad.png',
    target_url: '   ',
    duration_days: 10,
  });
  const instagramResult = await service.create(authUser, {
    title: 'Instagram',
    image_url: 'https://cdn.example.com/feed-ad.png',
    target_url: '  https://www.instagram.com/atta/  ',
    duration_days: 10,
  });

  assert.equal(emptyResult.ad.target_url, '');
  assert.equal(instagramResult.ad.target_url, 'https://www.instagram.com/atta/');
  assert.deepEqual(createdTargetUrls, [
    '',
    'https://www.instagram.com/atta/',
  ]);
});

test('feed ad creation rejects non-http target urls when present', async () => {
  const service = createService();

  await assert.rejects(
    () =>
      service.create(authUser, {
        title: 'Промо',
        image_url: 'https://cdn.example.com/feed-ad.png',
        target_url: 'ftp://example.com/file',
        duration_days: 10,
      }),
    /Некорректная ссылка/,
  );
});

test('feed ad update preserves, changes, and clears target url by id', async () => {
  const updateArgs: Record<string, unknown>[] = [];
  const service = createService({
    update: async (args) => {
      updateArgs.push(args);
      return feedAd(args['data'] as Record<string, unknown>);
    },
  });

  await service.update('feed-ad-1', { title: 'Только заголовок' });
  const changed = await service.update('feed-ad-1', {
    target_url: ' https://example.com/new ',
  });
  const cleared = await service.update('feed-ad-1', {
    target_url: '',
  });

  assert.equal(
    (updateArgs[0]['data'] as Record<string, unknown>)['targetUrl'],
    undefined,
  );
  assert.deepEqual(updateArgs.map((args) => args['where']), [
    { id: 'feed-ad-1' },
    { id: 'feed-ad-1' },
    { id: 'feed-ad-1' },
  ]);
  assert.equal(changed.ad.target_url, 'https://example.com/new');
  assert.equal(cleared.ad.target_url, '');
});

test('activation keeps other active ads and preserves day durations as 24h blocks', async () => {
  for (const durationDays of [1, 2, 5, 10, 15, 20, 30]) {
    let activeCountArgs: Record<string, unknown> | undefined;
    let updateData: Record<string, unknown> | undefined;
    const service = createService({
      findUnique: async () => feedAd({ durationDays }),
      count: async (args) => {
        activeCountArgs = args;
        return 2;
      },
      update: async (args) => {
        updateData = args['data'] as Record<string, unknown>;
        return feedAd(updateData);
      },
    });

    const result = await service.activate('feed-ad-1');
    const activatedAt = updateData?.['activatedAt'] as Date;
    const expiresAt = updateData?.['expiresAt'] as Date;
    const where = activeCountArgs?.['where'] as Record<string, unknown>;

    assert.deepEqual(where['id'], { not: 'feed-ad-1' });
    assert.equal(where['isActive'], true);
    assert.equal(updateData?.['isActive'], true);
    assert.equal(
      expiresAt.getTime() - activatedAt.getTime(),
      durationDays * 86400000,
    );
    assert.equal(result.ad.is_active, true);
  }
});

test('activation rejects fourth visible active feed ad for placement', async () => {
  const service = createService({
    count: async () => 3,
  });

  await assert.rejects(
    () => service.activate('feed-ad-1'),
    /Feed ads limit reached for placement/,
  );
});

test('active feed ad query excludes expired ads', async () => {
  let findManyArgs: Record<string, unknown> | undefined;
  const service = createService({
    findMany: async (args) => {
      findManyArgs = args;
      return [];
    },
  });

  const result = await service.getActive('home');
  const where = findManyArgs?.['where'] as Record<string, unknown>;
  const clauses = where['OR'] as Array<{ expiresAt: unknown }>;

  assert.equal(where['isActive'], true);
  assert.equal(clauses[0].expiresAt, null);
  assert.ok((clauses[1].expiresAt as { gt: unknown }).gt instanceof Date);
  assert.equal(result.ad, null);
});

test('active feed ad query rotates to the ad after cursor and wraps', async () => {
  const items = [
    feedAd({ id: 'feed-ad-1', isActive: true }),
    feedAd({ id: 'feed-ad-2', isActive: true }),
    feedAd({ id: 'feed-ad-3', isActive: true }),
  ];
  const service = createService({
    findMany: async () => items,
  });

  const second = await service.getActive('home', 'feed-ad-1');
  const third = await service.getActive('home', 'feed-ad-2');
  const first = await service.getActive('home', 'feed-ad-3');

  assert.equal(second.ad?.id, 'feed-ad-2');
  assert.equal(third.ad?.id, 'feed-ad-3');
  assert.equal(first.ad?.id, 'feed-ad-1');
});

test('feed ad counter debounce skips duplicate source increments without blocking tracking', async () => {
  let updateCalls = 0;
  const service = new FeedAdsService(
    {
      feedAd: {
        update: async () => {
          updateCalls += 1;
          return feedAd();
        },
      },
    } as never,
    {} as never,
    {
      debounce: async () => updateCalls === 0,
    } as never,
  );

  const first = await service.recordImpression('feed-ad-1', {
    ip: '203.0.113.10',
    userAgent: 'atta-app/1',
  });
  const duplicate = await service.recordImpression('feed-ad-1', {
    ip: '203.0.113.10',
    userAgent: 'atta-app/1',
  });

  assert.equal(first.tracked, true);
  assert.equal(duplicate.tracked, true);
  assert.equal(updateCalls, 1);
});
