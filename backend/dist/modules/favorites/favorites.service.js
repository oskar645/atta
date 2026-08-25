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
exports.FavoritesService = void 0;
const common_1 = require("@nestjs/common");
const serializers_1 = require("../../common/serializers");
const listings_service_1 = require("../listings/listings.service");
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
let FavoritesService = class FavoritesService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async list(authUser, params) {
        const limit = pageLimit(params?.limit);
        const cursor = decodeCursor(params?.cursor);
        const cursorDate = cursor ? new Date(cursor.createdAt) : null;
        const cursorId = cursor?.id ?? '';
        const favorites = await this.prisma.favorite.findMany({
            where: {
                userId: authUser.userId,
                ...(cursorDate && !Number.isNaN(cursorDate.getTime())
                    ? {
                        OR: [
                            { createdAt: { lt: cursorDate } },
                            { createdAt: cursorDate, id: { lt: cursorId } },
                        ],
                    }
                    : {}),
            },
            orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
            take: limit + 1,
        });
        const pageItems = favorites.slice(0, limit);
        const hasMore = favorites.length > limit;
        const last = hasMore ? pageItems[pageItems.length - 1] : null;
        const listingIds = Array.from(new Set(pageItems.map((favorite) => favorite.listingId)));
        const listings = listingIds.length === 0
            ? []
            : await this.prisma.listing.findMany({
                where: {
                    id: {
                        in: listingIds,
                    },
                },
                include: listings_service_1.listingInclude,
            });
        const visibleListingsById = new Map(listings
            .filter((listing) => (0, listings_service_1.canViewListing)(listing, authUser))
            .map((listing) => [listing.id, (0, serializers_1.serializeListing)(listing)]));
        return {
            items: pageItems.map((favorite) => {
                const listing = visibleListingsById.get(favorite.listingId);
                return {
                    ...(0, serializers_1.serializeFavorite)(favorite),
                    ...(listing ? { listing } : {}),
                };
            }),
            favorite_ids: pageItems.map((favorite) => favorite.listingId),
            nextCursor: last
                ? encodeCursor({
                    createdAt: last.createdAt.toISOString(),
                    id: last.id,
                })
                : null,
            hasMore,
            limit,
        };
    }
    async add(authUser, listingId) {
        const listing = await this.prisma.listing.findUnique({
            where: {
                id: listingId,
            },
            select: {
                id: true,
            },
        });
        if (!listing) {
            throw new common_1.NotFoundException('Listing not found');
        }
        const existingFavorite = await this.prisma.favorite.findFirst({
            where: {
                userId: authUser.userId,
                listingId,
            },
        });
        if (existingFavorite) {
            throw new common_1.ConflictException('Listing is already favorite');
        }
        const favorite = await this.prisma.favorite.create({
            data: {
                userId: authUser.userId,
                listingId,
            },
        });
        return {
            item: (0, serializers_1.serializeFavorite)(favorite),
        };
    }
    async remove(authUser, listingId) {
        const favorite = await this.prisma.favorite.findFirst({
            where: {
                userId: authUser.userId,
                listingId,
            },
        });
        if (!favorite) {
            throw new common_1.NotFoundException('Favorite not found');
        }
        await this.prisma.favorite.delete({
            where: {
                id: favorite.id,
            },
        });
        return {
            deleted: true,
            listing_id: listingId,
        };
    }
};
exports.FavoritesService = FavoritesService;
exports.FavoritesService = FavoritesService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], FavoritesService);
//# sourceMappingURL=favorites.service.js.map