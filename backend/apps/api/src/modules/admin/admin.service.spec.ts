import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  ListingStatus,
  UserStatus,
  WalletTransactionType,
} from '@prisma/client';

import { AdminService } from './admin.service';

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
    {} as any,
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
    } as any,
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
