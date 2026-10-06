import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { WALLET_TIME_ZONE } from '../wallet/wallet.constants';
import { AnalyticsSignal } from './analytics-signal';

type Counts = { guests: bigint; guest_opens: bigint; registered_opens: bigint; messages: bigint; active_chats: bigint };
type PlatformCounts = {
  ios_active: bigint;
  android_active: bigint;
  web_active: bigint;
  ios_registrations: bigint;
  android_registrations: bigint;
  web_registrations: bigint;
  unknown_registrations: bigint;
  versions: unknown;
};
export const periods = ['today', 'yesterday', 'week', 'month', 'all'] as const;
const platformPeriods = ['today', 'week', 'month', 'all'] as const;

@Injectable()
export class UsageAnalyticsService {
  private revision = 0;
  constructor(private readonly prisma: PrismaService, private readonly signal: AnalyticsSignal) {
    signal.subscribe(() => { this.cached = undefined; this.revision++; });
  }

  async guest(guestId: string, userId?: string, now = new Date()) {
    if (userId) return { recorded: false };
    const count = await this.prisma.$executeRaw`
      INSERT INTO analytics_guest_days (guest_id, day)
      VALUES (${guestId}::uuid, (${now}::timestamptz AT TIME ZONE ${WALLET_TIME_ZONE})::date)
      ON CONFLICT DO NOTHING`;
    if (count) this.signal.changed();
    return { recorded: count > 0 };
  }

  async listingOpen(eventId: string, listingId: string, userId?: string, now = new Date()) {
    // One immutable classification per opening; retries cannot reclassify it after login.
    const count = await this.prisma.$executeRaw`
      INSERT INTO analytics_listing_opens (event_id, listing_id, registered, opened_at)
      VALUES (${eventId}::uuid, ${listingId}::uuid, ${!!userId}, (${now}::timestamptz AT TIME ZONE 'UTC'))
      ON CONFLICT DO NOTHING`;
    if (count) this.signal.changed();
    return { recorded: count > 0 };
  }

  private pending?: Promise<Record<string, unknown>>;
  private cached?: { until: number; value: Record<string, unknown> };
  async dashboard(now = new Date()): Promise<Record<string, unknown>> {
    if (this.cached && this.cached.until > Date.now()) return this.cached.value;
    if (this.pending) return this.pending;
    const revision = this.revision;
    this.pending = this.aggregate(now);
    try {
      const value = await this.pending;
      if (revision === this.revision) this.cached = { until: Date.now() + 1000, value };
      return value;
    } finally { this.pending = undefined; }
  }

  async aggregate(now: Date) {
    // One MVCC snapshot for all metrics and periods. Date predicates match covering indexes.
    const [results, platformResults] = await Promise.all([
      this.prisma.$transaction(periods.map(period => this.prisma.$queryRaw<Counts[]>`
      WITH bounds AS (
        SELECT (${now}::timestamptz AT TIME ZONE ${WALLET_TIME_ZONE})::date AS today
      ), dates AS (
        SELECT CASE ${period}
          WHEN 'today' THEN today
          WHEN 'yesterday' THEN today - 1
          WHEN 'week' THEN today - 6
          WHEN 'month' THEN date_trunc('month', today)::date
          ELSE '-infinity'::date END AS start_day,
          CASE WHEN ${period} = 'yesterday' THEN today ELSE today + 1 END AS end_day
        FROM bounds
      ), times AS (
        SELECT *, (start_day::timestamp AT TIME ZONE ${WALLET_TIME_ZONE}) AT TIME ZONE 'UTC' AS start_at,
          CASE WHEN ${period} = 'yesterday'
            THEN (end_day::timestamp AT TIME ZONE ${WALLET_TIME_ZONE}) AT TIME ZONE 'UTC'
            ELSE (${now}::timestamptz AT TIME ZONE 'UTC') END AS end_at
        FROM dates
      )
      SELECT
        (SELECT count(DISTINCT guest_id) FROM analytics_guest_days, times
          WHERE day >= start_day AND day < end_day)::bigint AS guests,
        (SELECT count(*) FROM analytics_listing_opens, times
          WHERE registered = false AND opened_at >= start_at AND opened_at < end_at)::bigint AS guest_opens,
        (SELECT count(*) FROM analytics_listing_opens, times
          WHERE registered = true AND opened_at >= start_at AND opened_at < end_at)::bigint AS registered_opens,
        (SELECT count(*) FROM chat_messages, times
          WHERE created_at >= start_at AND created_at < end_at)::bigint AS messages,
        (SELECT count(DISTINCT chat_id) FROM chat_messages, times
          WHERE created_at >= start_at AND created_at < end_at)::bigint AS active_chats
      `), { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead }),
      this.prisma.$transaction(platformPeriods.map(period => this.prisma.$queryRaw<PlatformCounts[]>`
        WITH bounds AS (
          SELECT (${now}::timestamptz AT TIME ZONE ${WALLET_TIME_ZONE})::date AS today
        ), dates AS (
          SELECT CASE ${period}
            WHEN 'today' THEN today
            WHEN 'week' THEN today - 6
            WHEN 'month' THEN date_trunc('month', today)::date
            ELSE '-infinity'::date END AS start_day,
            today + 1 AS end_day
          FROM bounds
        ), times AS (
          SELECT *,
            (start_day::timestamp AT TIME ZONE ${WALLET_TIME_ZONE}) AT TIME ZONE 'UTC' AS start_at,
            (${now}::timestamptz AT TIME ZONE 'UTC') AS end_at
          FROM dates
        ), active AS (
          SELECT platform, count(DISTINCT user_id)::bigint AS users
          FROM analytics_platform_activity, times
          WHERE day >= start_day AND day < end_day
          GROUP BY platform
        ), registrations AS (
          SELECT registration_platform AS platform, count(*)::bigint AS users
          FROM (
            SELECT u.id,
              (SELECT uc.platform
               FROM user_consents uc
               WHERE uc.user_id = u.id
                 AND uc.consent_type = 'TERMS_ACCEPTANCE'::"UserConsentType"
                 AND uc.platform IS NOT NULL
               ORDER BY uc.created_at ASC
               LIMIT 1) AS registration_platform
            FROM users u, times
            WHERE u.created_at >= start_at AND u.created_at < end_at
              AND u.deleted_at IS NULL
              AND u.status <> 'DELETED'::"UserStatus"
          ) registered
          GROUP BY registration_platform
        ), latest_versions AS (
          SELECT DISTINCT ON (user_id, platform)
            user_id, platform, app_version, build_number
          FROM analytics_platform_activity, times
          WHERE day >= start_day AND day < end_day
            AND app_version <> ''
          ORDER BY user_id, platform, last_activity_at DESC
        ), version_counts AS (
          SELECT platform, app_version, build_number,
            count(DISTINCT user_id)::bigint AS users
          FROM latest_versions
          GROUP BY platform, app_version, build_number
        )
        SELECT
          COALESCE((SELECT users FROM active WHERE platform = 'IOS'), 0)::bigint AS ios_active,
          COALESCE((SELECT users FROM active WHERE platform = 'ANDROID'), 0)::bigint AS android_active,
          COALESCE((SELECT users FROM active WHERE platform = 'WEB'), 0)::bigint AS web_active,
          COALESCE((SELECT users FROM registrations WHERE platform = 'IOS'), 0)::bigint AS ios_registrations,
          COALESCE((SELECT users FROM registrations WHERE platform = 'ANDROID'), 0)::bigint AS android_registrations,
          COALESCE((SELECT users FROM registrations WHERE platform = 'WEB'), 0)::bigint AS web_registrations,
          COALESCE((SELECT users FROM registrations WHERE platform IS NULL), 0)::bigint AS unknown_registrations,
          COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
              'platform', lower(platform::text),
              'version', app_version,
              'buildNumber', build_number,
              'users', users
            ) ORDER BY users DESC, platform, app_version DESC)
            FROM version_counts
          ), '[]'::jsonb) AS versions
      `), { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead }),
    ]);
    return {
      timezone: WALLET_TIME_ZONE,
      asOf: now.toISOString(),
      periods: Object.fromEntries(periods.map((period, i) => {
        const row = results[i][0];
        return [period, {
          guests: Number(row.guests), guestOpens: Number(row.guest_opens),
          registeredOpens: Number(row.registered_opens),
          totalOpens: Number(row.guest_opens) + Number(row.registered_opens),
          messages: Number(row.messages), activeChats: Number(row.active_chats),
        }];
      })),
      platforms: Object.fromEntries(platformPeriods.map((period, i) => {
        const row = platformResults[i][0];
        return [period, {
          active: {
            ios: Number(row.ios_active),
            android: Number(row.android_active),
            web: Number(row.web_active),
          },
          registrations: {
            ios: Number(row.ios_registrations),
            android: Number(row.android_registrations),
            web: Number(row.web_registrations),
            unknown: Number(row.unknown_registrations),
          },
          versions: Array.isArray(row.versions) ? row.versions : [],
        }];
      })),
    };
  }
}
