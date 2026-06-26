import { test } from 'node:test';
import assert from 'node:assert/strict';

import { PromotionStatus, PromotionType, WalletTransactionReason, WalletTransactionType } from '@prisma/client';

import { AdminService } from './admin.service';

function createService(prisma: Record<string, unknown>) {
  return new AdminService(
    prisma as never,
    {} as never,
    {} as never,
    {} as never,
  );
}

test('admin promotions list works', async () => {
  const service = createService({
    promotion: {
      updateMany: async () => ({ count: 0 }),
      findMany: async () => [
        {
          id: 'promo-1',
          listingId: 'listing-1',
          userId: 'user-1',
          type: PromotionType.SHOWCASE,
          status: PromotionStatus.ACTIVE,
          costBonus: 50,
          startsAt: new Date('2026-06-18T10:00:00.000Z'),
          endsAt: new Date('2026-06-19T10:00:00.000Z'),
          impressionsCount: 12,
          clicksCount: 3,
          createdAt: new Date('2026-06-18T09:00:00.000Z'),
          listing: {
            title: 'Bike',
            photos: [{ publicUrl: 'https://cdn.example.com/bike.jpg' }],
          },
          user: {
            displayName: 'Seller',
            name: 'Seller',
            phone: '+79990000000',
          },
        },
      ],
    },
  });

  const response = await service.listPromotions({});
  assert.equal(response.items.length, 1);
  assert.equal(response.items[0].type, 'showcase');
});

test('admin promotion summary works', async () => {
  const counts = [1, 2, 3, 4, 5];
  let countIndex = 0;
  const service = createService({
    promotion: {
      updateMany: async () => ({ count: 0 }),
      count: async () => counts[countIndex++],
      aggregate: async () => ({
        _sum: {
          costBonus: 120,
          impressionsCount: 88,
          clicksCount: 9,
        },
      }),
    },
  });

  const response = await service.getPromotionsSummary();
  assert.equal(response.activeShowcaseCount, 1);
  assert.equal(response.totalBonusSpentToday, 120);
  assert.equal(response.totalShowcaseClicks, 9);
});

test('admin wallet transactions list works', async () => {
  const service = createService({
    walletTransaction: {
      findMany: async () => [
        {
          id: 'tx-1',
          userId: 'user-1',
          type: WalletTransactionType.SPEND,
          amount: 50,
          reason: WalletTransactionReason.PROMOTION_SHOWCASE,
          metadata: { source: 'bonus' },
          createdAt: new Date('2026-06-18T12:00:00.000Z'),
          user: {
            displayName: 'Seller',
            name: 'Seller',
            phone: '+79990000000',
          },
        },
      ],
    },
  });

  const response = await service.listWalletTransactions({});
  assert.equal(response.items.length, 1);
  assert.equal(response.items[0].reason, 'promotion_showcase');
});

test('admin bonus analytics works', async () => {
  const service = createService({
    walletTransaction: {
      findMany: async () => [
        {
          userId: 'user-1',
          type: WalletTransactionType.ACCRUAL,
          amount: 25,
          reason: WalletTransactionReason.WELCOME_BONUS,
          createdAt: new Date('2026-06-18T12:00:00.000Z'),
        },
        {
          userId: 'user-1',
          type: WalletTransactionType.SPEND,
          amount: 50,
          reason: WalletTransactionReason.PROMOTION_SHOWCASE,
          createdAt: new Date('2026-06-18T13:00:00.000Z'),
        },
        {
          userId: 'user-2',
          type: WalletTransactionType.REFUND,
          amount: 10,
          reason: WalletTransactionReason.PROMOTION_TURBO,
          createdAt: new Date('2026-06-18T14:00:00.000Z'),
        },
      ],
    },
    wallet: {
      count: async () => 2,
    },
  });

  const response = await service.getBonusAnalytics({ period: 'day' });
  assert.equal(response.totalBonusAccrued, 25);
  assert.equal(response.totalBonusSpent, 50);
  assert.equal(response.totalBonusRefunded, 10);
  assert.equal(response.spentByReason.promotion_showcase, 50);
});
