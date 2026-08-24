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
exports.ViewedListingsService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../prisma/prisma.service");
const pageLimit = (value) => Math.max(1, Math.min(Number.isFinite(value ?? NaN) ? value : 50, 100));
const encodeCursor = (payload) => Buffer.from(JSON.stringify(payload)).toString('base64url');
const decodeCursor = (cursor) => {
    const raw = cursor?.trim();
    if (!raw)
        return null;
    try {
        const decoded = JSON.parse(Buffer.from(raw, 'base64url').toString('utf8'));
        return decoded && typeof decoded === 'object' ? decoded : null;
    }
    catch {
        return null;
    }
};
let ViewedListingsService = class ViewedListingsService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async list(authUser, params) {
        const limit = pageLimit(params?.limit);
        const cursor = decodeCursor(params?.cursor);
        const cursorDate = cursor ? new Date(cursor.viewedAt) : null;
        const cursorListingId = cursor?.listingId ?? '';
        const items = await this.prisma.viewedListing.findMany({
            where: {
                userId: authUser.userId,
                ...(cursorDate && !Number.isNaN(cursorDate.getTime())
                    ? {
                        OR: [
                            { viewedAt: { lt: cursorDate } },
                            { viewedAt: cursorDate, listingId: { lt: cursorListingId } },
                        ],
                    }
                    : {}),
            },
            orderBy: [{ viewedAt: 'desc' }, { listingId: 'desc' }],
            take: limit + 1,
        });
        const pageItems = items.slice(0, limit);
        const hasMore = items.length > limit;
        const last = hasMore ? pageItems[pageItems.length - 1] : null;
        return {
            source: 'timeweb',
            items: pageItems.map((item) => ({
                listing_id: item.listingId,
                viewed_at: item.viewedAt.toISOString(),
            })),
            nextCursor: last
                ? encodeCursor({
                    viewedAt: last.viewedAt.toISOString(),
                    listingId: last.listingId,
                })
                : null,
            hasMore,
            limit,
        };
    }
    async mark(authUser, listingId) {
        await this.prisma.viewedListing.upsert({
            where: {
                userId_listingId: {
                    userId: authUser.userId,
                    listingId,
                },
            },
            update: {
                viewedAt: new Date(),
            },
            create: {
                userId: authUser.userId,
                listingId,
            },
        });
        return {
            viewed: true,
            listing_id: listingId,
        };
    }
};
exports.ViewedListingsService = ViewedListingsService;
exports.ViewedListingsService = ViewedListingsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], ViewedListingsService);
//# sourceMappingURL=viewed-listings.service.js.map