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
let UserFollowsService = class UserFollowsService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async list(authUser) {
        const items = await this.prisma.userFollow.findMany({
            where: {
                followerId: authUser.userId,
            },
            orderBy: {
                createdAt: 'desc',
            },
        });
        return {
            source: 'timeweb',
            items: items.map((item) => ({
                follower_id: item.followerId,
                seller_id: item.sellerId,
                created_at: item.createdAt.toISOString(),
            })),
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