import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ReportsService } from './reports.service';

test('admin list excludes hidden reports', async () => {
  let capturedWhere: Record<string, unknown> | undefined;

  const service = new ReportsService(
    {
      report: {
        findMany: async (args: Record<string, unknown>) => {
          capturedWhere = args['where'] as Record<string, unknown> | undefined;
          return [];
        },
      },
    } as any,
    {} as any,
  );

  await service.listForAdmin();

  assert.deepEqual(capturedWhere, {
    status: {
      notIn: ['hidden', 'deleted'],
    },
  });
});

test('hide marks report hidden without deleting it', async () => {
  const updates: Array<Record<string, unknown>> = [];
  const service = new ReportsService(
    {
      report: {
        findUnique: async () => ({
          id: 'report-1',
          decision: null,
          handledAt: null,
          closedAt: null,
        }),
        update: async (args: Record<string, any>) => {
          updates.push(args);
          return {
            id: 'report-1',
            listingId: null,
            listingOwnerId: 'user-2',
            reporterId: 'user-1',
            reason: 'Спам',
            comment: '',
            status: 'hidden',
            decision: 'hidden',
            adminUid: 'admin-1',
            adminComment: null,
            createdAt: new Date('2026-01-01T00:00:00.000Z'),
            handledAt: new Date('2026-01-01T00:00:00.000Z'),
            closedAt: new Date('2026-01-01T00:00:00.000Z'),
          };
        },
      },
    } as any,
    {} as any,
  );

  const result = await service.hide('report-1', { userId: 'admin-1' } as any);

  assert.equal(updates[0]?.['data']?.['status'], 'hidden');
  assert.equal(result.hidden, true);
  assert.equal(result.item.status, 'hidden');
});
