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
const prisma_service_1 = require("../prisma/prisma.service");
const storage_service_1 = require("../storage/storage.service");
let FeedAdsService = class FeedAdsService {
    constructor(prisma, storageService) {
        this.prisma = prisma;
        this.storageService = storageService;
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
    async getActive(placement) {
        const now = new Date();
        const item = await this.prisma.feedAd.findFirst({
            where: {
                placement: this.placementFromInput(placement),
                isActive: true,
                OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
            },
            orderBy: [{ activatedAt: 'desc' }, { createdAt: 'desc' }],
        });
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
                targetUrl: (body['target_url'] ?? '').toString().trim(),
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
                title: body['title'] == null ? undefined : (body['title'] ?? '').toString().trim(),
                imageUrl: body['image_url'] == null
                    ? undefined
                    : (body['image_url'] ?? '').toString().trim(),
                targetUrl: body['target_url'] == null
                    ? undefined
                    : (body['target_url'] ?? '').toString().trim(),
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
        await this.prisma.feedAd.updateMany({
            where: { placement: ad.placement },
            data: {
                isActive: false,
            },
        });
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
    async recordImpression(id) {
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
    async recordClick(id) {
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
        storage_service_1.StorageService])
], FeedAdsService);
//# sourceMappingURL=feed-ads.service.js.map