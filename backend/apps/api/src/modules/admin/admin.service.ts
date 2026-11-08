import { AccountDeletionService } from '../auth/account-deletion.service';
import * as fs from 'fs';
import * as os from 'os';
import { createHash } from 'crypto';
import { Inject, Optional } from '@nestjs/common';
import { SavedSearchAlertsService } from '../saved-searches/saved-search-alerts.service';
import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import {
  FeedAdPlacement,
  ListingRaiseCampaignStatus,
  ListingStatus,
  NotificationType,
  PaymentProvider,
  PaymentStatus,
  Prisma,
  PromotionStatus,
  PromotionType,
  ReferralRewardStatus,
  SupportTicketStatus,
  UserBlockStatus,
  UserBlockType,
  UserStatus,
  WalletTransactionReason,
  WalletTransactionType,
} from '@prisma/client';

import { maskPhone } from '../../common/phone';
import { buildReferralCode, resolveReferralUserId } from '../../common/referral-code';
import {
  normalizeStoredMediaUrl,
  listingStatusFromInput,
  serializeListing,
  serializeUser,
  toIsoString,
} from '../../common/serializers';
import {
  LISTING_PUBLICATION_NOT_READY,
  isListingReadyForPublication,
  listingModerationReadySql,
} from '../../common/listing-publication';
import { AuthenticatedUser } from '../auth/auth.types';
import { AppVisitsService } from '../app-visits/app-visits.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { ReviewsService } from '../reviews/reviews.service';
import { StorageService } from '../storage/storage.service';
import { UserBlocksService } from '../user-blocks/user-blocks.service';
import { promotionTypeToResponse } from '../promotions/promotion-plans.constants';
import { ArchiveListingDto } from '../listings/dto/archive-listing.dto';
import { LISTING_PHOTO_REQUIRED } from '../listings/listings.service';
import { AdminRegistrationStatsDto } from './dto/admin-registration-stats.dto';
import { BlockUserDto, UnblockUserDto, UpdateUserBlockDto } from './dto/block-user.dto';
import { ListAdminBonusAnalyticsDto } from './dto/list-admin-bonus-analytics.dto';
import { ListAdminPointsPurchasesDto } from './dto/list-admin-points-purchases.dto';
import { ListRaffleParticipantsDto } from './dto/list-raffle-participants.dto';
import { calculateRaffleTickets } from './raffle-ticket-calculation';
import { ListAdminPromotionsDto } from './dto/list-admin-promotions.dto';
import { ListAdminWalletTransactionsDto } from './dto/list-admin-wallet-transactions.dto';
import { ListAdminBlocksDto } from './dto/list-admin-blocks.dto';
import { ListAdminListingsDto } from './dto/list-admin-listings.dto';
import { ListAdminUsersDto } from './dto/list-admin-users.dto';
import { ListDeletedUsersDto } from './dto/list-deleted-users.dto';
import { AdminAnalyticsPeriodDto } from './dto/admin-marketplace-analytics.dto';
import { currentHttpMetrics } from '../../common/server-metrics';
import { AdminDashboardSignal } from '../../common/admin-dashboard-signal';

const promotionStatusFromInput = (
  value?: string,
): PromotionStatus | undefined => {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'active':
      return PromotionStatus.ACTIVE;
    case 'expired':
      return PromotionStatus.EXPIRED;
    case 'cancelled':
      return PromotionStatus.CANCELLED;
    default:
      return undefined;
  }
};

const MOSCOW_OFFSET_MS = 3 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

export const moscowCalendarBounds = (date: Date) => {
  const shifted = new Date(date.getTime() + MOSCOW_OFFSET_MS);
  const year = shifted.getUTCFullYear();
  const monthIndex = shifted.getUTCMonth();
  const day = shifted.getUTCDate();
  const utcFromMoscow = (
    yearValue: number,
    monthIndexValue: number,
    dayValue: number,
  ) => new Date(
    Date.UTC(yearValue, monthIndexValue, dayValue) - MOSCOW_OFFSET_MS,
  );

  return {
    year,
    month: monthIndex + 1,
    yearStart: utcFromMoscow(year, 0, 1),
    yearEnd: utcFromMoscow(year + 1, 0, 1),
    monthStart: utcFromMoscow(year, monthIndex, 1),
    nextMonthStart: utcFromMoscow(year, monthIndex + 1, 1),
    dayStart: utcFromMoscow(year, monthIndex, day),
    nextDayStart: utcFromMoscow(year, monthIndex, day + 1),
  };
};

const moscowDateKey = (date: Date) => {
  const shifted = new Date(date.getTime() + MOSCOW_OFFSET_MS);
  return [
    shifted.getUTCFullYear(),
    String(shifted.getUTCMonth() + 1).padStart(2, '0'),
    String(shifted.getUTCDate()).padStart(2, '0'),
  ].join('-');
};

const promotionTypeFromInput = (
  value?: string,
): PromotionType | undefined => {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'showcase':
      return PromotionType.SHOWCASE;
    case 'bump':
      return PromotionType.BUMP;
    case 'vip':
      return PromotionType.VIP;
    case 'turbo':
      return PromotionType.TURBO;
    default:
      return undefined;
  }
};

const walletTransactionTypeFromInput = (
  value?: string,
): WalletTransactionType | undefined => {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'accrual':
      return WalletTransactionType.ACCRUAL;
    case 'spend':
      return WalletTransactionType.SPEND;
    case 'refund':
      return WalletTransactionType.REFUND;
    default:
      return undefined;
  }
};

const protectedAdminPhones = new Set<string>([
  '79288888645',
  '79306939954',
]);

const moderationDiffFields = [
  'title',
  'description',
  'price',
  'city',
  'category',
  'subcategory',
  'address',
  'phone_hidden',
  'delivery',
  'car',
  'deal_type',
  'real_estate_type',
  'clothes_type',
  'clothes_size',
  'oem_part_number',
] as const;

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly appVisitsService: AppVisitsService,
    private readonly notificationsService: NotificationsService,
    private readonly reviewsService: ReviewsService,
    private readonly storageService: StorageService,
    private readonly userBlocksService: UserBlocksService,
    @Optional() @Inject(SavedSearchAlertsService) private readonly savedSearchAlerts: SavedSearchAlertsService | undefined,
    private readonly accountDeletion: AccountDeletionService,
    @Optional() private readonly adminDashboardSignal?: AdminDashboardSignal,
  ) {}

  private pageLimit(value: number | undefined, fallback: number, max = 100) {
    const parsed = Number(value ?? fallback);
    if (!Number.isFinite(parsed)) return fallback;
    return Math.min(Math.max(Math.trunc(parsed), 1), max);
  }

  private analyticsStart(period = 'month', now = new Date()) {
    const bounds = moscowCalendarBounds(now);
    if (period === 'today') return bounds.dayStart;
    if (period === '7d') return new Date(now.getTime() - 7 * 86400000);
    if (period === 'month') return bounds.monthStart;
    return null;
  }

  async getZeroResultSearches(query: AdminAnalyticsPeriodDto) {
    const from = this.analyticsStart(query.period);
    const contains = query.search?.normalize('NFKC').trim().toLocaleLowerCase('ru-RU') ?? '';
    const limit = this.pageLimit(query.limit, 30);
    let cursor: { count: number; lastSearchedAt: Date; normalizedQuery: string } | null = null;
    if (query.cursor) {
      try {
        const parsed = JSON.parse(Buffer.from(query.cursor, 'base64url').toString('utf8')) as Record<string, unknown>;
        const date = new Date(String(parsed.lastSearchedAt ?? ''));
        if (Number.isInteger(parsed.count) && Number(parsed.count) > 0 && !Number.isNaN(date.getTime()) && typeof parsed.normalizedQuery === 'string') {
          cursor = { count: Number(parsed.count), lastSearchedAt: date, normalizedQuery: parsed.normalizedQuery };
        }
      } catch { /* Invalid cursors simply start from the first page. */ }
    }
    type Row = { query: string; normalized_query: string; count: bigint; last_searched_at: Date };
    const rows = await this.prisma.$queryRaw<Row[]>(Prisma.sql`
      WITH grouped AS (
        SELECT
          "normalized_query",
          (array_agg("query" ORDER BY "created_at" DESC, "id" DESC))[1] AS "query",
          count(*)::bigint AS "count",
          max("created_at") AS "last_searched_at"
        FROM "zero_result_searches"
        WHERE 1 = 1
          ${from ? Prisma.sql`AND "created_at" >= ${from}` : Prisma.empty}
          ${contains ? Prisma.sql`AND "normalized_query" ILIKE ${`%${contains}%`}` : Prisma.empty}
        GROUP BY "normalized_query"
      )
      SELECT "query", "normalized_query", "count", "last_searched_at"
      FROM grouped
      WHERE 1 = 1
        ${cursor ? Prisma.sql`AND (
          "count" < ${cursor.count} OR
          ("count" = ${cursor.count} AND "last_searched_at" < ${cursor.lastSearchedAt}) OR
          ("count" = ${cursor.count} AND "last_searched_at" = ${cursor.lastSearchedAt} AND "normalized_query" > ${cursor.normalizedQuery})
        )` : Prisma.empty}
      ORDER BY "count" DESC, "last_searched_at" DESC, "normalized_query" ASC
      LIMIT ${limit + 1}
    `);
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    const last = page.at(-1);
    return {
      items: page.map((row) => ({
        query: row.query,
        normalized_query: row.normalized_query,
        count: Number(row.count),
        last_searched_at: row.last_searched_at.toISOString(),
      })),
      has_more: hasMore,
      next_cursor: hasMore && last ? Buffer.from(JSON.stringify({
        count: Number(last.count),
        lastSearchedAt: last.last_searched_at.toISOString(),
        normalizedQuery: last.normalized_query,
      })).toString('base64url') : null,
    };
  }

  async getAllSearches(query: AdminAnalyticsPeriodDto) {
    const from = this.analyticsStart(query.period);
    const contains = query.search?.normalize('NFKC').trim().toLocaleLowerCase('ru-RU') ?? '';
    const limit = this.pageLimit(query.limit, 30);
    let cursor: { count: number; lastSearchedAt: Date; normalizedQuery: string } | null = null;
    if (query.cursor) {
      try {
        const parsed = JSON.parse(Buffer.from(query.cursor, 'base64url').toString('utf8')) as Record<string, unknown>;
        const date = new Date(String(parsed.lastSearchedAt ?? ''));
        if (Number.isInteger(parsed.count) && Number(parsed.count) > 0 && !Number.isNaN(date.getTime()) && typeof parsed.normalizedQuery === 'string') {
          cursor = { count: Number(parsed.count), lastSearchedAt: date, normalizedQuery: parsed.normalizedQuery };
        }
      } catch { /* Invalid cursors start at the first page. */ }
    }
    type Row = { query: string; normalized_query: string; count: bigint; last_searched_at: Date; with_results: bigint };
    const rows = await this.prisma.$queryRaw<Row[]>(Prisma.sql`
      WITH grouped AS (
        SELECT "normalized_query",
          (array_agg("query" ORDER BY "created_at" DESC, "id" DESC))[1] AS "query",
          count(*)::bigint AS "count",
          count(*) FILTER (WHERE "result_count" > 0)::bigint AS "with_results",
          max("created_at") AS "last_searched_at"
        FROM "search_attempts"
        WHERE 1 = 1
          ${from ? Prisma.sql`AND "created_at" >= ${from}` : Prisma.empty}
          ${contains ? Prisma.sql`AND "normalized_query" ILIKE ${`%${contains}%`}` : Prisma.empty}
        GROUP BY "normalized_query"
      )
      SELECT "query", "normalized_query", "count", "with_results", "last_searched_at"
      FROM grouped
      WHERE 1 = 1
        ${cursor ? Prisma.sql`AND (
          "count" < ${cursor.count} OR
          ("count" = ${cursor.count} AND "last_searched_at" < ${cursor.lastSearchedAt}) OR
          ("count" = ${cursor.count} AND "last_searched_at" = ${cursor.lastSearchedAt} AND "normalized_query" > ${cursor.normalizedQuery})
        )` : Prisma.empty}
      ORDER BY "count" DESC, "last_searched_at" DESC, "normalized_query" ASC
      LIMIT ${limit + 1}
    `);
    const page = rows.slice(0, limit);
    const last = page.at(-1);
    const hasMore = rows.length > limit;
    return {
      items: page.map((row) => ({
        query: row.query,
        normalized_query: row.normalized_query,
        count: Number(row.count),
        with_results: Number(row.with_results),
        last_searched_at: row.last_searched_at.toISOString(),
      })),
      has_more: hasMore,
      next_cursor: hasMore && last ? Buffer.from(JSON.stringify({
        count: Number(last.count),
        lastSearchedAt: last.last_searched_at.toISOString(),
        normalizedQuery: last.normalized_query,
      })).toString('base64url') : null,
    };
  }

  async getRepeatedMessages() {
    type Row = {
      sender_id: string; display_name: string; phone: string | null;
      sample_text: string; recipients: bigint; messages: bigint; last_sent_at: Date;
    };
    const rows = await this.prisma.$queryRaw<Row[]>(Prisma.sql`
      WITH candidates AS (
        SELECT m."sender_id", m."text", m."created_at", m."id",
          CASE WHEN c."buyer_id" = m."sender_id" THEN c."seller_id" ELSE c."buyer_id" END AS recipient_id,
          lower(regexp_replace(btrim(m."text"), '\\s+', ' ', 'g')) AS normalized_text
        FROM "chat_messages" m
        JOIN "chats" c ON c."id" = m."chat_id"
        WHERE m."created_at" >= now() - interval '24 hours'
          AND m."deleted_at" IS NULL AND m."message_type" = 'TEXT'
          AND length(btrim(m."text")) >= 10
      ), grouped AS (
        SELECT "sender_id", normalized_text,
          count(DISTINCT recipient_id)::bigint AS recipients,
          count(*)::bigint AS messages,
          max("created_at") AS last_sent_at,
          (array_agg("text" ORDER BY "created_at" DESC, "id" DESC))[1] AS sample_text
        FROM candidates
        GROUP BY "sender_id", normalized_text
        HAVING count(DISTINCT recipient_id) >= 6
      )
      SELECT g."sender_id", u."display_name", u."phone", g.sample_text,
        g.recipients, g.messages, g.last_sent_at
      FROM grouped g JOIN "users" u ON u."id" = g."sender_id"
      WHERE u."deleted_at" IS NULL
      ORDER BY g.last_sent_at DESC
      LIMIT 100
    `);
    return { items: rows.map((row) => ({
      sender_id: row.sender_id,
      display_name: row.display_name,
      phone: row.phone,
      sample_text: row.sample_text,
      recipients: Number(row.recipients),
      messages: Number(row.messages),
      last_sent_at: row.last_sent_at.toISOString(),
    })) };
  }

  async getPopularCategories(query: AdminAnalyticsPeriodDto) {
    const from = this.analyticsStart(query.period);
    const rows = await this.prisma.$queryRaw<Array<{ category: string; views: bigint }>>(Prisma.sql`
      SELECT l."category", count(*)::bigint AS "views"
      FROM "listing_views" v
      JOIN "listings" l ON l."id" = v."listing_id"
      WHERE l."deleted_at" IS NULL
        ${from ? Prisma.sql`AND v."viewed_at" >= ${from}` : Prisma.empty}
      GROUP BY l."category"
      ORDER BY "views" DESC
      LIMIT 200
    `);
    const items = rows.map((row) => ({ category: row.category, views: Number(row.views) }));
    return { total: items.length, metric: 'views', items };
  }

  async getZeroViewListings(query: AdminAnalyticsPeriodDto) {
    const from = this.analyticsStart(query.period);
    const where: Prisma.ListingWhereInput = {
      deletedAt: null,
      viewCount: 0,
      ...(from ? { createdAt: { gte: from } } : {}),
    };
    const [total, rows] = await Promise.all([
      this.prisma.listing.count({ where }),
      this.prisma.listing.findMany({
        where,
        include: { photos: { orderBy: { sortOrder: 'asc' }, take: 1 } },
        orderBy: { createdAt: query.sort === 'newest' ? 'desc' : 'asc' },
        take: 200,
      }),
    ]);
    return {
      total,
      items: rows.map((item) => serializeListing(item)),
    };
  }

  private encodeAdminCursor(value: Record<string, string>) {
    return Buffer.from(JSON.stringify(value)).toString('base64url');
  }

  private decodeAdminCursor(cursor?: string) {
    const normalized = cursor?.trim();
    if (!normalized) return null;
    try {
      const parsed = JSON.parse(
        Buffer.from(normalized, 'base64url').toString('utf8'),
      );
      if (!parsed || typeof parsed !== 'object') return null;
      return parsed as Record<string, string>;
    } catch {
      return null;
    }
  }

  private dateIdCursorWhere(
    field: 'createdAt' | 'updatedAt' | 'startsAt' | 'deletedAt',
    cursor?: string,
  ) {
    const decoded = this.decodeAdminCursor(cursor);
    const rawDate = decoded?.[field];
    const id = decoded?.id;
    if (!rawDate || !id) return {};
    const date = new Date(rawDate);
    if (Number.isNaN(date.getTime())) return {};
    return {
      OR: [
        { [field]: { lt: date } },
        { [field]: date, id: { lt: id } },
      ],
    };
  }

  private pageInfo<T extends { id: string }>(
    rows: T[],
    limit: number,
    cursorFor: (row: T) => Record<string, string>,
  ) {
    const items = rows.slice(0, limit);
    const last = rows.length > limit ? items[items.length - 1] : null;
    return {
      items,
      hasMore: rows.length > limit,
      nextCursor: last ? this.encodeAdminCursor(cursorFor(last)) : null,
    };
  }

  async getDashboardStats(now = new Date()) {
    const calendar = moscowCalendarBounds(now);
    const monthStart = calendar.monthStart;
    const days30 = new Date(now.getTime() - 30 * 86400000);
    const days14 = new Date(now.getTime() - 14 * 86400000);
    const onlineCutoff = new Date(now.getTime() - 2 * 60000);
    const deletedUsers = await this.prisma.user.count({
      where: { status: UserStatus.DELETED, deletedAt: { not: null } },
    });

    const [users, onlineUsers, todayVisits, listings, activeListings, pendingModeration, sold, sales30d, supportOpen, reportsOpen, activeAds, newListings14d, newListingsDaily, spentPoints30d, pointsPurchasesMonth, revenue, promotionsToday, zeroResultSearches, allSearches, zeroViewListings] =
      await Promise.all([
        this.prisma.user.count({
          where: {
            deletedAt: null,
            status: {
              not: UserStatus.DELETED,
            },
          },
        }),
        this.prisma.userPresence.count({
          where: {
            isOnline: true,
            lastSeen: {
              gte: onlineCutoff,
            },
          },
        }),
        this.appVisitsService.countToday(now),
        this.prisma.listing.count({
          where: { deletedAt: null },
        }),
        this.prisma.listing.count({
          where: {
            deletedAt: null,
            status: ListingStatus.APPROVED,
          },
        }),
        this.countModerationReady(),
        this.prisma.listing.count({
          where: {
            deletedAt: null,
            status: ListingStatus.SOLD,
          },
        }),
        this.prisma.listing.count({
          where: {
            deletedAt: null,
            status: ListingStatus.SOLD,
            archivedAt: {
              gte: days30,
            },
          },
        }),
        this.prisma.supportTicket.count(),
        this.prisma.report.count({
          where: { status: 'open' },
        }),
        this.prisma.feedAd.count({
          where: {
            placement: FeedAdPlacement.HOME,
            isActive: true,
            OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
          },
        }),
        this.prisma.listing.count({
          where: {
            createdAt: {
              gte: days14,
            },
          },
        }),
        this.prisma.listing.findMany({
          where: {
            createdAt: {
              gte: days14,
            },
          },
          select: {
            createdAt: true,
          },
        }),
        this.prisma.walletTransaction.aggregate({
          _sum: {
            amount: true,
          },
          where: {
            createdAt: {
              gte: days30,
              lte: now,
            },
            type: WalletTransactionType.SPEND,
          },
        }),
        this.getPointsPurchasesSummary({
          from: monthStart.toISOString(),
          to: now.toISOString(),
        }),
        this.getDashboardRevenue(now),
        this.getDashboardPromotions(now),
        this.prisma.zeroResultSearch.count({
          where: { createdAt: { gte: monthStart } },
        }),
        this.prisma.searchAttempt.count({
          where: { createdAt: { gte: monthStart } },
        }),
        this.prisma.listing.count({
          where: { deletedAt: null, viewCount: 0 },
        }),
      ]);

    const dailyMap = new Map<string, number>();
    for (let index = 13; index >= 0; index -= 1) {
      const day = new Date(now.getTime() - index * 86400000);
      const key = moscowDateKey(day);
      dailyMap.set(key, 0);
    }
    for (const item of newListingsDaily) {
      const key = moscowDateKey(item.createdAt);
      dailyMap.set(key, (dailyMap.get(key) ?? 0) + 1);
    }
    const listingsDaily = Array.from(dailyMap.entries()).map(([day, count]) => ({
      day,
      listings_new: count,
    }));

    return {
      source: 'timeweb',
      stats: {
        users,
        deletedUsers,
        onlineUsers,
        todayVisits,
        listings,
        activeListings,
        pendingModeration,
        sold,
        sales30d,
        supportTickets: supportOpen,
        supportOpen,
        reportsOpen,
        activeAds,
        newListings14d,
        spentPoints30d: spentPoints30d._sum.amount ?? 0,
        pointsPurchasesMonth,
        revenue,
        promotionsToday,
        zeroResultSearches,
        allSearches,
        zeroViewListings,
      },
      daily: {
        listings: listingsDaily,
      },
    };
  }

  async getDashboardMetrics(scopesInput?: string, now = new Date()) {
    const supported = new Set([
      'users',
      'presence',
      'visits',
      'listings',
      'wallet',
      'payments',
      'promotions',
      'support',
      'reports',
      'ads',
      'searches',
    ]);
    const scopes = [...new Set((scopesInput ?? '')
      .split(',')
      .map((scope) => scope.trim())
      .filter((scope) => supported.has(scope)))];
    if (scopes.length === 0) {
      throw new BadRequestException('Не указаны поддерживаемые Dashboard scopes');
    }

    const calendar = moscowCalendarBounds(now);
    const days30 = new Date(now.getTime() - 30 * 86400000);
    const onlineCutoff = new Date(now.getTime() - 2 * 60000);
    const parts = await Promise.all(scopes.map(async (scope) => {
      switch (scope) {
        case 'users': {
          const [users, deletedUsers] = await Promise.all([
            this.prisma.user.count({
              where: { deletedAt: null, status: { not: UserStatus.DELETED } },
            }),
            this.prisma.user.count({
              where: { status: UserStatus.DELETED, deletedAt: { not: null } },
            }),
          ]);
          return { users, deletedUsers };
        }
        case 'presence':
          return {
            onlineUsers: await this.prisma.userPresence.count({
              where: { isOnline: true, lastSeen: { gte: onlineCutoff } },
            }),
          };
        case 'visits':
          return { todayVisits: await this.appVisitsService.countToday(now) };
        case 'listings': {
          const [listings, activeListings, pendingModeration, sold, sales30d, zeroViewListings] =
            await Promise.all([
              this.prisma.listing.count({ where: { deletedAt: null } }),
              this.prisma.listing.count({
                where: { deletedAt: null, status: ListingStatus.APPROVED },
              }),
              this.countModerationReady(),
              this.prisma.listing.count({
                where: { deletedAt: null, status: ListingStatus.SOLD },
              }),
              this.prisma.listing.count({
                where: {
                  deletedAt: null,
                  status: ListingStatus.SOLD,
                  archivedAt: { gte: days30 },
                },
              }),
              this.prisma.listing.count({
                where: { deletedAt: null, viewCount: 0 },
              }),
            ]);
          return { listings, activeListings, pendingModeration, sold, sales30d, zeroViewListings };
        }
        case 'wallet': {
          const aggregate = await this.prisma.walletTransaction.aggregate({
            _sum: { amount: true },
            where: {
              createdAt: { gte: days30, lte: now },
              type: WalletTransactionType.SPEND,
            },
          });
          return { spentPoints30d: aggregate._sum.amount ?? 0 };
        }
        case 'payments': {
          const [pointsPurchasesMonth, revenue] = await Promise.all([
            this.getPointsPurchasesSummary({
              from: calendar.monthStart.toISOString(),
              to: now.toISOString(),
            }),
            this.getDashboardRevenue(now),
          ]);
          return {
            pointsPurchasesMonth,
            revenue,
          };
        }
        case 'promotions':
          return { promotionsToday: await this.getDashboardPromotions(now) };
        case 'support':
          return { supportTickets: await this.prisma.supportTicket.count() };
        case 'reports':
          return {
            reportsOpen: await this.prisma.report.count({ where: { status: 'open' } }),
          };
        case 'ads':
          return {
            activeAds: await this.prisma.feedAd.count({
              where: {
                placement: FeedAdPlacement.HOME,
                isActive: true,
                OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
              },
            }),
          };
        case 'searches': {
          const [zeroResultSearches, allSearches] = await Promise.all([
            this.prisma.zeroResultSearch.count({
              where: { createdAt: { gte: calendar.monthStart } },
            }),
            this.prisma.searchAttempt.count({
              where: { createdAt: { gte: calendar.monthStart } },
            }),
          ]);
          return { zeroResultSearches, allSearches };
        }
        default:
          return {};
      }
    }));

    return {
      source: 'timeweb',
      scopes,
      stats: Object.assign({}, ...parts),
    };
  }

  async getDashboardRevenue(now = new Date()) {
    const { dayStart } = moscowCalendarBounds(now);
    const starts = [
      dayStart,
      new Date(dayStart.getTime() - 6 * DAY_MS),
      new Date(dayStart.getTime() - 29 * DAY_MS),
    ];
    const totals = await Promise.all(starts.map((from) =>
      this.prisma.payment.aggregate({
        _sum: { amountRub: true },
        where: {
          provider: PaymentProvider.YOOKASSA,
          status: PaymentStatus.SUCCEEDED,
          currency: 'RUB',
          creditedAt: { gte: from, lte: now },
        },
      }),
    ));
    return {
      todayRub: this.numberFromDb(totals[0]._sum.amountRub),
      days7Rub: this.numberFromDb(totals[1]._sum.amountRub),
      days30Rub: this.numberFromDb(totals[2]._sum.amountRub),
    };
  }

  async getDashboardPromotions(now = new Date()) {
    const { dayStart } = moscowCalendarBounds(now);
    const reasons = [
      WalletTransactionReason.PROMOTION_BUMP,
      WalletTransactionReason.PROMOTION_VIP,
      WalletTransactionReason.PROMOTION_SHOWCASE,
      WalletTransactionReason.PROMOTION_TURBO,
    ];
    const rows = await this.prisma.walletTransaction.groupBy({
      by: ['reason'],
      _count: { _all: true },
      _sum: { amount: true },
      where: {
        type: WalletTransactionType.SPEND,
        reason: { in: reasons },
        createdAt: { gte: dayStart, lte: now },
      },
    });
    const counts = new Map(rows.map((row) => [row.reason, row._count._all]));
    return {
      byType: {
        bump: counts.get(WalletTransactionReason.PROMOTION_BUMP) ?? 0,
        vip: counts.get(WalletTransactionReason.PROMOTION_VIP) ?? 0,
        showcase: counts.get(WalletTransactionReason.PROMOTION_SHOWCASE) ?? 0,
        turbo: counts.get(WalletTransactionReason.PROMOTION_TURBO) ?? 0,
      },
      total: rows.reduce((sum, row) => sum + row._count._all, 0),
      pointsSpent: rows.reduce((sum, row) => sum + (row._sum.amount ?? 0), 0),
    };
  }

  async getServerStatus() {
    const startedAt = process.hrtime.bigint();
    let databaseOk = true;
    try {
      await this.prisma.$queryRaw`SELECT 1`;
    } catch {
      databaseOk = false;
    }
    const databaseResponseMs = Math.round(
      Number(process.hrtime.bigint() - startedAt) / 1_000_000,
    );
    const totalMemoryBytes = os.totalmem();
    const usedMemoryBytes = Math.max(0, totalMemoryBytes - os.freemem());
    const cores = Math.max(1, os.cpus().length);
    const cpuPercent = Math.min(100, Math.max(0, (os.loadavg()[0] / cores) * 100));
    const processMemoryBytes = process.memoryUsage().rss;
    let diskTotalBytes: number | null = null;
    let diskUsedBytes: number | null = null;
    try {
      const disk = fs.statfsSync(process.cwd());
      diskTotalBytes = Number(disk.blocks) * Number(disk.bsize);
      diskUsedBytes = diskTotalBytes - Number(disk.bavail) * Number(disk.bsize);
    } catch {
      // Some containers do not expose filesystem statistics.
    }
    return {
      source: 'server',
      capturedAt: new Date().toISOString(),
      cpu: { percent: Number(cpuPercent.toFixed(1)), cores },
      memory: {
        usedBytes: usedMemoryBytes,
        totalBytes: totalMemoryBytes,
        percent: Number(((usedMemoryBytes / totalMemoryBytes) * 100).toFixed(1)),
        applicationBytes: processMemoryBytes,
      },
      disk: {
        usedBytes: diskUsedBytes,
        totalBytes: diskTotalBytes,
        percent: diskTotalBytes && diskUsedBytes != null
          ? Number(((diskUsedBytes / diskTotalBytes) * 100).toFixed(1))
          : null,
      },
      database: { ok: databaseOk, responseMs: databaseResponseMs },
      http: currentHttpMetrics(),
      uptimeSeconds: Math.floor(process.uptime()),
    };
  }

  async listUsers(query: ListAdminUsersDto = {}) {
    const limit = this.pageLimit(query.limit, 100);
    const search = query.search?.trim();
    const phoneDigits = (search ?? '').replace(/\D/g, '');
    const cursorWhere = this.dateIdCursorWhere('createdAt', query.cursor);
    const where: Prisma.UserWhereInput = {
      deletedAt: null,
      status: {
        not: UserStatus.DELETED,
      },
      ...(Object.keys(cursorWhere).length > 0 ? { AND: [cursorWhere] } : {}),
      ...(search
        ? {
            OR: [
              ...(this.isUuid(search) ? [{ id: search }] : []),
              { displayName: { contains: search, mode: 'insensitive' } },
              { name: { contains: search, mode: 'insensitive' } },
              { phone: { contains: search } },
              ...(phoneDigits.length >= 4
                ? [{ phone: { contains: phoneDigits } }]
                : []),
            ],
          }
        : {}),
    };
    const users = await this.prisma.user.findMany({
      where: {
        ...where,
      },
      include: {
        adminProfile: true,
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const page = this.pageInfo(users, limit, (user) => ({
      createdAt: user.createdAt.toISOString(),
      id: user.id,
    }));

    return {
      source: 'timeweb',
      items: page.items.map((user) => serializeUser(user, { includePrivate: true })),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      limit,
    };
  }

  async listDeletedUsers(query: ListDeletedUsersDto = {}) {
    const limit = this.pageLimit(query.limit, 50);
    const period = query.period ?? 'all';
    const dateRange = this.adminPeriodRange(period);
    const where: Prisma.UserWhereInput = {
      status: UserStatus.DELETED,
      deletedAt: {
        not: null,
        ...(dateRange ? { gte: dateRange } : {}),
      },
      ...this.dateIdCursorWhere('deletedAt', query.cursor),
    };
    const [rows, total] = await Promise.all([
      this.prisma.user.findMany({
        where,
        orderBy: [{ deletedAt: 'desc' }, { id: 'desc' }],
        take: limit + 1,
        select: { id: true, displayName: true, name: true, phone: true, deletedAt: true },
      }),
      this.prisma.user.count({ where: {
        status: UserStatus.DELETED,
        deletedAt: { not: null, ...(dateRange ? { gte: dateRange } : {}) },
      } }),
    ]);
    const page = this.pageInfo(rows, limit, (user) => ({
      deletedAt: user.deletedAt!.toISOString(),
      id: user.id,
    }));
    const identities = await this.prisma.deletedUserIdentity.findMany({
      where: { userId: { in: page.items.map((user) => user.id) } },
    });
    const identityByUser = new Map(identities.map((identity) => [identity.userId, identity]));
    return {
      source: 'timeweb',
      items: page.items.map((user) => {
        const identity = identityByUser.get(user.id);
        return {
          id: user.id,
          display_name: identity?.displayName || user.displayName.trim() || user.name.trim() || 'Удалённый пользователь',
          phone: identity?.phone || user.phone?.trim() || null,
          deleted_at: user.deletedAt!.toISOString(),
        };
      }),
      total,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      limit,
    };
  }

  private adminPeriodRange(period: string, now = new Date()) {
    if (period === 'all') return null;
    const bounds = moscowCalendarBounds(now);
    if (period === 'today') return bounds.dayStart;
    if (period === 'month') return bounds.monthStart;
    if (period === '7d') return new Date(now.getTime() - 7 * 86400000);
    return null;
  }

  async getUserRegistrationStats(query: AdminRegistrationStatsDto = {}) {
    const now = new Date();
    const currentBounds = moscowCalendarBounds(now);
    const currentYear = currentBounds.year;
    const currentMonth = currentBounds.month;
    const requestedYear = Number.isInteger(query.year) ? query.year! : currentYear;
    const maximumSafeYear = currentYear + 100;
    if (requestedYear < 2000 || requestedYear > maximumSafeYear) {
      throw new BadRequestException(
        `Год должен быть в диапазоне 2000–${maximumSafeYear}`,
      );
    }
    const year = requestedYear;
    const yearBounds = moscowCalendarBounds(
      new Date(Date.UTC(year, 0, 1) - MOSCOW_OFFSET_MS),
    );
    const activeUserWhere: Prisma.UserWhereInput = {
      deletedAt: null,
      status: {
        not: UserStatus.DELETED,
      },
    };

    const parseMoscowDate = (value: string | undefined) => {
      if (!value) return null;
      const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
      if (!match) return null;
      const yearValue = Number(match[1]);
      const monthIndex = Number(match[2]) - 1;
      const dayValue = Number(match[3]);
      const date = new Date(
        Date.UTC(yearValue, monthIndex, dayValue) - MOSCOW_OFFSET_MS,
      );
      const shifted = new Date(date.getTime() + MOSCOW_OFFSET_MS);
      if (
        shifted.getUTCFullYear() !== yearValue ||
        shifted.getUTCMonth() !== monthIndex ||
        shifted.getUTCDate() !== dayValue
      ) {
        throw new BadRequestException('Некорректная дата периода');
      }
      return date;
    };
    const customFrom = parseMoscowDate(query.from);
    const customToStart = parseMoscowDate(query.to);
    if ((customFrom == null) !== (customToStart == null)) {
      throw new BadRequestException('Укажите обе даты периода');
    }
    const customTo = customToStart == null
      ? null
      : new Date(customToStart.getTime() + DAY_MS);
    if (customFrom && customTo && customFrom >= customTo) {
      throw new BadRequestException('Дата начала должна быть раньше даты окончания');
    }

    const [
      totalUsers,
      firstUser,
      currentMonthCount,
      todayCount,
      yesterdayCount,
      last7DaysCount,
      customRangeCount,
      monthRows,
    ] =
      await Promise.all([
        this.prisma.user.count({ where: activeUserWhere }),
        this.prisma.user.findFirst({
          orderBy: { createdAt: 'asc' },
          select: { createdAt: true },
        }),
        this.prisma.user.count({
          where: {
            ...activeUserWhere,
            createdAt: {
              gte: currentBounds.monthStart,
              lt: currentBounds.nextMonthStart,
            },
          },
        }),
        this.prisma.user.count({
          where: {
            ...activeUserWhere,
            createdAt: {
              gte: currentBounds.dayStart,
              lt: currentBounds.nextDayStart,
            },
          },
        }),
        this.prisma.user.count({
          where: {
            ...activeUserWhere,
            createdAt: {
              gte: new Date(currentBounds.dayStart.getTime() - DAY_MS),
              lt: currentBounds.dayStart,
            },
          },
        }),
        this.prisma.user.count({
          where: {
            ...activeUserWhere,
            createdAt: {
              gte: new Date(currentBounds.dayStart.getTime() - 6 * DAY_MS),
              lt: currentBounds.nextDayStart,
            },
          },
        }),
        customFrom && customTo
          ? this.prisma.user.count({
              where: {
                ...activeUserWhere,
                createdAt: { gte: customFrom, lt: customTo },
              },
            })
          : Promise.resolve(null),
        this.prisma.$queryRaw<
          Array<{ month: number | bigint; count: number | bigint }>
        >`
          SELECT
            EXTRACT(MONTH FROM u."created_at" AT TIME ZONE 'Europe/Moscow')::int AS month,
            COUNT(*)::bigint AS count
          FROM "users" u
          WHERE u."deleted_at" IS NULL
            AND u."status" <> ${UserStatus.DELETED}::"UserStatus"
            AND u."created_at" >= ${yearBounds.yearStart}
            AND u."created_at" < ${yearBounds.yearEnd}
          GROUP BY month
        `,
      ]);

    const firstYear = firstUser
      ? moscowCalendarBounds(firstUser.createdAt).year
      : currentYear;
    const availableYears = Array.from(
      { length: Math.max(currentYear - firstYear + 1, 0) },
      (_, index) => firstYear + index,
    );
    const countsByMonth = new Map<number, number>();
    for (const row of monthRows) {
      countsByMonth.set(
        this.numberFromDb(row.month),
        this.numberFromDb(row.count),
      );
    }
    const startMonth = year === firstYear && firstUser
      ? moscowCalendarBounds(firstUser.createdAt).month
      : 1;
    const endMonth = year === currentYear ? currentMonth : 12;
    const months = !firstUser || year < firstYear || year > currentYear || startMonth > endMonth
      ? []
      : Array.from(
          { length: endMonth - startMonth + 1 },
          (_, index) => endMonth - index,
        ).map((month) => ({
          month,
          count: countsByMonth.get(month) ?? 0,
        }));

    return {
      source: 'timeweb',
      year,
      available_years: availableYears,
      total_users: totalUsers,
      todayCount,
      yesterday_count: yesterdayCount,
      last_7_days_count: last7DaysCount,
      current_month_count: currentMonthCount,
      custom_range: customFrom && customToStart
        ? {
            from: query.from,
            to: query.to,
            count: customRangeCount,
          }
        : null,
      months,
    };
  }

  async listOnlineUsers() {
    const onlineCutoff = new Date(Date.now() - 2 * 60 * 1000);
    const users = await this.prisma.user.findMany({
      where: {
        deletedAt: null,
        status: {
          not: UserStatus.DELETED,
        },
        presence: {
          is: {
            isOnline: true,
            lastSeen: { gte: onlineCutoff },
          },
        },
      },
      include: {
        presence: true,
      },
    });

    const items = users
      .map((user) => {
        const lastSeenAt = user.presence?.lastSeen ?? null;
        const isOnline =
          user.presence?.isOnline === true &&
          lastSeenAt != null &&
          lastSeenAt >= onlineCutoff;

        return {
          id: user.id,
          display_name:
            user.displayName.trim() ||
            user.name.trim() ||
            user.phone?.trim() ||
            'Пользователь',
          name: user.name.trim() || user.displayName.trim() || 'Пользователь',
          phone: user.phone?.trim() || null,
          avatar_url: normalizeStoredMediaUrl(user.avatarUrl, {
            category: 'avatars',
          }),
          is_online: isOnline,
          last_seen_at: toIsoString(lastSeenAt),
        };
      })
      .filter((item) => item.is_online)
      .sort((left, right) => {
        const leftTime = Date.parse(left.last_seen_at ?? '1970-01-01T00:00:00.000Z');
        const rightTime = Date.parse(right.last_seen_at ?? '1970-01-01T00:00:00.000Z');
        return rightTime - leftTime;
      });

    return {
      source: 'timeweb',
      items,
    };
  }

  async listTodayVisits() {
    return this.appVisitsService.listToday();
  }

  async getUserById(id: string) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      include: {
        adminProfile: true,
      },
    });

    return {
      source: 'timeweb',
      user: user ? serializeUser(user, { includePrivate: true }) : null,
    };
  }

  private resolveBlockDuration(dto: BlockUserDto, now: Date) {
    const duration = (dto.duration ?? '').trim().toLowerCase();
    if (duration === 'permanent' || duration === 'forever') {
      return {
        type: UserBlockType.PERMANENT,
        endsAt: null,
      };
    }
    if (duration === 'custom') {
      const endsAt = dto.ends_at ? new Date(dto.ends_at) : null;
      if (!endsAt || Number.isNaN(endsAt.getTime()) || endsAt <= now) {
        throw new BadRequestException('Укажите будущую дату окончания блокировки');
      }
      return {
        type: UserBlockType.TEMPORARY,
        endsAt,
      };
    }

    const daysByDuration: Record<string, number> = {
      one_day: 1,
      '1_day': 1,
      '1d': 1,
      seven_days: 7,
      '7_days': 7,
      '7d': 7,
      thirty_days: 30,
      '30_days': 30,
      '30d': 30,
    };
    const days = daysByDuration[duration];
    if (!days) {
      throw new BadRequestException('Неизвестный срок блокировки');
    }
    return {
      type: UserBlockType.TEMPORARY,
      endsAt: new Date(now.getTime() + days * 24 * 60 * 60 * 1000),
    };
  }

  private serializeAdminBlock(block: any) {
    const user = block.user
      ? serializeUser(block.user, { includePrivate: true })
      : null;
    return {
      ...this.userBlocksService.serializeBlock(block),
      user,
      listing: block.listing ? serializeListing(block.listing) : null,
      admin: block.admin
        ? serializeUser(block.admin, { includePrivate: true })
        : null,
      support_tickets_count: block._count?.appeals ?? 0,
      previous_blocks_count: block.user?._count?.blocks ?? 0,
      violations_count: block.user?._count?.blocks ?? 0,
    };
  }

  async listBlocks(query: ListAdminBlocksDto | string = {}) {
    const status = typeof query === 'string' ? query : query.status;
    const limit = this.pageLimit(typeof query === 'string' ? undefined : query.limit, 100);
    const cursor = typeof query === 'string' ? undefined : query.cursor;
    const now = new Date();
    await this.prisma.userBlock.updateMany({
      where: {
        status: UserBlockStatus.ACTIVE,
        endsAt: {
          not: null,
          lte: now,
        },
      },
      data: {
        status: UserBlockStatus.EXPIRED,
      },
    });

    const normalized = (status ?? 'active').trim().toLowerCase();
    if (normalized === 'appeals') {
      const tickets = await this.prisma.supportTicket.findMany({
        where: {
          isBlockAppeal: true,
          ...this.dateIdCursorWhere('updatedAt', cursor),
        },
        include: {
          userBlock: true,
        },
        orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }],
        take: limit + 1,
      });
      const page = this.pageInfo(tickets, limit, (ticket) => ({
        updatedAt: ticket.updatedAt.toISOString(),
        id: ticket.id,
      }));
      return {
        source: 'timeweb',
        items: page.items.map((ticket) => ({
          id: ticket.id,
          ticket_id: ticket.id,
          user_id: ticket.userId,
          block_id: ticket.userBlockId,
          subject: ticket.subject,
          status: ticket.status.toLowerCase(),
          last_message: ticket.lastMessage,
          unread_for_admin: ticket.unreadForAdmin,
          created_at: ticket.createdAt.toISOString(),
          updated_at: ticket.updatedAt.toISOString(),
          block: this.userBlocksService.serializeBlock(ticket.userBlock),
        })),
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        limit,
      };
    }
    const where: Prisma.UserBlockWhereInput =
      normalized === 'history'
        ? {}
        : normalized === 'temporary'
          ? { type: UserBlockType.TEMPORARY, status: UserBlockStatus.ACTIVE }
          : normalized === 'permanent'
            ? { type: UserBlockType.PERMANENT, status: UserBlockStatus.ACTIVE }
            : normalized === 'finished' || normalized === 'completed'
              ? { status: { in: [UserBlockStatus.EXPIRED, UserBlockStatus.LIFTED] } }
              : { status: UserBlockStatus.ACTIVE };

    const blocks = await this.prisma.userBlock.findMany({
      where: {
        ...where,
        ...this.dateIdCursorWhere('startsAt', cursor),
      },
      include: {
        user: {
          include: {
            adminProfile: true,
            _count: {
              select: {
                blocks: true,
              },
            },
          },
        },
        listing: {
          include: {
            owner: {
              include: {
                adminProfile: true,
              },
            },
            photos: {
              orderBy: {
                sortOrder: 'asc',
              },
            },
          },
        },
        admin: {
          include: {
            adminProfile: true,
          },
        },
        _count: {
          select: {
            appeals: true,
          },
        },
      },
      orderBy: [{ startsAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const page = this.pageInfo(blocks, limit, (block) => ({
      startsAt: block.startsAt.toISOString(),
      id: block.id,
    }));

    return {
      source: 'timeweb',
      items: page.items.map((block) => this.serializeAdminBlock(block)),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      limit,
    };
  }

  async blockUser(
    userId: string,
    authUser: AuthenticatedUser,
    dto: BlockUserDto,
  ) {
    if (userId === authUser.userId) {
      throw new BadRequestException('Нельзя заблокировать текущий аккаунт администратора');
    }
    const reason = dto.reason?.trim() ?? '';
    if (!reason) {
      throw new BadRequestException('Причина блокировки обязательна');
    }
    const now = new Date();
    const duration = this.resolveBlockDuration(dto, now);
    const listingId = dto.listing_id?.trim() || undefined;

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, phone: true, deletedAt: true, status: true },
    });
    if (!user || user.deletedAt || user.status === UserStatus.DELETED) {
      throw new NotFoundException('Пользователь не найден');
    }

    const existing = await this.userBlocksService.getActiveBlock(userId);
    if (existing) {
      throw new BadRequestException('У пользователя уже есть активная блокировка');
    }

    const block = await this.prisma.$transaction(async (tx) => {
      const created = await tx.userBlock.create({
        data: {
          userId,
          listingId,
          adminId: authUser.userId,
          type: duration.type,
          status: UserBlockStatus.ACTIVE,
          reason,
          internalNote: dto.internal_note?.trim() || null,
          startsAt: now,
          endsAt: duration.endsAt,
        },
      });

      if (listingId) {
        await tx.listing.updateMany({
          where: { id: listingId, ownerId: userId },
          data: {
            status: ListingStatus.REJECTED,
            rejectionReason: reason,
            moderationNote: dto.internal_note?.trim() || reason,
            moderatedBy: authUser.userId,
            moderatedAt: now,
            publishedAt: null,
            archivedAt: null,
            deletedAt: null,
          },
        });
      }

      await tx.listing.updateMany({
        where: {
          ownerId: userId,
          status: ListingStatus.APPROVED,
        },
        data: {
          status: ListingStatus.ARCHIVED,
          archivedAt: now,
          publishedAt: null,
          moderationNote: 'Скрыто из ленты на время блокировки пользователя.',
        },
      });

      await tx.user.update({
        where: { id: userId },
        data: {
          status: UserStatus.BLOCKED,
          blockedAt: now,
          blockReason: reason,
        },
      });

      if (dto.ban_phone_identity === true && user.phone?.trim()) {
        await tx.blockedIdentity.create({
          data: {
            normalizedPhone: user.phone.trim(),
            userBlockId: created.id,
            bannedUntil: duration.endsAt,
            permanent: duration.type === UserBlockType.PERMANENT,
            reason,
          },
        });
      }

      await tx.auditLog.create({
        data: {
          actorUserId: authUser.userId,
          actorRole: 'admin',
          action: 'user.block',
          entityType: 'user',
          entityId: userId,
          newData: {
            blockId: created.id,
            listingId: listingId ?? null,
            duration: dto.duration,
            endsAt: duration.endsAt?.toISOString() ?? null,
          },
        },
      });

      return created;
    });

    await this.notificationsService.createSystemNotification({
      userId,
      title: 'Аккаунт заблокирован',
      body: reason,
      type: NotificationType.GENERIC,
      payload: {
        actionType: 'account_blocked',
        blockId: block.id,
        endsAt: duration.endsAt?.toISOString() ?? null,
        permanent: duration.type === UserBlockType.PERMANENT,
      },
    });
    return {
      source: 'timeweb',
      block: this.userBlocksService.serializeBlock(block),
    };
  }

  async unblockUserBlock(
    blockId: string,
    authUser: AuthenticatedUser,
    dto?: UnblockUserDto,
  ) {
    const block = await this.prisma.userBlock.findUnique({ where: { id: blockId } });
    if (!block) {
      throw new NotFoundException('Блокировка не найдена');
    }
    const now = new Date();
    const reason = dto?.reason?.trim() || 'Разблокировано администратором';

    const updated = await this.prisma.$transaction(async (tx) => {
      const lifted = await tx.userBlock.update({
        where: { id: blockId },
        data: {
          status: UserBlockStatus.LIFTED,
          liftedAt: now,
          liftedByAdminId: authUser.userId,
          liftReason: reason,
        },
      });
      await tx.blockedIdentity.updateMany({
        where: {
          userBlockId: blockId,
          liftedAt: null,
        },
        data: {
          liftedAt: now,
          liftedByAdminId: authUser.userId,
        },
      });
      const activeOther = await tx.userBlock.count({
        where: {
          userId: block.userId,
          id: { not: blockId },
          status: UserBlockStatus.ACTIVE,
          OR: [{ endsAt: null }, { endsAt: { gt: now } }],
        },
      });
      if (activeOther === 0) {
        await tx.user.update({
          where: { id: block.userId },
          data: {
            status: UserStatus.ACTIVE,
            blockedAt: null,
            blockReason: null,
          },
        });
      }
      await tx.auditLog.create({
        data: {
          actorUserId: authUser.userId,
          actorRole: 'admin',
          action: 'user.unblock',
          entityType: 'user',
          entityId: block.userId,
          newData: { blockId, reason },
        },
      });
      return lifted;
    });

    return {
      source: 'timeweb',
      block: this.userBlocksService.serializeBlock(updated),
    };
  }

  async updateUserBlock(
    blockId: string,
    authUser: AuthenticatedUser,
    dto: UpdateUserBlockDto,
  ) {
    const block = await this.prisma.userBlock.findUnique({ where: { id: blockId } });
    if (!block) {
      throw new NotFoundException('Блокировка не найдена');
    }
    if (block.status !== UserBlockStatus.ACTIVE) {
      throw new BadRequestException('Можно изменить только активную блокировку');
    }

    const now = new Date();
    const permanentRequested = dto.permanent === true;
    const temporaryRequested = dto.permanent === false || dto.ends_at != null;
    let nextType = block.type;
    let nextEndsAt = block.endsAt;

    if (permanentRequested) {
      nextType = UserBlockType.PERMANENT;
      nextEndsAt = null;
    } else if (temporaryRequested) {
      const endsAt = dto.ends_at ? new Date(dto.ends_at) : block.endsAt;
      if (!endsAt || Number.isNaN(endsAt.getTime()) || endsAt <= now) {
        throw new BadRequestException('Укажите будущую дату окончания блокировки');
      }
      nextType = UserBlockType.TEMPORARY;
      nextEndsAt = endsAt;
    }

    const changeReason = dto.reason?.trim() || 'Изменение срока блокировки';
    const internalNote =
      dto.internal_note === undefined
        ? block.internalNote
        : dto.internal_note.trim() || null;

    const updated = await this.prisma.$transaction(async (tx) => {
      const saved = await tx.userBlock.update({
        where: { id: blockId },
        data: {
          type: nextType,
          endsAt: nextEndsAt,
          internalNote,
        },
      });
      await tx.blockedIdentity.updateMany({
        where: {
          userBlockId: blockId,
          liftedAt: null,
        },
        data: {
          permanent: nextType === UserBlockType.PERMANENT,
          bannedUntil: nextType === UserBlockType.PERMANENT ? null : nextEndsAt,
        },
      });
      await tx.user.update({
        where: { id: block.userId },
        data: {
          status: UserStatus.BLOCKED,
          blockedAt: block.startsAt,
          blockReason: block.reason,
        },
      });
      await tx.auditLog.create({
        data: {
          actorUserId: authUser.userId,
          actorRole: 'admin',
          action: 'user.block.update',
          entityType: 'user',
          entityId: block.userId,
          newData: {
            blockId,
            reason: changeReason,
            previousEndsAt: block.endsAt?.toISOString() ?? null,
            nextEndsAt: nextEndsAt?.toISOString() ?? null,
            previousType: block.type,
            nextType,
          },
        },
      });
      return saved;
    });

    return {
      source: 'timeweb',
      block: this.userBlocksService.serializeBlock(updated),
    };
  }

  async deleteUser(id: string, authUser: AuthenticatedUser) {
    if (id === authUser.userId) {
      return {
        source: 'timeweb',
        deleted: false,
        message: 'Нельзя удалить текущий аккаунт администратора',
      };
    }

    const user = await this.prisma.user.findUnique({
      where: { id },
      include: {
        adminProfile: true,
      },
    });

    if (!user) {
      throw new NotFoundException('Пользователь не найден');
    }

    if (protectedAdminPhones.has((user.phone ?? '').trim())) {
      return {
        source: 'timeweb',
        deleted: false,
        message: 'Этот администратор защищён от удаления',
      };
    }

    if (user.adminProfile?.isAdmin === true) {
      const adminsCount = await this.prisma.adminUser.count({
        where: {
          isAdmin: true,
        },
      });
      if (adminsCount <= 1) {
        return {
          source: 'timeweb',
          deleted: false,
          message: 'Нельзя удалить последнего администратора',
        };
      }
    }

    await this.performSoftDeleteUser(id, {
      actorUserId: authUser.userId,
      reason: 'Удалено администратором',
    });

    return {
      source: 'timeweb',
      deleted: true,
      user_id: id,
    };
  }

  private async countModerationReady() {
    const [row] = await this.prisma.$queryRaw<{ count: bigint }[]>(Prisma.sql`
      SELECT count(*) AS count FROM listings l WHERE ${listingModerationReadySql()}
    `);
    return Number(row.count);
  }

  private moderationReadyPageIds(cursor: string | undefined, take: number) {
    const decoded = this.decodeAdminCursor(cursor);
    const date = decoded?.createdAt ? new Date(decoded.createdAt) : null;
    // Prisma stores created_at as UTC timestamp without time zone.
    const after = date && !Number.isNaN(date.getTime()) && decoded?.id
      ? Prisma.sql`AND (l.created_at < ${date.toISOString()}::timestamp OR (l.created_at = ${date.toISOString()}::timestamp AND l.id < ${decoded.id}::uuid))`
      : Prisma.empty;
    return this.prisma.$queryRaw<{ id: string }[]>(Prisma.sql`
      SELECT l.id FROM listings l
      WHERE ${listingModerationReadySql()} ${after}
      ORDER BY l.created_at DESC, l.id DESC LIMIT ${take}
    `);
  }

  async getModerationQueue(query: ListAdminListingsDto | string = {}) {
    if (typeof query === 'string') {
      return this.listListings(query);
    }
    return this.listListings({ ...query, status: query.status ?? 'pending' });
  }

  async listListings(query: ListAdminListingsDto | string = {}) {
    const status = typeof query === 'string' ? query : query.status;
    const limit = this.pageLimit(typeof query === 'string' ? undefined : query.limit, 100);
    const cursor = typeof query === 'string' ? undefined : query.cursor;
    const period = typeof query === 'string' ? 'all' : query.period ?? 'all';
    const search = typeof query === 'string' ? '' : query.search?.trim() ?? '';
    const normalizedStatus = (status ?? '').trim().toLowerCase();
    const isPending =
      normalizedStatus === 'pending' || normalizedStatus.length === 0;
    const pendingModeration = await this.countModerationReady();
    // Select eligible IDs in the database before pagination; hydrate only this page.
    const pendingIds = isPending
      ? await this.moderationReadyPageIds(cursor, limit + 1)
      : undefined;
    const eventField = normalizedStatus === 'approved' ? 'publishedAt'
      : normalizedStatus === 'rejected' ? 'moderatedAt'
      : normalizedStatus === 'sold' || normalizedStatus === 'archived' ? 'archivedAt'
      : normalizedStatus === 'deleted' ? 'deletedAt' : 'createdAt';
    const since = this.adminPeriodRange(period);
    const periodWhere = since ? { [eventField]: { gte: since } } : {};
    const searchWhere: Prisma.ListingWhereInput = search ? {
      OR: [
        { title: { contains: search, mode: 'insensitive' } },
        { owner: { is: { displayName: { contains: search, mode: 'insensitive' } } } },
        { owner: { is: { name: { contains: search, mode: 'insensitive' } } } },
      ],
    } : {};
    const baseWhere: Prisma.ListingWhereInput = isPending
      ? { id: { in: pendingIds!.map((row) => row.id) }, ...periodWhere, ...searchWhere }
      : {
          ...(normalizedStatus === 'deleted' ? { deletedAt: { not: null } } : { deletedAt: null }),
          ...periodWhere,
          ...searchWhere,
          ...(normalizedStatus === 'all'
            ? {}
            : { status: listingStatusFromInput(normalizedStatus) }),
        };
    const where: Prisma.ListingWhereInput = {
      ...baseWhere,
      ...(!isPending ? this.dateIdCursorWhere('createdAt', cursor) : {}),
    };
    const countWhere: Prisma.ListingWhereInput = isPending
      ? {
          status: ListingStatus.PENDING,
          deletedAt: null,
          archivedAt: null,
          ...periodWhere,
          ...searchWhere,
        }
      : baseWhere;
    const [items, total] = await Promise.all([
      this.prisma.listing.findMany({
        where,
        include: {
          owner: {
            include: {
              adminProfile: true,
            },
          },
          photos: {
            orderBy: {
              sortOrder: 'asc',
            },
          },
          moderationRevisions: {
            where: {
              resolvedAt: null,
            },
            orderBy: {
              createdAt: 'asc',
            },
            take: 1,
          },
        },
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        take: limit + 1,
      }),
      isPending && period === 'all' && search.length === 0
        ? pendingModeration
        : this.prisma.listing.count({ where: countWhere }),
    ]);
    const page = this.pageInfo(items, limit, (listing) => ({
      createdAt: listing.createdAt.toISOString(),
      id: listing.id,
    }));

    return {
      source: 'timeweb',
      items: page.items.map((listing) => this.serializeAdminListing(listing)),
      total,
      pendingModeration,
      pending_moderation: pendingModeration,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      limit,
      statuses: [
        'pending',
        'approved',
        'rejected',
        'sold',
        'deleted',
        'archived',
      ],
    };
  }

  private serializeAdminListing(
    listing: Parameters<typeof serializeListing>[0] & {
      moderationRevisions?: { snapshot: Prisma.JsonValue }[];
    },
  ) {
    const serialized = serializeListing(listing);
    const revision = listing.moderationRevisions?.[0];
    const diff = revision ? this.buildModerationDiff(serialized, revision.snapshot) : null;
    return diff && diff.changed.length > 0
      ? {
          ...serialized,
          moderation_diff: diff,
        }
      : serialized;
  }

  private buildModerationDiff(
    current: ReturnType<typeof serializeListing>,
    snapshot: Prisma.JsonValue,
  ) {
    if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot)) {
      return null;
    }

    const before = snapshot as Record<string, unknown>;
    const fields = moderationDiffFields
      .map((field) => {
        const previous = this.normalizeModerationValue(before[field]);
        const next = this.normalizeModerationValue(current[field]);
        if (this.stableJson(previous) === this.stableJson(next)) {
          return null;
        }
        return {
          field,
          label: this.moderationFieldLabel(field),
          before: before[field] ?? null,
          after: current[field] ?? null,
        };
      })
      .filter((item): item is NonNullable<typeof item> => item != null);

    const photoDiff = this.buildPhotoModerationDiff(
      before['photos'],
      current['photo_items'],
    );

    return {
      changed: [
        ...fields,
        ...(photoDiff.changed ? [{
          field: 'photos',
          label: 'Фотографии',
          before: photoDiff.before,
          after: photoDiff.after,
          added: photoDiff.added,
          removed: photoDiff.removed,
        }] : []),
      ],
    };
  }

  private buildPhotoModerationDiff(beforeRaw: unknown, afterRaw: unknown) {
    const before = this.normalizePhotoSnapshot(beforeRaw);
    const after = this.normalizePhotoSnapshot(afterRaw);
    const beforeKeys = new Set(before.map((photo) => photo.key));
    const afterKeys = new Set(after.map((photo) => photo.key));
    const added = after.filter((photo) => !beforeKeys.has(photo.key));
    const removed = before.filter((photo) => !afterKeys.has(photo.key));
    const orderChanged =
      before.length === after.length &&
      before.some((photo, index) => photo.key !== after[index]?.key);

    return {
      changed: added.length > 0 || removed.length > 0 || orderChanged,
      before,
      after,
      added,
      removed,
    };
  }

  private normalizePhotoSnapshot(value: unknown) {
    if (!Array.isArray(value)) return [];
    return value
      .map((item, index) => {
        if (!item || typeof item !== 'object') return null;
        const row = item as Record<string, unknown>;
        const id = this.normalizeText(row['id']);
        const storageKey =
          this.normalizeText(row['storage_key']) || this.normalizeText(row['storageKey']);
        const url = this.normalizeText(row['url']);
        const key = id || storageKey || url;
        if (!key) return null;
        return {
          id,
          storage_key: storageKey,
          url,
          sort_order: Number(row['sort_order'] ?? row['sortOrder'] ?? index),
          key,
        };
      })
      .filter((item): item is NonNullable<typeof item> => item != null)
      .sort((a, b) => a.sort_order - b.sort_order || a.key.localeCompare(b.key));
  }

  private normalizeModerationValue(value: unknown): unknown {
    if (value == null) return null;
    if (typeof value === 'string') {
      const trimmed = value.trim();
      return trimmed.length === 0 ? null : trimmed;
    }
    if (typeof value === 'bigint') return value.toString();
    if (typeof value === 'number') return Number.isFinite(value) ? value : null;
    if (typeof value === 'boolean') return value;
    if (Array.isArray(value)) {
      return value
        .map((item) => this.normalizeModerationValue(item))
        .filter((item) => item != null);
    }
    if (typeof value === 'object') {
      const entries = Object.entries(value as Record<string, unknown>)
        .map(([key, raw]) => [key, this.normalizeModerationValue(raw)] as const)
        .filter(([, normalized]) => normalized != null)
        .sort(([left], [right]) => left.localeCompare(right));
      return Object.fromEntries(entries);
    }
    return String(value);
  }

  private stableJson(value: unknown) {
    return JSON.stringify(value);
  }

  private normalizeText(value: unknown) {
    return typeof value === 'string' ? value.trim() : '';
  }

  private moderationFieldLabel(field: string) {
    const labels: Record<string, string> = {
      title: 'Название',
      description: 'Описание',
      price: 'Цена',
      city: 'Город',
      category: 'Категория',
      subcategory: 'Подкатегория',
      address: 'Адрес',
      phone_hidden: 'Телефон скрыт',
      delivery: 'Доставка',
      car: 'Характеристики',
      deal_type: 'Тип сделки',
      real_estate_type: 'Вид товара',
      clothes_type: 'Тип одежды',
      clothes_size: 'Размер одежды',
      oem_part_number: 'Номер детали (OEM)',
    };
    return labels[field] ?? field;
  }

  private priceReductionDataOnApproval(
    listing: {
      price: bigint | number;
      moderationRevisions?: { snapshot: Prisma.JsonValue }[];
    },
    now: Date,
  ): Prisma.ListingUpdateInput {
    const revision = listing.moderationRevisions?.[0];
    if (!revision || typeof revision.snapshot !== 'object' || Array.isArray(revision.snapshot)) {
      return {};
    }

    const snapshot = revision.snapshot as Record<string, unknown>;
    if (!Object.prototype.hasOwnProperty.call(snapshot, 'price')) {
      return {};
    }

    const previous = this.parseModerationPrice(snapshot['price']);
    const next =
      typeof listing.price === 'bigint'
        ? listing.price
        : BigInt(Math.trunc(Number(listing.price) || 0));
    if (previous == null || previous === next) {
      return {};
    }

    if (previous > next) {
      return {
        previousPrice: previous,
        priceReducedAt: now,
      };
    }

    return {
      previousPrice: null,
      priceReducedAt: null,
    };
  }

  private parseModerationPrice(value: unknown) {
    if (typeof value === 'bigint') return value;
    if (typeof value === 'number' && Number.isFinite(value)) {
      return BigInt(Math.trunc(value));
    }
    if (typeof value === 'string') {
      const normalized = value.trim();
      if (/^\d+$/.test(normalized)) {
        return BigInt(normalized);
      }
    }
    return null;
  }

  private async resolveModerationRevisions(listingId: string, resolvedAt: Date) {
    const revisions = this.prisma.listingModerationRevision;
    if (!revisions) {
      return;
    }
    await revisions.updateMany({
      where: {
        listingId,
        resolvedAt: null,
      },
      data: {
        resolvedAt,
      },
    });
  }

  async listPromotions(query: ListAdminPromotionsDto) {
    await this.expirePromotionsByTime();

    const limit = this.pageLimit(query.limit, 50);
    const range = this.resolveRange({
      from: query.from,
      to: query.to,
    });
    const status = promotionStatusFromInput(query.status);
    const type = promotionTypeFromInput(query.type);
    const items = await this.prisma.promotion.findMany({
      where: {
        ...(status ? { status } : {}),
        ...(type ? { type } : {}),
        ...(query.userId?.trim() ? { userId: query.userId.trim() } : {}),
        ...(query.listingId?.trim()
          ? { listingId: query.listingId.trim() }
          : {}),
        ...(range ? { createdAt: range } : {}),
        ...this.dateIdCursorWhere('createdAt', query.cursor),
      },
      include: {
        listing: {
          include: {
            photos: {
              orderBy: {
                sortOrder: 'asc',
              },
            },
          },
        },
        user: {
          include: {
            adminProfile: true,
          },
        },
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const page = this.pageInfo(items, limit, (promotion) => ({
      createdAt: promotion.createdAt.toISOString(),
      id: promotion.id,
    }));

    const now = Date.now();
    return {
      source: 'timeweb',
      items: page.items.map((promotion) => ({
        promotionId: promotion.id,
        type: promotionTypeToResponse(promotion.type),
        status: promotion.status.toLowerCase(),
        listingId: promotion.listingId,
        listingTitle: promotion.listing.title,
        listingPrice: Number(promotion.listing.price),
        listingPhoto: promotion.listing.photos[0]?.publicUrl ?? null,
        userId: promotion.userId,
        userName: promotion.user.displayName || promotion.user.name,
        userPhone: promotion.user.phone,
        costBonus: promotion.costBonus,
        startsAt: promotion.startsAt.toISOString(),
        endsAt: promotion.endsAt.toISOString(),
        timeRemainingSeconds: Math.max(
          0,
          Math.ceil((promotion.endsAt.getTime() - now) / 1000),
        ),
        impressionsCount: promotion.impressionsCount,
        clicksCount: promotion.clicksCount,
        createdAt: promotion.createdAt.toISOString(),
      })),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      limit,
    };
  }

  async getPromotionsSummary(now = new Date()) {
    await this.expirePromotionsByTime();

    const calendar = moscowCalendarBounds(now);
    const startToday = calendar.dayStart;
    const startMonth = calendar.monthStart;

    const [
      activeShowcaseCount,
      activeBumpCount,
      activeVipCount,
      activeTurboCount,
      expiredTodayCount,
      spentToday,
      spentThisMonth,
      showcaseTotals,
    ] = await Promise.all([
      this.prisma.promotion.count({
        where: { status: PromotionStatus.ACTIVE, type: PromotionType.SHOWCASE },
      }),
      this.prisma.promotion.count({
        where: { status: PromotionStatus.ACTIVE, type: PromotionType.BUMP },
      }),
      this.prisma.promotion.count({
        where: { status: PromotionStatus.ACTIVE, type: PromotionType.VIP },
      }),
      this.prisma.promotion.count({
        where: { status: PromotionStatus.ACTIVE, type: PromotionType.TURBO },
      }),
      this.prisma.promotion.count({
        where: {
          status: PromotionStatus.EXPIRED,
          endsAt: {
            gte: startToday,
            lte: now,
          },
        },
      }),
      this.prisma.promotion.aggregate({
        _sum: {
          costBonus: true,
        },
        where: {
          createdAt: {
            gte: startToday,
            lte: now,
          },
        },
      }),
      this.prisma.promotion.aggregate({
        _sum: {
          costBonus: true,
        },
        where: {
          createdAt: {
            gte: startMonth,
            lte: now,
          },
        },
      }),
      this.prisma.promotion.aggregate({
        _sum: {
          impressionsCount: true,
          clicksCount: true,
        },
        where: {
          type: PromotionType.SHOWCASE,
        },
      }),
    ]);

    return {
      source: 'timeweb',
      activeShowcaseCount,
      activeBumpCount,
      activeVipCount,
      activeTurboCount,
      expiredTodayCount,
      totalBonusSpentToday: spentToday._sum.costBonus ?? 0,
      totalBonusSpentThisMonth: spentThisMonth._sum.costBonus ?? 0,
      totalShowcaseImpressions: showcaseTotals._sum.impressionsCount ?? 0,
      totalShowcaseClicks: showcaseTotals._sum.clicksCount ?? 0,
    };
  }

  async cancelPromotion(id: string, authUser: AuthenticatedUser) {
    const updated = await this.prisma.$transaction(async (tx) => {
      const promotion = await tx.promotion.findUnique({ where: { id } });
      if (!promotion) {
        throw new NotFoundException('Promotion not found');
      }

      if (promotion.type === PromotionType.BUMP && promotion.raiseCampaignId) {
        // The worker locks this same row before raising. Wait for an in-flight
        // raise, then stop the campaign before cancellation can commit.
        // Lock the campaign before updating Promotion, as the worker does.
        await tx.$queryRaw`
          SELECT "id" FROM "listing_raise_campaigns"
          WHERE "id" = ${promotion.raiseCampaignId}::uuid
          FOR UPDATE
        `;
        await tx.listingRaiseCampaign.updateMany({
          where: {
            id: promotion.raiseCampaignId,
            status: ListingRaiseCampaignStatus.ACTIVE,
          },
          data: {
            status: ListingRaiseCampaignStatus.CANCELLED,
            nextRaiseAt: null,
            cancelReason: 'admin_cancelled_promotion',
          },
        });
      }

      if (promotion.status === PromotionStatus.CANCELLED) {
        return promotion;
      }
      return tx.promotion.update({
        where: { id },
        data: { status: PromotionStatus.CANCELLED },
      });
    });

    return {
      source: 'timeweb',
      promotionId: updated.id,
      status: updated.status.toLowerCase(),
      cancelledBy: authUser.userId,
    };
  }

  async listWallets(query: ListAdminUsersDto = {}) {
    const limit = this.pageLimit(query.limit, 100);
    const wallets = await this.prisma.wallet.findMany({
      where: {
        ...this.dateIdCursorWhere('updatedAt', query.cursor),
      },
      include: {
        user: {
          include: {
            adminProfile: true,
          },
        },
      },
      orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const page = this.pageInfo(wallets, limit, (wallet) => ({
      updatedAt: wallet.updatedAt.toISOString(),
      id: wallet.id,
    }));

    return {
      source: 'timeweb',
      items: page.items.map((wallet) => ({
        userId: wallet.userId,
        userName: wallet.user.displayName || wallet.user.name,
        userPhone: wallet.user.phone,
        bonusBalance: wallet.bonusBalance,
        lastBonusAccrualAt: toIsoString(wallet.lastBonusAccrualAt),
        createdAt: wallet.createdAt.toISOString(),
      })),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      limit,
    };
  }

  async listWalletTransactions(query: ListAdminWalletTransactionsDto) {
    const limit = this.pageLimit(query.limit, 50);
    const range = this.resolveRange({
      from: query.from,
      to: query.to,
    });
    const type = walletTransactionTypeFromInput(query.type);
    const reason = this.parseWalletReason(query.reason);
    const items = await this.prisma.walletTransaction.findMany({
      where: {
        ...(type ? { type } : {}),
        ...(reason ? { reason } : {}),
        ...(query.userId?.trim() ? { userId: query.userId.trim() } : {}),
        ...(range ? { createdAt: range } : {}),
        ...this.dateIdCursorWhere('createdAt', query.cursor),
      },
      include: {
        user: {
          include: {
            adminProfile: true,
          },
        },
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const page = this.pageInfo(items, limit, (item) => ({
      createdAt: item.createdAt.toISOString(),
      id: item.id,
    }));

    return {
      source: 'timeweb',
      items: page.items.map((item) => ({
        transactionId: item.id,
        userId: item.userId,
        userName: item.user.displayName || item.user.name,
        userPhone: item.user.phone,
        type: item.type.toLowerCase(),
        amount: item.amount,
        reason: item.reason.toLowerCase(),
        metadata: item.metadata,
        createdAt: item.createdAt.toISOString(),
      })),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      limit,
    };
  }

  async getBonusAnalytics(query: ListAdminBonusAnalyticsDto) {
    const range = this.resolveAnalyticsRange(query);
    const transactions = await this.prisma.walletTransaction.findMany({
      where: {
        createdAt: range,
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    const totalBonusAccrued = transactions
      .filter((item) => item.type === WalletTransactionType.ACCRUAL)
      .reduce((sum, item) => sum + item.amount, 0);
    const totalBonusSpent = transactions
      .filter((item) => item.type === WalletTransactionType.SPEND)
      .reduce((sum, item) => sum + item.amount, 0);
    const totalBonusRefunded = transactions
      .filter((item) => item.type === WalletTransactionType.REFUND)
      .reduce((sum, item) => sum + item.amount, 0);
    const spentByReason = {
      promotion_showcase: 0,
      promotion_bump: 0,
      promotion_vip: 0,
      promotion_turbo: 0,
    };

    const spendingUsers = new Set<string>();
    for (const item of transactions) {
      if (item.type === WalletTransactionType.SPEND) {
        spendingUsers.add(item.userId);
      }

      switch (item.reason) {
        case WalletTransactionReason.PROMOTION_SHOWCASE:
          spentByReason.promotion_showcase += item.amount;
          break;
        case WalletTransactionReason.PROMOTION_BUMP:
          spentByReason.promotion_bump += item.amount;
          break;
        case WalletTransactionReason.PROMOTION_VIP:
          spentByReason.promotion_vip += item.amount;
          break;
        case WalletTransactionReason.PROMOTION_TURBO:
          spentByReason.promotion_turbo += item.amount;
          break;
        default:
          break;
      }
    }

    const activeUsersWithWallet = await this.prisma.wallet.count({
      where: {
        bonusBalance: {
          gt: 0,
        },
      },
    });
    const fromDate =
      range.gte instanceof Date ? range.gte : new Date(range.gte);
    const toDate =
      range.lte instanceof Date ? range.lte : new Date(range.lte);

    return {
      source: 'timeweb',
      period: (query.period ?? 'month').trim().toLowerCase() || 'month',
      from: fromDate.toISOString(),
      to: toDate.toISOString(),
      totalBonusAccrued,
      totalBonusSpent,
      totalBonusRefunded,
      spentByReason,
      activeUsersWithWallet,
      usersSpentBonusesCount: spendingUsers.size,
      note: 'Реальные платежи не подключены. Сейчас учитываются только бонусы.',
    };
  }

  private raffleRange(query: ListRaffleParticipantsDto) {
    if (!query.from || !query.to) {
      throw new BadRequestException('Укажите период розыгрыша');
    }
    const from = new Date(query.from);
    const to = new Date(query.to);
    if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()) || from > to) {
      throw new BadRequestException('Укажите корректный период розыгрыша');
    }
    return { from, to };
  }

  private raffleTicketPrice(query: ListRaffleParticipantsDto) {
    const price = query.ticketPrice;
    if (typeof price !== 'string' || !/^[1-9][0-9]*$/.test(price)) {
      throw new BadRequestException('Укажите положительную целую цену билета');
    }
    return price;
  }

  async freezeRaffle(query: ListRaffleParticipantsDto, authUser: AuthenticatedUser) {
    const { from, to } = this.raffleRange(query);
    const ticketPrice = this.raffleTicketPrice(query);
    const fingerprint = createHash('sha256')
      .update(`${from.toISOString()}|${to.toISOString()}|${ticketPrice}`)
      .digest('hex');

    try {
      return await this.prisma.$transaction(async (transaction) => {
      const existing = await transaction.raffleSnapshot.findUnique({ where: { fingerprint } });
      if (existing) return this.raffleSnapshotSummary(existing.id, transaction);

      const snapshot = await transaction.raffleSnapshot.create({
        data: {
          from,
          to,
          ticketPriceRub: new Prisma.Decimal(ticketPrice),
          participantsCount: 0,
          ticketsCount: 0n,
          amountRub: new Prisma.Decimal(0),
          fingerprint,
          createdById: authUser.userId,
        },
      });
      const participants = this.raffleParticipantsSql(from, to, ticketPrice);
      const price = new Prisma.Decimal(ticketPrice);
      await transaction.$executeRaw(Prisma.sql`
        INSERT INTO "raffle_snapshot_participants" (
          "id", "snapshot_id", "user_id", "name", "phone", "total_rub",
          "tickets", "remainder_rub", "first_at", "last_at", "first_ticket", "last_ticket"
        )
        SELECT gen_random_uuid(), ${snapshot.id}::uuid, ranked.user_id,
          COALESCE(NULLIF(TRIM(u."display_name"), ''), NULLIF(TRIM(u."name"), ''), 'Пользователь'),
          COALESCE(u."phone", ''), ranked.total_rub, ranked.ticket_count,
          MOD(ranked.total_rub, ${price}), ranked.first_at, ranked.last_at,
          ranked.first_ticket, ranked.last_ticket
        FROM (
          SELECT eligible.*,
            COALESCE(SUM(ticket_count) OVER (
              ORDER BY user_id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ), 0)::bigint + 1 AS first_ticket,
            SUM(ticket_count) OVER (ORDER BY user_id ROWS UNBOUNDED PRECEDING)::bigint AS last_ticket
          FROM (
            SELECT raffle.*, FLOOR(raffle.total_rub / ${price})::bigint AS ticket_count
            FROM (${participants}) raffle
          ) eligible
        ) ranked
        JOIN "users" u ON u."id" = ranked.user_id
      `);
      await transaction.$executeRaw(Prisma.sql`
        UPDATE "raffle_snapshots" s SET
          "participants_count" = totals.participants,
          "tickets_count" = totals.tickets,
          "amount_rub" = totals.amount
        FROM (
          SELECT COUNT(*)::int AS participants, COALESCE(SUM(tickets), 0)::bigint AS tickets,
            COALESCE(SUM("total_rub"), 0)::numeric AS amount
          FROM "raffle_snapshot_participants" WHERE "snapshot_id" = ${snapshot.id}::uuid
        ) totals WHERE s."id" = ${snapshot.id}::uuid
      `);
      return this.raffleSnapshotSummary(snapshot.id, transaction);
      }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        const existing = await this.prisma.raffleSnapshot.findUnique({ where: { fingerprint } });
        if (existing) return this.raffleSnapshotSummary(existing.id);
      }
      throw error;
    }
  }

  private async raffleSnapshotSummary(snapshotId: string, client: any = this.prisma) {
    const snapshot = await client.raffleSnapshot.findUnique({ where: { id: snapshotId } });
    if (!snapshot) throw new NotFoundException('Зафиксированный розыгрыш не найден');
    return {
      id: snapshot.id,
      snapshotId: snapshot.id,
      fixed: true,
      from: snapshot.from.toISOString(),
      to: snapshot.to.toISOString(),
      ticketPriceRub: snapshot.ticketPriceRub.toString(),
      participants: snapshot.participantsCount,
      tickets: snapshot.ticketsCount.toString(),
      amountRub: Number(snapshot.amountRub.toString()),
      createdAt: snapshot.createdAt.toISOString(),
    };
  }

  private raffleParticipantsSql(from: Date, to: Date, ticketPrice: string, cursor?: string) {
    const filters = this.buildPointsPurchaseFilters({
      fromDate: from, toDate: to, search: '', dateColumn: 'credited_at',
    });
    if (cursor) filters.push(Prisma.sql`p."user_id" > ${cursor}::uuid`);
    return Prisma.sql`
      SELECT p."user_id", SUM(p."amount_rub" - p."refunded_amount_rub") AS total_rub,
        MIN(p."credited_at") AS first_at, MAX(p."credited_at") AS last_at
      FROM "payments" p JOIN "users" u ON u."id" = p."user_id"
      WHERE ${Prisma.join(filters, ' AND ')}
      GROUP BY p."user_id"
      HAVING SUM(p."amount_rub" - p."refunded_amount_rub") >= ${new Prisma.Decimal(ticketPrice)}
    `;
  }

  async getRaffleSummary(query: ListRaffleParticipantsDto) {
    if (query.snapshotId) return this.raffleSnapshotSummary(query.snapshotId);
    const { from, to } = this.raffleRange(query);
    const ticketPrice = this.raffleTicketPrice(query);
    const participants = this.raffleParticipantsSql(from, to, ticketPrice);
    const rows = await this.prisma.$queryRaw<Array<{
      participants: bigint; tickets: bigint; amount: string;
    }>>(Prisma.sql`
      SELECT COUNT(*)::bigint AS participants,
        COALESCE(SUM(FLOOR(total_rub / ${new Prisma.Decimal(ticketPrice)})), 0)::bigint AS tickets,
        COALESCE(SUM(total_rub), 0)::text AS amount
      FROM (${participants}) raffle
    `);
    const row = rows[0];
    return {
      from: from.toISOString(), to: to.toISOString(), ticketPriceRub: ticketPrice,
      participants: Number(row?.participants ?? 0),
      tickets: Number(row?.tickets ?? 0),
      amountRub: Number(row?.amount ?? 0),
    };
  }

  async listRaffleParticipants(query: ListRaffleParticipantsDto) {
    if (query.snapshotId) {
      const limit = Math.min(query.limit ?? 30, 100);
      if (query.cursor && !/^[0-9a-f-]{36}$/i.test(query.cursor)) {
        throw new BadRequestException('Некорректный курсор');
      }
      const rows = await this.prisma.raffleSnapshotParticipant.findMany({
        where: { snapshotId: query.snapshotId },
        orderBy: { userId: 'asc' },
        take: limit + 1,
        ...(query.cursor ? { cursor: { snapshotId_userId: { snapshotId: query.snapshotId, userId: query.cursor } }, skip: 1 } : {}),
      });
      const page = rows.slice(0, limit);
      return {
        nextCursor: rows.length > limit ? page[page.length - 1]?.userId ?? null : null,
        items: page.map((row) => ({
          userId: row.userId, name: row.name, phone: row.phone,
          totalRub: Number(row.totalRub.toString()), tickets: Number(row.tickets),
          remainderRub: Number(row.remainderRub.toString()),
          firstAt: row.firstAt.toISOString(), lastAt: row.lastAt.toISOString(),
        })),
      };
    }
    const { from, to } = this.raffleRange(query);
    const ticketPrice = this.raffleTicketPrice(query);
    const limit = Math.min(query.limit ?? 30, 100);
    const cursor = query.cursor;
    if (cursor && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(cursor)) {
      throw new BadRequestException('Некорректный курсор');
    }
    const participants = this.raffleParticipantsSql(from, to, ticketPrice, cursor);
    const rows = await this.prisma.$queryRaw<Array<{
      user_id: string; display_name: string | null; name: string | null;
      phone: string | null; total_rub: string;
      first_at: Date; last_at: Date;
    }>>(Prisma.sql`
      SELECT raffle.user_id::text AS user_id, u."display_name", u."name", u."phone",
        raffle.total_rub::text AS total_rub,
        raffle.first_at, raffle.last_at
      FROM (${participants}) raffle
      JOIN "users" u ON u."id" = raffle.user_id
      ORDER BY raffle.user_id ASC LIMIT ${limit + 1}
    `);
    const page = rows.slice(0, limit);
    return {
      nextCursor: rows.length > limit ? page[page.length - 1].user_id : null,
      items: page.map((row) => ({
        userId: row.user_id,
        name: row.display_name?.trim() || row.name?.trim() || 'Пользователь',
        phone: row.phone?.trim() || '',
        totalRub: Number(row.total_rub),
        ...calculateRaffleTickets(row.total_rub, ticketPrice),
        firstAt: row.first_at.toISOString(),
        lastAt: row.last_at.toISOString(),
      })),
    };
  }

  async listRaffleTickets(query: ListRaffleParticipantsDto) {
    if (query.snapshotId) return this.listRaffleSnapshotTickets(query);
    const { from, to } = this.raffleRange(query);
    const ticketPrice = this.raffleTicketPrice(query);
    const limit = Math.min(query.limit ?? 50, 100);
    const cursorText = query.cursor?.trim() || '0';
    if (!/^\d+$/.test(cursorText)) {
      throw new BadRequestException('Некорректный курсор билета');
    }
    const cursor = BigInt(cursorText);
    const search = query.search?.trim() ?? '';
    const ticketSearch = /^#?\d{1,30}$/.test(search)
      ? BigInt(search.replace(/^#/, ''))
      : null;
    const participants = this.raffleParticipantsSql(from, to, ticketPrice);
    const price = new Prisma.Decimal(ticketPrice);
    const searchPattern = `%${search}%`;
    const searchFilter = ticketSearch != null
      ? Prisma.sql`ticket_no = ${ticketSearch}`
      : search
        ? Prisma.sql`(
            COALESCE(NULLIF(TRIM(r.display_name), ''), NULLIF(TRIM(r.name), ''), 'Пользователь')
              ILIKE ${searchPattern}
            OR COALESCE(r.phone, '') ILIKE ${searchPattern}
          )`
        : Prisma.sql`TRUE`;
    const seriesFrom = ticketSearch != null
      ? Prisma.sql`GREATEST(r.start_ticket, ${ticketSearch})`
      : Prisma.sql`GREATEST(r.start_ticket, ${cursor + 1n})`;
    const seriesTo = ticketSearch != null
      ? Prisma.sql`LEAST(r.end_ticket, ${ticketSearch})`
      : Prisma.sql`r.end_ticket`;

    const rows = await this.prisma.$queryRaw<Array<{
      ticket_no: bigint;
      user_id: string;
      display_name: string | null;
      name: string | null;
      phone: string | null;
    }>>(Prisma.sql`
      WITH eligible AS (
        SELECT raffle.user_id, u."display_name", u."name", u."phone",
          FLOOR(raffle.total_rub / ${price})::bigint AS ticket_count
        FROM (${participants}) raffle
        JOIN "users" u ON u."id" = raffle.user_id
      ), ranked AS (
        SELECT eligible.*,
          COALESCE(SUM(ticket_count) OVER (
            ORDER BY user_id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
          ), 0)::bigint + 1 AS start_ticket,
          SUM(ticket_count) OVER (ORDER BY user_id ROWS UNBOUNDED PRECEDING)::bigint
            AS end_ticket
        FROM eligible
      )
      SELECT ticket_no, r.user_id::text AS user_id,
        r.display_name, r.name, r.phone
      FROM ranked r
      CROSS JOIN LATERAL generate_series(${seriesFrom}, ${seriesTo}) ticket_no
      WHERE r.end_ticket > ${cursor} AND ${searchFilter}
      ORDER BY ticket_no ASC
      LIMIT ${limit + 1}
    `);
    const page = rows.slice(0, limit);
    return {
      nextCursor: rows.length > limit
        ? page[page.length - 1]?.ticket_no.toString() ?? null
        : null,
      items: page.map((row) => ({
        ticketNumber: row.ticket_no.toString(),
        userId: row.user_id,
        name: row.display_name?.trim() || row.name?.trim() || 'Пользователь',
        phone: row.phone?.trim() || '',
      })),
    };
  }

  private async listRaffleSnapshotTickets(query: ListRaffleParticipantsDto) {
    const snapshotId = query.snapshotId!;
    await this.raffleSnapshotSummary(snapshotId);
    const limit = Math.min(query.limit ?? 50, 100);
    const cursorText = query.cursor?.trim() || '0';
    if (!/^\d{1,30}$/.test(cursorText)) throw new BadRequestException('Некорректный курсор билета');
    const cursor = BigInt(cursorText);
    const search = query.search?.trim() ?? '';
    const number = /^#?\d{1,30}$/.test(search) ? BigInt(search.replace(/^#/, '')) : null;
    const like = `%${search}%`;
    const rows = await this.prisma.$queryRaw<Array<{
      ticket_no: bigint; user_id: string; name: string; phone: string;
    }>>(Prisma.sql`
      SELECT ticket_no, p."user_id"::text AS user_id, p.name, p.phone
      FROM "raffle_snapshot_participants" p
      CROSS JOIN LATERAL generate_series(
        ${number == null ? Prisma.sql`GREATEST(p."first_ticket", ${cursor + 1n})` : number},
        ${number == null ? Prisma.sql`p."last_ticket"` : number}
      ) ticket_no
      WHERE p."snapshot_id" = ${snapshotId}::uuid
        AND p."last_ticket" > ${cursor}
        AND ${number == null && search
          ? Prisma.sql`(p.name ILIKE ${like} OR p.phone ILIKE ${like})`
          : number == null ? Prisma.sql`TRUE` : Prisma.sql`${number} BETWEEN p."first_ticket" AND p."last_ticket"`}
      ORDER BY ticket_no ASC LIMIT ${limit + 1}
    `);
    const page = rows.slice(0, limit);
    return {
      nextCursor: rows.length > limit ? page[page.length - 1]?.ticket_no.toString() ?? null : null,
      items: page.map((row) => ({
        ticketNumber: row.ticket_no.toString(), userId: row.user_id, name: row.name, phone: row.phone,
      })),
    };
  }

  async getPointsPurchasesSummary(query: ListAdminPointsPurchasesDto) {
    const { fromDate, toDate } = this.resolvePointsPurchasesRange(query);
    const search = (query.search ?? '').trim();
    const filters = this.buildPointsPurchaseFilters({ fromDate, toDate, search });
    const whereSql = Prisma.join(filters, ' AND ');
    const rows = await this.prisma.$queryRaw<
      Array<{
        total_amount_rub: string | number | null;
        total_points: bigint | number | null;
        purchases_count: bigint | number | null;
        unique_buyers_count: bigint | number | null;
      }>
    >`
      SELECT
        COALESCE(SUM(p."amount_rub"), 0)::text AS total_amount_rub,
        COALESCE(SUM(p."points_amount"), 0)::bigint AS total_points,
        COUNT(DISTINCT p."id")::bigint AS purchases_count,
        COUNT(DISTINCT p."user_id")::bigint AS unique_buyers_count
      FROM "payments" p
      JOIN "users" u ON u."id" = p."user_id"
      WHERE ${whereSql}
    `;
    const row = rows[0] ?? {
      total_amount_rub: 0,
      total_points: 0,
      purchases_count: 0,
      unique_buyers_count: 0,
    };

    return {
      source: 'timeweb',
      from: fromDate.toISOString(),
      to: toDate.toISOString(),
      totalAmountRub: this.numberFromDb(row.total_amount_rub),
      totalPoints: this.numberFromDb(row.total_points),
      purchasesCount: this.numberFromDb(row.purchases_count),
      uniqueBuyersCount: this.numberFromDb(row.unique_buyers_count),
    };
  }

  async listPointsPurchases(query: ListAdminPointsPurchasesDto) {
    const { fromDate, toDate } = this.resolvePointsPurchasesRange(query);
    const limit = Math.min(Math.max(query.limit ?? 30, 1), 100);
    const search = (query.search ?? '').trim();
    const cursor = this.decodePointsPurchaseCursor(query.cursor);
    const filters = this.buildPointsPurchaseFilters({ fromDate, toDate, search });
    if (cursor) {
      filters.push(Prisma.sql`(p."created_at", p."id") < (${cursor.createdAt}, ${cursor.id}::uuid)`);
    }
    const whereSql = Prisma.join(filters, ' AND ');
    const rows = await this.prisma.$queryRaw<
      Array<{
        payment_id: string;
        user_id: string;
        display_name: string | null;
        username: string | null;
        phone: string | null;
        amount_rub: string | number;
        points: number;
        status: string;
        created_at: Date;
      }>
    >`
      SELECT
        p."id"::text AS payment_id,
        p."user_id"::text AS user_id,
        u."display_name" AS display_name,
        NULLIF(u."name", '') AS username,
        u."phone" AS phone,
        p."amount_rub"::text AS amount_rub,
        p."points_amount" AS points,
        p."status"::text AS status,
        p."created_at" AS created_at
      FROM "payments" p
      JOIN "users" u ON u."id" = p."user_id"
      WHERE ${whereSql}
      ORDER BY p."created_at" DESC, p."id" DESC
      LIMIT ${limit + 1}
    `;

    const pageRows = rows.slice(0, limit);
    const next = rows.length > limit ? pageRows[pageRows.length - 1] : null;

    return {
      source: 'timeweb',
      from: fromDate.toISOString(),
      to: toDate.toISOString(),
      limit,
      nextCursor: next
        ? this.encodePointsPurchaseCursor({
            createdAt: next.created_at,
            id: next.payment_id,
          })
        : null,
      items: pageRows.map((row) => ({
        paymentId: row.payment_id,
        userId: row.user_id,
        displayName:
          row.display_name?.trim() ||
          row.username?.trim() ||
          row.phone?.trim() ||
          'Пользователь',
        username: row.username?.trim() || null,
        phone: row.phone?.trim() ? maskPhone(row.phone) : null,
        amountRub: this.numberFromDb(row.amount_rub),
        points: this.numberFromDb(row.points),
        status: 'Оплачено',
        createdAt: row.created_at.toISOString(),
      })),
    };
  }

  async getReferralSummary(query: ListAdminBonusAnalyticsDto) {
    const range = this.resolveAnalyticsRange(query);
    const [referrals, purchased, spent, daily] = await Promise.all([
      this.prisma.referral.findMany({
        where: {
          createdAt: range,
        },
      }),
      this.prisma.walletTransaction.aggregate({
        _sum: { amount: true },
        where: {
          createdAt: range,
          reason: WalletTransactionReason.POINTS_PURCHASE,
          type: WalletTransactionType.ACCRUAL,
        },
      }),
      this.prisma.walletTransaction.aggregate({
        _sum: { amount: true },
        where: {
          createdAt: range,
          type: WalletTransactionType.SPEND,
        },
      }),
      this.prisma.walletTransaction.aggregate({
        _sum: { amount: true },
        where: {
          createdAt: range,
          reason: WalletTransactionReason.DAILY_LOGIN_BONUS,
          type: WalletTransactionType.ACCRUAL,
        },
      }),
    ]);

    const rewarded = referrals.filter(
      (item) => item.rewardStatus === ReferralRewardStatus.REWARDED,
    );

    return {
      source: 'timeweb',
      period: (query.period ?? 'month').trim().toLowerCase() || 'month',
      from: this.dateFilterValueToIso(range.gte),
      to: this.dateFilterValueToIso(range.lte),
      newRegistrationsByInvite: referrals.filter((item) => item.registeredAt)
        .length,
      rewardedReferralBonuses: rewarded.length,
      referralPointsAwarded: rewarded.reduce(
        (sum, item) => sum + item.rewardAmount,
        0,
      ),
      unfinishedInvites: referrals.filter((item) => !item.registeredAt).length,
      rewardFailures: referrals.filter(
        (item) =>
          item.rewardStatus === ReferralRewardStatus.NOT_REWARDED ||
          item.rewardStatus === ReferralRewardStatus.FAILED_RETRYABLE,
      ).length,
      pointsPurchased: purchased._sum.amount ?? 0,
      pointsSpent: spent._sum.amount ?? 0,
      dailyBonusesAwarded: daily._sum.amount ?? 0,
    };
  }

  async listReferrals(query: ListAdminBonusAnalyticsDto) {
    const range = this.resolveAnalyticsRange(query);
    const search = query.search?.trim();
    const userId = query.userId?.trim();
    if (search || userId) {
      return this.listReferralUsers(query, range);
    }

    const limit = this.pageLimit(query.limit, 50);
    const referrals = await this.prisma.referral.findMany({
      where: {
        createdAt: range,
        ...this.dateIdCursorWhere('createdAt', query.cursor),
      },
      include: {
        inviter: {
          include: {
            adminProfile: true,
          },
        },
        invited: {
          include: {
            adminProfile: true,
          },
        },
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const page = this.pageInfo(referrals, limit, (referral) => ({
      createdAt: referral.createdAt.toISOString(),
      id: referral.id,
    }));

    return {
      source: 'timeweb',
      period: (query.period ?? 'month').trim().toLowerCase() || 'month',
      from: this.dateFilterValueToIso(range.gte),
      to: this.dateFilterValueToIso(range.lte),
      items: this.buildReferralUserItemsFromReferrals(page.items),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      limit,
    };
  }

  async getUserReferrals(userId: string, query: ListAdminBonusAnalyticsDto) {
    const normalizedUserId = userId.trim();
    if (!this.isUuid(normalizedUserId)) {
      throw new NotFoundException('User not found');
    }

    const user = await this.prisma.user.findFirst({
      where: {
        id: normalizedUserId,
        deletedAt: null,
        status: {
          not: UserStatus.DELETED,
        },
      },
      include: {
        adminProfile: true,
      },
    });
    if (!user) {
      throw new NotFoundException('User not found');
    }

    const range = this.resolveAnalyticsRange(query);
    return {
      source: 'timeweb',
      period: (query.period ?? 'month').trim().toLowerCase() || 'month',
      from: this.dateFilterValueToIso(range.gte),
      to: this.dateFilterValueToIso(range.lte),
      item: await this.buildReferralUserItem(user, range),
    };
  }

  private async listReferralUsers(
    query: ListAdminBonusAnalyticsDto,
    range: { gte: string | Date; lte: string | Date },
  ) {
    const search = query.search?.trim();
    const userId = query.userId?.trim();
    const searchLooksLikeUuid = search ? this.isUuid(search) : false;
    const decodedReferralUserId = search ? resolveReferralUserId(search) : null;
    const phoneDigits = (search ?? '').replace(/\D/g, '');
    const cursorWhere = this.dateIdCursorWhere('createdAt', query.cursor);
    const userSearchOr: Prisma.UserWhereInput[] = [
      ...(userId && this.isUuid(userId) ? [{ id: userId }] : []),
      ...(searchLooksLikeUuid ? [{ id: search }] : []),
      ...(decodedReferralUserId ? [{ id: decodedReferralUserId }] : []),
      ...(search
        ? [
            { displayName: { contains: search, mode: 'insensitive' as const } },
            { name: { contains: search, mode: 'insensitive' as const } },
            { phone: { contains: search } },
          ]
        : []),
      ...(phoneDigits.length >= 4 ? [{ phone: { contains: phoneDigits } }] : []),
    ];
    const limit = this.pageLimit(query.limit, 25);
    const matchingUsers = await this.prisma.user.findMany({
      where: {
        deletedAt: null,
        status: {
          not: UserStatus.DELETED,
        },
        ...(Object.keys(cursorWhere).length > 0 ? { AND: [cursorWhere] } : {}),
        ...(userSearchOr.length > 0
          ? { OR: userSearchOr }
          : { id: '00000000-0000-0000-0000-000000000000' }),
      },
      include: {
        adminProfile: true,
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const page = this.pageInfo(matchingUsers, limit, (user) => ({
      createdAt: user.createdAt.toISOString(),
      id: user.id,
    }));

    return {
      source: 'timeweb',
      period: (query.period ?? 'month').trim().toLowerCase() || 'month',
      from: this.dateFilterValueToIso(range.gte),
      to: this.dateFilterValueToIso(range.lte),
      items: await Promise.all(
        page.items.map((user) => this.buildReferralUserItem(user, range)),
      ),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      limit,
    };
  }

  private buildReferralUserItemsFromReferrals(referrals: any[]) {
    const users = new Map<string, {
      inviter: Record<string, unknown>;
      referralCode: string;
      inviteLink: string;
      openedCount: number;
      registeredCount: number;
      rewardedCount: number;
      referralPoints: number;
      unfinishedCount: number;
      invitations: Array<Record<string, unknown>>;
    }>();

    for (const referral of referrals) {
      const key = referral.inviterUserId;
      const existing = users.get(key);
      const inviter = this.serializeReferralUser(referral.inviter);
      const item = existing ?? {
        inviter,
        referralCode: buildReferralCode(referral.inviterUserId),
        inviteLink: this.buildInviteLink(buildReferralCode(referral.inviterUserId)),
        openedCount: 0,
        registeredCount: 0,
        rewardedCount: 0,
        referralPoints: 0,
        unfinishedCount: 0,
        invitations: [] as Array<Record<string, unknown>>,
      };
      if (referral.openedAt || referral.appOpenedAt) item.openedCount += 1;
      if (referral.registeredAt || referral.invitedUserId) item.registeredCount += 1;
      if (referral.rewardStatus === ReferralRewardStatus.REWARDED) {
        item.rewardedCount += 1;
        item.referralPoints += referral.rewardAmount;
      }
      if (!referral.registeredAt && !referral.invitedUserId) {
        item.unfinishedCount += 1;
      }
      item.invitations.push(this.serializeReferral(referral));
      users.set(key, item);
    }

    return Array.from(users.values());
  }

  private async buildReferralUserItem(
    user: any,
    range: { gte: string | Date; lte: string | Date },
  ) {
    const referrals = await this.prisma.referral.findMany({
      where: {
        inviterUserId: user.id,
        createdAt: range,
      },
      include: {
        inviter: {
          include: {
            adminProfile: true,
          },
        },
        invited: {
          include: {
            adminProfile: true,
          },
        },
      },
      orderBy: {
        createdAt: 'desc',
      },
      take: 500,
    });
    const referralCode = buildReferralCode(user.id);
    const item = {
      inviter: this.serializeReferralUser(user),
      referralCode,
      inviteLink: this.buildInviteLink(referralCode),
      openedCount: 0,
      registeredCount: 0,
      rewardedCount: 0,
      referralPoints: 0,
      unfinishedCount: 0,
      rejectedCount: 0,
      invitations: [] as Array<Record<string, unknown>>,
    };
    for (const referral of referrals) {
      if (referral.openedAt || referral.appOpenedAt) item.openedCount += 1;
      if (referral.registeredAt || referral.invitedUserId) item.registeredCount += 1;
      if (referral.rewardStatus === ReferralRewardStatus.REWARDED) {
        item.rewardedCount += 1;
        item.referralPoints += referral.rewardAmount;
      }
      if (!referral.registeredAt && !referral.invitedUserId) {
        item.unfinishedCount += 1;
      }
      if (
        referral.rewardStatus === ReferralRewardStatus.NOT_REWARDED ||
        referral.rewardStatus === ReferralRewardStatus.FAILED_RETRYABLE
      ) {
        item.rejectedCount += 1;
      }
      item.invitations.push(this.serializeReferral(referral));
    }
    return item;
  }

  async getReferralById(id: string) {
    const referral = await this.prisma.referral.findUnique({
      where: {
        id,
      },
      include: {
        inviter: {
          include: {
            adminProfile: true,
          },
        },
        invited: {
          include: {
            adminProfile: true,
          },
        },
      },
    });
    if (!referral) {
      throw new NotFoundException('Referral not found');
    }

    return {
      source: 'timeweb',
      item: this.serializeReferral(referral),
    };
  }

  async approveListing(id: string, authUser: AuthenticatedUser) {
    const listing = await this.prisma.listing.findUnique({
      where: { id },
      include: {
        owner: {
          include: {
            adminProfile: true,
          },
        },
        photos: {
          orderBy: {
            sortOrder: 'asc',
          },
        },
        moderationRevisions: {
          where: {
            resolvedAt: null,
          },
          orderBy: {
            createdAt: 'asc',
          },
          take: 1,
        },
      },
    });

    if (!listing) {
      throw new NotFoundException('Listing not found');
    }
    if (listing.photos.length === 0) {
      throw new BadRequestException(LISTING_PHOTO_REQUIRED);
    }
    if (!isListingReadyForPublication(listing)) {
      throw new BadRequestException(LISTING_PUBLICATION_NOT_READY);
    }

    const now = new Date();
    const updated = await this.prisma.listing.update({
      where: { id },
      data: {
        status: ListingStatus.APPROVED,
        rejectionReason: null,
        moderationNote: null,
        moderatedBy: authUser.userId,
        moderatedAt: now,
        publishedAt: listing.publishedAt ?? now,
        archivedAt: null,
        deletedAt: null,
        ...this.priceReductionDataOnApproval(listing, now),
      },
      include: {
        owner: {
          include: {
            adminProfile: true,
          },
        },
        photos: {
          orderBy: {
            sortOrder: 'asc',
          },
        },
      },
    });

    await this.savedSearchAlerts?.notifyApprovedListing(id);
    await this.resolveModerationRevisions(id, now);

    await this.notificationsService.createSystemNotification({
      userId: updated.ownerId,
      title: 'Объявление одобрено',
      body: `Объявление "${updated.title}" прошло модерацию.`,
      type: NotificationType.MODERATION,
      payload: {
        listingId: updated.id,
        status: 'approved',
      },
    });
    this.adminDashboardSignal?.changed('listings');

    return {
      source: 'timeweb',
      listing: serializeListing(updated),
    };
  }

  async rejectListing(
    id: string,
    authUser: AuthenticatedUser,
    params?: {
      reason?: string;
      moderationNote?: string;
    },
  ) {
    await this.ensureListingExists(id);

    const now = new Date();
    const updated = await this.prisma.listing.update({
      where: { id },
      data: {
        status: ListingStatus.REJECTED,
        rejectionReason: params?.reason?.trim() || 'Отклонено модератором',
        moderationNote: params?.moderationNote?.trim() || null,
        moderatedBy: authUser.userId,
        moderatedAt: now,
        publishedAt: null,
        archivedAt: null,
        deletedAt: null,
      },
      include: {
        owner: {
          include: {
            adminProfile: true,
          },
        },
        photos: {
          orderBy: {
            sortOrder: 'asc',
          },
        },
      },
    });

    await this.resolveModerationRevisions(id, now);

    await this.notificationsService.createSystemNotification({
      userId: updated.ownerId,
      title: 'Объявление отклонено',
      body: updated.rejectionReason ?? 'Объявление не прошло модерацию.',
      type: NotificationType.MODERATION,
      payload: {
        listingId: updated.id,
        status: 'rejected',
      },
    });
    this.adminDashboardSignal?.changed('listings');

    return {
      source: 'timeweb',
      listing: serializeListing(updated),
    };
  }

  async archiveListing(
    id: string,
    authUser: AuthenticatedUser,
    dto?: ArchiveListingDto,
  ) {
    await this.ensureListingExists(id);
    const nextStatus = dto?.status?.trim().toLowerCase() === 'sold'
      ? ListingStatus.SOLD
      : ListingStatus.ARCHIVED;
    const nextReason = dto?.note?.trim();

    const updated = await this.prisma.listing.update({
      where: { id },
      data: {
        status: nextStatus,
        rejectionReason:
          nextReason && nextReason.length > 0
            ? nextReason
            : nextStatus === ListingStatus.SOLD
              ? 'Объявление отмечено как проданное администратором.'
              : 'Объявление снято с публикации администратором.',
        moderatedBy: authUser.userId,
        moderatedAt: new Date(),
        archivedAt: new Date(),
      },
      include: {
        owner: {
          include: {
            adminProfile: true,
          },
        },
        photos: {
          orderBy: {
            sortOrder: 'asc',
          },
        },
      },
    });
    this.adminDashboardSignal?.changed('listings');

    return {
      source: 'timeweb',
      listing: serializeListing(updated),
      status_after_archive: nextStatus.toLowerCase(),
    };
  }

  async deleteListing(
    id: string,
    authUser: AuthenticatedUser,
    params?: {
      reason?: string;
      moderationNote?: string;
    },
  ) {
    await this.ensureListingExists(id);

    const updated = await this.prisma.listing.update({
      where: { id },
      data: {
        status: ListingStatus.DELETED,
        rejectionReason: params?.reason?.trim() || 'Удалено модератором',
        moderationNote: params?.moderationNote?.trim() || null,
        moderatedBy: authUser.userId,
        moderatedAt: new Date(),
        deletedAt: new Date(),
        publishedAt: null,
      },
      include: {
        owner: {
          include: {
            adminProfile: true,
          },
        },
        photos: {
          orderBy: {
            sortOrder: 'asc',
          },
        },
      },
    });

    await this.notificationsService.createSystemNotification({
      userId: updated.ownerId,
      title: 'Объявление удалено',
      body: updated.rejectionReason ?? 'Объявление удалено модератором.',
      type: NotificationType.MODERATION,
      payload: {
        listingId: updated.id,
        status: 'deleted',
      },
    });

    await this.storageService.deleteListingPhotosForListings([id]);
    this.adminDashboardSignal?.changed('listings');

    return {
      source: 'timeweb',
      listing: serializeListing(updated),
    };
  }

  async deleteReview(id: string, authUser: AuthenticatedUser) {
    return this.reviewsService.deleteReviewAsAdmin(authUser, id);
  }

  async getReportsPlaceholder() {
    const items = await this.prisma.report.findMany({
      orderBy: {
        createdAt: 'desc',
      },
      take: 100,
    });
    return {
      source: 'timeweb',
      items: items.map((report) => ({
        id: report.id,
        listing_id: report.listingId,
        listing_owner_id: report.listingOwnerId,
        reporter_id: report.reporterId,
        reason: report.reason,
        comment: report.comment,
        status: report.status,
        created_at: report.createdAt.toISOString(),
      })),
    };
  }

  async getSupportTicketsPlaceholder() {
    const items = await this.prisma.supportTicket.findMany({
      orderBy: {
        updatedAt: 'desc',
      },
      take: 100,
    });

    return {
      source: 'timeweb',
      items: items.map((ticket) => ({
        id: ticket.id,
        user_id: ticket.userId,
        name: ticket.name,
        subject: ticket.subject,
        status: ticket.status.toLowerCase(),
        unread_for_admin: ticket.unreadForAdmin,
        unread_for_user: ticket.unreadForUser,
        last_message: ticket.lastMessage,
        created_at: ticket.createdAt.toISOString(),
        updated_at: ticket.updatedAt.toISOString(),
      })),
    };
  }

  private async ensureListingExists(id: string) {
    const listing = await this.prisma.listing.findUnique({
      where: { id },
      select: { id: true },
    });

    if (!listing) {
      throw new NotFoundException('Listing not found');
    }
  }

  private async performSoftDeleteUser(
    userId: string,
    params: {
      actorUserId: string;
      reason: string;
    },
  ) {
    await this.accountDeletion.deleteUser(userId, params);
  }

  private async expirePromotionsByTime() {
    await this.prisma.promotion.updateMany({
      where: {
        status: PromotionStatus.ACTIVE,
        endsAt: {
          lte: new Date(),
        },
      },
      data: {
        status: PromotionStatus.EXPIRED,
      },
    });
  }

  private resolveRange(params: {
    from?: string;
    to?: string;
  }): Prisma.DateTimeFilter | undefined {
    const from = params.from ? new Date(params.from) : null;
    const to = params.to ? new Date(params.to) : null;
    const hasFrom = from != null && !Number.isNaN(from.getTime());
    const hasTo = to != null && !Number.isNaN(to.getTime());

    if (!hasFrom && !hasTo) {
      return undefined;
    }

    return {
      ...(hasFrom ? { gte: from! } : {}),
      ...(hasTo ? { lte: to! } : {}),
    };
  }

  private resolveAnalyticsRange(
    query: ListAdminBonusAnalyticsDto,
    now = new Date(),
  ) {
    const explicit = this.resolveRange({
      from: query.from,
      to: query.to,
    });
    if (explicit?.gte && explicit.lte) {
      return explicit as { gte: Date; lte: Date };
    }

    const period = (query.period ?? 'month').trim().toLowerCase();
    const calendar = moscowCalendarBounds(now);
    let start = calendar.monthStart;

    if (period === 'day') {
      start = calendar.dayStart;
    } else if (period === 'week') {
      start = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    }

    return {
      gte: explicit?.gte ?? start,
      lte: explicit?.lte ?? now,
    };
  }

  private resolvePointsPurchasesRange(
    query: Pick<ListAdminPointsPurchasesDto, 'from' | 'to'>,
    now = new Date(),
  ) {
    const explicit = this.resolveRange({
      from: query.from,
      to: query.to,
    });
    const monthStart = moscowCalendarBounds(now).monthStart;
    return {
      fromDate: (explicit?.gte as Date | undefined) ?? monthStart,
      toDate: (explicit?.lte as Date | undefined) ?? now,
    };
  }

  private buildPointsPurchaseFilters({
    fromDate,
    toDate,
    search,
    dateColumn = 'created_at',
  }: {
    fromDate: Date;
    toDate: Date;
    search: string;
    dateColumn?: 'created_at' | 'credited_at';
  }) {
    const filters: Prisma.Sql[] = [
      Prisma.sql`p."provider" = ${PaymentProvider.YOOKASSA}::"PaymentProvider"`,
      Prisma.sql`p."status" = ${PaymentStatus.SUCCEEDED}::"PaymentStatus"`,
      Prisma.sql`p."credited_at" IS NOT NULL`,
      Prisma.sql`p."is_test" = false`,
      Prisma.sql`LOWER(COALESCE(p."metadata"->>'test', 'false')) <> 'true'`,
      Prisma.sql`LOWER(COALESCE(p."metadata"->>'testMode', 'false')) <> 'true'`,
      Prisma.sql`LOWER(COALESCE(p."metadata"->>'live', 'true')) <> 'false'`,
      dateColumn === 'credited_at'
        ? Prisma.sql`p."credited_at" >= ${fromDate}`
        : Prisma.sql`p."created_at" >= ${fromDate}`,
      dateColumn === 'credited_at'
        ? Prisma.sql`p."credited_at" <= ${toDate}`
        : Prisma.sql`p."created_at" <= ${toDate}`,
      Prisma.sql`EXISTS (
        SELECT 1
        FROM "wallet_transactions" wt
        WHERE wt."user_id" = p."user_id"
          AND wt."type" = ${WalletTransactionType.ACCRUAL}::"WalletTransactionType"
          AND wt."reason" = ${WalletTransactionReason.POINTS_PURCHASE}::"WalletTransactionReason"
          AND wt."amount" = p."points_amount"
          AND wt."metadata"->>'paymentId' = p."id"::text
      )`,
    ];
    const normalizedSearch = search.trim();
    if (normalizedSearch.length > 0) {
      const like = `%${normalizedSearch}%`;
      const digits = normalizedSearch.replace(/\D/g, '');
      filters.push(Prisma.sql`(
        p."user_id"::text ILIKE ${like}
        OR u."display_name" ILIKE ${like}
        OR u."name" ILIKE ${like}
        OR u."phone" ILIKE ${like}
        ${digits ? Prisma.sql`OR regexp_replace(COALESCE(u."phone", ''), '\\D', '', 'g') ILIKE ${`%${digits}%`}` : Prisma.empty}
      )`);
    }
    return filters;
  }

  private encodePointsPurchaseCursor(value: { createdAt: Date; id: string }) {
    return Buffer.from(
      JSON.stringify({
        createdAt: value.createdAt.toISOString(),
        id: value.id,
      }),
      'utf8',
    ).toString('base64url');
  }

  private decodePointsPurchaseCursor(cursor?: string) {
    const raw = (cursor ?? '').trim();
    if (!raw) return null;
    try {
      const decoded = JSON.parse(Buffer.from(raw, 'base64url').toString('utf8'));
      const createdAt = new Date(String(decoded.createdAt ?? ''));
      const id = String(decoded.id ?? '').trim();
      if (Number.isNaN(createdAt.getTime()) || !this.isUuid(id)) {
        return null;
      }
      return { createdAt, id };
    } catch {
      return null;
    }
  }

  private numberFromDb(value: unknown) {
    if (typeof value === 'bigint') return Number(value);
    if (typeof value === 'number') return value;
    const parsed = Number((value ?? '0').toString());
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private parseWalletReason(value?: string) {
    const normalized = (value ?? '').trim().toUpperCase();
    if (!normalized) {
      return undefined;
    }

    return Object.values(WalletTransactionReason).find(
      (item) => item === normalized,
    );
  }

  private dateFilterValueToIso(value: string | Date) {
    return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
  }

  private serializeReferral(referral: any) {
    return {
      id: referral.id,
      inviter: this.serializeReferralUser(referral.inviter),
      invited: referral.invited ? this.serializeReferralUser(referral.invited) : null,
      inviterUserId: referral.inviterUserId,
      invitedUserId: referral.invitedUserId,
      referralCode: referral.referralCode,
      inviteLink: this.buildInviteLink(referral.referralCode),
      openedAt: toIsoString(referral.openedAt),
      appOpenedAt: toIsoString(referral.appOpenedAt),
      signupStartedAt: toIsoString(referral.signupStartedAt),
      registeredAt: toIsoString(referral.registeredAt),
      registrationCompleted: Boolean(referral.registeredAt || referral.invitedUserId),
      isNewUser: referral.isNewUser,
      rewardStatus: referral.rewardStatus.toLowerCase(),
      rewardAmount: referral.rewardAmount,
      rewardedAt: toIsoString(referral.rewardedAt),
      bonusAwarded: referral.rewardStatus === ReferralRewardStatus.REWARDED,
      failureReason: referral.failureReason,
      failureText: this.referralFailureText(referral),
      walletTransactionId: referral.walletTransactionId,
      createdAt: referral.createdAt.toISOString(),
    };
  }

  private serializeReferralUser(user: any) {
    const displayName =
      user.displayName?.trim() ||
      user.name?.trim() ||
      user.phone?.trim() ||
      'Пользователь';
    return {
      id: user.id,
      name: displayName,
      displayName: user.displayName?.trim() || displayName,
      username: user.displayName?.trim() || null,
      phone: this.safePhone(user.phone),
      avatarUrl: normalizeStoredMediaUrl(user.avatarUrl ?? user.photoUrl, {
        category: 'avatars',
      }),
      referralCode: buildReferralCode(user.id),
      profilePath: `/admin/users/${user.id}`,
    };
  }

  private buildInviteLink(referralCode: string) {
    return `https://attamarket.online/invite?ref=${encodeURIComponent(referralCode)}`;
  }

  private safePhone(phone?: string | null) {
    const digits = (phone ?? '').replace(/\D/g, '');
    if (digits.length < 4) return phone?.trim() || null;
    return `${digits.slice(0, 1)}***${digits.slice(-4)}`;
  }

  private isUuid(value: string) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    );
  }

  private referralFailureText(referral: any) {
    if (referral.rewardStatus === ReferralRewardStatus.REWARDED) {
      return null;
    }
    if (!referral.registeredAt && !referral.invitedUserId) {
      return 'Ссылка открыта, но регистрация не завершена';
    }
    switch (referral.failureReason) {
      case 'APP_OPENED_WITHOUT_REFERRAL_CODE':
        return 'После установки приложение открыто без реферального кода';
      case 'USER_ALREADY_REGISTERED':
        return 'Пользователь уже был зарегистрирован';
      case 'SELF_REFERRAL':
        return 'Самоприглашение';
      case 'BONUS_ALREADY_AWARDED_FOR_INVITED_USER':
        return 'Бонус уже начислялся за этого пользователя';
      case 'REWARD_ERROR_RETRYABLE':
        return 'Ошибка начисления — требуется проверка';
      case 'INVALID_REFERRAL_CODE':
        return 'Реферальный код не распознан';
      case 'INVITER_NOT_FOUND':
        return 'Аккаунт пригласившего не найден';
      default:
        return referral.failureReason ? 'Бонус не начислен' : null;
    }
  }
}
