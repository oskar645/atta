import assert from 'node:assert/strict';
import { test } from 'node:test';

import { ListingsService } from './listings.service';

const attempt = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function serviceWithStore() {
  const rows = new Map<string, any>();
  const prisma = {
    zeroResultSearch: {
      deleteMany: async ({ where }: any) => ({ count: rows.delete(where.attemptId) ? 1 : 0 }),
      upsert: async ({ where, create, update }: any) => {
        rows.set(where.attemptId, { ...(rows.get(where.attemptId) ?? create), ...update });
      },
    },
  };
  return {
    rows,
    service: new ListingsService(prisma as any, {} as any, {} as any, {} as any),
  };
}

test('one attempt supersedes an intermediate zero with its final normalized query', async () => {
  const { service, rows } = serviceWithStore();
  await service.recordSearchAttempt({ attemptId: attempt, query: 'арматур', resultCount: 0, hasRestrictiveFilters: false });
  await service.recordSearchAttempt({ attemptId: attempt, query: ' АРМАТУРА!!! ', resultCount: 0, hasRestrictiveFilters: false });
  assert.equal(rows.size, 1);
  assert.equal(rows.get(attempt).normalizedQuery, 'арматура');
});

test('a final result or restrictive filter removes an earlier zero', async () => {
  const { service, rows } = serviceWithStore();
  await service.recordSearchAttempt({ attemptId: attempt, query: 'арматур', resultCount: 0, hasRestrictiveFilters: false });
  await service.recordSearchAttempt({ attemptId: attempt, query: 'арматура', resultCount: 1, hasRestrictiveFilters: false });
  assert.equal(rows.size, 0);
  await service.recordSearchAttempt({ attemptId: attempt, query: 'арматура', resultCount: 0, hasRestrictiveFilters: true });
  assert.equal(rows.size, 0);
});

test('independent attempts remain independently countable', async () => {
  const { service, rows } = serviceWithStore();
  await service.recordSearchAttempt({ attemptId: attempt, query: 'Арматура', resultCount: 0, hasRestrictiveFilters: false });
  await service.recordSearchAttempt({ attemptId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', query: 'арматура.', resultCount: 0, hasRestrictiveFilters: false });
  assert.equal(rows.size, 2);
  assert.deepEqual([...rows.values()].map((x) => x.normalizedQuery), ['арматура', 'арматура']);
});
