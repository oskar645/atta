import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ListingStatus, PromotionStatus, UserStatus } from '@prisma/client';

import { FavoritesService } from './favorites.service';

test('favorites list is sorted by createdAt desc', async () => {
  let capturedOrderBy: unknown;

  const service = new FavoritesService(
    {
      favorite: {
        findMany: async (args: Record<string, unknown>) => {
          capturedOrderBy = args['orderBy'];
          return [];
        },
      },
      listing: {
        findMany: async () => [],
      },
    } as any,
  );

  await service.list({ userId: 'user-1' } as any);

  assert.deepEqual(capturedOrderBy, [{ createdAt: 'desc' }, { id: 'desc' }]);
});

test('favorites list keeps compatible fields and embeds visible listings', async () => {
  const favorites = [
    favoriteFixture('favorite-2', 'listing-2', new Date('2026-01-02T00:00:00.000Z')),
    favoriteFixture('favorite-1', 'listing-1', new Date('2026-01-01T00:00:00.000Z')),
  ];

  const service = new FavoritesService(
    {
      favorite: {
        findMany: async () => favorites,
      },
      listing: {
        findMany: async () => [
          listingFixture('listing-1'),
          listingFixture('listing-2'),
        ],
      },
    } as any,
  );

  const response = await service.list({ userId: 'user-1' } as any);

  assert.deepEqual(response.favorite_ids, ['listing-2', 'listing-1']);
  assert.equal(response.items[0]?.id, 'favorite-2');
  assert.equal(response.items[0]?.user_id, 'user-1');
  assert.equal(response.items[0]?.listing_id, 'listing-2');
  assert.equal(response.items[0]?.created_at, '2026-01-02T00:00:00.000Z');
  assert.equal(response.items[0]?.listing?.id, 'listing-2');
  assert.equal(response.items[1]?.listing?.id, 'listing-1');
});

test('favorites list fetches page listings in one batch and preserves order', async () => {
  let listingFindManyCalls = 0;
  let listingWhere: unknown;
  const favorites = [
    favoriteFixture('favorite-3', 'listing-3', new Date('2026-01-03T00:00:00.000Z')),
    favoriteFixture('favorite-2', 'listing-2', new Date('2026-01-02T00:00:00.000Z')),
    favoriteFixture('favorite-1', 'listing-1', new Date('2026-01-01T00:00:00.000Z')),
  ];

  const service = new FavoritesService(
    {
      favorite: {
        findMany: async () => favorites,
      },
      listing: {
        findMany: async (args: Record<string, unknown>) => {
          listingFindManyCalls += 1;
          listingWhere = args['where'];
          return [
            listingFixture('listing-1'),
            listingFixture('listing-2'),
            listingFixture('listing-3'),
          ];
        },
      },
    } as any,
  );

  const response = await service.list({ userId: 'user-1' } as any);

  assert.equal(listingFindManyCalls, 1);
  assert.deepEqual(listingWhere, {
    id: {
      in: ['listing-3', 'listing-2', 'listing-1'],
    },
  });
  assert.deepEqual(
    response.items.map((item) => item.listing_id),
    ['listing-3', 'listing-2', 'listing-1'],
  );
  assert.deepEqual(
    response.items.map((item) => item.listing?.id),
    ['listing-3', 'listing-2', 'listing-1'],
  );
});

test('favorites list does not embed hidden listings for non-owner users', async () => {
  const favorite = favoriteFixture(
    'favorite-1',
    'listing-hidden',
    new Date('2026-01-01T00:00:00.000Z'),
  );
  const service = new FavoritesService(
    {
      favorite: {
        findMany: async () => [favorite],
      },
      listing: {
        findMany: async () => [
          listingFixture('listing-hidden', {
            status: ListingStatus.PENDING,
            ownerId: 'owner-1',
          }),
        ],
      },
    } as any,
  );

  const response = await service.list({ userId: 'user-1' } as any);

  assert.deepEqual(response.favorite_ids, ['listing-hidden']);
  assert.equal(response.items[0]?.listing_id, 'listing-hidden');
  assert.equal('listing' in response.items[0]!, false);
});

test('favorites list embeds owner/admin accessible non-public listings', async () => {
  const favorite = favoriteFixture(
    'favorite-1',
    'listing-pending',
    new Date('2026-01-01T00:00:00.000Z'),
  );
  const service = new FavoritesService(
    {
      favorite: {
        findMany: async () => [favorite],
      },
      listing: {
        findMany: async () => [
          listingFixture('listing-pending', {
            status: ListingStatus.PENDING,
            ownerId: 'user-1',
          }),
        ],
      },
    } as any,
  );

  const response = await service.list({ userId: 'user-1' } as any);

  assert.equal(response.items[0]?.listing?.id, 'listing-pending');
  assert.equal(response.items[0]?.listing?.status, 'pending');
});

test('favorites list pagination cursor contract is unchanged', async () => {
  const favorites = [
    favoriteFixture('favorite-3', 'listing-3', new Date('2026-01-03T00:00:00.000Z')),
    favoriteFixture('favorite-2', 'listing-2', new Date('2026-01-02T00:00:00.000Z')),
  ];
  const service = new FavoritesService(
    {
      favorite: {
        findMany: async () => favorites,
      },
      listing: {
        findMany: async () => [listingFixture('listing-3')],
      },
    } as any,
  );

  const response = await service.list({ userId: 'user-1' } as any, {
    limit: 1,
  });

  assert.deepEqual(response.favorite_ids, ['listing-3']);
  assert.equal(response.items.length, 1);
  assert.equal(response.hasMore, true);
  assert.equal(response.limit, 1);
  assert.equal(typeof response.nextCursor, 'string');
});

const favoriteFixture = (id: string, listingId: string, createdAt: Date) => ({
  id,
  userId: 'user-1',
  listingId,
  createdAt,
});

const listingFixture = (
  id: string,
  overrides: Record<string, unknown> = {},
) => ({
  ...listingFixtureBase(id),
  ...overrides,
});

const listingFixtureBase = (id: string) => ({
  id,
  ownerId: 'owner-1',
  ownerEmail: 'owner@example.com',
  ownerName: 'Owner',
  title: `Listing ${id}`,
  description: 'Description',
  category: 'Все',
  subcategory: '',
  price: BigInt(1000),
  previousPrice: null,
  priceReducedAt: null,
  phone: '+79990000000',
  phoneHidden: false,
  city: 'Город',
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
  oemPartNumber: null,
  viewCount: 0,
  status: ListingStatus.APPROVED,
  rejectionReason: '',
  moderationNote: null,
  moderatedBy: null,
  moderatedAt: null,
  publishedAt: new Date('2026-01-01T00:00:00.000Z'),
  archivedAt: null,
  deletedAt: null,
  createdAt: new Date('2026-01-01T00:00:00.000Z'),
  updatedAt: new Date('2026-01-01T00:00:00.000Z'),
  photos: [
    {
      id: `${id}-photo`,
      publicUrl: 'https://example.com/photo.jpg',
      storageBucket: 'local',
      storageKey: `listings/${id}/photo.jpg`,
      sortOrder: 0,
    },
  ],
  promotions: [
    {
      type: 'VIP',
      status: PromotionStatus.EXPIRED,
      endsAt: new Date('2026-01-01T00:00:00.000Z'),
      createdAt: new Date('2026-01-01T00:00:00.000Z'),
    },
  ],
  owner: {
    id: 'owner-1',
    email: 'owner@example.com',
    phone: '+79990000000',
    phoneVerified: true,
    displayName: 'Owner',
    name: 'Owner',
    avatarUrl: null,
    photoUrl: null,
    status: UserStatus.ACTIVE,
    blockedAt: null,
    blockReason: null,
    lastLoginAt: null,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-01T00:00:00.000Z'),
    deletedAt: null,
    adminProfile: null,
  },
});
