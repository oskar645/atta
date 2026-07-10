import { test } from 'node:test';
import assert from 'node:assert/strict';

import { FavoritesService } from './favorites.service';

test('favorites list is sorted by createdAt desc', async () => {
  let capturedOrderBy: Record<string, unknown> | undefined;

  const service = new FavoritesService(
    {
      favorite: {
        findMany: async (args: Record<string, unknown>) => {
          capturedOrderBy = args['orderBy'] as Record<string, unknown> | undefined;
          return [];
        },
      },
    } as any,
  );

  await service.list({ userId: 'user-1' } as any);

  assert.deepEqual(capturedOrderBy, {
    createdAt: 'desc',
  });
});
