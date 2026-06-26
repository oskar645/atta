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
let ViewedListingsService = class ViewedListingsService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async list(authUser) {
        const items = await this.prisma.viewedListing.findMany({
            where: {
                userId: authUser.userId,
            },
            orderBy: {
                viewedAt: 'desc',
            },
        });
        return {
            source: 'timeweb',
            items: items.map((item) => ({
                listing_id: item.listingId,
                viewed_at: item.viewedAt.toISOString(),
            })),
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