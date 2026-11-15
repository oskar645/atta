"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var AdminAppDownloadsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminAppDownloadsService = void 0;
const common_1 = require("@nestjs/common");
const env_1 = require("../../config/env");
const prisma_service_1 = require("../prisma/prisma.service");
const redis_service_1 = require("../redis/redis.service");
const apple_app_downloads_source_1 = require("./apple-app-downloads.source");
const google_play_downloads_source_1 = require("./google-play-downloads.source");
const SNAPSHOT_CACHE_KEY = 'admin:app-downloads:snapshot:v1';
const SYNC_LOCK_KEY = 'admin:app-downloads:sync-lock:v1';
let AdminAppDownloadsService = AdminAppDownloadsService_1 = class AdminAppDownloadsService {
    constructor(prisma, redis, apple, google) {
        this.prisma = prisma;
        this.redis = redis;
        this.apple = apple;
        this.google = google;
        this.logger = new common_1.Logger(AdminAppDownloadsService_1.name);
        this.syncTimer = null;
    }
    onModuleInit() {
        void this.syncAll();
        this.syncTimer = setInterval(() => void this.syncAll(), env_1.env.APP_DOWNLOAD_SYNC_INTERVAL_MINUTES * 60 * 1000);
        this.syncTimer.unref?.();
    }
    onModuleDestroy() {
        if (this.syncTimer) {
            clearInterval(this.syncTimer);
            this.syncTimer = null;
        }
    }
    async getSnapshot(now = new Date()) {
        try {
            const cached = await this.redis.get(SNAPSHOT_CACHE_KEY);
            if (cached)
                return JSON.parse(cached);
        }
        catch {
            // PostgreSQL remains the durable fallback when Redis is unavailable.
        }
        const [ios, android] = await Promise.all([
            this.buildPlatformSnapshot(this.apple, now),
            this.buildPlatformSnapshot(this.google, now),
        ]);
        const snapshot = { ios, android };
        try {
            await this.redis.setWithTtl(SNAPSHOT_CACHE_KEY, JSON.stringify(snapshot), env_1.env.APP_DOWNLOAD_CACHE_TTL_SECONDS);
        }
        catch {
            // A response must still be available from PostgreSQL.
        }
        return snapshot;
    }
    async syncAll() {
        let locked = true;
        try {
            locked =
                (await this.redis.setNxWithTtl(SYNC_LOCK_KEY, '1', 30 * 60)) === 'OK';
        }
        catch {
            // Upserts are idempotent, so a Redis outage does not prevent syncing.
        }
        if (!locked)
            return;
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
            }
            catch {
                // The next read will still use durable PostgreSQL data.
            }
        }
        try {
            await this.redis.del(SYNC_LOCK_KEY);
        }
        catch {
            // The lock expires automatically.
        }
    }
    async syncSource(source) {
        if (!source.isConfigured())
            return false;
        const latest = await this.prisma.appDownloadDailyStat.findFirst({
            where: { platform: source.platform },
            orderBy: { reportDate: 'desc' },
            select: { reportDate: true },
        });
        const sinceDate = latest
            ? this.addDays(this.isoDate(latest.reportDate), -62)
            : undefined;
        const points = await source.fetchDailyDownloads(sinceDate);
        if (points.length === 0)
            return false;
        const syncedAt = new Date();
        for (let offset = 0; offset < points.length; offset += 500) {
            const chunk = points.slice(offset, offset + 500);
            await this.prisma.$transaction(chunk.map((point) => this.prisma.appDownloadDailyStat.upsert({
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
            })));
        }
        return true;
    }
    async buildPlatformSnapshot(source, now) {
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
        const byDate = new Map(rows.map((row) => [this.isoDate(row.reportDate), row.downloads]));
        const todayDate = this.dateInTimeZone(now, source.timeZone);
        const yesterdayDate = this.addDays(todayDate, -1);
        const latestReportDate = this.isoDate(rows[rows.length - 1].reportDate);
        const sumFrom = (days) => {
            const firstDate = this.addDays(latestReportDate, -(days - 1));
            return rows
                .filter((row) => {
                const date = this.isoDate(row.reportDate);
                return date >= firstDate && date <= latestReportDate;
            })
                .reduce((total, row) => total + row.downloads, 0);
        };
        const lastUpdatedAt = rows.reduce((latest, row) => row.lastSyncedAt > latest ? row.lastSyncedAt : latest, rows[0].lastSyncedAt);
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
    dateInTimeZone(date, timeZone) {
        const parts = new Intl.DateTimeFormat('en-US', {
            timeZone,
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
        }).formatToParts(date);
        const read = (type) => parts.find((part) => part.type === type)?.value ?? '';
        return `${read('year')}-${read('month')}-${read('day')}`;
    }
    isoDate(date) {
        return date.toISOString().slice(0, 10);
    }
    addDays(date, amount) {
        const value = new Date(`${date}T00:00:00.000Z`);
        value.setUTCDate(value.getUTCDate() + amount);
        return value.toISOString().slice(0, 10);
    }
};
exports.AdminAppDownloadsService = AdminAppDownloadsService;
exports.AdminAppDownloadsService = AdminAppDownloadsService = AdminAppDownloadsService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        redis_service_1.RedisService,
        apple_app_downloads_source_1.AppleAppDownloadsSource,
        google_play_downloads_source_1.GooglePlayDownloadsSource])
], AdminAppDownloadsService);
//# sourceMappingURL=admin-app-downloads.service.js.map