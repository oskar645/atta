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
exports.UserFollowsService = void 0;
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
let UserFollowsService = class UserFollowsService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async list(authUser, params) {
        const limit = pageLimit(params?.limit);
        const cursor = decodeCursor(params?.cursor);
        const cursorDate = cursor ? new Date(cursor.createdAt) : null;
        const cursorSellerId = cursor?.sellerId ?? '';
        const items = await this.prisma.userFollow.findMany({
            where: {
                followerId: authUser.userId,
                ...(cursorDate && !Number.isNaN(cursorDate.getTime())
                    ? {
                        OR: [
                            { createdAt: { lt: cursorDate } },
                            { createdAt: cursorDate, sellerId: { lt: cursorSellerId } },
                        ],
                    }
                    : {}),
            },
            orderBy: [{ createdAt: 'desc' }, { sellerId: 'desc' }],
            take: limit + 1,
        });
        const pageItems = items.slice(0, limit);
        const hasMore = items.length > limit;
        const last = hasMore ? pageItems[pageItems.length - 1] : null;
        return {
            source: 'timeweb',
            items: pageItems.map((item) => ({
                follower_id: item.followerId,
                seller_id: item.sellerId,
                created_at: item.createdAt.toISOString(),
            })),
            nextCursor: last
                ? encodeCursor({
                    createdAt: last.createdAt.toISOString(),
                    sellerId: last.sellerId,
                })
                : null,
            hasMore,
            limit,
        };
    }
    async follow(authUser, sellerId) {
        await this.prisma.userFollow.upsert({
            where: {
                followerId_sellerId: {
                    followerId: authUser.userId,
                    sellerId,
                },
            },
            update: {},
            create: {
                followerId: authUser.userId,
                sellerId,
            },
        });
        return {
            followed: true,
            seller_id: sellerId,
        };
    }
    async unfollow(authUser, sellerId) {
        await this.prisma.userFollow.deleteMany({
            where: {
                followerId: authUser.userId,
                sellerId,
            },
        });
        return {
            followed: false,
            seller_id: sellerId,
        };
    }
    async countFollowers(sellerId) {
        const count = await this.prisma.userFollow.count({
            where: {
                sellerId,
            },
        });
        return {
            source: 'timeweb',
            seller_id: sellerId,
            followers_count: count,
        };
    }
};
exports.UserFollowsService = UserFollowsService;
exports.UserFollowsService = UserFollowsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], UserFollowsService);
//# sourceMappingURL=user-follows.service.js.map