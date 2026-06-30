import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ListingStatus } from '@prisma/client';

import { AdminService } from './admin.service';

test('moderation list uses pending filter without deleted or archived items', async () => {
  let capturedWhere: Record<string, unknown> | undefined;

  const service = new AdminService(
    {
      listing: {
        findMany: async (args: Record<string, unknown>) => {
          capturedWhere = args['where'] as Record<string, unknown>?;
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

