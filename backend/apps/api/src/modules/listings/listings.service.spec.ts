import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ForbiddenException, NotFoundException } from '@nestjs/common';
import {
  ListingStatus,
  PromotionStatus,
  PromotionType,
  UserStatus,
} from '@prisma/client';

import { ListingsService } from './listings.service';

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

function createApprovedListing(
  id: string,
  publishedAt: string,
  category = 'misc',
) {
  const published = new Date(publishedAt);
  return {
    id,
    ownerId: ownerUser.userId,
    ownerEmail: 'owner@example.com',
    ownerName: 'Owner',
    title: `Listing ${id}`,
    description: '',
    category,
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

function createService(overrides?: {
  findOwnerById?: () => Promise<unknown>;
  create?: (args: Record<string, unknown>) => Promise<unknown>;
  findUnique?: () => Promise<unknown>;
  update?: (args: Record<string, unknown>) => Promise<unknown>;
  findMany?: (args?: Record<string, unknown>) => Promise<unknown>;
  findFavorites?: (args?: Record<string, unknown>) => Promise<unknown>;
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
    favorite: {
      findMany: overrides?.findFavorites ?? (async () => []),
    },
    $transaction: async <T>(handler: () => Promise<T>) => handler(),
  };

  return new ListingsService(
    prisma as never,
    {} as never,
    {} as never,
  );
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
  let savedListing = listing;
  const prisma = {
    listing: {
      findUnique: async () => ({
        ...listing,
        owner: {
          phone: '79281234567',
        },
      }),
      update: async (args: Record<string, unknown>) => {
        updateArgs = args;
        savedListing = {
          ...savedListing,
          ...(args.data as Record<string, unknown>),
          updatedAt: new Date(),
        } as typeof listing;
        return savedListing;
      },
      findUniqueOrThrow: async () => savedListing,
    },
    listingPhoto: {
      deleteMany: async () => ({}),
      createMany: async () => ({}),
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
  assert.equal(response.listing.status, 'pending');
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

test('public feed is sorted by publishedAt desc, then createdAt desc, then id desc', async () => {
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

test('public feed keeps first 8 regular listings before paid block', async () => {
  const ordinary = Array.from({ length: 10 }, (_, index) =>
    createApprovedListing(
      `listing-${10 - index}`,
      `2026-06-19T10:${(59 - index).toString().padStart(2, '0')}:00.000Z`,
    ),
  );
  const boosted = {
    ...createApprovedListing('listing-boosted', '2026-06-19T09:10:00.000Z'),
    promotions: [createPromotion(PromotionType.BUMP, '2026-06-19T11:00:00.000Z')],
  };
  const service = createService({
    findMany: async () => [...ordinary, boosted],
  });

  const response = await service.findAll();

  assert.deepEqual(
    response.items.map((item: { id: string }) => item.id),
    [
      'listing-10',
      'listing-9',
      'listing-8',
      'listing-7',
      'listing-6',
      'listing-5',
      'listing-4',
      'listing-3',
      'listing-boosted',
      'listing-2',
      'listing-1',
    ],
  );
});

test('paid block sorts vip above bump and newer activations first', async () => {
  const service = createService({
    findMany: async () => [
      ...Array.from({ length: 8 }, (_, index) =>
        createApprovedListing(
          `listing-head-${index + 1}`,
          `2026-06-19T10:${(59 - index).toString().padStart(2, '0')}:00.000Z`,
        ),
      ),
      {
        ...createApprovedListing('listing-bump', '2026-06-19T08:00:00.000Z'),
        promotions: [createPromotion(PromotionType.BUMP, '2026-06-19T11:00:00.000Z')],
      },
      {
        ...createApprovedListing('listing-vip-new', '2026-06-19T07:00:00.000Z'),
        promotions: [createPromotion(PromotionType.VIP, '2026-06-19T12:00:00.000Z')],
      },
      {
        ...createApprovedListing('listing-vip-old', '2026-06-19T06:00:00.000Z'),
        promotions: [createPromotion(PromotionType.VIP, '2026-06-19T10:30:00.000Z')],
      },
    ],
  });

  const response = await service.findAll();

  assert.deepEqual(response.items.slice(8, 11).map((item: { id: string }) => item.id), [
    'listing-vip-new',
    'listing-vip-old',
    'listing-bump',
  ]);
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

test('public feed keeps paid block stable across pagination without duplicates', async () => {
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
    findMany: async () => [...ordinary, ...paid],
  });

  const firstPage = await service.findAll({ limit: 10 });
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
      'listing-vip',
      'listing-bump',
    ],
  );
  assert.deepEqual(
    secondPage.items.map((item: { id: string }) => item.id),
    ['listing-2', 'listing-1'],
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
      return listings;
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
