import { test } from 'node:test';
import assert from 'node:assert/strict';

import { BadRequestException } from '@nestjs/common';
import {
  ListingStatus,
  PromotionStatus,
  PromotionType,
  WalletTransactionReason,
} from '@prisma/client';

import { PromotionsService } from './promotions.service';

const authUser = {
  userId: 'user-1',
  sessionId: 'session-1',
  role: 'user',
} as const;

type CreatedPromotion = {
  listingId: string;
  userId: string;
  type: PromotionType;
  costBonus: number;
  startsAt: Date;
  endsAt: Date;
  status: PromotionStatus;
};

function listing(promotions: unknown[] = []) {
  const now = new Date('2026-08-24T10:00:00.000Z');
  return {
    id: 'listing-1',
    ownerId: authUser.userId,
    ownerEmail: 'seller@example.com',
    ownerName: 'Seller',
    title: 'Listing',
    description: 'Description',
    category: 'transport',
    subcategory: 'bike',
    price: 1000,
    previousPrice: null,
    priceReducedAt: null,
    phone: '',
    phoneHidden: false,
    city: 'Москва',
    address: null,
    latitude: null,
    longitude: null,
    locationJson: {},
    delivery: {},
    car: null,
    dealType: null,
    realEstateType: null,
    clothesType: null,
    clothesSize: null,
    photos: [],
    viewCount: 0,
    status: ListingStatus.APPROVED,
    rejectionReason: null,
    moderationNote: null,
    moderatedBy: null,
    moderatedAt: null,
    publishedAt: now,
    archivedAt: null,
    deletedAt: null,
    createdAt: now,
    updatedAt: now,
    owner: {
      id: authUser.userId,
      email: 'seller@example.com',
      phone: '',
      displayName: 'Seller',
      name: 'Seller',
      avatarUrl: null,
      photoUrl: null,
      phoneVerified: false,
      status: 'ACTIVE',
      lastLoginAt: null,
      blockedAt: null,
      blockReason: null,
      deletedAt: null,
      createdAt: now,
      updatedAt: now,
      adminProfile: null,
    },
    promotions,
  };
}

function activePromotion(type: PromotionType, costBonus: number) {
  const now = new Date('2026-08-24T10:00:00.000Z');
  return {
    id: `promotion-${type.toLowerCase()}`,
    listingId: 'listing-1',
    userId: authUser.userId,
    type,
    costBonus,
    startsAt: now,
    endsAt: new Date(now.getTime() + 24 * 60 * 60 * 1000),
    status: PromotionStatus.ACTIVE,
    impressionsCount: 0,
    clicksCount: 0,
    createdAt: now,
    updatedAt: now,
  };
}

function createService(options?: {
  balance?: number;
  existingPromotion?: ReturnType<typeof activePromotion> | null;
}) {
  const createdPromotions: CreatedPromotion[] = [];
  const spent: Array<{ amount: number; metadata: Record<string, unknown> }> = [];
  const wallet = {
    id: 'wallet-1',
    userId: authUser.userId,
    bonusBalance: options?.balance ?? 10_000,
  };
  const existingPromotion = options?.existingPromotion ?? null;

  const tx = {
    $executeRaw: async () => null,
    promotion: {
      updateMany: async () => ({ count: 0 }),
      findFirst: async () => existingPromotion,
      create: async ({ data }: { data: CreatedPromotion }) => {
        const created = {
          id: `created-${createdPromotions.length + 1}`,
          impressionsCount: 0,
          clicksCount: 0,
          createdAt: data.startsAt,
          updatedAt: data.startsAt,
          ...data,
        };
        createdPromotions.push(data);
        return created;
      },
    },
    wallet: {
      findUniqueOrThrow: async () => ({ ...wallet }),
    },
  };

  const prisma = {
    listing: {
      findUnique: async () => listing(existingPromotion ? [existingPromotion] : []),
      findUniqueOrThrow: async () =>
        listing([
          existingPromotion ??
            activePromotion(
              createdPromotions[0]?.type ?? PromotionType.SHOWCASE,
              createdPromotions[0]?.costBonus ?? 0,
            ),
        ]),
    },
    promotion: {
      updateMany: async () => ({ count: 0 }),
      findFirst: async () => existingPromotion,
    },
    $transaction: async (callback: (transaction: typeof tx) => unknown) =>
      callback(tx),
  };

  const walletService = {
    ensureWalletAndBonuses: async () => ({ ...wallet }),
    getWallet: async () => ({ balance: wallet.bonusBalance }),
    resolveSpendReason: async (reason: WalletTransactionReason) => reason,
    spendBonus: async (
      _userId: string,
      amount: number,
      _reason: WalletTransactionReason,
      metadata: Record<string, unknown>,
    ) => {
      if (wallet.bonusBalance < amount) {
        throw new BadRequestException('Недостаточно бонусов');
      }
      wallet.bonusBalance -= amount;
      spent.push({ amount, metadata });
      return { ...wallet };
    },
  };

  const service = new PromotionsService(
    prisma as any,
    walletService as any,
    { debounce: async () => true } as any,
  );

  return { service, createdPromotions, spent };
}

test('old VIP client without quantity keeps 150 bonuses and 48 hours', async () => {
  const { service, createdPromotions, spent } = createService();

  await service.promoteListing('listing-1', authUser, { type: 'vip' });

  assert.equal(spent[0]?.amount, 150);
  assert.equal(createdPromotions[0]?.costBonus, 150);
  assert.equal(
    createdPromotions[0]!.endsAt.getTime() -
      createdPromotions[0]!.startsAt.getTime(),
    48 * 60 * 60 * 1000,
  );
});

test('old showcase client without quantity keeps 230 bonuses and 24 hours', async () => {
  const { service, createdPromotions, spent } = createService();

  await service.promoteListing('listing-1', authUser, { type: 'showcase' });

  assert.equal(spent[0]?.amount, 230);
  assert.equal(createdPromotions[0]?.costBonus, 230);
  assert.equal(
    createdPromotions[0]!.endsAt.getTime() -
      createdPromotions[0]!.startsAt.getTime(),
    24 * 60 * 60 * 1000,
  );
});

test('VIP quantity multiplies existing 48-hour periods and price', async () => {
  const { service, createdPromotions, spent } = createService();

  await service.promoteListing('listing-1', authUser, {
    type: 'vip',
    days: 3,
  });

  assert.equal(spent[0]?.amount, 450);
  assert.equal(createdPromotions[0]?.costBonus, 450);
  assert.equal(spent[0]?.metadata.quantity, 3);
  assert.equal(
    createdPromotions[0]!.endsAt.getTime() -
      createdPromotions[0]!.startsAt.getTime(),
    144 * 60 * 60 * 1000,
  );
});

test('showcase quantity multiplies 24-hour days and price', async () => {
  const { service, createdPromotions, spent } = createService();

  await service.promoteListing('listing-1', authUser, {
    type: 'showcase',
    days: 5,
  });

  assert.equal(spent[0]?.amount, 1150);
  assert.equal(createdPromotions[0]?.costBonus, 1150);
  assert.equal(spent[0]?.metadata.quantity, 5);
  assert.equal(
    createdPromotions[0]!.endsAt.getTime() -
      createdPromotions[0]!.startsAt.getTime(),
    120 * 60 * 60 * 1000,
  );
});

test('promotion quantity outside 1..30 is rejected before spending', async () => {
  const low = createService();
  await assert.rejects(
    () => low.service.promoteListing('listing-1', authUser, {
      type: 'vip',
      days: 0,
    }),
    BadRequestException,
  );
  assert.equal(low.spent.length, 0);

  const high = createService();
  await assert.rejects(
    () => high.service.promoteListing('listing-1', authUser, {
      type: 'showcase',
      days: 31,
    }),
    BadRequestException,
  );
  assert.equal(high.spent.length, 0);
});

test('insufficient bonuses uses multiplied price and does not activate', async () => {
  const { service, createdPromotions, spent } = createService({ balance: 449 });

  await assert.rejects(
    () => service.promoteListing('listing-1', authUser, {
      type: 'vip',
      days: 3,
    }),
    BadRequestException,
  );

  assert.equal(spent.length, 0);
  assert.equal(createdPromotions.length, 0);
});

test('active VIP and showcase still return already active without spending', async () => {
  for (const type of [PromotionType.VIP, PromotionType.SHOWCASE]) {
    const existing = activePromotion(type, type === PromotionType.VIP ? 150 : 230);
    const { service, spent, createdPromotions } = createService({
      existingPromotion: existing,
    });

    const response = await service.promoteListing('listing-1', authUser, {
      type: type.toLowerCase(),
      days: 5,
    });

    assert.match(response.message, /уже актив/);
    assert.equal(spent.length, 0);
    assert.equal(createdPromotions.length, 0);
  }
});

test('BUMP still passes requested days to existing raise campaign flow', async () => {
  const { service } = createService();
  let capturedDays: number | undefined;
  (service as any).purchaseRaiseCampaign = async ({ days }: { days: number }) => {
    capturedDays = days;
    return { days };
  };

  const response = await service.promoteListing('listing-1', authUser, {
    type: 'bump',
    days: 7,
  });

  assert.equal(capturedDays, 7);
  assert.deepEqual(response, { days: 7 });
});
