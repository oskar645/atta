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
    clothesSize: null,
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

function createService(overrides?: {
  findOwnerById?: () => Promise<unknown>;
  create?: (args: Record<string, unknown>) => Promise<unknown>;
  findUnique?: () => Promise<unknown>;
  update?: (args: Record<string, unknown>) => Promise<unknown>;
  findMany?: (args?: Record<string, unknown>) => Promise<unknown>;
  findFavorites?: (args?: Record<string, unknown>) => Promise<unknown>;
  queryRaw?: (strings: TemplateStringsArray, ...values: unknown[]) => Promise<unknown>;
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
    ...(overrides?.queryRaw ? { $queryRaw: overrides.queryRaw } : {}),
  };

  return new ListingsService(
    prisma as never,
    {} as never,
    {} as never,
  );
}

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
  'promotions'
> & {
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

function rawRowForListing(
  listing: TestApprovedListing,
  sortGroup: number,
  promotedAt: Date | null = null,
): RawFeedRow {
  const sortAt = listing.publishedAt ?? listing.createdAt;
  return {
    id: listing.id,
    promoted_at: promotedAt,
    sort_group: sortGroup,
    sort_at: sortAt,
    published_at: listing.publishedAt,
    created_at: listing.createdAt,
  };
}

function uuidFromNumber(value: number) {
  return `00000000-0000-4000-8000-${value.toString().padStart(12, '0')}`;
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
  const orderedRows = orderedListings.map((listing, index) =>
    rawRowForListing(
      listing,
      index + 1,
      options?.promotedIds?.[listing.id] != null
        ? new Date(options.promotedIds[listing.id]!)
        : null,
    ),
  );
  const rawCalls: Array<{ text: string; values: unknown[]; cursorId: unknown }> = [];

  const service = createService({
    queryRaw: async (strings: TemplateStringsArray, ...values: unknown[]) => {
      const flattened = flattenSql(strings, values);
      const cursorId = findCursorUuidValue(strings, values);
      rawCalls.push({ ...flattened, cursorId });

      let filteredRows = orderedRows;
      if (flattened.values.includes('auto')) {
        filteredRows = filteredRows.filter(
          (row) => listingsById.get(row.id)?.category === 'auto',
        );
      }
      const searchPattern = flattened.values.find(
        (value): value is string =>
          typeof value === 'string' && value.startsWith('%') && value.endsWith('%'),
      );
      if (searchPattern) {
        const search = searchPattern.slice(1, -1).toLowerCase();
        filteredRows = filteredRows.filter((row) => {
          const listing = listingsById.get(row.id);
          return (
            listing?.title.toLowerCase().includes(search) ||
            listing?.description.toLowerCase().includes(search) ||
            listing?.category.toLowerCase().includes(search)
          );
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
        dealType: null,
        realEstateType: null,
        clothesType: null,
        clothesSize: null,
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

  assert.deepEqual(ids.slice(8, 10), ['listing-12', 'listing-13']);
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

test('public feed $queryRaw cursor remains stable with protected top-10 and many active promotions', async () => {
  const regularHead = Array.from({ length: 9 }, (_, index) =>
    createApprovedListing(
      uuidFromNumber(300 - index),
      `2026-07-02T11:${(59 - index).toString().padStart(2, '0')}:00.000Z`,
    ),
  );
  const promoted = Array.from({ length: 12 }, (_, index) => ({
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
  const orderedListings = [...regularHead, ...promoted, ...expired];
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

  const ids = [
    ...firstPage.items.map((item: { id: string }) => item.id),
    ...secondPage.items.map((item: { id: string }) => item.id),
    ...thirdPage.items.map((item: { id: string }) => item.id),
  ];

  assert.deepEqual(firstPage.items.slice(0, 9).map((item: { id: string }) => item.id), regularHead.map((listing) => listing.id));
  assert.equal(firstPage.items[9]!.id, promoted[0]!.id);
  assert.ok(secondPage.items.some((item: { id: string }) => item.id === promoted[10]!.id));
  assert.ok(thirdPage.items.some((item: { id: string }) => item.id === expired[0]!.id));
  assert.equal(firstPage.hasMore, true);
  assert.equal(secondPage.hasMore, true);
  assert.equal(thirdPage.hasMore, false);
  assert.equal(ids.length, orderedListings.length);
  assert.equal(new Set(ids).size, orderedListings.length);
  assert.deepEqual(ids, orderedListings.map((listing) => listing.id));
  assert.match(rawCalls[0]!.text, /PROTECTED_FEED_HEAD_SIZE|natural_rank|moved_count|promoted_at/);
  assert.match(rawCalls[1]!.text, /"id"\s*<\s*\$\d+::uuid/);
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
