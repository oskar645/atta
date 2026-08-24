import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ViewedListingsService } from './viewed-listings.service';

const authUser = {
  userId: 'user-1',
  sessionId: 'session-1',
  role: 'user' as const,
};

test('mark keeps viewed_listings history separate from listing view counter', async () => {
  let upsertArgs: Record<string, unknown> | undefined;
  const prisma = {
    viewedListing: {
      upsert: async (args: Record<string, unknown>) => {
        upsertArgs = args;
      },
    },
    listingView: {
      create: async () => {
        throw new Error('listing_views should not be touched by history mark');
      },
    },
    listing: {
      update: async () => {
        throw new Error('viewCount should not be touched by history mark');
      },
    },
  };
  const service = new ViewedListingsService(prisma as never);

  const response = await service.mark(authUser, 'listing-1');

  assert.deepEqual(response, {
    viewed: true,
    listing_id: 'listing-1',
  });
  assert.deepEqual(upsertArgs, {
    where: {
      userId_listingId: {
        userId: authUser.userId,
        listingId: 'listing-1',
      },
    },
    update: {
      viewedAt: upsertArgs != null
        ? (upsertArgs.update as { viewedAt: Date }).viewedAt
        : undefined,
    },
    create: {
      userId: authUser.userId,
      listingId: 'listing-1',
    },
  });
  assert.ok((upsertArgs?.update as { viewedAt?: unknown }).viewedAt instanceof Date);
});
