import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';

import { env } from '../../config/env';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { AppleAppDownloadsSource } from './apple-app-downloads.source';
import {
  AppDownloadPlatformSnapshot,
  AppDownloadsSnapshot,
  AppDownloadSource,
} from './app-downloads.types';
import { GooglePlayDownloadsSource } from './google-play-downloads.source';

const SNAPSHOT_CACHE_KEY = 'admin:app-downloads:snapshot:v1';
const SYNC_LOCK_KEY = 'admin:app-downloads:sync-lock:v1';

@Injectable()
export class AdminAppDownloadsService
  implements OnModuleInit, OnModuleDestroy
{
  private readonly logger = new Logger(AdminAppDownloadsService.name);
  private syncTimer: NodeJS.Timeout | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly apple: AppleAppDownloadsSource,
    private readonly google: GooglePlayDownloadsSource,
  ) {}

  onModuleInit() {
    void this.syncAll();
    this.syncTimer = setInterval(
      () => void this.syncAll(),
      env.APP_DOWNLOAD_SYNC_INTERVAL_MINUTES * 60 * 1000,
    );
    this.syncTimer.unref?.();
  }

  onModuleDestroy() {
    if (this.syncTimer) {
      clearInterval(this.syncTimer);
      this.syncTimer = null;
    }
  }

  async getSnapshot(now = new Date()): Promise<AppDownloadsSnapshot> {
    try {
      const cached = await this.redis.get(SNAPSHOT_CACHE_KEY);
      if (cached) return JSON.parse(cached) as AppDownloadsSnapshot;
    } catch {
      // PostgreSQL remains the durable fallback when Redis is unavailable.
    }

    const [ios, android] = await Promise.all([
      this.buildPlatformSnapshot(this.apple, now),
      this.buildPlatformSnapshot(this.google, now),
    ]);
    const snapshot = { ios, android };
    try {
      await this.redis.setWithTtl(
        SNAPSHOT_CACHE_KEY,
        JSON.stringify(snapshot),
        env.APP_DOWNLOAD_CACHE_TTL_SECONDS,
      );
    } catch {
      // A response must still be available from PostgreSQL.
    }
    return snapshot;
  }

  async syncAll() {
    let locked = true;
    try {
      locked =
        (await this.redis.setNxWithTtl(SYNC_LOCK_KEY, '1', 30 * 60)) === 'OK';
    } catch {
      // Upserts are idempotent, so a Redis outage does not prevent syncing.
    }
    if (!locked) return;

    const results = await Promise.allSettled([
      this.syncSource(this.apple),
      this.syncSource(this.google),
    ]);
    if (results[0].status === 'rejected') {
      this.logger.warn('iOS app download sync failed; cached data retained');
    }
    if (results[1].status === 'rejected') {
      this.logger.warn('Android app download sync failed; cached data retained');
    }
    if (results.some((result) => result.status === 'fulfilled' && result.value)) {
      try {
        await this.redis.del(SNAPSHOT_CACHE_KEY);
      } catch {
        // The next read will still use durable PostgreSQL data.
      }
    }
    try {
      await this.redis.del(SYNC_LOCK_KEY);
    } catch {
      // The lock expires automatically.
    }
  }

  private async syncSource(source: AppDownloadSource) {
    if (!source.isConfigured()) return false;
    const latest = await this.prisma.appDownloadDailyStat.findFirst({
      where: { platform: source.platform },
      orderBy: { reportDate: 'desc' },
      select: { reportDate: true },
    });
    const sinceDate = latest
      ? this.addDays(this.isoDate(latest.reportDate), -62)
      : undefined;
    const points = await source.fetchDailyDownloads(sinceDate);
    if (points.length === 0) return false;
    const syncedAt = new Date();
    for (let offset = 0; offset < points.length; offset += 500) {
      const chunk = points.slice(offset, offset + 500);
      await this.prisma.$transaction(
        chunk.map((point) =>
          this.prisma.appDownloadDailyStat.upsert({
            where: {
              platform_reportDate: {
                platform: source.platform,
                reportDate: new Date(`${point.date}T00:00:00.000Z`),
              },
            },
            create: {
              platform: source.platform,
              reportDate: new Date(`${point.date}T00:00:00.000Z`),
              downloads: point.downloads,
              sourceMetric: source.metric,
              sourceTimeZone: source.timeZone,
              lastSyncedAt: syncedAt,
            },
            update: {
              downloads: point.downloads,
              sourceMetric: source.metric,
              sourceTimeZone: source.timeZone,
              lastSyncedAt: syncedAt,
            },
          }),
        ),
      );
    }
    return true;
  }

  private async buildPlatformSnapshot(
    source: AppDownloadSource,
    now: Date,
  ): Promise<AppDownloadPlatformSnapshot> {
    const rows = await this.prisma.appDownloadDailyStat.findMany({
      where: { platform: source.platform },
      orderBy: { reportDate: 'asc' },
      select: {
        reportDate: true,
        downloads: true,
        lastSyncedAt: true,
      },
    });
    if (rows.length === 0) {
      return {
        platform: source.platform,
        configured: source.isConfigured(),
        status: source.isConfigured() ? 'noData' : 'notConfigured',
        metric: source.metric,
        metricLabel: source.metricLabel,
        timeZone: source.timeZone,
        today: null,
        yesterday: null,
        last7Days: null,
        last30Days: null,
        allTime: null,
        latestReportDate: null,
        lastUpdatedAt: null,
      };
    }

    const byDate = new Map(
      rows.map((row) => [this.isoDate(row.reportDate), row.downloads]),
    );
    const todayDate = this.dateInTimeZone(now, source.timeZone);
    const yesterdayDate = this.addDays(todayDate, -1);
    const latestReportDate = this.isoDate(rows[rows.length - 1].reportDate);
    const sumFrom = (days: number) => {
      const firstDate = this.addDays(latestReportDate, -(days - 1));
      return rows
        .filter((row) => {
          const date = this.isoDate(row.reportDate);
          return date >= firstDate && date <= latestReportDate;
        })
        .reduce((total, row) => total + row.downloads, 0);
    };
    const lastUpdatedAt = rows.reduce(
      (latest, row) =>
        row.lastSyncedAt > latest ? row.lastSyncedAt : latest,
      rows[0].lastSyncedAt,
    );

    return {
      platform: source.platform,
      configured: source.isConfigured(),
      status: 'ready',
      metric: source.metric,
      metricLabel: source.metricLabel,
      timeZone: source.timeZone,
      today: byDate.get(todayDate) ?? null,
      yesterday: byDate.get(yesterdayDate) ?? null,
      last7Days: sumFrom(7),
      last30Days: sumFrom(30),
      allTime: rows.reduce((total, row) => total + row.downloads, 0),
      latestReportDate,
      lastUpdatedAt: lastUpdatedAt.toISOString(),
    };
  }

  private dateInTimeZone(date: Date, timeZone: string) {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(date);
    const read = (type: Intl.DateTimeFormatPartTypes) =>
      parts.find((part) => part.type === type)?.value ?? '';
    return `${read('year')}-${read('month')}-${read('day')}`;
  }

  private isoDate(date: Date) {
    return date.toISOString().slice(0, 10);
  }

  private addDays(date: string, amount: number) {
    const value = new Date(`${date}T00:00:00.000Z`);
    value.setUTCDate(value.getUTCDate() + amount);
    return value.toISOString().slice(0, 10);
  }
}
