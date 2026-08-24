import { test } from 'node:test';
import assert from 'node:assert/strict';

import { BadRequestException } from '@nestjs/common';
import {
  ListingStatus,
  ReferralRewardStatus,
  UserStatus,
  WalletTransactionType,
} from '@prisma/client';

import { buildReferralCode } from '../../common/referral-code';
import { AdminService } from './admin.service';

const adminUser = {
  userId: 'admin-1',
  sessionId: 'session-1',
  role: 'admin' as const,
};

test('moderation list uses pending filter without deleted or archived items', async () => {
  let capturedWhere: Record<string, unknown> | undefined;

  const service = new AdminService(
    {
      listing: {
        findMany: async (args: Record<string, unknown>) => {
          capturedWhere = args['where'] as Record<string, unknown> | undefined;
          return [];
        },
        count: async () => 0,
      },
      user: { count: async () => 0 },
      userPresence: { count: async () => 0 },
      supportTicket: { count: async () => 0 },
      report: { count: async () => 0 },
      feedAd: { count: async () => 0 },
      promotion: { aggregate: async () => ({ _sum: { price: 0 } }) },
      walletTransaction: { aggregate: async () => ({ _sum: { amount: 0 } }) },
      $queryRaw: async () => [],
    } as any,
    { countToday: async () => 0, listToday: async () => ({ items: [] }) } as any,
    { countToday: async () => 0, listToday: async () => ({ items: [] }) } as any,
    { countToday: async () => 0, listToday: async () => ({ items: [] }) } as any,
    {} as any,
    {} as any,
  );

  await service.listListings('pending');

  assert.deepEqual(capturedWhere, {
    deletedAt: null,
    archivedAt: null,
    status: ListingStatus.PENDING,
  });
});

test('users list excludes soft-deleted users', async () => {
  let capturedWhere: Record<string, unknown> | undefined;

  const service = new AdminService(
    {
      listing: {
        findMany: async () => [],
        count: async () => 0,
      },
      user: {
        findMany: async (args: Record<string, unknown>) => {
          capturedWhere = args['where'] as Record<string, unknown> | undefined;
          return [];
        },
        count: async () => 0,
      },
      userPresence: { count: async () => 0 },
      supportTicket: { count: async () => 0 },
      report: { count: async () => 0 },
      feedAd: { count: async () => 0 },
      promotion: { aggregate: async () => ({ _sum: { price: 0 } }) },
      walletTransaction: { aggregate: async () => ({ _sum: { amount: 0 } }) },
      $queryRaw: async () => [],
    } as any,
    { countToday: async () => 0, listToday: async () => ({ items: [] }) } as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
  );

  await service.listUsers();

  assert.deepEqual(capturedWhere, {
    deletedAt: null,
    status: {
      not: UserStatus.DELETED,
    },
  });
});

test('dashboard stats count spent wallet points for last 30 days', async () => {
  let capturedUserCountWhere: Record<string, unknown> | undefined;
  let capturedWalletAggregateWhere: Record<string, unknown> | undefined;

  const service = new AdminService(
    {
      listing: {
        count: async () => 0,
        findMany: async () => [],
      },
      user: {
        count: async (args?: Record<string, unknown>) => {
          capturedUserCountWhere = args?.['where'] as
            | Record<string, unknown>
            | undefined;
          return 5;
        },
      },
      userPresence: { count: async () => 0 },
      supportTicket: { count: async () => 0 },
      report: { count: async () => 0 },
      feedAd: { count: async () => 0 },
      walletTransaction: {
        aggregate: async (args: Record<string, unknown>) => {
          capturedWalletAggregateWhere =
            (args['where'] as Record<string, unknown> | undefined);
          return { _sum: { amount: 415 } };
        },
      },
      $queryRaw: async () => [
        {
          total_amount_rub: '0',
          total_points: BigInt(0),
          purchases_count: BigInt(0),
          unique_buyers_count: BigInt(0),
        },
      ],
    } as any,
    { countToday: async () => 0, listToday: async () => ({ items: [] }) } as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
  );

  const result = await service.getDashboardStats();

  assert.equal(result.stats.spentPoints30d, 415);
  assert.deepEqual(capturedUserCountWhere, {
    deletedAt: null,
    status: {
      not: UserStatus.DELETED,
    },
  });
  assert.equal(
    capturedWalletAggregateWhere?.['type'],
    WalletTransactionType.SPEND,
  );
  assert.equal(
    typeof (capturedWalletAggregateWhere?.['createdAt'] as Record<string, unknown>)
      ?.['gte'],
    'object',
  );
});

test('referral search returns user A personal stats and not app summary', async () => {
  const { service, users } = createReferralSearchService();

  const result = await service.listReferrals({ search: 'Alice' });
  const item = result.items[0] as any;

  assert.equal(result.items.length, 1);
  assert.equal(item.inviter.id, users.a.id);
  assert.equal(item.openedCount, 2);
  assert.equal(item.registeredCount, 1);
  assert.equal(item.rewardedCount, 1);
  assert.equal(item.referralPoints, 50);
  assert.equal(item.unfinishedCount, 1);
  assert.equal(item.rejectedCount, 1);
});

test('referral search returns different stats for users A and B', async () => {
  const { service, users } = createReferralSearchService();

  const resultA = await service.listReferrals({ search: 'Alice' });
  const resultB = await service.listReferrals({ search: 'Bob' });
  const itemA = resultA.items[0] as any;
  const itemB = resultB.items[0] as any;

  assert.equal(itemA.inviter.id, users.a.id);
  assert.equal(itemB.inviter.id, users.b.id);
  assert.notDeepEqual(
    {
      opened: itemA.openedCount,
      registered: itemA.registeredCount,
      rewarded: itemA.rewardedCount,
      points: itemA.referralPoints,
    },
    {
      opened: itemB.openedCount,
      registered: itemB.registeredCount,
      rewarded: itemB.rewardedCount,
      points: itemB.referralPoints,
    },
  );
});

test('referral search supports phone, nickname/name, referralCode and userId', async () => {
  const { service, users } = createReferralSearchService();

  const byPhone = await service.listReferrals({ search: '+7 (999) 111-22-33' });
  const byNickname = await service.listReferrals({ search: 'alice_nick' });
  const byName = await service.listReferrals({ search: 'Alice' });
  const byReferralCode = await service.listReferrals({
    search: buildReferralCode(users.b.id),
  });
  const byUserId = await service.listReferrals({ userId: users.b.id });

  assert.equal((byPhone.items[0] as any).inviter.id, users.a.id);
  assert.equal((byNickname.items[0] as any).inviter.id, users.a.id);
  assert.equal((byName.items[0] as any).inviter.id, users.a.id);
  assert.equal((byReferralCode.items[0] as any).inviter.id, users.b.id);
  assert.equal((byUserId.items[0] as any).inviter.id, users.b.id);
});

test('referral search returns empty items for no matches', async () => {
  const { service } = createReferralSearchService();

  const result = await service.listReferrals({ search: 'nobody' });

  assert.deepEqual(result.items, []);
});

test('empty referral search keeps global inviter list separate from summary', async () => {
  const { service } = createReferralSearchService();

  const list = await service.listReferrals({});
  const summary = await service.getReferralSummary({});

  assert.equal(list.items.length, 2);
  assert.equal(summary.newRegistrationsByInvite, 2);
  assert.equal(summary.rewardedReferralBonuses, 2);
  assert.equal(summary.referralPointsAwarded, 80);
  assert.equal((list.items[0] as any).newRegistrationsByInvite, undefined);
  assert.equal((list.items[0] as any).referralPointsAwarded, undefined);
});

test('moderator cannot approve listing without photos', async () => {
  const service = createApproveListingService({
    photos: [],
    status: ListingStatus.PENDING,
  });

  await assert.rejects(
    () => service.approveListing('listing-1', adminUser),
    (error) =>
      error instanceof BadRequestException &&
      error.message === 'LISTING_PHOTO_REQUIRED',
  );
});

test('moderator can approve listing with one photo', async () => {
  let updateArgs: Record<string, any> | undefined;
  const service = createApproveListingService({
    photos: [listingPhoto('photo-1')],
    status: ListingStatus.PENDING,
    onUpdate: (args) => {
      updateArgs = args;
    },
  });

  const response = await service.approveListing('listing-1', adminUser);

  assert.equal(updateArgs?.data.status, ListingStatus.APPROVED);
  assert.ok(updateArgs?.data.publishedAt instanceof Date);
  assert.equal(response.listing.status, 'approved');
  assert.equal(response.listing.photo_urls.length, 1);
});

test('moderator approval records price reduction from public snapshot', async () => {
  let updateArgs: Record<string, any> | undefined;
  const service = createApproveListingService({
    photos: [listingPhoto('photo-1')],
    status: ListingStatus.PENDING,
    price: BigInt(9000),
    moderationSnapshot: {
      price: '10000',
    },
    onUpdate: (args) => {
      updateArgs = args;
    },
  });

  await service.approveListing('listing-1', adminUser);

  assert.equal(updateArgs?.data.previousPrice, BigInt(10000));
  assert.ok(updateArgs?.data.priceReducedAt instanceof Date);
});

test('moderator approval clears price reduction on public increase', async () => {
  let updateArgs: Record<string, any> | undefined;
  const service = createApproveListingService({
    photos: [listingPhoto('photo-1')],
    status: ListingStatus.PENDING,
    price: BigInt(11000),
    moderationSnapshot: {
      price: '9000',
    },
    onUpdate: (args) => {
      updateArgs = args;
    },
  });

  await service.approveListing('listing-1', adminUser);

  assert.equal(updateArgs?.data.previousPrice, null);
  assert.equal(updateArgs?.data.priceReducedAt, null);
});

test('re-moderation without photos is rejected', async () => {
  const service = createApproveListingService({
    photos: [],
    status: ListingStatus.REJECTED,
  });

  await assert.rejects(
    () => service.approveListing('listing-1', adminUser),
    (error) =>
      error instanceof BadRequestException &&
      error.message === 'LISTING_PHOTO_REQUIRED',
  );
});

test('points purchases summary serializes successful paid totals', async () => {
  const service = new AdminService(
    {
      $queryRaw: async () => [
        {
          total_amount_rub: '24500.00',
          total_points: BigInt(24500),
          purchases_count: BigInt(37),
          unique_buyers_count: BigInt(18),
        },
      ],
    } as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
  );

  const result = await service.getPointsPurchasesSummary({
    from: '2026-08-01T00:00:00.000Z',
    to: '2026-08-08T12:00:00.000Z',
  });

  assert.equal(result.totalAmountRub, 24500);
  assert.equal(result.totalPoints, 24500);
  assert.equal(result.purchasesCount, 37);
  assert.equal(result.uniqueBuyersCount, 18);
});

test('points purchases list masks phone and returns cursor for next page', async () => {
  const createdAt = new Date('2026-08-08T12:00:00.000Z');
  const rows = [0, 1].map((index) => ({
    payment_id:
      index === 0
        ? '11111111-1111-4111-8111-111111111111'
        : '22222222-2222-4222-8222-222222222222',
    user_id: '33333333-3333-4333-8333-333333333333',
    display_name: 'Alice',
    username: 'alice_nick',
    phone: '+7 (999) 111-22-33',
    amount_rub: '500.00',
    points: 500,
    status: 'SUCCEEDED',
    created_at: createdAt,
  }));
  const service = new AdminService(
    {
      $queryRaw: async () => rows,
    } as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
  );

  const result = await service.listPointsPurchases({
    from: '2026-08-01T00:00:00.000Z',
    to: '2026-08-08T12:00:00.000Z',
    limit: 1,
  });

  assert.equal(result.items.length, 1);
  assert.equal((result.items[0] as any).phone, '***2233');
  assert.equal((result.items[0] as any).status, 'Оплачено');
  assert.equal(result.nextCursor != null, true);
});

function createReferralSearchService() {
  const now = new Date('2026-08-04T10:00:00.000Z');
  const users = {
    a: referralUser({
      id: '11111111-1111-4111-8111-111111111111',
      displayName: 'alice_nick',
      name: 'Alice A',
      phone: '+79991112233',
      createdAt: now,
    }),
    b: referralUser({
      id: '22222222-2222-4222-8222-222222222222',
      displayName: 'bob_nick',
      name: 'Bob B',
      phone: '+79994445566',
      createdAt: now,
    }),
    invitedA: referralUser({
      id: '33333333-3333-4333-8333-333333333333',
      displayName: 'invited_a',
      name: 'Invited A',
      phone: '+79990000001',
      createdAt: now,
    }),
    invitedB: referralUser({
      id: '44444444-4444-4444-8444-444444444444',
      displayName: 'invited_b',
      name: 'Invited B',
      phone: '+79990000002',
      createdAt: now,
    }),
  };
  const referrals = [
    referralRecord({
      id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      inviter: users.a,
      invited: users.invitedA,
      rewardStatus: ReferralRewardStatus.REWARDED,
      rewardAmount: 50,
      openedAt: now,
      registeredAt: now,
    }),
    referralRecord({
      id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      inviter: users.a,
      invited: null,
      rewardStatus: ReferralRewardStatus.NOT_REWARDED,
      rewardAmount: 0,
      openedAt: now,
      registeredAt: null,
      failureReason: 'USER_ALREADY_REGISTERED',
    }),
    referralRecord({
      id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      inviter: users.b,
      invited: users.invitedB,
      rewardStatus: ReferralRewardStatus.REWARDED,
      rewardAmount: 30,
      openedAt: now,
      registeredAt: now,
    }),
  ];
  const allUsers = Object.values(users);
  const prisma = {
    user: {
      findMany: async (args: any) => allUsers.filter((user) => matchesUserWhere(user, args.where)),
      findFirst: async (args: any) =>
        allUsers.find((user) => user.id === args.where.id) ?? null,
    },
    referral: {
      findMany: async (args: any) => {
        const inviterUserId = args.where?.inviterUserId;
        if (inviterUserId) {
          return referrals.filter((item) => item.inviterUserId === inviterUserId);
        }
        return referrals;
      },
    },
    walletTransaction: {
      aggregate: async () => ({ _sum: { amount: 0 } }),
    },
  };

  const service = new AdminService(
    prisma as any,
    { countToday: async () => 0, listToday: async () => ({ items: [] }) } as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
  );
  return { service, users };
}

function createApproveListingService(params: {
  photos: ReturnType<typeof listingPhoto>[];
  status: ListingStatus;
  price?: bigint;
  moderationSnapshot?: Record<string, unknown>;
  onUpdate?: (args: Record<string, any>) => void;
}) {
  return new AdminService(
    {
      listing: {
        findUnique: async () =>
          listingForModeration(params.status, params.photos, {
            price: params.price,
            moderationSnapshot: params.moderationSnapshot,
          }),
        update: async (args: Record<string, any>) => {
          params.onUpdate?.(args);
          return {
            ...listingForModeration(
              (args.data as { status: ListingStatus }).status,
              params.photos,
              {
                price: params.price,
                previousPrice:
                  (args.data as { previousPrice?: bigint | null }).previousPrice ??
                  null,
                priceReducedAt:
                  (args.data as { priceReducedAt?: Date | null }).priceReducedAt ??
                  null,
              },
            ),
            rejectionReason:
              (args.data as { rejectionReason?: string | null }).rejectionReason ??
              null,
            moderationNote:
              (args.data as { moderationNote?: string | null }).moderationNote ??
              null,
            moderatedBy:
              (args.data as { moderatedBy?: string | null }).moderatedBy ?? null,
            moderatedAt:
              (args.data as { moderatedAt?: Date | null }).moderatedAt ?? null,
            publishedAt:
              (args.data as { publishedAt?: Date | null }).publishedAt ?? null,
          };
        },
      },
    } as any,
    {} as any,
    {
      createSystemNotification: async () => undefined,
    } as any,
    {} as any,
    {} as any,
    {} as any,
  );
}

function listingForModeration(
  status: ListingStatus,
  photos: ReturnType<typeof listingPhoto>[],
  options?: {
    price?: bigint;
    previousPrice?: bigint | null;
    priceReducedAt?: Date | null;
    moderationSnapshot?: Record<string, unknown>;
  },
) {
  const now = new Date('2026-08-04T10:00:00.000Z');
  return {
    id: 'listing-1',
    ownerId: 'owner-1',
    ownerEmail: 'owner@example.com',
    ownerName: 'Owner',
    title: 'Listing',
    description: 'Description',
    category: 'misc',
    subcategory: '',
    price: options?.price ?? BigInt(100),
    previousPrice: options?.previousPrice ?? null,
    priceReducedAt: options?.priceReducedAt ?? null,
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
    status,
    rejectionReason: null,
    moderationNote: null,
    moderatedBy: null,
    moderatedAt: null,
    publishedAt: null,
    archivedAt: null,
    deletedAt: null,
    viewCount: 0,
    createdAt: now,
    updatedAt: now,
    owner: {
      id: 'owner-1',
      email: 'owner@example.com',
      phone: '',
      phoneVerified: true,
      displayName: 'Owner',
      name: 'Owner',
      avatarUrl: null,
      photoUrl: null,
      status: UserStatus.ACTIVE,
      blockedAt: null,
      blockReason: null,
      lastLoginAt: null,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      adminProfile: null,
    },
    photos,
    moderationRevisions: options?.moderationSnapshot
      ? [
          {
            snapshot: options.moderationSnapshot,
          },
        ]
      : [],
  };
}

function listingPhoto(id: string) {
  return {
    id,
    listingId: 'listing-1',
    storageBucket: 'local',
    storageKey: `listings/listing-1/${id}.jpg`,
    publicUrl: `https://cdn.example.com/${id}.jpg`,
    sortOrder: 0,
    sizeBytes: null,
    mimeType: 'image/jpeg',
    createdAt: new Date('2026-08-04T10:00:00.000Z'),
  };
}

function referralUser(overrides: Record<string, unknown>) {
  return {
    id: '',
    displayName: '',
    name: '',
    phone: null,
    avatarUrl: null,
    photoUrl: null,
    adminProfile: null,
    createdAt: new Date('2026-08-04T10:00:00.000Z'),
    updatedAt: new Date('2026-08-04T10:00:00.000Z'),
    ...overrides,
  };
}

function referralRecord(overrides: Record<string, unknown>) {
  const inviter = overrides.inviter as any;
  const invited = (overrides.invited as any | null) ?? null;
  return {
    id: '',
    inviter,
    invited,
    inviterUserId: inviter.id,
    invitedUserId: invited?.id ?? null,
    referralCode: buildReferralCode(inviter.id),
    openedAt: null,
    appOpenedAt: null,
    signupStartedAt: null,
    registeredAt: null,
    isNewUser: true,
    rewardStatus: ReferralRewardStatus.PENDING,
    rewardAmount: 0,
    rewardedAt: null,
    failureReason: null,
    walletTransactionId: null,
    createdAt: new Date('2026-08-04T10:00:00.000Z'),
    updatedAt: new Date('2026-08-04T10:00:00.000Z'),
    ...overrides,
  };
}

function matchesUserWhere(user: any, where: any) {
  const clauses = where?.OR ?? [];
  return clauses.some((clause: any) => {
    if (clause.id != null) return user.id === clause.id;
    if (clause.displayName?.contains != null) {
      return user.displayName.toLowerCase().includes(
        clause.displayName.contains.toLowerCase(),
      );
    }
    if (clause.name?.contains != null) {
      return user.name.toLowerCase().includes(clause.name.contains.toLowerCase());
    }
    if (clause.phone?.contains != null) {
      return (user.phone ?? '').includes(clause.phone.contains);
    }
    return false;
  });
}
