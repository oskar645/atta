import assert from 'node:assert/strict';
import { test } from 'node:test';
import { GUARDS_METADATA } from '@nestjs/common/constants';

import { AdminGuard } from '../auth/admin.guard';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminAppDownloadsController } from './admin-app-downloads.controller';
import { AdminAppDownloadsService } from './admin-app-downloads.service';
import { AppDownloadSource } from './app-downloads.types';
import { AppleAppDownloadsSource } from './apple-app-downloads.source';
import { GooglePlayDownloadsSource } from './google-play-downloads.source';

type Row = {
  platform: string;
  reportDate: Date;
  downloads: number;
  sourceMetric: string;
  sourceTimeZone: string;
  lastSyncedAt: Date;
};

const source = (
  platform: 'ios' | 'android',
  points: Array<{ date: string; downloads: number }> = [],
): AppDownloadSource => ({
  platform,
  metric: platform === 'ios' ? 'firstTimeDownload' : 'dailyUserInstalls',
  metricLabel: platform === 'ios' ? 'Первые загрузки' : 'Установки пользователями',
  timeZone: platform === 'ios' ? 'UTC' : 'America/Los_Angeles',
  isConfigured: () => true,
  fetchDailyDownloads: async () => points,
});

const harness = (initialRows: Row[] = []) => {
  const rows = [...initialRows];
  const cache = new Map<string, string>();
  const prisma = {
    appDownloadDailyStat: {
      findMany: async ({ where }: { where: { platform: string } }) =>
        rows
          .filter((row) => row.platform === where.platform)
          .sort((a, b) => a.reportDate.getTime() - b.reportDate.getTime()),
      findFirst: async ({ where }: { where: { platform: string } }) =>
        rows
          .filter((row) => row.platform === where.platform)
          .sort((a, b) => b.reportDate.getTime() - a.reportDate.getTime())[0] ??
        null,
      upsert: async (args: any) => {
        const key = args.where.platform_reportDate;
        const existing = rows.find(
          (row) =>
            row.platform === key.platform &&
            row.reportDate.getTime() === key.reportDate.getTime(),
        );
        if (existing) Object.assign(existing, args.update);
        else rows.push({ ...args.create });
      },
    },
    $transaction: async (operations: Array<Promise<unknown>>) =>
      Promise.all(operations),
  };
  const redis = {
    get: async (key: string) => cache.get(key) ?? null,
    setWithTtl: async (key: string, value: string) => void cache.set(key, value),
    setNxWithTtl: async () => 'OK',
    del: async (key: string) => void cache.delete(key),
  };
  return { rows, cache, prisma, redis };
};

const row = (platform: 'ios' | 'android', date: string, downloads: number): Row => ({
  platform,
  reportDate: new Date(`${date}T00:00:00.000Z`),
  downloads,
  sourceMetric: platform === 'ios' ? 'firstTimeDownload' : 'dailyUserInstalls',
  sourceTimeZone: platform === 'ios' ? 'UTC' : 'America/Los_Angeles',
  lastSyncedAt: new Date('2026-11-05T09:15:00.000Z'),
});

test('aggregates each platform separately and keeps an unavailable today as null', async () => {
  const iosRows = [
    row('ios', '2026-10-29', 1),
    row('ios', '2026-10-30', 2),
    row('ios', '2026-10-31', 3),
    row('ios', '2026-11-01', 4),
    row('ios', '2026-11-02', 5),
    row('ios', '2026-11-03', 6),
    row('ios', '2026-11-04', 12),
  ];
  const h = harness([...iosRows, row('android', '2026-11-05', 20)]);
  const service = new AdminAppDownloadsService(
    h.prisma as any,
    h.redis as any,
    source('ios') as any,
    source('android') as any,
  );

  const result = await service.getSnapshot(new Date('2026-11-05T12:00:00Z'));
  assert.equal(result.ios.today, null);
  assert.equal(result.ios.yesterday, 12);
  assert.equal(result.ios.last7Days, 33);
  assert.equal(result.ios.last30Days, 33);
  assert.equal(result.ios.allTime, 33);
  assert.equal(result.android.today, 20);
  assert.equal(result.android.allTime, 20);
  assert.equal(result.ios.lastUpdatedAt, '2026-11-05T09:15:00.000Z');
});

test('repeat sync upserts the same platform/date instead of duplicating it', async () => {
  const h = harness();
  const service = new AdminAppDownloadsService(
    h.prisma as any,
    h.redis as any,
    source('ios', [{ date: '2026-11-04', downloads: 7 }]) as any,
    source('android') as any,
  );
  await service.syncAll();
  await service.syncAll();
  assert.equal(h.rows.filter((item) => item.platform === 'ios').length, 1);
  assert.equal(h.rows[0].downloads, 7);
});

test('a failed Apple source does not prevent a successful Android sync', async () => {
  const h = harness();
  const brokenApple = source('ios');
  brokenApple.fetchDailyDownloads = async () => {
    throw new Error('private credential detail must not reach response');
  };
  const service = new AdminAppDownloadsService(
    h.prisma as any,
    h.redis as any,
    brokenApple as any,
    source('android', [{ date: '2026-11-04', downloads: 9 }]) as any,
  );
  await service.syncAll();
  const result = await service.getSnapshot(new Date('2026-11-05T12:00:00Z'));
  assert.equal(result.ios.today, null);
  assert.equal(result.android.yesterday, 9);
  assert.doesNotMatch(JSON.stringify(result), /private credential detail/);
});

test('a failed Google source does not prevent iOS and the last cache remains usable', async () => {
  const h = harness([row('android', '2026-11-03', 5)]);
  const brokenGoogle = source('android');
  brokenGoogle.fetchDailyDownloads = async () => {
    throw new Error('expired credential');
  };
  const service = new AdminAppDownloadsService(
    h.prisma as any,
    h.redis as any,
    source('ios', [{ date: '2026-11-04', downloads: 11 }]) as any,
    brokenGoogle as any,
  );
  await service.syncAll();
  const first = await service.getSnapshot(new Date('2026-11-05T12:00:00Z'));
  h.rows.length = 0;
  const cached = await service.getSnapshot(new Date('2026-11-05T12:00:00Z'));
  assert.deepEqual(cached, first);
  assert.equal(first.ios.yesterday, 11);
  assert.equal(first.android.allTime, 5);
});

test('official report parsers select the documented installation metrics', () => {
  const apple = Object.create(AppleAppDownloadsSource.prototype) as AppleAppDownloadsSource;
  assert.deepEqual(
    apple.parseReport(
      'Date\tDownload Type\tCounts\n2026-11-04\tFirst-time Download\t12\n2026-11-04\tRedownload\t4\n',
    ),
    [{ date: '2026-11-04', downloads: 12 }],
  );
  const google = Object.create(GooglePlayDownloadsSource.prototype) as GooglePlayDownloadsSource;
  assert.deepEqual(
    google.parseReport(
      Buffer.from('Date,Package Name,Daily User Installs\n2026-11-04,online.atta,15\n'),
    ),
    [{ date: '2026-11-04', downloads: 15 }],
  );
});

test('app downloads endpoint has both authentication and admin guards', () => {
  const guards = Reflect.getMetadata(
    GUARDS_METADATA,
    AdminAppDownloadsController,
  ) as unknown[];
  assert.ok(guards.includes(JwtAuthGuard));
  assert.ok(guards.includes(AdminGuard));
});
