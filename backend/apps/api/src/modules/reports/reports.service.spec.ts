import { test } from 'node:test';
import assert from 'node:assert/strict';

import { BadRequestException } from '@nestjs/common';

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
  const updates: Array<Record<string, any>> = [];
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

test('create derives listing owner from backend listing lookup', async () => {
  let createArgs: Record<string, any> | undefined;
  const service = new ReportsService(
    {
      listing: {
        findUnique: async (args: Record<string, any>) => {
          assert.deepEqual(args, {
            where: {
              id: 'listing-1',
            },
            select: {
              ownerId: true,
            },
          });
          return {
            ownerId: 'real-owner',
          };
        },
      },
      report: {
        create: async (args: Record<string, any>) => {
          createArgs = args;
          return {
            id: 'report-1',
            listingId: args.data.listingId,
            listingOwnerId: args.data.listingOwnerId,
            reporterId: args.data.reporterId,
            reason: args.data.reason,
            comment: args.data.comment,
            status: args.data.status,
            decision: null,
            adminUid: null,
            adminComment: null,
            createdAt: new Date('2026-01-01T00:00:00.000Z'),
            listing: {
              id: 'listing-1',
              title: 'Listing',
              ownerId: 'real-owner',
              owner: {
                id: 'real-owner',
                displayName: 'Owner',
                name: 'Owner',
              },
              photos: [],
            },
            listingOwner: {
              id: 'real-owner',
              displayName: 'Owner',
              name: 'Owner',
            },
            reporter: {
              id: 'reporter-1',
              displayName: 'Reporter',
              name: 'Reporter',
            },
          };
        },
      },
      adminUser: {
        findMany: async () => [],
      },
    } as any,
    {
      createSystemNotification: async () => null,
      serializeNotification: (item: unknown) => item,
    } as any,
  );

  const result = await service.create(
    { userId: 'reporter-1' } as any,
    {
      listingId: 'listing-1',
      reportedUserId: 'attacker-chosen-user',
      listingOwnerId: 'attacker-chosen-owner',
      reason: 'spam',
    },
  );

  assert.equal(createArgs?.['data']?.['listingOwnerId'], 'real-owner');
  assert.equal(result.item.listing_owner_id, 'real-owner');
  assert.equal(result.item.reported_user_id, 'real-owner');
});

test('create rejects missing listing instead of trusting client owner', async () => {
  const service = new ReportsService(
    {
      listing: {
        findUnique: async () => null,
      },
    } as any,
    {} as any,
  );

  await assert.rejects(
    () =>
      service.create(
        { userId: 'reporter-1' } as any,
        {
          listingId: 'missing-listing',
          reportedUserId: 'attacker-chosen-user',
        },
      ),
    BadRequestException,
  );
});
