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
Object.defineProperty(exports, "__esModule", { value: true });
exports.FeedAdsService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const crypto_1 = require("crypto");
const prisma_service_1 = require("../prisma/prisma.service");
const rate_limit_service_1 = require("../rate-limit/rate-limit.service");
const storage_service_1 = require("../storage/storage.service");
const FEED_AD_IMPRESSION_DEBOUNCE_MS = 30 * 1000;
const FEED_AD_CLICK_DEBOUNCE_MS = 5 * 1000;
let FeedAdsService = class FeedAdsService {
    constructor(prisma, storageService, rateLimitService) {
        this.prisma = prisma;
        this.storageService = storageService;
        this.rateLimitService = rateLimitService;
    }
    serialize(item) {
        return {
            id: item.id,
            title: item.title,
            image_url: item.imageUrl,
            target_url: item.targetUrl,
            duration_days: item.durationDays,
            is_active: item.isActive,
            placement: item.placement.toLowerCase(),
            created_at: item.createdAt.toISOString(),
            activated_at: item.activatedAt?.toISOString() ?? null,
            expires_at: item.expiresAt?.toISOString() ?? null,
            updated_at: item.updatedAt?.toISOString() ?? null,
            impression_count: Number(item.impressionCount),
            click_count: Number(item.clickCount),
        };
    }
    placementFromInput(value) {
        return (value ?? '').trim().toLowerCase() === 'home'
            ? client_1.FeedAdPlacement.HOME
            : client_1.FeedAdPlacement.HOME;
    }
    normalizeTargetUrl(value) {
        const targetUrl = (value ?? '').toString().trim();
        if (!targetUrl)
            return '';
        let parsed;
        try {
            parsed = new URL(targetUrl);
        }
        catch {
            throw new common_1.BadRequestException('Некорректная ссылка');
        }
        if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
            throw new common_1.BadRequestException('Некорректная ссылка');
        }
        return targetUrl;
    }
    async listAll(placement) {
        const items = await this.prisma.feedAd.findMany({
            where: {
                placement: this.placementFromInput(placement),
            },
            orderBy: {
                createdAt: 'desc',
            },
        });
        return {
            source: 'timeweb',
            items: items.map((item) => this.serialize(item)),
        };
    }
    async getActive(placement, afterId) {
        const now = new Date();
        const items = await this.prisma.feedAd.findMany({
            where: {
                placement: this.placementFromInput(placement),
                isActive: true,
                OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
            },
            orderBy: [{ activatedAt: 'asc' }, { createdAt: 'asc' }],
            take: 3,
        });
        const cursor = (afterId ?? '').trim();
        const currentIndex = cursor
            ? items.findIndex((item) => item.id === cursor)
            : -1;
        const item = items.length === 0
            ? null
            : items[(currentIndex + 1 + items.length) % items.length];
        return {
            source: 'timeweb',
            ad: item ? this.serialize(item) : null,
        };
    }
    async create(authUser, body) {
        const item = await this.prisma.feedAd.create({
            data: {
                title: (body['title'] ?? '').toString().trim(),
                imageUrl: (body['image_url'] ?? '').toString().trim(),
                targetUrl: this.normalizeTargetUrl(body['target_url']),
                durationDays: Number(body['duration_days'] ?? 0) || 0,
                isActive: body['is_active'] == true,
                placement: this.placementFromInput(body['placement']?.toString()),
                createdById: authUser.userId,
            },
        });
        return {
            source: 'timeweb',
            ad: this.serialize(item),
        };
    }
    async update(id, body) {
        await this.ensureExists(id);
        const item = await this.prisma.feedAd.update({
            where: { id },
            data: {
                title: body['title'] == null
                    ? undefined
                    : (body['title'] ?? '').toString().trim(),
                imageUrl: body['image_url'] == null
                    ? undefined
                    : (body['image_url'] ?? '').toString().trim(),
                targetUrl: body['target_url'] == null
                    ? undefined
                    : this.normalizeTargetUrl(body['target_url']),
                durationDays: body['duration_days'] == null
                    ? undefined
                    : Number(body['duration_days'] ?? 0) || 0,
            },
        });
        return {
            source: 'timeweb',
            ad: this.serialize(item),
        };
    }
    async activate(id) {
        const ad = await this.ensureExists(id);
        const now = new Date();
        const expiresAt = new Date(now.getTime() + ad.durationDays * 86400000);
        if (!ad.isActive || (ad.expiresAt != null && ad.expiresAt <= now)) {
            const activeCount = await this.prisma.feedAd.count({
                where: {
                    id: { not: id },
                    placement: ad.placement,
                    isActive: true,
                    OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
                },
            });
            if (activeCount >= 3) {
                throw new common_1.BadRequestException('Feed ads limit reached for placement');
            }
        }
        const updated = await this.prisma.feedAd.update({
            where: { id },
            data: {
                isActive: true,
                activatedAt: now,
                expiresAt,
            },
        });
        return {
            source: 'timeweb',
            ad: this.serialize(updated),
        };
    }
    async deactivate(id) {
        await this.ensureExists(id);
        const updated = await this.prisma.feedAd.update({
            where: { id },
            data: {
                isActive: false,
            },
        });
        return {
            source: 'timeweb',
            ad: this.serialize(updated),
        };
    }
    async remove(id) {
        await this.ensureExists(id);
        await this.storageService.deleteFeedAdImage(id);
        await this.prisma.feedAd.delete({
            where: { id },
        });
        return {
            deleted: true,
            id,
        };
    }
    async recordImpression(id, source) {
        const shouldCount = await this.shouldCountCounterEvent('impression', id, source, FEED_AD_IMPRESSION_DEBOUNCE_MS);
        if (!shouldCount) {
            return {
                tracked: true,
                id,
                event: 'impression',
            };
        }
        await this.prisma.feedAd.update({
            where: { id },
            data: {
                impressionCount: {
                    increment: 1,
                },
            },
        });
        return {
            tracked: true,
            id,
            event: 'impression',
        };
    }
    async recordClick(id, source) {
        const shouldCount = await this.shouldCountCounterEvent('click', id, source, FEED_AD_CLICK_DEBOUNCE_MS);
        if (!shouldCount) {
            return {
                tracked: true,
                id,
                event: 'click',
            };
        }
        await this.prisma.feedAd.update({
            where: { id },
            data: {
                clickCount: {
                    increment: 1,
                },
            },
        });
        return {
            tracked: true,
            id,
            event: 'click',
        };
    }
    async ensureExists(id) {
        const item = await this.prisma.feedAd.findUnique({
            where: { id },
        });
        if (!item) {
            throw new common_1.NotFoundException('Feed ad not found');
        }
        return item;
    }
    shouldCountCounterEvent(event, id, source, windowMs) {
        const sourceKey = this.counterSourceKey(source);
        if (!sourceKey) {
            return Promise.resolve(true);
        }
        return this.rateLimitService.debounce(`feed-ad:${event}:${id}:${sourceKey}`, windowMs);
    }
    counterSourceKey(source) {
        const ip = source?.ip?.trim();
        const userAgent = source?.userAgent?.trim();
        if (!ip && !userAgent) {
            return '';
        }
        return (0, crypto_1.createHash)('sha256')
            .update(`${ip || 'unknown'}:${userAgent || 'unknown'}`)
            .digest('hex');
    }
    async attachImage(authUser, feedAdId, file) {
        await this.ensureExists(feedAdId);
        const uploaded = await this.storageService.saveUploadedFile({
            buffer: file.buffer,
            category: 'feed-ads',
            contentType: file.mimetype,
            context: {
                feedAdId,
                userId: authUser.userId,
            },
            originalName: file.originalname,
        });
        await this.storageService.deleteFeedAdImage(feedAdId);
        const item = await this.prisma.feedAd.update({
            where: {
                id: feedAdId,
            },
            data: {
                imageBucket: uploaded.bucket ?? 'local',
                imageKey: uploaded.key,
                imageUrl: uploaded.url,
                createdById: authUser.userId,
            },
        });
        return {
            source: 'timeweb',
            ad: this.serialize(item),
        };
    }
};
exports.FeedAdsService = FeedAdsService;
exports.FeedAdsService = FeedAdsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        storage_service_1.StorageService,
        rate_limit_service_1.RateLimitService])
], FeedAdsService);
//# sourceMappingURL=feed-ads.service.js.map