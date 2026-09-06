import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  BadRequestException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import {
  ListingStatus,
  PromotionStatus,
  PromotionType,
  UserStatus,
} from '@prisma/client';

import {
  LISTING_PUBLICATION_NOT_READY,
  ListingsService,
  normalizeOemPartNumber,
} from './listings.service';
import { listingSearchDebugVariants } from '../../common/listing-search';

const ownerUser = {
  userId: 'owner-1',
  sessionId: 'session-1',
  role: 'user' as const,
};

const strangerUser = {
  userId: 'user-2',
  sessionId: 'session-2',
  role: 'user' as const,
};

const anotherStrangerUser = {
  userId: 'user-3',
  sessionId: 'session-3',
  role: 'user' as const,
};

const adminUser = {
  userId: 'admin-1',
  sessionId: 'session-admin-1',
  role: 'admin' as const,
};

const adminOwnerUser = {
  userId: ownerUser.userId,
  sessionId: 'session-admin-owner-1',
  role: 'admin' as const,
};

function createApprovedListing(
  id: string,
  publishedAt: string,
  category = 'Другое',
) {
  const published = new Date(publishedAt);
  return {
    id,
    ownerId: ownerUser.userId,
    ownerEmail: 'owner@example.com',
    ownerName: 'Owner',
    title: `Listing ${id}`,
    description: 'Описание объявления',
    category,
    subcategory: '',
    price: BigInt(1000),
    phone: '',
    phoneHidden: false,
    city: '',
    address: '',
    latitude: null,
    longitude: null,
    locationJson: {},
    delivery: {},
    car: null,
    dealType: null,
    realEstateType: null,
    clothesType: null,
    clothesSize: null,
    oemPartNumber: null as string | null,
    oemPartNumberNormalized: null as string | null,
    status: ListingStatus.APPROVED,
    rejectionReason: '',
    moderationNote: null,
    moderatedBy: null,
    moderatedAt: null,
    publishedAt: published,
    archivedAt: null,
    deletedAt: null,
    viewCount: 0,
    createdAt: published,
    updatedAt: published,
    owner: null,
    photos: [],
    promotions: [],
  };
}

function listingPhoto(id = 'photo-1', listingId = 'listing-1') {
  return {
    id,
    listingId,
    storageBucket: 'local',
    storageKey: `listings/${listingId}/${id}.jpg`,
    publicUrl: `https://example.com/${id}.jpg`,
    sortOrder: 0,
    sizeBytes: 128,
    mimeType: 'image/jpeg',
    createdAt: new Date('2026-07-01T10:00:00.000Z'),
  };
}

function listingOwner() {
  return {
    id: ownerUser.userId,
    email: 'owner@example.com',
    phone: '79281234567',
    phoneVerified: true,
    displayName: 'Owner',
    name: 'Owner',
    avatarUrl: null,
    photoUrl: null,
    status: UserStatus.ACTIVE,
    blockedAt: null,
    blockReason: null,
    lastLoginAt: null,
    createdAt: new Date('2026-07-01T10:00:00.000Z'),
    updatedAt: new Date('2026-07-01T10:00:00.000Z'),
    deletedAt: null,
    adminProfile: null,
  };
}

function createPromotion(
  type: PromotionType,
  createdAt: string,
  endsAt = '2099-06-20T00:00:00.000Z',
  status = PromotionStatus.ACTIVE,
) {
  const created = new Date(createdAt);
  return {
    id: `promotion-${type}-${created.getTime()}`,
    listingId: 'listing-id',
    userId: ownerUser.userId,
    type,
    costBonus: type === PromotionType.VIP ? 150 : 35,
    startsAt: created,
    endsAt: new Date(endsAt),
    status,
    impressionsCount: 0,
    clicksCount: 0,
    createdAt: created,
    updatedAt: created,
  };
}

function createFreshListings(count: number, options?: { startMinute?: number }) {
  const startMinute = options?.startMinute ?? 59;
  return Array.from({ length: count }, (_, index) =>
    createApprovedListing(
      `listing-${index + 1}`,
      `2026-06-19T10:${(startMinute - index).toString().padStart(2, '0')}:00.000Z`,
    ),
  );
}

function withPromotion<T extends ReturnType<typeof createApprovedListing>>(
  listing: T,
  type: PromotionType,
) {
  return {
    ...listing,
    promotions: [createPromotion(type, '2026-06-19T12:00:00.000Z')],
  };
}

function withPromotionAt<T extends ReturnType<typeof createApprovedListing>>(
  listing: T,
  type: PromotionType,
  createdAt: string,
) {
  return {
    ...listing,
    promotions: [createPromotion(type, createdAt)],
  };
}

function createService(overrides?: {
  findOwnerById?: () => Promise<unknown>;
  create?: (args: Record<string, unknown>) => Promise<unknown>;
  findUnique?: () => Promise<unknown>;
  update?: (args: Record<string, unknown>) => Promise<unknown>;
  findMany?: (args?: Record<string, unknown>) => Promise<unknown>;
  findFavorites?: (args?: Record<string, unknown>) => Promise<unknown>;
  findListingView?: (args?: Record<string, unknown>) => Promise<unknown>;
  createListingView?: (args: Record<string, unknown>) => Promise<unknown>;
  findPromotions?: (args?: Record<string, unknown>) => Promise<unknown>;
  queryRaw?: (strings: TemplateStringsArray, ...values: unknown[]) => Promise<unknown>;
  executeRaw?: (strings: TemplateStringsArray, ...values: unknown[]) => Promise<unknown>;
}) {
  const prisma = {
    user: {
      findUnique:
        overrides?.findOwnerById ??
        (async () => ({
          id: ownerUser.userId,
          email: 'owner@example.com',
          phone: '79281234567',
          displayName: 'Owner',
          name: 'Owner',
          status: 'ACTIVE',
        })),
    },
    listing: {
      create:
        overrides?.create ??
        (async () => ({
          id: 'listing-1',
          ownerId: ownerUser.userId,
          ownerEmail: 'owner@example.com',
          ownerName: 'Owner',
          title: 'Listing',
          description: '',
          category: 'misc',
          subcategory: '',
          price: BigInt(0),
          phone: '79281234567',
          phoneHidden: false,
          city: '',
          address: '',
          locationJson: {},
          delivery: {},
          car: null,
          dealType: null,
          realEstateType: null,
          clothesType: null,
          clothesSize: null,
          oemPartNumber: null,
          oemPartNumberNormalized: null,
          status: ListingStatus.PENDING,
          rejectionReason: '',
          moderationNote: null,
          moderatedBy: null,
          moderatedAt: null,
          publishedAt: null,
          archivedAt: null,
          deletedAt: null,
          viewCount: 0,
          createdAt: new Date(),
          updatedAt: new Date(),
          owner: {
            id: ownerUser.userId,
            email: 'owner@example.com',
            phone: '79281234567',
            phoneVerified: true,
            displayName: 'Owner',
            name: 'Owner',
            avatarUrl: null,
            photoUrl: null,
            status: 'ACTIVE',
            blockedAt: null,
            blockReason: null,
            lastLoginAt: null,
            createdAt: new Date(),
            updatedAt: new Date(),
            deletedAt: null,
            adminProfile: null,
          },
          photos: [],
          promotions: [],
        })),
      findUnique: overrides?.findUnique ?? (async () => null),
      findMany: overrides?.findMany ?? (async () => []),
      update:
        overrides?.update ??
        (async (args: Record<string, unknown>) => ({
          id: 'listing-1',
          ownerId: 'owner-1',
          title: 'Listing',
          description: '',
          category: 'misc',
          subcategory: '',
          price: BigInt(0),
          phone: '',
          phoneHidden: false,
          city: '',
          address: '',
          locationJson: {},
          delivery: {},
          car: null,
          dealType: null,
          realEstateType: null,
          clothesType: null,
          clothesSize: null,
          oemPartNumber: null,
          oemPartNumberNormalized: null,
          status: ListingStatus.ARCHIVED,
          rejectionReason: '',
          moderationNote: null,
          moderatedBy: null,
          moderatedAt: null,
          publishedAt: null,
          archivedAt: new Date(),
          deletedAt: null,
          viewCount: 0,
          createdAt: new Date(),
          updatedAt: new Date(),
          owner: null,
          photos: [],
          promotions: [],
          ...args,
        })),
    },
    listingPhoto: {
      deleteMany: async () => ({}),
      createMany: async () => ({}),
    },
    favorite: {
      findMany: overrides?.findFavorites ?? (async () => []),
    },
    listingView: {
      findFirst: overrides?.findListingView ?? (async () => null),
      create:
        overrides?.createListingView ??
        (async (args: Record<string, unknown>) => ({
          id: 'listing-view-1',
          ...args,
        })),
    },
    promotion: {
      findMany: overrides?.findPromotions ?? (async () => []),
    },
    $transaction: async <T>(handler: (tx: any) => Promise<T>) => handler(prisma),
    ...(overrides?.queryRaw ? { $queryRaw: overrides.queryRaw } : {}),
    ...(overrides?.executeRaw ? { $executeRaw: overrides.executeRaw } : {}),
  };

  return new ListingsService(
    prisma as never,
    {} as never,
    { expirePromotionsByTime: async () => undefined } as never,
  );
}

function createListingViewCounterService(options?: {
  existingViews?: Array<{ listingId: string; viewerUserId: string | null }>;
  ownerId?: string;
  initialViewCount?: number;
}) {
  const listingId = 'listing-1';
  const listing = {
    ...createApprovedListing(listingId, '2026-06-19T10:00:00.000Z'),
    ownerId: options?.ownerId ?? ownerUser.userId,
    viewCount: options?.initialViewCount ?? 0,
  };
  const views = [...(options?.existingViews ?? [])];
  const createdViews: Array<{ listingId: string; viewerUserId: string | null }> = [];
  const advisoryLocks: unknown[][] = [];
  let transactionQueue = Promise.resolve();

  const prisma = {
    listing: {
      findUnique: async () => ({ ...listing }),
      update: async (args: Record<string, any>) => {
        listing.viewCount += Number(args.data?.viewCount?.increment ?? 0);
        return { ...listing };
      },
    },
    listingView: {
      findFirst: async (args: Record<string, any>) => {
        const where = args.where ?? {};
        const found = views.find(
          (view) =>
            view.listingId === where.listingId &&
            view.viewerUserId === where.viewerUserId,
        );
        return found ? { id: `view-${views.indexOf(found) + 1}` } : null;
      },
      create: async (args: Record<string, any>) => {
        const view = {
          listingId: String(args.data.listingId),
          viewerUserId: (args.data.viewerUserId ?? null) as string | null,
        };
        views.push(view);
        createdViews.push(view);
        return { id: `view-${views.length}`, ...view };
      },
    },
    $executeRaw: async (
      strings: TemplateStringsArray,
      ...values: unknown[]
    ) => {
      advisoryLocks.push(values);
      return 1;
    },
    $transaction: async <T>(handler: (tx: any) => Promise<T>) => {
      const run = transactionQueue.then(() => handler(prisma));
      transactionQueue = run.then(
        () => undefined,
        () => undefined,
      );
      return run;
    },
  };

  return {
    service: new ListingsService(prisma as never, {} as never, {} as never),
    listingId,
    get viewCount() {
      return listing.viewCount;
    },
    createdViews,
    advisoryLocks,
  };
}

test('incrementView does not count owner views', async () => {
  const harness = createListingViewCounterService();

  for (let index = 0; index < 10; index += 1) {
    const response = await harness.service.incrementView(
      harness.listingId,
      ownerUser,
    );
    assert.equal(response.view_count, 0);
  }

  assert.equal(harness.viewCount, 0);
  assert.equal(harness.createdViews.length, 0);
  assert.equal(harness.advisoryLocks.length, 0);
});

test('findVipListings returns only active VIP promotions with cursor metadata', async () => {
  const listing = {
    ...createApprovedListing('listing-vip-1', '2026-06-19T10:00:00.000Z'),
    photos: [
      {
        id: 'photo-1',
        listingId: 'listing-vip-1',
        storageBucket: 'local',
        storageKey: 'listings/photo.jpg',
        publicUrl: 'https://example.com/photo.jpg',
        sortOrder: 0,
        sizeBytes: 128,
        mimeType: 'image/jpeg',
        createdAt: new Date('2026-06-19T10:00:00.000Z'),
      },
    ],
    owner: {
      id: ownerUser.userId,
      email: 'owner@example.com',
      phone: '79281234567',
      phoneVerified: true,
      displayName: 'Owner',
      name: 'Owner',
      avatarUrl: null,
      photoUrl: null,
      status: UserStatus.ACTIVE,
      blockedAt: null,
      blockReason: null,
      lastLoginAt: null,
      createdAt: new Date('2026-06-19T10:00:00.000Z'),
      updatedAt: new Date('2026-06-19T10:00:00.000Z'),
      deletedAt: null,
      adminProfile: null,
    },
  };
  const firstPromotion = {
    ...createPromotion(PromotionType.VIP, '2026-06-20T12:00:00.000Z'),
    id: '00000000-0000-0000-0000-000000000002',
    listingId: listing.id,
    listing: {
      ...listing,
      promotions: [
        {
          ...createPromotion(PromotionType.VIP, '2026-06-20T12:00:00.000Z'),
          id: '00000000-0000-0000-0000-000000000002',
          listingId: listing.id,
        },
      ],
    },
  };
  const secondPromotion = {
    ...createPromotion(PromotionType.VIP, '2026-06-20T11:00:00.000Z'),
    id: '00000000-0000-0000-0000-000000000001',
    listingId: 'listing-vip-2',
    listing: {
      ...listing,
      id: 'listing-vip-2',
      promotions: [
        {
          ...createPromotion(PromotionType.VIP, '2026-06-20T11:00:00.000Z'),
          id: '00000000-0000-0000-0000-000000000001',
          listingId: 'listing-vip-2',
        },
      ],
    },
  };
  let capturedArgs: Record<string, any> | undefined;
  const service = createService({
    findPromotions: async (args?: Record<string, unknown>) => {
      capturedArgs = args as Record<string, any>;
      return [firstPromotion, secondPromotion];
    },
  });

  const response = await service.findVipListings({ limit: 1 });

  assert.equal(capturedArgs?.where?.type, PromotionType.VIP);
  assert.equal(capturedArgs?.where?.status, PromotionStatus.ACTIVE);
  assert.equal(capturedArgs?.where?.listing?.status, ListingStatus.APPROVED);
  assert.equal(response.items.length, 1);
  assert.equal(response.items[0].id, 'listing-vip-1');
  assert.equal(response.items[0].promotions.activeVip?.status, 'active');
  assert.equal(response.hasMore, true);
  assert.equal(typeof response.nextCursor, 'string');
});

test('findVipListings applies optional category filter', async () => {
  let capturedArgs: Record<string, any> | undefined;
  const service = createService({
    findPromotions: async (args?: Record<string, unknown>) => {
      capturedArgs = args as Record<string, any>;
      return [];
    },
  });

  const response = await service.findVipListings({
    limit: 20,
    category: 'Авто',
  });

  assert.equal(capturedArgs?.where?.listing?.category, 'Авто');
  assert.equal(response.items.length, 0);
  assert.equal(response.hasMore, false);
});

test('findVipListings keeps unfiltered request backward-compatible', async () => {
  let capturedArgs: Record<string, any> | undefined;
  const service = createService({
    findPromotions: async (args?: Record<string, unknown>) => {
      capturedArgs = args as Record<string, any>;
      return [];
    },
  });

  await service.findVipListings({ limit: 20 });

  assert.equal('category' in capturedArgs?.where?.listing, false);
});

test('findVipListings applies text search inside VIP scope', async () => {
  let capturedArgs: Record<string, any> | undefined;
  const service = createService({
    findPromotions: async (args?: Record<string, unknown>) => {
      capturedArgs = args as Record<string, any>;
      return [];
    },
  });

  await service.findVipListings({ limit: 20, search: 'фара Toyota' });

  assert.equal(capturedArgs?.where?.type, PromotionType.VIP);
  assert.equal(capturedArgs?.where?.listing?.AND?.length, 1);
  assert.deepEqual(
    capturedArgs?.where?.listing?.AND?.[0]?.OR?.[0]?.OR?.[0]?.title,
    { contains: 'фара toyota', mode: 'insensitive' },
  );
});

test('findVipListings applies normalized OEM search with category', async () => {
  let capturedArgs: Record<string, any> | undefined;
  const service = createService({
    findPromotions: async (args?: Record<string, unknown>) => {
      capturedArgs = args as Record<string, any>;
      return [];
    },
  });

  await service.findVipListings({
    limit: 20,
    category: 'Запчасти',
    search: '81150-06C70',
  });

  assert.equal(capturedArgs?.where?.listing?.category, 'Запчасти');
  assert.ok(
    capturedArgs?.where?.listing?.AND?.[0]?.OR?.some(
      (group: Record<string, any>) => group.OR?.some(
        (condition: Record<string, unknown>) =>
          condition.oemPartNumberNormalized === '8115006C70',
      ),
    ),
  );
});

test('findVipListings builds generic transliteration variants without brand whitelist', async () => {
  let capturedArgs: Record<string, any> | undefined;
  const service = createService({
    findPromotions: async (args?: Record<string, unknown>) => {
      capturedArgs = args as Record<string, any>;
      return [];
    },
  });

  await service.findVipListings({
    limit: 20,
    search: 'Глобарис',
  });

  assert.ok(
    capturedArgs?.where?.listing?.AND?.[0]?.OR?.some(
      (group: Record<string, any>) => group.OR?.some(
        (condition: Record<string, any>) =>
          condition.title?.contains === 'globaris',
      ),
    ),
  );
});

test('findVipListings keeps OEM search deterministic without typo variants', async () => {
  let capturedArgs: Record<string, any> | undefined;
  const service = createService({
    findPromotions: async (args?: Record<string, unknown>) => {
      capturedArgs = args as Record<string, any>;
      return [];
    },
  });

  await service.findVipListings({
    limit: 20,
    search: '81150-06C70',
  });

  const serializedSearchWhere = JSON.stringify(capturedArgs?.where?.listing?.AND?.[0]);
  const debug = listingSearchDebugVariants('81150-06C70');

  assert.ok(serializedSearchWhere.includes('8115006C70'));
  assert.deepEqual(
    debug.tokens.flatMap((token) => token.typoFragments),
    [],
  );
  assert.deepEqual(
    debug.tokens.flatMap((token) => token.deletionTypoVariants),
    [],
  );
});

test('findVipListings supports limited typo fragments for ordinary text', async () => {
  let capturedArgs: Record<string, any> | undefined;
  const service = createService({
    findPromotions: async (args?: Record<string, unknown>) => {
      capturedArgs = args as Record<string, any>;
      return [];
    },
  });

  await service.findVipListings({
    limit: 20,
    search: 'Toyta',
  });

  const serializedSearchWhere = JSON.stringify(capturedArgs?.where?.listing?.AND?.[0]);
  assert.ok(serializedSearchWhere.includes('"contains":"toy"'));
  assert.ok(serializedSearchWhere.includes('"contains":"ta"'));
});

test('findVipListings uses shared transliteration for multi-word search', async () => {
  let capturedArgs: Record<string, any> | undefined;
  const service = createService({
    findPromotions: async (args?: Record<string, unknown>) => {
      capturedArgs = args as Record<string, any>;
      return [];
    },
  });

  await service.findVipListings({
    limit: 20,
    search: 'Тойота Камри',
  });

  const serializedSearchWhere = JSON.stringify(capturedArgs?.where?.listing?.AND?.[0]);
  assert.ok(serializedSearchWhere.includes('"contains":"toyota"'));
  assert.ok(serializedSearchWhere.includes('"contains":"camry"'));
});

test('findVipListings keeps typo search inside VIP scope', async () => {
  let capturedArgs: Record<string, any> | undefined;
  const service = createService({
    findPromotions: async (args?: Record<string, unknown>) => {
      capturedArgs = args as Record<string, any>;
      return [];
    },
  });

  await service.findVipListings({
    limit: 20,
    search: 'Samsng',
  });

  assert.equal(capturedArgs?.where?.type, PromotionType.VIP);
  assert.ok(JSON.stringify(capturedArgs?.where?.listing?.AND?.[0]).includes('"contains":"sam"'));
});

test('findVipListings paginates with shared search conditions', async () => {
  let capturedArgs: Record<string, any> | undefined;
  const service = createService({
    findPromotions: async (args?: Record<string, unknown>) => {
      capturedArgs = args as Record<string, any>;
      return [];
    },
  });

  await service.findVipListings({
    limit: 20,
    search: 'Bosch',
    cursor: Buffer.from(
      JSON.stringify({
        createdAt: '2026-08-24T10:00:00.000Z',
        id: 'promotion-1',
      }),
    ).toString('base64url'),
  });

  assert.equal(capturedArgs?.take, 21);
  assert.ok(capturedArgs?.where?.OR);
  assert.ok(JSON.stringify(capturedArgs?.where?.listing?.AND?.[0]).includes('бош'));
});

test('findVipListings applies mixed text and OEM search inside VIP scope', async () => {
  let capturedArgs: Record<string, any> | undefined;
  const service = createService({
    findPromotions: async (args?: Record<string, unknown>) => {
      capturedArgs = args as Record<string, any>;
      return [];
    },
  });

  await service.findVipListings({
    limit: 20,
    search: 'фара 81150-06C70',
  });

  assert.equal(capturedArgs?.where?.type, PromotionType.VIP);
  assert.ok(
    capturedArgs?.where?.listing?.AND?.[0]?.OR?.some(
      (group: Record<string, any>) => group.OR?.some(
        (condition: Record<string, unknown>) =>
          condition.oemPartNumberNormalized === '8115006C70',
      ),
    ),
  );
});

test('findVipListings applies shared characteristics search inside VIP scope', async () => {
  let capturedArgs: Record<string, any> | undefined;
  const service = createService({
    findPromotions: async (args?: Record<string, unknown>) => {
      capturedArgs = args as Record<string, any>;
      return [];
    },
  });

  await service.findVipListings({
    limit: 20,
    category: 'Одежда',
    search: 'XL',
  });

  const serializedSearchWhere = JSON.stringify(capturedArgs?.where?.listing?.AND?.[0]);
  assert.equal(capturedArgs?.where?.type, PromotionType.VIP);
  assert.equal(capturedArgs?.where?.listing?.category, 'Одежда');
  assert.ok(serializedSearchWhere.includes('"clothesSize"'));
  assert.ok(serializedSearchWhere.includes('"path":["vin"]'));
  assert.ok(serializedSearchWhere.includes('"path":["note"]'));
});

test('incrementView counts a regular user once per listing', async () => {
  const harness = createListingViewCounterService();

  const first = await harness.service.incrementView(
    harness.listingId,
    strangerUser,
  );
  assert.equal(first.view_count, 1);

  for (let index = 0; index < 10; index += 1) {
    const response = await harness.service.incrementView(
      harness.listingId,
      strangerUser,
    );
    assert.equal(response.view_count, 1);
  }

  assert.equal(harness.viewCount, 1);
  assert.deepEqual(harness.createdViews, [
    { listingId: harness.listingId, viewerUserId: strangerUser.userId },
  ]);
});

test('incrementView counts another regular user for the same listing', async () => {
  const harness = createListingViewCounterService();

  await harness.service.incrementView(harness.listingId, strangerUser);
  const response = await harness.service.incrementView(
    harness.listingId,
    anotherStrangerUser,
  );

  assert.equal(response.view_count, 2);
  assert.equal(harness.viewCount, 2);
  assert.deepEqual(
    harness.createdViews.map((view) => view.viewerUserId),
    [strangerUser.userId, anotherStrangerUser.userId],
  );
});

test('incrementView counts every admin view of another owner listing', async () => {
  const harness = createListingViewCounterService();

  for (let index = 0; index < 10; index += 1) {
    const response = await harness.service.incrementView(
      harness.listingId,
      adminUser,
    );
    assert.equal(response.view_count, index + 1);
  }

  assert.equal(harness.viewCount, 10);
  assert.equal(harness.createdViews.length, 10);
  assert.equal(harness.advisoryLocks.length, 0);
});

test('incrementView does not count admin views of own listing', async () => {
  const harness = createListingViewCounterService();

  for (let index = 0; index < 10; index += 1) {
    const response = await harness.service.incrementView(
      harness.listingId,
      adminOwnerUser,
    );
    assert.equal(response.view_count, 0);
  }

  assert.equal(harness.viewCount, 0);
  assert.equal(harness.createdViews.length, 0);
});

test('incrementView does not increment when listing_views already has regular user view', async () => {
  const harness = createListingViewCounterService({
    initialViewCount: 7,
    existingViews: [
      { listingId: 'listing-1', viewerUserId: strangerUser.userId },
    ],
  });

  const response = await harness.service.incrementView(
    harness.listingId,
    strangerUser,
  );

  assert.equal(response.view_count, 7);
  assert.equal(harness.viewCount, 7);
  assert.equal(harness.createdViews.length, 0);
  assert.equal(harness.advisoryLocks.length, 1);
});

test('incrementView protects regular user duplicate race with transaction lock', async () => {
  const harness = createListingViewCounterService();

  await Promise.all(
    Array.from({ length: 8 }, () =>
      harness.service.incrementView(harness.listingId, strangerUser),
    ),
  );

  assert.equal(harness.viewCount, 1);
  assert.deepEqual(harness.createdViews, [
    { listingId: harness.listingId, viewerUserId: strangerUser.userId },
  ]);
  assert.equal(harness.advisoryLocks.length, 8);
});

type RawFeedRow = {
  id: string;
  promoted_at: Date | null;
  sort_group: number;
  sort_at: Date;
  published_at: Date | null;
  created_at: Date;
};

type TestApprovedListing = Omit<
  ReturnType<typeof createApprovedListing>,
  'car' | 'dealType' | 'realEstateType' | 'clothesType' | 'clothesSize' | 'promotions'
> & {
  car?: Record<string, unknown> | null;
  dealType?: string | null;
  realEstateType?: string | null;
  clothesType?: string | null;
  clothesSize?: string | null;
  promotions?: unknown[] | null;
};

type SqlLike = {
  strings: readonly string[];
  values: readonly unknown[];
};

const isSqlLike = (value: unknown): value is SqlLike =>
  typeof value === 'object' &&
  value != null &&
  Array.isArray((value as { strings?: unknown }).strings) &&
  Array.isArray((value as { values?: unknown }).values);

function flattenSql(strings: readonly string[], values: readonly unknown[]) {
  let text = '';
  const flattenedValues: unknown[] = [];

  strings.forEach((part, index) => {
    text += part;
    if (index >= values.length) {
      return;
    }

    const value = values[index];
    if (isSqlLike(value)) {
      const nested = flattenSql(value.strings, value.values);
      text += nested.text;
      flattenedValues.push(...nested.values);
      return;
    }

    text += `$${flattenedValues.length + 1}`;
    flattenedValues.push(value);
  });

  return {
    text,
    values: flattenedValues,
  };
}

function findCursorUuidValue(
  strings: readonly string[],
  values: readonly unknown[],
): unknown {
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (
      strings[index]?.includes('"id" <') &&
      strings[index + 1]?.trimStart().startsWith('::uuid')
    ) {
      return value;
    }

    if (isSqlLike(value)) {
      const nested = findCursorUuidValue(value.strings, value.values);
      if (nested != null) {
        return nested;
      }
    }
  }

  return null;
}

function findVipRotationValue(
  strings: readonly string[],
  values: readonly unknown[],
): number {
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (
      typeof value === 'number' &&
      strings[index]?.includes('- (') &&
      strings[index + 1]?.includes('% GREATEST')
    ) {
      return value;
    }

    if (isSqlLike(value)) {
      const nested = findVipRotationValue(value.strings, value.values);
      if (nested !== 0) {
        return nested;
      }
    }
  }

  return 0;
}

function rawRowForListing(
  listing: TestApprovedListing,
  sortGroup: number,
  promotedAt: Date | null = null,
): RawFeedRow {
  const sortAt = promotedAt ?? listing.publishedAt ?? listing.createdAt;
  return {
    id: listing.id,
    promoted_at: promotedAt,
    sort_group: sortGroup,
    sort_at: sortAt,
    published_at: listing.publishedAt,
    created_at: listing.createdAt,
  };
}

function promotionActivatedAt(listing: TestApprovedListing) {
  const now = Date.now();
  let latest: Date | null = null;

  for (const promotion of listing.promotions ?? []) {
    if (
      typeof promotion !== 'object' ||
      promotion == null ||
      !('status' in promotion) ||
      !('type' in promotion) ||
      !('createdAt' in promotion) ||
      !('endsAt' in promotion)
    ) {
      continue;
    }

    const promo = promotion as {
      status?: PromotionStatus;
      type?: PromotionType;
      createdAt?: Date | string | null;
      endsAt?: Date | string | null;
    };
    if (
      promo.status !== PromotionStatus.ACTIVE ||
      (
        promo.type !== PromotionType.VIP &&
        promo.type !== PromotionType.BUMP &&
        promo.type !== PromotionType.TURBO
      )
    ) {
      continue;
    }

    const endsAt = promo.endsAt instanceof Date
      ? promo.endsAt
      : promo.endsAt == null
        ? null
        : new Date(promo.endsAt);
    const createdAt = promo.createdAt instanceof Date
      ? promo.createdAt
      : promo.createdAt == null
        ? null
        : new Date(promo.createdAt);
    if (
      endsAt == null ||
      createdAt == null ||
      Number.isNaN(endsAt.getTime()) ||
      Number.isNaN(createdAt.getTime()) ||
      endsAt.getTime() <= now
    ) {
      continue;
    }

    if (latest == null || createdAt.getTime() > latest.getTime()) {
      latest = createdAt;
    }
  }

  return latest;
}

function compareNaturalListings(a: TestApprovedListing, b: TestApprovedListing) {
  const publishedDiff =
    (b.publishedAt?.getTime() ?? 0) - (a.publishedAt?.getTime() ?? 0);
  if (publishedDiff !== 0) {
    return publishedDiff;
  }

  const createdDiff = b.createdAt.getTime() - a.createdAt.getTime();
  if (createdDiff !== 0) {
    return createdDiff;
  }

  return b.id.localeCompare(a.id);
}

function buildRankedRawRows(
  listings: TestApprovedListing[],
  promotedIds?: Record<string, string>,
) {
  const natural = [...listings].sort(compareNaturalListings);
  const promotedAtById = new Map<string, Date>();
  for (const listing of natural) {
    const promotedAt = promotedIds?.[listing.id] != null
      ? new Date(promotedIds[listing.id]!)
      : promotionActivatedAt(listing);
    if (promotedAt != null && !Number.isNaN(promotedAt.getTime())) {
      promotedAtById.set(listing.id, promotedAt);
    }
  }

  const movedPromoted = natural
    .slice(10)
    .filter((listing) => promotedAtById.has(listing.id))
    .sort((a, b) => {
      const promotedDiff =
        promotedAtById.get(b.id)!.getTime() - promotedAtById.get(a.id)!.getTime();
      if (promotedDiff !== 0) {
        return promotedDiff;
      }

      const createdDiff = b.createdAt.getTime() - a.createdAt.getTime();
      if (createdDiff !== 0) {
        return createdDiff;
      }

      return b.id.localeCompare(a.id);
    });
  const movedIds = new Set(movedPromoted.map((listing) => listing.id));
  const ordered = [
    ...natural.slice(0, 9),
    ...movedPromoted,
    ...natural.slice(9).filter((listing) => !movedIds.has(listing.id)),
  ];

  return ordered.map((listing, index) =>
    rawRowForListing(listing, index + 1, promotedAtById.get(listing.id) ?? null),
  );
}

function buildVipInterleavedRawRows(
  listings: TestApprovedListing[],
  promotedIds?: Record<string, string>,
  vipRotation = 0,
) {
  const natural = [...listings].sort(compareNaturalListings);
  const vipPromotedAtById = new Map<string, Date>();
  for (const listing of natural) {
    const promotedAt = promotedIds?.[listing.id] != null
      ? new Date(promotedIds[listing.id]!)
      : promotionActivatedAt(listing);
    const hasVip = (listing.promotions ?? []).some((promotion) => {
      if (typeof promotion !== 'object' || promotion == null) return false;
      const promo = promotion as { type?: PromotionType; status?: PromotionStatus };
      return promo.type === PromotionType.VIP && promo.status === PromotionStatus.ACTIVE;
    });
    if (hasVip && promotedAt != null && !Number.isNaN(promotedAt.getTime())) {
      vipPromotedAtById.set(listing.id, promotedAt);
    }
  }

  const ordinary = natural.filter((listing) => !vipPromotedAtById.has(listing.id));
  const vipQueue = natural
    .filter((listing) => vipPromotedAtById.has(listing.id))
    .sort((a, b) => {
      const promotedDiff =
        vipPromotedAtById.get(b.id)!.getTime() - vipPromotedAtById.get(a.id)!.getTime();
      if (promotedDiff !== 0) {
        return promotedDiff;
      }

      const createdDiff = b.createdAt.getTime() - a.createdAt.getTime();
      if (createdDiff !== 0) {
        return createdDiff;
      }

      return b.id.localeCompare(a.id);
    });
  const rotatedVipQueue = vipQueue.length === 0
    ? vipQueue
    : [
        ...vipQueue.slice(vipRotation % vipQueue.length),
        ...vipQueue.slice(0, vipRotation % vipQueue.length),
      ];
  const headCount = Math.min(ordinary.length, 10);
  const rows: RawFeedRow[] = [];

  ordinary.slice(0, headCount).forEach((listing, index) => {
    rows.push(rawRowForListing(listing, index + 1));
  });
  rotatedVipQueue.forEach((listing, index) => {
    rows.push(
      rawRowForListing(
        listing,
        headCount + 1 + index * 3,
        vipPromotedAtById.get(listing.id) ?? null,
      ),
    );
  });
  ordinary.slice(headCount).forEach((listing, index) => {
    const ordinaryTailRank = index + 1;
    rows.push(
      rawRowForListing(
        listing,
        headCount + ordinaryTailRank + Math.ceil(ordinaryTailRank / 2),
      ),
    );
  });

  return rows.sort((a, b) => {
    const groupDiff = a.sort_group - b.sort_group;
    if (groupDiff !== 0) return groupDiff;
    const sortAtDiff = b.sort_at.getTime() - a.sort_at.getTime();
    if (sortAtDiff !== 0) return sortAtDiff;
    const createdDiff = b.created_at.getTime() - a.created_at.getTime();
    if (createdDiff !== 0) return createdDiff;
    return b.id.localeCompare(a.id);
  });
}

function uuidFromNumber(value: number) {
  return `00000000-0000-4000-8000-${value.toString().padStart(12, '0')}`;
}

function compactTestSearchText(value: string) {
  return value
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, '');
}

function editDistanceAtMostOne(left: string, right: string) {
  if (Math.abs(left.length - right.length) > 1) return false;
  let leftIndex = 0;
  let rightIndex = 0;
  let edits = 0;

  while (leftIndex < left.length && rightIndex < right.length) {
    if (left[leftIndex] === right[rightIndex]) {
      leftIndex += 1;
      rightIndex += 1;
      continue;
    }

    edits += 1;
    if (edits > 1) return false;

    if (left.length > right.length) {
      leftIndex += 1;
    } else if (right.length > left.length) {
      rightIndex += 1;
    } else {
      leftIndex += 1;
      rightIndex += 1;
    }
  }

  return edits + (left.length - leftIndex) + (right.length - rightIndex) <= 1;
}

function listingMatchesRawSearch(
  listing: TestApprovedListing | undefined,
  flattenedValues: unknown[],
) {
  if (listing == null) return false;

  const searchableText = [
    listing.title,
    listing.description,
    listing.category,
    listing.subcategory,
    listing.city,
    listing.address,
    listing.ownerName,
    listing.dealType,
    listing.realEstateType,
    listing.clothesType,
    listing.clothesSize,
    ...Object.values((listing.car ?? {}) as Record<string, unknown>),
  ].join(' ').toLowerCase();
  const searchableCompact = compactTestSearchText(searchableText);
  const searchableWords = searchableText
    .split(/[^\p{L}\p{N}]+/u)
    .map(compactTestSearchText)
    .filter(Boolean);
  const likeSearches = flattenedValues
    .filter((value): value is string =>
      typeof value === 'string' && value.startsWith('%') && value.endsWith('%'),
    )
    .map((value) => value.slice(1, -1).toLowerCase());
  const fuzzySearches = flattenedValues
    .filter((value): value is string =>
      typeof value === 'string' &&
      !value.startsWith('%') &&
      /^[\p{L}]{5,}$/u.test(value),
    )
    .map(compactTestSearchText);
  const normalizedSearches = new Set(
    flattenedValues
      .filter((value): value is string =>
        typeof value === 'string' &&
        !value.startsWith('%') &&
        /\d/.test(value) &&
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value),
      )
      .map((value) => normalizeOemPartNumber(value))
      .filter((value): value is string => value != null),
  );
  const exactCodeSearch = [...normalizedSearches].sort(
    (left, right) => right.length - left.length,
  )[0];

  if (exactCodeSearch != null) {
    const embeddedCodeSearches = [...normalizedSearches].filter(
      (candidate) => candidate.length >= 6 || normalizedSearches.size === 1,
    );
    return (
      embeddedCodeSearches.some((candidate) =>
        searchableCompact.includes(candidate.toLowerCase()),
      ) ||
      (
        listing.oemPartNumberNormalized != null &&
        normalizedSearches.has(listing.oemPartNumberNormalized)
      )
    );
  }

  return (
    likeSearches.some((search) =>
      searchableText.includes(search) ||
      searchableCompact.includes(compactTestSearchText(search)),
    ) ||
    fuzzySearches.some((search) =>
      searchableWords.some((word) => editDistanceAtMostOne(word, search)),
    )
  );
}

function createRawFeedHarness(
  orderedListings: TestApprovedListing[],
  options?: {
    promotedIds?: Record<string, string>;
  },
) {
  const listingsById = new Map(
    orderedListings.map((listing) => [listing.id, listing]),
  );
  const orderedRows = buildRankedRawRows(orderedListings, options?.promotedIds);
  const rawCalls: Array<{ text: string; values: unknown[]; cursorId: unknown }> = [];

  const service = createService({
    queryRaw: async (strings: TemplateStringsArray, ...values: unknown[]) => {
      const flattened = flattenSql(strings, values);
      const cursorId = findCursorUuidValue(strings, values);
      rawCalls.push({ ...flattened, cursorId });

      const isVipInterleaved = flattened.text.includes('vip_promoted_at');
      const vipRotation = isVipInterleaved
        ? findVipRotationValue(strings, values)
        : 0;
      let filteredRows = isVipInterleaved
        ? buildVipInterleavedRawRows(
            orderedListings,
            options?.promotedIds,
            vipRotation,
          )
        : orderedRows;
      if (flattened.values.includes('auto')) {
        filteredRows = filteredRows.filter(
          (row) => listingsById.get(row.id)?.category === 'auto',
        );
      }
      const hasSearch = flattened.values.some((value) =>
        typeof value === 'string' &&
        value.startsWith('%'),
      );
      if (hasSearch) {
        filteredRows = filteredRows.filter((row) => {
          const listing = listingsById.get(row.id);
          return listingMatchesRawSearch(listing, flattened.values);
        });
      }

      const take = Number(values[values.length - 1]);
      const startIndex =
        typeof cursorId === 'string'
          ? filteredRows.findIndex((row) => row.id === cursorId) + 1
          : 0;
      return filteredRows.slice(startIndex, startIndex + take);
    },
    findMany: async (args?: Record<string, unknown>) => {
      const ids = ((args?.where as { id?: { in?: string[] } } | undefined)?.id?.in) ?? [];
      return ids
        .map((id) => listingsById.get(id))
        .filter((listing): listing is TestApprovedListing => listing != null);
    },
  });

  return {
    service,
    rawCalls,
  };
}

test('owner cannot change listing status via generic update endpoint', async () => {
  const service = createService({
    findUnique: async () => ({
      id: 'listing-1',
      ownerId: ownerUser.userId,
      status: ListingStatus.APPROVED,
    }),
  });

  await assert.rejects(
    service.update('listing-1', ownerUser, { status: 'sold' }),
    ForbiddenException,
  );
});

test('owner edit of approved listing sends it back to moderation', async () => {
  const listing = createApprovedListing(
    'listing-1',
    '2026-07-01T10:00:00.000Z',
  );
  let updateArgs: Record<string, unknown> | undefined;
  let revisionCreateArgs: Record<string, unknown> | undefined;
  let savedListing = {
    ...listing,
    price: BigInt(100000),
    city: 'Грозный',
    oemPartNumber: '81150-06C70',
    oemPartNumberNormalized: '8115006C70',
    owner: listingOwner(),
    photos: [listingPhoto()],
  };
  const prisma = {
    listing: {
      findUnique: async () => savedListing,
      update: async (args: Record<string, unknown>) => {
        updateArgs = args;
        savedListing = {
          ...savedListing,
          ...Object.fromEntries(
            Object.entries(args.data as Record<string, unknown>).filter(
              ([, value]) => value !== undefined,
            ),
          ),
          updatedAt: new Date(),
        };
        return savedListing;
      },
      findUniqueOrThrow: async () => savedListing,
    },
    listingPhoto: {
      deleteMany: async () => ({}),
      createMany: async () => ({}),
    },
    listingModerationRevision: {
      findFirst: async () => null,
      create: async (args: Record<string, unknown>) => {
        revisionCreateArgs = args;
        return { id: 'revision-1' };
      },
    },
    $transaction: async <T>(handler: (tx: unknown) => Promise<T>) =>
      handler(prisma),
  };
  const service = new ListingsService(
    prisma as never,
    {} as never,
    {} as never,
  );

  const response = await service.update('listing-1', ownerUser, {
    title: 'Updated listing',
    status: 'approved',
  });

  assert.equal(
    (updateArgs?.data as Record<string, unknown>).status,
    ListingStatus.PENDING,
  );
  const snapshot = (revisionCreateArgs?.data as Record<string, unknown>)
    ?.snapshot as Record<string, unknown>;
  assert.equal((revisionCreateArgs?.data as Record<string, unknown>)?.listingId, 'listing-1');
  assert.equal(snapshot['price'], '100000');
  assert.equal(snapshot['city'], 'Грозный');
  assert.equal(snapshot['oem_part_number'], '81150-06C70');
  assert.deepEqual(snapshot['photos'], [
    {
      id: 'photo-1',
      storage_key: 'listings/listing-1/photo-1.jpg',
      url: 'https://example.com/photo-1.jpg',
      sort_order: 0,
    },
  ]);
  assert.equal(response.listing.status, 'pending');
});

test('update can add, change and clear OEM for auto parts listings', async () => {
  const listing = {
    ...createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z', 'Запчасти'),
    status: ListingStatus.PENDING,
    subcategory: 'Оптика',
    city: 'Грозный',
    photos: [listingPhoto()],
    owner: listingOwner(),
  };
  const updateData: Array<Record<string, unknown>> = [];
  let savedListing: Record<string, unknown> = {
    ...listing,
    oemPartNumber: null,
    oemPartNumberNormalized: null,
  };
  const prisma = {
    listing: {
      findUnique: async () => listing,
      update: async (args: Record<string, any>) => {
        updateData.push(args.data);
        savedListing = {
          ...savedListing,
          ...Object.fromEntries(
            Object.entries(args.data ?? {}).filter(([, value]) => value !== undefined),
          ),
          updatedAt: new Date(),
        };
        return savedListing;
      },
      findUniqueOrThrow: async () => savedListing,
    },
    listingPhoto: {
      deleteMany: async () => ({}),
      createMany: async () => ({}),
    },
    listingModerationRevision: {
      findFirst: async () => null,
      create: async () => ({ id: 'revision-1' }),
    },
    $transaction: async <T>(handler: (tx: unknown) => Promise<T>) =>
      handler(prisma),
  };
  const service = new ListingsService(prisma as never, {} as never, {} as never);

  await service.update('listing-1', ownerUser, {
    category: 'Запчасти',
    oem_part_number: '81150-06c70',
  });
  await service.update('listing-1', ownerUser, {
    category: 'Запчасти',
    oem_part_number: '81150 06C71',
  });
  await service.update('listing-1', ownerUser, {
    category: 'Запчасти',
    oem_part_number: '',
  });

  assert.equal(updateData[0]?.oemPartNumber, '81150-06c70');
  assert.equal(updateData[0]?.oemPartNumberNormalized, '8115006C70');
  assert.equal(updateData[1]?.oemPartNumber, '81150 06C71');
  assert.equal(updateData[1]?.oemPartNumberNormalized, '8115006C71');
  assert.equal(updateData[2]?.oemPartNumber, null);
  assert.equal(updateData[2]?.oemPartNumberNormalized, null);
});

test('mark sold works through explicit archive endpoint', async () => {
  let updateArgs: Record<string, unknown> | undefined;
  const service = createService({
    findUnique: async () => ({
      id: 'listing-1',
      ownerId: ownerUser.userId,
      status: ListingStatus.APPROVED,
    }),
    update: async (args) => {
      updateArgs = args;
      return {
        id: 'listing-1',
        ownerId: ownerUser.userId,
        title: 'Listing',
        description: '',
        category: 'misc',
        subcategory: '',
        price: BigInt(0),
        phone: '',
        phoneHidden: false,
        city: '',
        address: '',
        locationJson: {},
        delivery: {},
        car: null,
        status: ListingStatus.SOLD,
        rejectionReason: 'Продано владельцем.',
        moderationNote: null,
        moderatedBy: null,
        moderatedAt: null,
        publishedAt: null,
        archivedAt: new Date(),
        deletedAt: null,
        viewCount: 0,
        createdAt: new Date(),
        updatedAt: new Date(),
        owner: null,
        photos: [],
        promotions: [],
      };
    },
  });

  const response = await service.archive('listing-1', ownerUser, {
    status: 'sold',
    note: 'Продано владельцем.',
  });

  assert.equal(response.status_after_archive, 'sold');
  assert.equal(
    (updateArgs?.data as Record<string, unknown>).status,
    ListingStatus.SOLD,
  );
});

test('archive without sale works through explicit archive endpoint', async () => {
  let updateArgs: Record<string, unknown> | undefined;
  const service = createService({
    findUnique: async () => ({
      id: 'listing-1',
      ownerId: ownerUser.userId,
      status: ListingStatus.APPROVED,
    }),
    update: async (args) => {
      updateArgs = args;
      return {
        id: 'listing-1',
        ownerId: ownerUser.userId,
        title: 'Listing',
        description: '',
        category: 'misc',
        subcategory: '',
        price: BigInt(0),
        phone: '',
        phoneHidden: false,
        city: '',
        address: '',
        locationJson: {},
        delivery: {},
        car: null,
        status: ListingStatus.ARCHIVED,
        rejectionReason: 'Снято владельцем с публикации.',
        moderationNote: null,
        moderatedBy: null,
        moderatedAt: null,
        publishedAt: null,
        archivedAt: new Date(),
        deletedAt: null,
        viewCount: 0,
        createdAt: new Date(),
        updatedAt: new Date(),
        owner: null,
        photos: [],
        promotions: [],
      };
    },
  });

  const response = await service.archive('listing-1', ownerUser, {
    status: 'archived',
  });

  assert.equal(response.status_after_archive, 'archived');
  assert.equal(
    (updateArgs?.data as Record<string, unknown>).status,
    ListingStatus.ARCHIVED,
  );
});

test('non-owner cannot archive listing through explicit endpoint', async () => {
  const service = createService({
    findUnique: async () => ({
      id: 'listing-1',
      ownerId: ownerUser.userId,
      status: ListingStatus.APPROVED,
    }),
  });

  await assert.rejects(
    service.archive('listing-1', strangerUser, { status: 'sold' }),
    ForbiddenException,
  );
});

test('create uses owner phone when dto phone is empty', async () => {
  let createArgs: Record<string, unknown> | undefined;
  const service = createService({
    create: async (args) => {
      createArgs = args;
      return {
        id: 'listing-1',
        ownerId: ownerUser.userId,
        ownerEmail: 'owner@example.com',
        ownerName: 'Owner',
        title: 'Listing',
        description: '',
        category: 'misc',
        subcategory: '',
        price: BigInt(0),
        phone: '79281234567',
        phoneHidden: false,
        city: '',
        address: '',
        locationJson: {},
        delivery: {},
        car: null,
        dealType: null,
        realEstateType: null,
        clothesType: null,
        clothesSize: null,
        oemPartNumber: null,
        oemPartNumberNormalized: null,
        status: ListingStatus.PENDING,
        rejectionReason: '',
        moderationNote: null,
        moderatedBy: null,
        moderatedAt: null,
        publishedAt: null,
        archivedAt: null,
        deletedAt: null,
        viewCount: 0,
        createdAt: new Date(),
        updatedAt: new Date(),
        owner: {
          id: ownerUser.userId,
          email: 'owner@example.com',
          phone: '79281234567',
          phoneVerified: true,
          displayName: 'Owner',
          name: 'Owner',
          avatarUrl: null,
          photoUrl: null,
          status: 'ACTIVE',
          blockedAt: null,
          blockReason: null,
          lastLoginAt: null,
          createdAt: new Date(),
          updatedAt: new Date(),
          deletedAt: null,
          adminProfile: null,
        },
        photos: [],
        promotions: [],
      };
    },
  });

  const response = await service.create(ownerUser, {
    title: 'Listing',
    description: 'Desc',
    category: 'misc',
    subcategory: '',
    price: 1000,
    phone: '',
    phone_hidden: false,
    city: 'Grozny',
  });

  assert.equal((createArgs?.data as Record<string, unknown>).phone, '79281234567');
  assert.equal(response.listing.phone, '79281234567');
});

test('create stores optional clothes size only for clothes listings', async () => {
  let createData: Record<string, unknown> | undefined;
  const service = createService({
    create: async (args) => {
      createData = args.data as Record<string, unknown>;
      return {
        ...createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z', 'Одежда'),
        status: ListingStatus.PENDING,
        clothesType: 'Верхняя одежда',
        clothesSize: createData.clothesSize,
      };
    },
  });

  const response = await service.create(ownerUser, {
    title: 'Куртка',
    description: 'Почти новая',
    category: 'Одежда',
    subcategory: 'Женская одежда',
    price: 1000,
    clothes_type: 'Верхняя одежда',
    clothes_size: 'XL',
  });

  assert.equal(createData?.clothesSize, 'XL');
  assert.equal(response.listing.clothes_size, 'XL');
});

test('create ignores clothes size for other categories', async () => {
  let createData: Record<string, unknown> | undefined;
  const service = createService({
    create: async (args) => {
      createData = args.data as Record<string, unknown>;
      return {
        ...createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z', 'misc'),
        status: ListingStatus.PENDING,
        clothesSize: createData.clothesSize,
      };
    },
  });

  await service.create(ownerUser, {
    title: 'Предмет',
    description: 'Описание',
    category: 'misc',
    subcategory: '',
    price: 1000,
    clothes_size: 'XL',
  });

  assert.equal(createData?.clothesSize, null);
});

test('create accepts auto parts without optional OEM number', async () => {
  let createData: Record<string, unknown> | undefined;
  const service = createService({
    create: async (args) => {
      createData = args.data as Record<string, unknown>;
      return {
        ...createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z', 'Запчасти'),
        status: ListingStatus.PENDING,
        oemPartNumber: createData.oemPartNumber,
        oemPartNumberNormalized: createData.oemPartNumberNormalized,
      };
    },
  });

  const response = await service.create(ownerUser, {
    title: 'Фара',
    description: 'Передняя',
    category: 'Запчасти',
    subcategory: 'Оптика',
    price: 1000,
  });

  assert.equal(createData?.oemPartNumber, null);
  assert.equal(createData?.oemPartNumberNormalized, null);
  assert.equal(response.listing.oem_part_number, null);
});

test('create stores and normalizes optional OEM only for auto parts', async () => {
  let createData: Record<string, unknown> | undefined;
  const service = createService({
    create: async (args) => {
      createData = args.data as Record<string, unknown>;
      return {
        ...createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z', 'Запчасти'),
        status: ListingStatus.PENDING,
        oemPartNumber: createData.oemPartNumber,
        oemPartNumberNormalized: createData.oemPartNumberNormalized,
      };
    },
  });

  const response = await service.create(ownerUser, {
    title: 'Фара',
    description: 'Передняя',
    category: 'Запчасти',
    subcategory: 'Оптика',
    price: 1000,
    oem_part_number: ' 81150-06c70 ',
  });

  assert.equal(createData?.oemPartNumber, '81150-06c70');
  assert.equal(createData?.oemPartNumberNormalized, '8115006C70');
  assert.equal(response.listing.oem_part_number, '81150-06c70');
});

test('create ignores OEM for non-parts categories', async () => {
  let createData: Record<string, unknown> | undefined;
  const service = createService({
    create: async (args) => {
      createData = args.data as Record<string, unknown>;
      return {
        ...createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z', 'Авто'),
        status: ListingStatus.PENDING,
        oemPartNumber: createData.oemPartNumber,
        oemPartNumberNormalized: createData.oemPartNumberNormalized,
      };
    },
  });

  await service.create(ownerUser, {
    title: 'Camry',
    description: 'Описание',
    category: 'Авто',
    subcategory: 'Легковые автомобили',
    price: 1000,
    oem_part_number: '81150-06C70',
  });

  assert.equal(createData?.oemPartNumber, null);
  assert.equal(createData?.oemPartNumberNormalized, null);
});

test('public feed is sorted by publishedAt desc, then createdAt desc, then id desc', async () => {
  const service = createService({
    findMany: async () => [
      {
        id: 'listing-c',
        ownerId: ownerUser.userId,
        ownerEmail: 'owner@example.com',
        ownerName: 'Owner',
        title: 'C',
        description: '',
        category: 'misc',
        subcategory: '',
        price: BigInt(0),
        phone: '',
        phoneHidden: false,
        city: '',
        address: '',
        locationJson: {},
        delivery: {},
        car: null,
        status: ListingStatus.APPROVED,
        rejectionReason: '',
        moderationNote: null,
        moderatedBy: null,
        moderatedAt: null,
        publishedAt: new Date('2026-06-19T10:00:10.000Z'),
        archivedAt: null,
        deletedAt: null,
        viewCount: 0,
        createdAt: new Date('2026-06-19T08:00:00.000Z'),
        updatedAt: new Date('2026-06-19T08:30:00.000Z'),
        owner: null,
        photos: [],
        promotions: [],
      },
      {
        id: 'listing-a',
        ownerId: ownerUser.userId,
        ownerEmail: 'owner@example.com',
        ownerName: 'Owner',
        title: 'A',
        description: '',
        category: 'misc',
        subcategory: '',
        price: BigInt(0),
        phone: '',
        phoneHidden: false,
        city: '',
        address: '',
        locationJson: {},
        delivery: {},
        car: null,
        status: ListingStatus.APPROVED,
        rejectionReason: '',
        moderationNote: null,
        moderatedBy: null,
        moderatedAt: null,
        publishedAt: new Date('2026-06-19T10:00:05.000Z'),
        archivedAt: null,
        deletedAt: null,
        viewCount: 999,
        createdAt: new Date('2026-06-19T09:00:00.000Z'),
        updatedAt: new Date('2026-06-19T12:00:00.000Z'),
        owner: null,
        photos: [],
        promotions: [],
      },
      {
        id: 'listing-b',
        ownerId: ownerUser.userId,
        ownerEmail: 'owner@example.com',
        ownerName: 'Owner',
        title: 'B',
        description: '',
        category: 'misc',
        subcategory: '',
        price: BigInt(0),
        phone: '',
        phoneHidden: false,
        city: '',
        address: '',
        locationJson: {},
        delivery: {},
        car: null,
        status: ListingStatus.APPROVED,
        rejectionReason: '',
        moderationNote: null,
        moderatedBy: null,
        moderatedAt: null,
        publishedAt: null,
        archivedAt: null,
        deletedAt: null,
        viewCount: 0,
        createdAt: new Date('2026-06-19T10:00:10.000Z'),
        updatedAt: new Date('2026-06-19T12:00:30.000Z'),
        owner: null,
        photos: [],
        promotions: [],
      },
    ],
  });

  const response = await service.findAll();

  assert.deepEqual(
    response.items.map((item: { id: string }) => item.id),
    ['listing-c', 'listing-a', 'listing-b'],
  );
});

test('public feed filters out blocked and deleted owners at query level', async () => {
  let findManyArgs: Record<string, unknown> | undefined;
  const service = createService({
    findMany: async (args?: Record<string, unknown>) => {
      findManyArgs = args;
      return [];
    },
  });

  await service.findAll();

  assert.deepEqual(findManyArgs?.where, {
    deletedAt: null,
    status: ListingStatus.APPROVED,
    photos: {
      some: {},
    },
    owner: {
      deletedAt: null,
      status: UserStatus.ACTIVE,
    },
  });
});

test('my listings include favorites count without exposing favorite users', async () => {
  const service = createService({
    findMany: async () => [
      createApprovedListing('listing-1', '2026-06-19T10:00:05.000Z'),
      createApprovedListing('listing-2', '2026-06-19T10:00:10.000Z'),
    ],
    findFavorites: async () => [
      { listingId: 'listing-1' },
      { listingId: 'listing-1' },
      { listingId: 'listing-2' },
    ],
  });

  const response = await service.findMy(ownerUser);

  assert.equal(response.items[0]?.favorites_count, 1);
  assert.equal(response.items[1]?.favorites_count, 2);
  assert.equal('user_id' in response.items[0]!, false);
  assert.equal('favorite_users' in response.items[0]!, false);
});

test('public listing with blocked owner is hidden from strangers', async () => {
  const service = createService({
    findUnique: async () => ({
      id: 'listing-1',
      ownerId: ownerUser.userId,
      status: ListingStatus.APPROVED,
      deletedAt: null,
      archivedAt: null,
      owner: {
        id: ownerUser.userId,
        status: UserStatus.BLOCKED,
        deletedAt: null,
      },
      photos: [],
      promotions: [],
    }),
  });

  await assert.rejects(
    service.findOne('listing-1', strangerUser),
    NotFoundException,
  );
});

test('public feed fallback keeps later createdAt and larger id first when publishedAt matches', async () => {
  const sharedPublishedAt = new Date('2026-06-19T10:00:10.000Z');
  const sharedCreatedAt = new Date('2026-06-19T09:00:00.000Z');
  const service = createService({
    findMany: async () => [
      {
        id: 'listing-b',
        ownerId: ownerUser.userId,
        ownerEmail: 'owner@example.com',
        ownerName: 'Owner',
        title: 'B',
        description: '',
        category: 'misc',
        subcategory: '',
        price: BigInt(0),
        phone: '',
        phoneHidden: false,
        city: '',
        address: '',
        locationJson: {},
        delivery: {},
        car: null,
        status: ListingStatus.APPROVED,
        rejectionReason: '',
        moderationNote: null,
        moderatedBy: null,
        moderatedAt: null,
        publishedAt: sharedPublishedAt,
        archivedAt: null,
        deletedAt: null,
        viewCount: 0,
        createdAt: sharedCreatedAt,
        updatedAt: new Date('2026-06-19T08:00:00.000Z'),
        owner: null,
        photos: [],
        promotions: [],
      },
      {
        id: 'listing-a',
        ownerId: ownerUser.userId,
        ownerEmail: 'owner@example.com',
        ownerName: 'Owner',
        title: 'A',
        description: '',
        category: 'misc',
        subcategory: '',
        price: BigInt(0),
        phone: '',
        phoneHidden: false,
        city: '',
        address: '',
        locationJson: {},
        delivery: {},
        car: null,
        status: ListingStatus.APPROVED,
        rejectionReason: '',
        moderationNote: null,
        moderatedBy: null,
        moderatedAt: null,
        publishedAt: sharedPublishedAt,
        archivedAt: null,
        deletedAt: null,
        viewCount: 0,
        createdAt: sharedCreatedAt,
        updatedAt: new Date('2026-06-19T12:00:00.000Z'),
        owner: null,
        photos: [],
        promotions: [],
      },
    ],
  });

  const response = await service.findAll();

  assert.deepEqual(
    response.items.map((item: { id: string }) => item.id),
    ['listing-b', 'listing-a'],
  );
});

test('public feed does not crash when listing promotions are missing', async () => {
  const service = createService({
    findMany: async () => [
      {
        id: 'listing-a',
        ownerId: ownerUser.userId,
        ownerEmail: 'owner@example.com',
        ownerName: 'Owner',
        title: 'A',
        description: '',
        category: 'misc',
        subcategory: '',
        price: BigInt(0),
        phone: '',
        phoneHidden: false,
        city: '',
        address: '',
        locationJson: {},
        delivery: {},
        car: null,
        status: ListingStatus.APPROVED,
        rejectionReason: '',
        moderationNote: null,
        moderatedBy: null,
        moderatedAt: null,
        publishedAt: new Date('2026-06-19T10:00:10.000Z'),
        archivedAt: null,
        deletedAt: null,
        viewCount: 0,
        createdAt: new Date('2026-06-19T09:00:00.000Z'),
        updatedAt: new Date('2026-06-19T12:00:00.000Z'),
        owner: null,
        photos: [],
      },
      {
        id: 'listing-b',
        ownerId: ownerUser.userId,
        ownerEmail: 'owner@example.com',
        ownerName: 'Owner',
        title: 'B',
        description: '',
        category: 'misc',
        subcategory: '',
        price: BigInt(0),
        phone: '',
        phoneHidden: false,
        city: '',
        address: '',
        locationJson: {},
        delivery: {},
        car: null,
        status: ListingStatus.APPROVED,
        rejectionReason: '',
        moderationNote: null,
        moderatedBy: null,
        moderatedAt: null,
        publishedAt: null,
        archivedAt: null,
        deletedAt: null,
        viewCount: 0,
        createdAt: new Date('2026-06-19T08:00:00.000Z'),
        updatedAt: new Date('2026-06-19T08:30:00.000Z'),
        owner: null,
        photos: [],
        promotions: null,
      },
    ],
  });

  const response = await service.findAll();

  assert.equal(response.items.length, 2);
  assert.deepEqual(
    response.items.map((item: { id: string }) => item.id),
    ['listing-a', 'listing-b'],
  );
});

test('listing at position 1 with VIP keeps position 1', async () => {
  const listings = createFreshListings(12);
  const service = createService({
    findMany: async () => [withPromotion(listings[0]!, PromotionType.VIP), ...listings.slice(1)],
  });

  const response = await service.findAll({ limit: 12 });

  assert.equal(response.items[0].id, 'listing-1');
});

test('listing at position 5 with VIP keeps position 5', async () => {
  const listings = createFreshListings(12);
  const service = createService({
    findMany: async () => [
      ...listings.slice(0, 4),
      withPromotion(listings[4]!, PromotionType.VIP),
      ...listings.slice(5),
    ],
  });

  const response = await service.findAll({ limit: 12 });

  assert.equal(response.items[4].id, 'listing-5');
});

test('listing at position 1 with BUMP keeps position 1', async () => {
  const listings = createFreshListings(12);
  const service = createService({
    findMany: async () => [withPromotion(listings[0]!, PromotionType.BUMP), ...listings.slice(1)],
  });

  const response = await service.findAll({ limit: 12 });

  assert.equal(response.items[0].id, 'listing-1');
});

test('listing at position 5 with BUMP keeps position 5', async () => {
  const listings = createFreshListings(12);
  const service = createService({
    findMany: async () => [
      ...listings.slice(0, 4),
      withPromotion(listings[4]!, PromotionType.BUMP),
      ...listings.slice(5),
    ],
  });

  const response = await service.findAll({ limit: 12 });

  assert.equal(response.items[4].id, 'listing-5');
});

test('old listing at position 50 with VIP is raised exactly to position 10', async () => {
  const listings = createFreshListings(55);
  const service = createService({
    findMany: async () => [
      ...listings.slice(0, 49),
      withPromotion(listings[49]!, PromotionType.VIP),
      ...listings.slice(50),
    ],
  });

  const response = await service.findAll({ limit: 55 });

  assert.equal(response.items[9].id, 'listing-50');
  assert.notEqual(response.items[8].id, 'listing-50');
});

test('old listing at position 50 with BUMP is raised exactly to position 10', async () => {
  const listings = createFreshListings(55);
  const service = createService({
    findMany: async () => [
      ...listings.slice(0, 49),
      withPromotion(listings[49]!, PromotionType.BUMP),
      ...listings.slice(50),
    ],
  });

  const response = await service.findAll({ limit: 55 });

  assert.equal(response.items[9].id, 'listing-50');
  assert.notEqual(response.items[8].id, 'listing-50');
});

test('new regular listings move promoted listing from position 1 down to 10', async () => {
  const promoted = withPromotion(
    createApprovedListing('listing-promoted', '2026-06-19T10:00:00.000Z'),
    PromotionType.VIP,
  );
  const newer = Array.from({ length: 9 }, (_, index) =>
    createApprovedListing(
      `listing-new-${index + 1}`,
      `2026-06-19T10:${(59 - index).toString().padStart(2, '0')}:00.000Z`,
    ),
  );
  const service = createService({
    findMany: async () => [...newer, promoted],
  });

  const response = await service.findAll({ limit: 10 });

  assert.equal(response.items[9].id, 'listing-promoted');
});

test('regular listings do not push active promoted listing below position 10', async () => {
  const promoted = withPromotion(
    createApprovedListing('listing-promoted', '2026-06-19T09:00:00.000Z'),
    PromotionType.BUMP,
  );
  const newer = createFreshListings(20);
  const service = createService({
    findMany: async () => [...newer, promoted],
  });

  const response = await service.findAll({ limit: 21 });

  assert.equal(response.items[9].id, 'listing-promoted');
});

test('expired promotion returns old listing to natural freshness position', async () => {
  const listings = createFreshListings(55);
  const expired = {
    ...listings[49]!,
    promotions: [
      createPromotion(
        PromotionType.VIP,
        '2026-06-19T12:00:00.000Z',
        '2026-06-19T12:30:00.000Z',
      ),
    ],
  };
  const service = createService({
    findMany: async () => [
      ...listings.slice(0, 49),
      expired,
      ...listings.slice(50),
    ],
  });

  const response = await service.findAll({ limit: 55 });

  assert.equal(response.items[49].id, 'listing-50');
});

test('simultaneous promotions stay deterministic without duplicates or losses', async () => {
  const listings = createFreshListings(15);
  const service = createService({
    findMany: async () => [
      ...listings.slice(0, 11),
      withPromotion(listings[11]!, PromotionType.VIP),
      withPromotion(listings[12]!, PromotionType.BUMP),
      ...listings.slice(13),
    ],
  });

  const response = await service.findAll({ limit: 15 });
  const ids = response.items.map((item: { id: string }) => item.id);

  assert.deepEqual(ids.slice(0, 9), listings.slice(0, 9).map((listing) => listing.id));
  assert.deepEqual(ids.slice(9, 11), ['listing-12', 'listing-13']);
  assert.equal(new Set(ids).size, 15);
  assert.deepEqual(ids.sort(), listings.map((listing) => listing.id).sort());
});

test('expired paid promotions do not affect public feed order', async () => {
  const service = createService({
    findMany: async () => [
      createApprovedListing('listing-fresh', '2026-06-19T10:10:00.000Z'),
      {
        ...createApprovedListing('listing-expired', '2026-06-19T09:10:00.000Z'),
        promotions: [
          createPromotion(
            PromotionType.VIP,
            '2026-06-19T11:00:00.000Z',
            '2026-06-19T11:30:00.000Z',
          ),
        ],
      },
    ],
  });

  const response = await service.findAll();

  assert.deepEqual(
    response.items.map((item: { id: string }) => item.id),
    ['listing-fresh', 'listing-expired'],
  );
});

test('public feed keeps paid listings stable across pagination without duplicates', async () => {
  const ordinary = Array.from({ length: 10 }, (_, index) =>
    createApprovedListing(
      `listing-${10 - index}`,
      `2026-06-19T10:${(59 - index).toString().padStart(2, '0')}:00.000Z`,
    ),
  );
  const paid = [
    {
      ...createApprovedListing('listing-vip', '2026-06-19T06:00:00.000Z'),
      promotions: [createPromotion(PromotionType.VIP, '2026-06-19T12:00:00.000Z')],
    },
    {
      ...createApprovedListing('listing-bump', '2026-06-19T05:00:00.000Z'),
      promotions: [createPromotion(PromotionType.BUMP, '2026-06-19T11:00:00.000Z')],
    },
  ];
  const service = createService({
    findMany: async (args?: Record<string, unknown>) =>
      (args?.where as { AND?: unknown } | undefined)?.AND == null
        ? ordinary.slice(0, 9)
        : [...ordinary.slice(8), ...paid],
  });

  const firstPage = await service.findAll({ limit: 8 });
  const secondPage = await service.findAll({
    limit: 10,
    cursor: firstPage.nextCursor ?? undefined,
  });

  assert.deepEqual(
    firstPage.items.map((item: { id: string }) => item.id),
    [
      'listing-10',
      'listing-9',
      'listing-8',
      'listing-7',
      'listing-6',
      'listing-5',
      'listing-4',
      'listing-3',
    ],
  );
  assert.deepEqual(
    secondPage.items.map((item: { id: string }) => item.id),
    ['listing-2', 'listing-1', 'listing-vip', 'listing-bump'],
  );
  assert.equal(
    new Set([
      ...firstPage.items.map((item: { id: string }) => item.id),
      ...secondPage.items.map((item: { id: string }) => item.id),
    ]).size,
    12,
  );
});

test('findAll returns paginated page with nextCursor and hasMore', async () => {
  const service = createService({
    findMany: async () => [
      createApprovedListing('listing-3', '2026-07-03T10:00:00.000Z'),
      createApprovedListing('listing-2', '2026-07-02T10:00:00.000Z'),
      createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z'),
    ],
  });

  const response = await service.findAll({ limit: 2 });

  assert.deepEqual(
    response.items.map((item: { id: string }) => item.id),
    ['listing-3', 'listing-2'],
  );
  assert.equal(response.hasMore, true);
  assert.equal(typeof response.nextCursor, 'string');
  assert.ok((response.nextCursor ?? '').length > 0);
});

test('findAll limits database page to requested limit plus one with stable order', async () => {
  let findManyArgs: Record<string, unknown> | undefined;
  const service = createService({
    findMany: async (args?: Record<string, unknown>) => {
      findManyArgs = args;
      return [
        createApprovedListing('listing-3', '2026-07-03T10:00:00.000Z'),
        createApprovedListing('listing-2', '2026-07-02T10:00:00.000Z'),
        createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z'),
      ];
    },
  });

  await service.findAll({ limit: 2 });

  assert.equal(findManyArgs?.take, 3);
  assert.deepEqual(findManyArgs?.orderBy, [
    {
      publishedAt: {
        sort: 'desc',
        nulls: 'last',
      },
    },
    {
      createdAt: 'desc',
    },
    {
      id: 'desc',
    },
  ]);
});

test('findAll cursor returns next page without duplicates and keeps category filter', async () => {
  let findManyArgs: Record<string, unknown> | undefined;
  const listings = [
    createApprovedListing('listing-4', '2026-07-04T10:00:00.000Z', 'auto'),
    createApprovedListing('listing-3', '2026-07-03T10:00:00.000Z', 'auto'),
    createApprovedListing('listing-2', '2026-07-02T10:00:00.000Z', 'auto'),
    createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z', 'auto'),
  ];
  const service = createService({
    findMany: async (args?: Record<string, unknown>) => {
      findManyArgs = args;
      return (args?.where as { AND?: unknown } | undefined)?.AND == null
        ? listings.slice(0, 3)
        : listings.slice(2);
    },
  });

  const firstPage = await service.findAll({
    category: 'auto',
    limit: 2,
  });
  const secondPage = await service.findAll({
    category: 'auto',
    limit: 2,
    cursor: firstPage.nextCursor ?? undefined,
  });

  assert.deepEqual(
    firstPage.items.map((item: { id: string }) => item.id),
    ['listing-4', 'listing-3'],
  );
  assert.deepEqual(
    secondPage.items.map((item: { id: string }) => item.id),
    ['listing-2', 'listing-1'],
  );
  assert.equal(secondPage.hasMore, false);
  assert.deepEqual(
    new Set([
      ...firstPage.items.map((item: { id: string }) => item.id),
      ...secondPage.items.map((item: { id: string }) => item.id),
    ]).size,
    4,
  );
  assert.equal(
    (findManyArgs?.where as Record<string, unknown>).category,
    'auto',
  );
});

test('findAll cursor uses keyset fields instead of loading all rows by cursor id', async () => {
  let secondFindManyArgs: Record<string, unknown> | undefined;
  const service = createService({
    findMany: async (args?: Record<string, unknown>) => {
      if (args?.where && (args.where as { AND?: unknown }).AND != null) {
        secondFindManyArgs = args;
        return [
          createApprovedListing('listing-2', '2026-07-02T10:00:00.000Z'),
          createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z'),
        ];
      }
      return [
        createApprovedListing('listing-4', '2026-07-04T10:00:00.000Z'),
        createApprovedListing('listing-3', '2026-07-03T10:00:00.000Z'),
        createApprovedListing('listing-2', '2026-07-02T10:00:00.000Z'),
      ];
    },
  });

  const firstPage = await service.findAll({ limit: 2 });
  const secondPage = await service.findAll({
    limit: 2,
    cursor: firstPage.nextCursor ?? undefined,
  });

  assert.deepEqual(
    secondPage.items.map((item: { id: string }) => item.id),
    ['listing-2', 'listing-1'],
  );
  assert.equal(secondFindManyArgs?.take, 3);
  assert.equal('cursor' in (secondFindManyArgs ?? {}), false);
  assert.ok(
    Array.isArray((secondFindManyArgs?.where as { AND?: unknown[] } | undefined)?.AND),
  );
});

test('public feed $queryRaw cursor pages through old UUID listings without duplicates or gaps', async () => {
  const orderedListings = Array.from({ length: 30 }, (_, index) => {
    const listing = createApprovedListing(
      uuidFromNumber(100 - index),
      `2026-07-01T10:${(59 - index).toString().padStart(2, '0')}:00.000Z`,
    );
    return {
      ...listing,
      title: index === 25 ? 'стабилизатор 13.5' : listing.title,
    };
  });
  orderedListings[25] = {
    ...orderedListings[25]!,
    id: '9518c1a6-f564-4411-9af9-0d6cef163d3f',
  };

  const { service, rawCalls } = createRawFeedHarness(orderedListings);

  const firstPage = await service.findAll({ limit: 10 });
  const secondPage = await service.findAll({
    limit: 10,
    cursor: firstPage.nextCursor ?? undefined,
  });
  const thirdPage = await service.findAll({
    limit: 10,
    cursor: secondPage.nextCursor ?? undefined,
  });

  const ids = [
    ...firstPage.items.map((item: { id: string }) => item.id),
    ...secondPage.items.map((item: { id: string }) => item.id),
    ...thirdPage.items.map((item: { id: string }) => item.id),
  ];

  assert.equal(firstPage.hasMore, true);
  assert.equal(secondPage.hasMore, true);
  assert.equal(thirdPage.hasMore, false);
  assert.equal(typeof firstPage.nextCursor, 'string');
  assert.equal(typeof secondPage.nextCursor, 'string');
  assert.equal(thirdPage.nextCursor, null);
  assert.equal(ids.length, 30);
  assert.equal(new Set(ids).size, 30);
  assert.deepEqual(ids, orderedListings.map((listing) => listing.id));
  assert.ok(secondPage.items.some((item: { id: string }) => item.id === orderedListings[10]!.id));
  assert.ok(ids.includes('9518c1a6-f564-4411-9af9-0d6cef163d3f'));
  assert.equal(rawCalls.length, 3);
  assert.equal(rawCalls[1]!.cursorId, firstPage.items[9]!.id);
  assert.equal(rawCalls[2]!.cursorId, secondPage.items[9]!.id);
  assert.match(rawCalls[1]!.text, /"id"\s*<\s*\$\d+::uuid/);
});

test('public feed $queryRaw cursor remains stable with top insert slot and more than 20 active promotions', async () => {
  const regularHead = Array.from({ length: 10 }, (_, index) =>
    createApprovedListing(
      uuidFromNumber(300 - index),
      `2026-07-02T11:${(59 - index).toString().padStart(2, '0')}:00.000Z`,
    ),
  );
  const promoted = Array.from({ length: 22 }, (_, index) => ({
    ...createApprovedListing(
      uuidFromNumber(200 - index),
      `2026-07-02T08:${(59 - index).toString().padStart(2, '0')}:00.000Z`,
    ),
    promotions: [createPromotion(PromotionType.VIP, '2026-07-02T12:00:00.000Z')],
  }));
  const expired = Array.from({ length: 8 }, (_, index) => ({
    ...createApprovedListing(
      uuidFromNumber(100 - index),
      `2026-07-01T07:${(59 - index).toString().padStart(2, '0')}:00.000Z`,
    ),
    promotions: [
      createPromotion(
        PromotionType.BUMP,
        '2026-07-01T12:00:00.000Z',
        '2026-07-01T12:30:00.000Z',
      ),
    ],
  }));
  const orderedListings = [...regularHead, ...expired, ...promoted];
  const { service, rawCalls } = createRawFeedHarness(orderedListings, {
    promotedIds: Object.fromEntries(
      promoted.map((listing) => [listing.id, '2026-07-02T12:00:00.000Z']),
    ),
  });

  const firstPage = await service.findAll({ limit: 10 });
  const secondPage = await service.findAll({
    limit: 10,
    cursor: firstPage.nextCursor ?? undefined,
  });
  const thirdPage = await service.findAll({
    limit: 10,
    cursor: secondPage.nextCursor ?? undefined,
  });
  const fourthPage = await service.findAll({
    limit: 10,
    cursor: thirdPage.nextCursor ?? undefined,
  });

  const ids = [
    ...firstPage.items.map((item: { id: string }) => item.id),
    ...secondPage.items.map((item: { id: string }) => item.id),
    ...thirdPage.items.map((item: { id: string }) => item.id),
    ...fourthPage.items.map((item: { id: string }) => item.id),
  ];

  assert.deepEqual(firstPage.items.slice(0, 9).map((item: { id: string }) => item.id), regularHead.slice(0, 9).map((listing) => listing.id));
  assert.equal(firstPage.items[9]!.id, promoted[0]!.id);
  assert.ok(secondPage.items.some((item: { id: string }) => item.id === promoted[10]!.id));
  assert.ok(thirdPage.items.some((item: { id: string }) => item.id === promoted[20]!.id));
  assert.ok(fourthPage.items.some((item: { id: string }) => item.id === expired[0]!.id));
  assert.equal(firstPage.hasMore, true);
  assert.equal(secondPage.hasMore, true);
  assert.equal(thirdPage.hasMore, true);
  assert.equal(fourthPage.hasMore, false);
  assert.equal(ids.length, orderedListings.length);
  assert.equal(new Set(ids).size, orderedListings.length);
  assert.deepEqual(ids, [
    ...regularHead.slice(0, 9).map((listing) => listing.id),
    ...promoted.map((listing) => listing.id),
    regularHead[9]!.id,
    ...expired.map((listing) => listing.id),
  ]);
  assert.match(rawCalls[0]!.text, /natural_rank|moved_count|promotion_queue_rank|promoted_at/);
  assert.match(rawCalls[1]!.text, /"id"\s*<\s*\$\d+::uuid/);
});

test('public feed $queryRaw keeps top-10 promotions in place and inserts old VIP/BUMP purchases at position 10', async () => {
  const listings = createFreshListings(60).map((listing, index) => {
    if (index === 0) {
      return withPromotionAt(listing, PromotionType.VIP, '2026-07-02T12:00:00.000Z');
    }
    if (index === 4) {
      return withPromotionAt(listing, PromotionType.BUMP, '2026-07-02T12:01:00.000Z');
    }
    if (index === 49) {
      return withPromotionAt(listing, PromotionType.VIP, '2026-07-02T12:02:00.000Z');
    }
    return listing;
  });
  const { service } = createRawFeedHarness(listings);

  const response = await service.findAll({ limit: 60 });
  const ids = response.items.map((item: { id: string }) => item.id);

  assert.equal(ids[0], 'listing-1');
  assert.equal(ids[4], 'listing-5');
  assert.equal(ids[9], 'listing-50');
  assert.equal(ids[10], 'listing-10');
});

test('public feed $queryRaw uses one newest-first VIP/BUMP promotion queue from position 10', async () => {
  const listings = createFreshListings(40).map((listing, index) => {
    if (index === 14) {
      return withPromotionAt(listing, PromotionType.VIP, '2026-07-02T12:00:00.000Z');
    }
    if (index === 15) {
      return withPromotionAt(listing, PromotionType.VIP, '2026-07-02T12:01:00.000Z');
    }
    if (index === 16) {
      return withPromotionAt(listing, PromotionType.BUMP, '2026-07-02T12:02:00.000Z');
    }
    if (index === 17) {
      return withPromotionAt(listing, PromotionType.VIP, '2026-07-02T12:03:00.000Z');
    }
    return listing;
  });
  const { service } = createRawFeedHarness(listings);

  const response = await service.findAll({ limit: 40 });

  assert.deepEqual(
    response.items.slice(9, 13).map((item: { id: string }) => item.id),
    ['listing-18', 'listing-17', 'listing-16', 'listing-15'],
  );
});

test('public feed vip interleave mode starts with 10 ordinary listings then alternates one VIP and two ordinary', async () => {
  const ordinary = Array.from({ length: 18 }, (_, index) =>
    createApprovedListing(
      uuidFromNumber(600 - index),
      `2026-07-03T12:${(59 - index).toString().padStart(2, '0')}:00.000Z`,
    ),
  );
  const vip = Array.from({ length: 4 }, (_, index) => ({
    ...createApprovedListing(
      uuidFromNumber(500 - index),
      `2026-07-03T09:${(59 - index).toString().padStart(2, '0')}:00.000Z`,
    ),
    promotions: [
      createPromotion(
        PromotionType.VIP,
        `2026-07-03T13:0${index}:00.000Z`,
      ),
    ],
  }));
  const { service } = createRawFeedHarness([...ordinary, ...vip]);

  const response = await service.findAll({
    limit: 22,
    feedMode: 'vip_interleave_v1',
  });
  const ids = response.items.map((item: { id: string }) => item.id);
  const vipIds = [...vip].reverse().map((listing) => listing.id);

  assert.deepEqual(ids.slice(0, 10), ordinary.slice(0, 10).map((listing) => listing.id));
  assert.equal(ids[10], vipIds[0]);
  assert.deepEqual(ids.slice(11, 13), ordinary.slice(10, 12).map((listing) => listing.id));
  assert.equal(ids[13], vipIds[1]);
  assert.deepEqual(ids.slice(14, 16), ordinary.slice(12, 14).map((listing) => listing.id));
  assert.equal(ids[16], vipIds[2]);
  assert.equal(ids.length, new Set(ids).size);
  assert.ok(!ids.slice(0, 20).some((id, index) =>
    index > 0 && vipIds.includes(id) && vipIds.includes(ids[index - 1]!),
  ));
});

test('public feed vip interleave mode rotates VIP order and keeps cursor pages unique', async () => {
  const ordinary = Array.from({ length: 24 }, (_, index) =>
    createApprovedListing(
      uuidFromNumber(700 - index),
      `2026-07-04T12:${(59 - index).toString().padStart(2, '0')}:00.000Z`,
    ),
  );
  const vip = Array.from({ length: 6 }, (_, index) => ({
    ...createApprovedListing(
      uuidFromNumber(650 - index),
      `2026-07-04T09:${(59 - index).toString().padStart(2, '0')}:00.000Z`,
    ),
    promotions: [
      createPromotion(
        PromotionType.VIP,
        `2026-07-04T13:0${index}:00.000Z`,
      ),
    ],
  }));
  const { service, rawCalls } = createRawFeedHarness([...ordinary, ...vip]);

  const firstRefresh = await service.findAll({
    limit: 15,
    feedMode: 'vip_interleave_v1',
    vipRotation: 0,
  });
  const firstRefreshSecondPage = await service.findAll({
    limit: 15,
    feedMode: 'vip_interleave_v1',
    vipRotation: 0,
    cursor: firstRefresh.nextCursor ?? undefined,
  });
  const secondRefresh = await service.findAll({
    limit: 15,
    feedMode: 'vip_interleave_v1',
    vipRotation: 1,
  });
  const firstIds = [
    ...firstRefresh.items.map((item: { id: string }) => item.id),
    ...firstRefreshSecondPage.items.map((item: { id: string }) => item.id),
  ];
  const vipIds = [...vip].reverse().map((listing) => listing.id);

  assert.equal(firstRefresh.items[10]!.id, vipIds[0]);
  assert.equal(secondRefresh.items[10]!.id, vipIds[1]);
  assert.equal(firstIds.length, 30);
  assert.equal(new Set(firstIds).size, 30);
  assert.deepEqual(
    firstIds.filter((id) => vipIds.includes(id)),
    vipIds,
  );
  assert.match(rawCalls[0]!.text, /vip_promoted_at|ordinary_head_count/);
  assert.match(rawCalls[1]!.text, /"id"\s*<\s*\$\d+::uuid/);
});

test('public feed without vip interleave mode keeps legacy paid ordering for old clients', async () => {
  const listings = createFreshListings(40).map((listing, index) => {
    if (index === 14) {
      return withPromotionAt(listing, PromotionType.VIP, '2026-07-02T12:00:00.000Z');
    }
    if (index === 15) {
      return withPromotionAt(listing, PromotionType.VIP, '2026-07-02T12:01:00.000Z');
    }
    return listing;
  });
  const { service } = createRawFeedHarness(listings);

  const response = await service.findAll({ limit: 40 });

  assert.deepEqual(
    response.items.slice(9, 11).map((item: { id: string }) => item.id),
    ['listing-16', 'listing-15'],
  );
});

test('public feed $queryRaw search and category filters keep working with cursor', async () => {
  const orderedListings = [
    {
      ...createApprovedListing(uuidFromNumber(410), '2026-07-03T10:10:00.000Z', 'auto'),
      title: 'Свежий стабилизатор',
    },
    {
      ...createApprovedListing(uuidFromNumber(409), '2026-07-03T10:09:00.000Z', 'auto'),
      title: 'Стабилизатор 13.5',
    },
    {
      ...createApprovedListing(uuidFromNumber(408), '2026-07-03T10:08:00.000Z', 'misc'),
      title: 'Стабилизатор другой категории',
    },
    {
      ...createApprovedListing(uuidFromNumber(407), '2026-07-03T10:07:00.000Z', 'auto'),
      title: 'Авто стабилизатор старый',
    },
  ];
  const { service, rawCalls } = createRawFeedHarness(orderedListings);

  const firstPage = await service.findAll({
    category: 'auto',
    search: 'стабилизатор',
    limit: 2,
  });
  const secondPage = await service.findAll({
    category: 'auto',
    search: 'стабилизатор',
    limit: 2,
    cursor: firstPage.nextCursor ?? undefined,
  });

  assert.deepEqual(
    firstPage.items.map((item: { id: string }) => item.id),
    [uuidFromNumber(410), uuidFromNumber(409)],
  );
  assert.deepEqual(
    secondPage.items.map((item: { id: string }) => item.id),
    [uuidFromNumber(407)],
  );
  assert.equal(secondPage.hasMore, false);
  assert.match(rawCalls[0]!.text, /l\."category" =/);
  assert.match(rawCalls[0]!.text, /l\."title" ILIKE/);
  assert.match(rawCalls[1]!.text, /"id"\s*<\s*\$\d+::uuid/);
});

test('public feed search finds all approved listings by normalized OEM variants', async () => {
  const matchingOne = {
    ...createApprovedListing(uuidFromNumber(420), '2026-07-03T10:10:00.000Z', 'Запчасти'),
    title: 'Фара левая',
    oemPartNumber: '81150-06C70',
    oemPartNumberNormalized: '8115006C70',
  };
  const matchingTwo = {
    ...createApprovedListing(uuidFromNumber(419), '2026-07-03T10:09:00.000Z', 'Запчасти'),
    title: 'Оптика Toyota',
    oemPartNumber: '81150 06c70',
    oemPartNumberNormalized: '8115006C70',
  };
  const nonMatching = {
    ...createApprovedListing(uuidFromNumber(418), '2026-07-03T10:08:00.000Z', 'Запчасти'),
    title: 'Фара правая',
    oemPartNumber: '81110-06C70',
    oemPartNumberNormalized: '8111006C70',
  };
  const { service, rawCalls } = createRawFeedHarness([
    matchingOne,
    matchingTwo,
    nonMatching,
  ]);

  for (const search of ['81150-06C70', '8115006C70', '81150 06c70']) {
    const response = await service.findAll({ search, limit: 10 });
    assert.deepEqual(
      response.items.map((item: { id: string }) => item.id),
      [matchingOne.id, matchingTwo.id],
    );
  }

  assert.match(rawCalls[0]!.text, /oem_part_number_normalized/);
});

test('public feed search covers title, description, language mix, case and spaces', async () => {
  const englishTitleRussianDescription = {
    ...createApprovedListing(uuidFromNumber(425), '2026-07-03T10:10:00.000Z'),
    title: 'BMW X5 Headlight',
    description: 'Передняя левая фара, хорошее состояние',
  };
  const russianTitleEnglishDescription = {
    ...createApprovedListing(uuidFromNumber(424), '2026-07-03T10:09:00.000Z'),
    title: 'Фара Toyota Camry',
    description: 'Original headlight for Toyota Camry',
  };
  const nonMatching = {
    ...createApprovedListing(uuidFromNumber(423), '2026-07-03T10:08:00.000Z'),
    title: 'Дверь Toyota Camry',
    description: 'Original door',
  };
  const { service } = createRawFeedHarness([
    englishTitleRussianDescription,
    russianTitleEnglishDescription,
    nonMatching,
  ]);

  assert.deepEqual(
    (await service.findAll({ search: 'фара', limit: 10 })).items.map(
      (item: { id: string }) => item.id,
    ),
    [englishTitleRussianDescription.id, russianTitleEnglishDescription.id],
  );
  assert.deepEqual(
    (await service.findAll({ search: 'HEADLIGHT', limit: 10 })).items.map(
      (item: { id: string }) => item.id,
    ),
    [englishTitleRussianDescription.id, russianTitleEnglishDescription.id],
  );
  assert.deepEqual(
    (await service.findAll({ search: '  Toyota   Camry  ', limit: 10 })).items.map(
      (item: { id: string }) => item.id,
    ),
    [russianTitleEnglishDescription.id, nonMatching.id],
  );
});

test('public feed search supports transliteration in title and description', async () => {
  const rayBanInTitle = {
    ...createApprovedListing(uuidFromNumber(435), '2026-07-03T10:10:00.000Z'),
    title: 'Ray-Ban Aviator',
    description: 'Оригинальные солнцезащитные очки',
  };
  const rayBanInDescription = {
    ...createApprovedListing(uuidFromNumber(434), '2026-07-03T10:09:00.000Z'),
    title: 'Очки Рэйбан',
    description: 'Original Ray-Ban Aviator',
  };
  const toyotaCamry = {
    ...createApprovedListing(uuidFromNumber(433), '2026-07-03T10:08:00.000Z', 'Автомобили'),
    title: 'Toyota Camry',
    description: 'Седан в хорошем состоянии',
  };
  const samsungGalaxy = {
    ...createApprovedListing(uuidFromNumber(432), '2026-07-03T10:07:00.000Z', 'Электроника'),
    title: 'Samsung Galaxy',
    description: 'Смартфон без сколов',
  };
  const { service } = createRawFeedHarness([
    rayBanInTitle,
    rayBanInDescription,
    toyotaCamry,
    samsungGalaxy,
  ]);

  assert.deepEqual(
    (await service.findAll({ search: 'рейбан', limit: 10 })).items.map(
      (item: { id: string }) => item.id,
    ),
    [rayBanInTitle.id, rayBanInDescription.id],
  );
  assert.deepEqual(
    (await service.findAll({ search: 'Rayban', limit: 10 })).items.map(
      (item: { id: string }) => item.id,
    ),
    [rayBanInTitle.id, rayBanInDescription.id],
  );
  assert.deepEqual(
    (await service.findAll({ search: 'Тойота Камри', category: 'Автомобили', limit: 10 }))
      .items.map((item: { id: string }) => item.id),
    [toyotaCamry.id],
  );
  assert.deepEqual(
    (await service.findAll({ search: 'Самсунг Galaxy', category: 'Электроника', limit: 10 }))
      .items.map((item: { id: string }) => item.id),
    [samsungGalaxy.id],
  );
});

test('public feed search finds visible characteristics across categories', async () => {
  const carByBrandModel = {
    ...createApprovedListing(uuidFromNumber(438), '2026-07-03T10:10:00.000Z', 'Автомобили'),
    title: 'Седан',
    car: {
      brand: 'Toyota',
      model: 'Camry',
      generation: 'XV70',
      vin: 'JTDBE32K',
    },
  };
  const realEstateByType = {
    ...createApprovedListing(uuidFromNumber(437), '2026-07-03T10:09:00.000Z', 'Недвижимость'),
    title: 'Участок у реки',
    realEstateType: 'Дом',
  };
  const clothesByTypeAndSize = {
    ...createApprovedListing(uuidFromNumber(436), '2026-07-03T10:08:00.000Z', 'Одежда'),
    title: 'Куртка',
    clothesType: 'Верхняя одежда',
    clothesSize: 'XL',
  };
  const genericCarNote = {
    ...createApprovedListing(uuidFromNumber(431), '2026-07-03T10:07:00.000Z'),
    title: 'Машина',
    car: {
      brand: 'Lada',
      model: 'Vesta',
      note: 'безключевой доступ',
    },
  };
  const { service, rawCalls } = createRawFeedHarness([
    carByBrandModel,
    realEstateByType,
    clothesByTypeAndSize,
    genericCarNote,
  ]);

  assert.deepEqual(
    (await service.findAll({ search: 'Toyota Camry', category: 'Автомобили', limit: 10 }))
      .items.map((item: { id: string }) => item.id),
    [carByBrandModel.id],
  );
  assert.deepEqual(
    (await service.findAll({ search: 'Дом', category: 'Недвижимость', limit: 10 }))
      .items.map((item: { id: string }) => item.id),
    [realEstateByType.id],
  );
  assert.deepEqual(
    (await service.findAll({ search: 'XL', category: 'Одежда', limit: 10 }))
      .items.map((item: { id: string }) => item.id),
    [clothesByTypeAndSize.id],
  );
  assert.deepEqual(
    (await service.findAll({ search: 'безключевой', limit: 10 })).items.map(
      (item: { id: string }) => item.id,
    ),
    [genericCarNote.id],
  );
  assert.match(rawCalls[0]!.text, /jsonb_each_text/);
});

test('public feed search finds codes in title, description, and characteristics', async () => {
  const codeInTitle = {
    ...createApprovedListing(uuidFromNumber(430), '2026-07-03T10:10:00.000Z', 'Запчасти'),
    title: 'Фара 81150-06C70',
  };
  const codeInDescription = {
    ...createApprovedListing(uuidFromNumber(421), '2026-07-03T10:09:00.000Z', 'Запчасти'),
    title: 'Фара левая',
    description: 'Маркировка 81150 06C71',
  };
  const codeInCharacteristic = {
    ...createApprovedListing(uuidFromNumber(420), '2026-07-03T10:08:00.000Z', 'Автомобили'),
    title: 'Toyota Camry',
    car: {
      brand: 'Toyota',
      model: 'Camry',
      vin: 'JT2-ABC 1234567890',
    },
  };
  const { service } = createRawFeedHarness([
    codeInTitle,
    codeInDescription,
    codeInCharacteristic,
  ]);

  for (const search of ['81150-06C70', '8115006C70', '81150 06C70']) {
    assert.deepEqual(
      (await service.findAll({ search, limit: 10 })).items.map(
        (item: { id: string }) => item.id,
      ),
      [codeInTitle.id],
    );
  }
  assert.deepEqual(
    (await service.findAll({ search: '8115006C71', limit: 10 })).items.map(
      (item: { id: string }) => item.id,
    ),
    [codeInDescription.id],
  );
  assert.deepEqual(
    (await service.findAll({ search: 'JT2ABC1234567890', limit: 10 })).items.map(
      (item: { id: string }) => item.id,
    ),
    [codeInCharacteristic.id],
  );
  assert.deepEqual(
    (await service.findAll({ search: 'JT2ABC1234567891', limit: 10 })).items,
    [],
  );
});

test('public feed search keeps typo tolerance bounded and OEM exact', async () => {
  const toyota = {
    ...createApprovedListing(uuidFromNumber(445), '2026-07-03T10:10:00.000Z', 'Автомобили'),
    title: 'Toyota Camry',
    description: 'Original sedan',
    oemPartNumber: '81150-06C70',
    oemPartNumberNormalized: '8115006C70',
  };
  const samsung = {
    ...createApprovedListing(uuidFromNumber(444), '2026-07-03T10:09:00.000Z', 'Электроника'),
    title: 'Samsung Galaxy',
    description: 'Android phone',
  };
  const rayBan = {
    ...createApprovedListing(uuidFromNumber(443), '2026-07-03T10:08:00.000Z'),
    title: 'Ray-Ban Aviator',
    description: 'Sunglasses',
  };
  const unrelated = {
    ...createApprovedListing(uuidFromNumber(442), '2026-07-03T10:07:00.000Z'),
    title: 'Кухонный стол',
    description: 'Дерево',
    oemPartNumber: '81150-06C71',
    oemPartNumberNormalized: '8115006C71',
  };
  const { service } = createRawFeedHarness([toyota, samsung, rayBan, unrelated]);

  for (const search of ['Toyta', 'Tooyota', 'Toyotaa', 'Camri', 'Kamry']) {
    assert.deepEqual(
      (await service.findAll({ search, limit: 10 })).items.map(
        (item: { id: string }) => item.id,
      ),
      [toyota.id],
    );
  }
  for (const search of ['Samsng', 'Samsungg']) {
    assert.deepEqual(
      (await service.findAll({ search, limit: 10 })).items.map(
        (item: { id: string }) => item.id,
      ),
      [samsung.id],
    );
  }
  assert.deepEqual(
    (await service.findAll({ search: 'Raybn', limit: 10 })).items.map(
      (item: { id: string }) => item.id,
    ),
    [rayBan.id],
  );
  assert.deepEqual((await service.findAll({ search: 'zzzzzz', limit: 10 })).items, []);
  assert.deepEqual((await service.findAll({ search: 'ab', limit: 10 })).items, []);
  assert.deepEqual((await service.findAll({ search: '12', limit: 10 })).items, []);
  assert.deepEqual(
    (await service.findAll({ search: '81150-06C71', limit: 10 })).items.map(
      (item: { id: string }) => item.id,
    ),
    [unrelated.id],
  );
});

test('public feed OEM search supports spaces, letters, short and long codes', async () => {
  const shortCode = {
    ...createApprovedListing(uuidFromNumber(428), '2026-07-03T10:10:00.000Z', 'Запчасти'),
    oemPartNumber: '1234',
    oemPartNumberNormalized: '1234',
  };
  const dashedCode = {
    ...createApprovedListing(uuidFromNumber(427), '2026-07-03T10:09:00.000Z', 'Запчасти'),
    oemPartNumber: '77-88-99',
    oemPartNumberNormalized: '778899',
  };
  const longCode = {
    ...createApprovedListing(uuidFromNumber(426), '2026-07-03T10:08:00.000Z', 'Запчасти'),
    oemPartNumber: 'AB-123456789012345678',
    oemPartNumberNormalized: 'AB123456789012345678',
  };
  const { service } = createRawFeedHarness([shortCode, dashedCode, longCode]);

  assert.deepEqual(
    (await service.findAll({ search: '1234', limit: 10 })).items.map(
      (item: { id: string }) => item.id,
    ),
    [shortCode.id],
  );
  assert.deepEqual(
    (await service.findAll({ search: '77 88 99', limit: 10 })).items.map(
      (item: { id: string }) => item.id,
    ),
    [dashedCode.id],
  );
  assert.deepEqual(
    (await service.findAll({ search: 'ab 123456789012345678', limit: 10 })).items.map(
      (item: { id: string }) => item.id,
    ),
    [longCode.id],
  );
});

test('public feed mixed text and OEM query can still match by normalized OEM token', async () => {
  const matching = {
    ...createApprovedListing(uuidFromNumber(429), '2026-07-03T10:10:00.000Z', 'Запчасти'),
    title: 'Фара Toyota Camry',
    description: 'Original Toyota part',
    oemPartNumber: '81150-06C70',
    oemPartNumberNormalized: '8115006C70',
  };
  const { service } = createRawFeedHarness([matching]);

  for (const search of ['фара 81150-06C70', 'Toyota 8115006C70']) {
    const response = await service.findAll({ search, limit: 10 });
    assert.deepEqual(
      response.items.map((item: { id: string }) => item.id),
      [matching.id],
    );
  }
});

test('public feed OEM search keeps existing public visibility filters', async () => {
  const { service, rawCalls } = createRawFeedHarness([
    {
      ...createApprovedListing(uuidFromNumber(430), '2026-07-03T10:10:00.000Z', 'Запчасти'),
      oemPartNumber: '81150-06C70',
      oemPartNumberNormalized: '8115006C70',
    },
  ]);

  await service.findAll({ search: '81150-06C70', limit: 10 });

  assert.match(rawCalls[0]!.text, /l\."deleted_at" IS NULL/);
  assert.match(rawCalls[0]!.text, /l\."status"::text = 'APPROVED'/);
  assert.match(rawCalls[0]!.text, /u\."status"::text = 'ACTIVE'/);
});

test('listing photo upload uses selected storage provider flow', async () => {
  const storageCalls: Array<Record<string, unknown>> = [];
  let status: ListingStatus = ListingStatus.APPROVED;
  let updateArgs: Record<string, unknown> | undefined;
  const service = new ListingsService(
    {
      listing: {
        findUnique: async () => ({
          id: 'listing-1',
          ownerId: ownerUser.userId,
          status,
          photos: [],
        }),
        update: async (args: Record<string, unknown>) => {
          updateArgs = args;
          status = (args.data as { status?: ListingStatus }).status ?? status;
          return {};
        },
        findUniqueOrThrow: async () => ({
          id: 'listing-1',
          ownerId: ownerUser.userId,
          title: 'Listing',
          description: '',
          category: 'misc',
          subcategory: '',
          price: BigInt(0),
          phone: '',
          phoneHidden: false,
          city: '',
          address: '',
          locationJson: {},
          delivery: {},
          car: null,
          status,
          rejectionReason: '',
          moderationNote: null,
          moderatedBy: null,
          moderatedAt: null,
          publishedAt: null,
          archivedAt: null,
          deletedAt: null,
          viewCount: 0,
          createdAt: new Date(),
          updatedAt: new Date(),
          owner: null,
          photos: [],
          promotions: [],
        }),
      },
      listingPhoto: {
        create: async () => ({
          id: 'photo-1',
          publicUrl:
            'https://s3.twcstorage.ru/atta-media-prod/listings/listing-1/photo.jpg',
          sortOrder: 0,
        }),
      },
    } as never,
    {
      saveUploadedFile: async (payload: Record<string, unknown>) => {
        storageCalls.push(payload);
        return {
          bucket: 'atta-media-prod',
          key: 'listings/listing-1/photo.jpg',
          mimeType: 'image/jpeg',
          provider: 's3',
          sizeBytes: 128,
          url: 'https://s3.twcstorage.ru/atta-media-prod/listings/listing-1/photo.jpg',
        };
      },
    } as never,
    {} as never,
  );

  const response = await service.uploadPhoto(
    ownerUser,
    'listing-1',
    {
      buffer: Buffer.from('photo'),
      mimetype: 'image/jpeg',
      originalname: 'photo.jpg',
    } as never,
  );

  assert.equal(storageCalls.length, 1);
  assert.equal(storageCalls[0].category, 'listings');
  assert.deepEqual(storageCalls[0].context, {
    listingId: 'listing-1',
    userId: ownerUser.userId,
  });
  assert.equal(
    (updateArgs?.data as Record<string, unknown>).status,
    ListingStatus.PENDING,
  );
  assert.equal(response.listing.status, 'pending');
  assert.match(response.photo.url, /listings\/listing-1\/photo\.jpg/);
});

test('create with approved status and no photos stays pending for regular user', async () => {
  let createArgs: Record<string, any> | undefined;
  const service = createService({
    create: async (args: Record<string, any>) => {
      createArgs = args;
      return {
        ...createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z'),
        status: args.data.status,
        publishedAt: args.data.publishedAt,
        photos: [],
      };
    },
  });

  const response = await service.create(ownerUser, {
    title: 'Listing',
    description: 'Description',
    category: 'misc',
    price: 100,
    status: 'approved',
    photo_urls: [],
  });

  assert.equal(createArgs?.data.status, ListingStatus.PENDING);
  assert.equal(createArgs?.data.publishedAt, null);
  assert.equal(response.listing.status, 'pending');
  assert.equal(response.listing.published_at, null);
});

test('pending create without photos is allowed as temporary listing', async () => {
  let createArgs: Record<string, any> | undefined;
  const service = createService({
    create: async (args: Record<string, any>) => {
      createArgs = args;
      return {
        ...createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z'),
        status: args.data.status,
        publishedAt: args.data.publishedAt,
        photos: [],
      };
    },
  });

  const response = await service.create(ownerUser, {
    title: 'Listing',
    description: 'Description',
    category: 'auto',
    price: 100,
    status: 'pending',
    photo_urls: [],
  });

  assert.equal(createArgs?.data.status, ListingStatus.PENDING);
  assert.equal(createArgs?.data.publishedAt, null);
  assert.equal(response.listing.status, 'pending');
});

test('placeholder create stays as non-ready pending draft for upload flow', async () => {
  let createArgs: Record<string, any> | undefined;
  const service = createService({
    create: async (args: Record<string, any>) => {
      createArgs = args;
      return {
        ...createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z'),
        title: args.data.title,
        description: args.data.description,
        category: args.data.category,
        subcategory: args.data.subcategory,
        price: BigInt(args.data.price),
        city: args.data.city,
        status: args.data.status,
        publishedAt: args.data.publishedAt,
        photos: [],
      };
    },
  });

  const response = await service.create(ownerUser, {
    title: 'Черновик объявления',
    description: 'Черновик объявления',
    category: 'Авто',
    subcategory: 'Легковые автомобили',
    price: 0,
    city: 'Грозный',
    status: 'pending',
    photo_urls: [],
  });

  assert.equal(createArgs?.data.status, ListingStatus.PENDING);
  assert.equal(createArgs?.data.publishedAt, null);
  assert.equal(response.listing.status, 'pending');
});

test('valid old create plus later photo upload remains pending-compatible', async () => {
  const listing = {
    ...createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z', 'Авто'),
    subcategory: 'Легковые автомобили',
    status: ListingStatus.PENDING,
    publishedAt: null,
    photos: [],
    owner: listingOwner(),
  };
  let savedListing: Record<string, any> = listing;
  const prisma = {
    listing: {
      findUnique: async () => savedListing,
      findUniqueOrThrow: async () => savedListing,
      update: async (args: Record<string, any>) => {
        savedListing = {
          ...savedListing,
          ...Object.fromEntries(
            Object.entries(args.data ?? {}).filter(([, value]) => value !== undefined),
          ),
        };
        return savedListing;
      },
    },
    listingPhoto: {
      create: async () => {
        const photo = listingPhoto('photo-1');
        savedListing = {
          ...savedListing,
          photos: [photo],
        };
        return photo;
      },
    },
    listingModerationRevision: {
      findFirst: async () => null,
      create: async () => ({ id: 'revision-1' }),
    },
    $transaction: async <T>(handler: (tx: unknown) => Promise<T>) =>
      handler(prisma),
  };
  const service = new ListingsService(
    prisma as never,
    {
      saveUploadedFile: async () => ({
        bucket: 'local',
        key: 'listings/listing-1/photo.jpg',
        url: 'https://example.com/photo.jpg',
        sizeBytes: 128,
        mimeType: 'image/jpeg',
      }),
    } as never,
    {} as never,
  );

  const response = await service.uploadPhoto(
    ownerUser,
    'listing-1',
    {
      buffer: Buffer.from('photo'),
      mimetype: 'image/jpeg',
      originalname: 'photo.jpg',
    } as never,
  );

  assert.equal(response.listing.status, 'pending');
  assert.equal(response.listing.photo_urls.length, 1);
});

function createPendingPatchService(initial: Record<string, any>) {
  let savedListing: Record<string, any> = {
    ...createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z', 'Авто'),
    subcategory: 'Легковые автомобили',
    status: ListingStatus.PENDING,
    publishedAt: null,
    photos: [listingPhoto()],
    owner: listingOwner(),
    ...initial,
  };
  const prisma = {
    listing: {
      findUnique: async () => savedListing,
      update: async (args: Record<string, any>) => {
        savedListing = {
          ...savedListing,
          ...Object.fromEntries(
            Object.entries(args.data ?? {}).filter(([, value]) => value !== undefined),
          ),
          updatedAt: new Date(),
        };
        return savedListing;
      },
      findUniqueOrThrow: async () => savedListing,
    },
    listingPhoto: {
      deleteMany: async () => {
        savedListing = { ...savedListing, photos: [] };
        return {};
      },
      createMany: async (args: Record<string, any>) => {
        savedListing = {
          ...savedListing,
          photos: args.data.map((item: Record<string, any>, index: number) => ({
            ...listingPhoto(`photo-${index + 1}`),
            ...item,
            id: `photo-${index + 1}`,
          })),
        };
        return {};
      },
    },
    listingModerationRevision: {
      findFirst: async () => null,
      create: async () => ({ id: 'revision-1' }),
    },
    $transaction: async <T>(handler: (tx: unknown) => Promise<T>) =>
      handler(prisma),
  };

  return new ListingsService(prisma as never, {} as never, {} as never);
}

test('pending PATCH rejects zero price direct API bypass', async () => {
  const service = createPendingPatchService({});

  await assert.rejects(
    () => service.update('listing-1', ownerUser, { price: 0 }),
    (error) =>
      error instanceof BadRequestException &&
      error.message === LISTING_PUBLICATION_NOT_READY,
  );
});

test('pending PATCH rejects missing photos direct API bypass', async () => {
  const service = createPendingPatchService({});

  await assert.rejects(
    () => service.update('listing-1', ownerUser, { photo_urls: [] }),
    (error) =>
      error instanceof BadRequestException &&
      error.message === LISTING_PUBLICATION_NOT_READY,
  );
});

test('pending PATCH rejects whitespace title direct API bypass', async () => {
  const service = createPendingPatchService({});

  await assert.rejects(
    () => service.update('listing-1', ownerUser, { title: '   ' }),
    (error) =>
      error instanceof BadRequestException &&
      error.message === LISTING_PUBLICATION_NOT_READY,
  );
});

test('valid final draft PATCH passes in pending moderation', async () => {
  const service = createPendingPatchService({
    title: 'Черновик объявления',
    description: 'Черновик объявления',
    price: BigInt(0),
  });

  const response = await service.update('listing-1', ownerUser, {
    title: 'Toyota Camry',
    description: 'Живой автомобиль',
    category: 'Авто',
    subcategory: 'Легковые автомобили',
    price: 1200000,
    city: 'Грозный',
  });

  assert.equal(response.listing.status, 'pending');
  assert.equal(response.listing.title, 'Toyota Camry');
});

test('approved PATCH cannot make listing incomplete', async () => {
  const service = createPendingPatchService({
    status: ListingStatus.APPROVED,
    publishedAt: new Date('2026-07-01T10:00:00.000Z'),
  });

  await assert.rejects(
    () => service.update('listing-1', ownerUser, { photo_urls: [] }),
    (error) =>
      error instanceof BadRequestException &&
      error.message === LISTING_PUBLICATION_NOT_READY,
  );
});

test('public feed only returns approved listings with at least one photo', async () => {
  let findManyArgs: Record<string, any> | undefined;
  const service = createService({
    findMany: async (args?: Record<string, any>) => {
      findManyArgs = args;
      return [];
    },
  });

  await service.findAll({ category: 'Одежда' });

  assert.deepEqual(findManyArgs?.where.photos, { some: {} });
  assert.equal(findManyArgs?.where.status, ListingStatus.APPROVED);
  assert.equal(findManyArgs?.where.category, 'Одежда');
});

test('public owner listing query does not expose non-public statuses', async () => {
  let findManyCalled = false;
  const service = createService({
    findMany: async () => {
      findManyCalled = true;
      return [createApprovedListing('listing-pending', '2026-06-19T10:00:00.000Z')];
    },
  });

  const response = await service.findAll({
    ownerId: 'owner-2',
    status: 'pending',
  });

  assert.equal(findManyCalled, false);
  assert.deepEqual(response.items, []);
  assert.equal(response.hasMore, false);
});

test('public owner listing query keeps approved owner listings public-compatible', async () => {
  let findManyArgs: Record<string, any> | undefined;
  const service = createService({
    findMany: async (args?: Record<string, unknown>) => {
      findManyArgs = args as Record<string, any>;
      return [createApprovedListing('listing-approved', '2026-06-19T10:00:00.000Z')];
    },
  });

  const response = await service.findAll({
    ownerId: 'owner-2',
    status: 'approved',
  });

  assert.equal(response.items.length, 1);
  assert.equal(findManyArgs?.where?.ownerId, 'owner-2');
  assert.equal(findManyArgs?.where?.status, ListingStatus.APPROVED);
  assert.deepEqual(findManyArgs?.where?.photos, { some: {} });
  assert.deepEqual(findManyArgs?.where?.owner, {
    deletedAt: null,
    status: UserStatus.ACTIVE,
  });
});

test('public owner archive mode only exposes archived and sold statuses', async () => {
  let findManyArgs: Record<string, any> | undefined;
  const archived = {
    ...createApprovedListing('listing-archived', '2026-06-19T10:00:00.000Z'),
    status: ListingStatus.ARCHIVED,
    archivedAt: new Date('2026-06-20T10:00:00.000Z'),
  };
  const sold = {
    ...createApprovedListing('listing-sold', '2026-06-18T10:00:00.000Z'),
    status: ListingStatus.SOLD,
    archivedAt: new Date('2026-06-21T10:00:00.000Z'),
  };
  const service = createService({
    findMany: async (args?: Record<string, unknown>) => {
      findManyArgs = args as Record<string, any>;
      return [archived, sold];
    },
  });

  const response = await service.findAll({
    ownerId: 'owner-2',
    publicMode: 'archive',
    limit: 20,
  });

  assert.deepEqual(
    response.items.map((item: { status: string }) => item.status),
    ['archived', 'sold'],
  );
  assert.equal(findManyArgs?.where?.ownerId, 'owner-2');
  assert.deepEqual(findManyArgs?.where?.status, {
    in: [ListingStatus.ARCHIVED, ListingStatus.SOLD],
  });
  assert.deepEqual(findManyArgs?.where?.photos, { some: {} });
  assert.deepEqual(findManyArgs?.where?.owner, {
    deletedAt: null,
    status: UserStatus.ACTIVE,
  });
});

test('delete last photo is rejected for publishable listing statuses', async () => {
  const service = new ListingsService(
    {
      listing: {
        findUnique: async () => ({
          id: 'listing-1',
          ownerId: ownerUser.userId,
          status: ListingStatus.PENDING,
          photos: [
            {
              id: 'photo-1',
              storageKey: 'listings/listing-1/photo.jpg',
              sortOrder: 0,
            },
          ],
        }),
      },
    } as never,
    { deleteStoredFile: async () => undefined } as never,
    {} as never,
  );

  await assert.rejects(
    () => service.deletePhoto(ownerUser, 'listing-1', 'photo-1'),
    (error) =>
      error instanceof BadRequestException &&
      error.message === 'LISTING_PHOTO_REQUIRED',
  );
});

test('delete one of multiple photos succeeds', async () => {
  const calls: string[] = [];
  const service = new ListingsService(
    {
      listing: {
        findUnique: async () => ({
          id: 'listing-1',
          ownerId: ownerUser.userId,
          status: ListingStatus.APPROVED,
          photos: [
            {
              id: 'photo-1',
              storageKey: 'listings/listing-1/1.jpg',
              sortOrder: 0,
            },
            {
              id: 'photo-2',
              storageKey: 'listings/listing-1/2.jpg',
              sortOrder: 1,
            },
          ],
        }),
        findUniqueOrThrow: async () => ({
          ...createApprovedListing('listing-1', '2026-07-01T10:00:00.000Z'),
          photos: [
            {
              id: 'photo-2',
              listingId: 'listing-1',
              storageBucket: 'local',
              storageKey: 'listings/listing-1/2.jpg',
              publicUrl: 'https://cdn.example.com/2.jpg',
              sortOrder: 0,
              sizeBytes: null,
              mimeType: null,
              createdAt: new Date(),
            },
          ],
        }),
        update: async () => ({}),
      },
      listingPhoto: {
        delete: async (args: Record<string, any>) => {
          calls.push(`delete:${args.where.id}`);
        },
        findMany: async () => [
          {
            id: 'photo-2',
            sortOrder: 1,
          },
        ],
        update: async (args: Record<string, any>) => {
          calls.push(`sort:${args.where.id}:${args.data.sortOrder}`);
        },
      },
    } as never,
    {
      deleteStoredFile: async (_category: string, key: string) => {
        calls.push(`storage:${key}`);
      },
    } as never,
    {} as never,
  );

  const response = await service.deletePhoto(ownerUser, 'listing-1', 'photo-1');

  assert.deepEqual(calls, [
    'storage:listings/listing-1/1.jpg',
    'delete:photo-1',
    'sort:photo-2:0',
  ]);
  assert.equal(response.deleted, true);
});

test('listing serialization normalizes duplicated bucket prefix in S3 photo url', async () => {
  const service = new ListingsService(
    {
      listing: {
        findUnique: async () => ({
          id: 'listing-1',
          ownerId: ownerUser.userId,
          ownerEmail: null,
          ownerName: 'ATTA User',
          title: 'Listing',
          description: '',
          category: 'misc',
          subcategory: '',
          price: BigInt(0),
          phone: '',
          phoneHidden: false,
          city: '',
          address: '',
          latitude: null,
          longitude: null,
          locationJson: {},
          delivery: {},
          car: null,
          dealType: null,
          realEstateType: null,
          clothesType: null,
          status: ListingStatus.APPROVED,
          rejectionReason: '',
          moderationNote: null,
          moderatedBy: null,
          moderatedAt: null,
          publishedAt: new Date(),
          archivedAt: null,
          deletedAt: null,
          viewCount: 0,
          createdAt: new Date(),
          updatedAt: new Date(),
          owner: null,
          promotions: [],
          photos: [
            {
              id: 'photo-1',
              listingId: 'listing-1',
              storageBucket: 'atta-media-prod',
              storageKey:
                'atta-media-prod/listing-photos/1782423161346-photo.jpg',
              publicUrl:
                'https://s3.twcstorage.ru/atta-media-prod/atta-media-prod/listing-photos/1782423161346-photo.jpg',
              sortOrder: 0,
              sizeBytes: 128,
              mimeType: 'image/jpeg',
              createdAt: new Date(),
            },
          ],
        }),
      },
    } as never,
    {} as never,
    {
      enrichListing: (listing: unknown) => listing,
    } as never,
  );

  const response = await service.findOne('listing-1', ownerUser);

  assert.equal(
    response.listing.photo_urls[0],
    '/media/object?category=listings&key=atta-media-prod%2Flisting-photos%2F1782423161346-photo.jpg',
  );
  assert.equal(
    response.listing.photo_items[0].url,
    '/media/object?category=listings&key=atta-media-prod%2Flisting-photos%2F1782423161346-photo.jpg',
  );
});
