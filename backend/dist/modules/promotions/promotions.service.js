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
exports.PromotionsService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const serializers_1 = require("../../common/serializers");
const prisma_service_1 = require("../prisma/prisma.service");
const wallet_service_1 = require("../wallet/wallet.service");
const promotion_plans_constants_1 = require("./promotion-plans.constants");
const promotableStatuses = new Set([
    client_1.ListingStatus.APPROVED,
]);
const listingInclude = {
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
    promotions: {
        where: {
            status: client_1.PromotionStatus.ACTIVE,
        },
        orderBy: {
            createdAt: 'desc',
        },
    },
};
let PromotionsService = class PromotionsService {
    constructor(prisma, walletService) {
        this.prisma = prisma;
        this.walletService = walletService;
    }
    getPlans() {
        return {
            items: promotion_plans_constants_1.PROMOTION_PLAN_ORDER.map((type) => {
                const plan = promotion_plans_constants_1.PROMOTION_PLANS[type];
                return {
                    type: (0, promotion_plans_constants_1.promotionTypeToResponse)(plan.type),
                    title: plan.title,
                    description: plan.description,
                    costBonus: plan.costBonus,
                    durationHours: Math.floor(plan.durationMs / (60 * 60 * 1000)),
                };
            }),
        };
    }
    async getListingPromotions(listingId, authUser) {
        const listing = await this.prisma.listing.findUnique({
            where: {
                id: listingId,
            },
            include: listingInclude,
        });
        if (!listing) {
            throw new common_1.NotFoundException('Listing not found');
        }
        return {
            listing_id: listing.id,
            promotions: this.buildPromotionFlags(listing.promotions),
            canPromote: this.canPromoteListing(listing, authUser),
            cannotPromoteReason: this.getCannotPromoteReason(listing, authUser),
            cannotPromoteCode: this.getCannotPromoteCode(listing, authUser),
        };
    }
    async promoteListing(listingId, authUser, inputType) {
        const type = this.parsePromotionType(inputType);
        const plan = promotion_plans_constants_1.PROMOTION_PLANS[type];
        const listing = await this.prisma.listing.findUnique({
            where: {
                id: listingId,
            },
            include: listingInclude,
        });
        if (!listing) {
            throw new common_1.NotFoundException('Listing not found');
        }
        const cannotPromoteReason = this.getCannotPromoteReason(listing, authUser);
        if (cannotPromoteReason) {
            throw new common_1.BadRequestException(cannotPromoteReason);
        }
        await this.expireStalePromotionsForListing(listing.id);
        const activePromotion = await this.prisma.promotion.findFirst({
            where: {
                listingId,
                userId: authUser.userId,
                type,
                status: client_1.PromotionStatus.ACTIVE,
                endsAt: {
                    gt: new Date(),
                },
            },
            orderBy: {
                createdAt: 'desc',
            },
        });
        if (activePromotion) {
            const freshListing = await this.prisma.listing.findUniqueOrThrow({
                where: {
                    id: listingId,
                },
                include: listingInclude,
            });
            return {
                message: type === client_1.PromotionType.SHOWCASE
                    ? 'Витрина ATTA уже активна'
                    : `${plan.title} уже активно`,
                listing: (0, serializers_1.serializeListing)(freshListing),
                promotion: this.serializePromotion(activePromotion),
                walletBalance: (await this.walletService.getWallet(authUser)).balance,
            };
        }
        const wallet = await this.walletService.ensureWalletAndBonuses(authUser.userId);
        if (wallet.bonusBalance < plan.costBonus) {
            throw new common_1.BadRequestException({
                message: 'Недостаточно поинтов',
                currentBalance: wallet.bonusBalance,
                requiredBalance: plan.costBonus,
            });
        }
        const walletReason = await this.walletService.resolveSpendReason(plan.walletReason);
        const { promotion, updatedWallet, alreadyActive } = await this.prisma.$transaction(async (tx) => {
            await tx.$executeRaw `
          SELECT pg_advisory_xact_lock(
            hashtext(${`${listingId}:${type}`})
          )
        `;
            await tx.promotion.updateMany({
                where: {
                    listingId,
                    status: client_1.PromotionStatus.ACTIVE,
                    endsAt: {
                        lte: new Date(),
                    },
                },
                data: {
                    status: client_1.PromotionStatus.EXPIRED,
                },
            });
            const existingPromotion = await tx.promotion.findFirst({
                where: {
                    listingId,
                    userId: authUser.userId,
                    type,
                    status: client_1.PromotionStatus.ACTIVE,
                    endsAt: {
                        gt: new Date(),
                    },
                },
                orderBy: {
                    createdAt: 'desc',
                },
            });
            if (existingPromotion) {
                return {
                    promotion: existingPromotion,
                    updatedWallet: await tx.wallet.findUniqueOrThrow({
                        where: {
                            userId: authUser.userId,
                        },
                    }),
                    alreadyActive: true,
                };
            }
            const updatedWallet = await this.walletService.spendBonus(authUser.userId, plan.costBonus, walletReason, {
                listingId,
                promotionType: (0, promotion_plans_constants_1.promotionTypeToResponse)(type),
                requestedWalletReason: plan.walletReason.toLowerCase(),
                walletReasonFallbackApplied: walletReason !== plan.walletReason,
            }, tx);
            const now = new Date();
            const endsAt = new Date(now.getTime() + plan.durationMs);
            const promotion = await tx.promotion.create({
                data: {
                    listingId,
                    userId: authUser.userId,
                    type,
                    costBonus: plan.costBonus,
                    startsAt: now,
                    endsAt,
                    status: client_1.PromotionStatus.ACTIVE,
                },
            });
            return {
                promotion,
                updatedWallet,
                alreadyActive: false,
            };
        });
        const freshListing = await this.prisma.listing.findUniqueOrThrow({
            where: {
                id: listingId,
            },
            include: listingInclude,
        });
        return {
            message: alreadyActive
                ? promotion.type === client_1.PromotionType.SHOWCASE
                    ? 'Витрина ATTA уже активна'
                    : `${plan.title} уже активно`
                : promotion.type === client_1.PromotionType.SHOWCASE
                    ? 'Объявление добавлено в Витрину ATTA'
                    : `${plan.title} активировано`,
            listing: (0, serializers_1.serializeListing)(freshListing),
            promotion: this.serializePromotion(promotion),
            walletBalance: updatedWallet.bonusBalance,
        };
    }
    async getShowcase() {
        await this.expirePromotionsByTime();
        const promotions = await this.prisma.promotion.findMany({
            where: {
                type: client_1.PromotionType.SHOWCASE,
                status: client_1.PromotionStatus.ACTIVE,
                endsAt: {
                    gt: new Date(),
                },
                listing: {
                    status: client_1.ListingStatus.APPROVED,
                    deletedAt: null,
                    archivedAt: null,
                },
            },
            include: {
                listing: {
                    include: {
                        owner: true,
                        photos: {
                            orderBy: {
                                sortOrder: 'asc',
                            },
                        },
                    },
                },
            },
            orderBy: {
                createdAt: 'desc',
            },
        });
        const uniquePromotions = promotions.filter((promotion, index, items) => items.findIndex((candidate) => candidate.listingId === promotion.listingId) === index);
        const sellerIds = [
            ...new Set(uniquePromotions.map((promotion) => promotion.listing.ownerId)),
        ];
        const groupedRatings = sellerIds.length
            ? await this.prisma.review.groupBy({
                by: ['sellerId'],
                where: {
                    sellerId: {
                        in: sellerIds,
                    },
                    deletedAt: null,
                },
                _avg: {
                    rating: true,
                },
            })
            : [];
        const ratingsBySellerId = new Map(groupedRatings.map((entry) => [entry.sellerId, entry._avg.rating]));
        return {
            items: uniquePromotions.map((promotion) => ({
                promotionId: promotion.id,
                listingId: promotion.listingId,
                title: promotion.listing.title,
                price: Number(promotion.listing.price),
                city: promotion.listing.city,
                firstPhotoUrl: promotion.listing.photos[0]?.publicUrl ?? null,
                sellerId: promotion.listing.ownerId,
                sellerName: promotion.listing.owner.displayName ||
                    promotion.listing.owner.name ||
                    promotion.listing.ownerName,
                sellerAvatarUrl: promotion.listing.owner.avatarUrl ??
                    promotion.listing.owner.photoUrl ??
                    null,
                sellerRating: ratingsBySellerId.get(promotion.listing.ownerId) == null
                    ? null
                    : Number(ratingsBySellerId.get(promotion.listing.ownerId)?.toFixed(2)),
                category: promotion.listing.category,
                startsAt: promotion.startsAt.toISOString(),
                endsAt: promotion.endsAt.toISOString(),
                impressionsCount: promotion.impressionsCount,
                clicksCount: promotion.clicksCount,
            })),
        };
    }
    async registerImpression(promotionId) {
        return this.bumpMetric(promotionId, 'impressionsCount');
    }
    async registerClick(promotionId) {
        return this.bumpMetric(promotionId, 'clicksCount');
    }
    async expirePromotionsByTime() {
        await this.prisma.promotion.updateMany({
            where: {
                status: client_1.PromotionStatus.ACTIVE,
                endsAt: {
                    lte: new Date(),
                },
            },
            data: {
                status: client_1.PromotionStatus.EXPIRED,
            },
        });
    }
    enrichListing(listing, authUser) {
        return {
            promotions: this.buildPromotionFlags(listing.promotions ?? []),
            canPromote: authUser ? this.canPromoteListing(listing, authUser) : false,
            cannotPromoteReason: authUser
                ? this.getCannotPromoteReason(listing, authUser)
                : 'Требуется авторизация',
            cannotPromoteCode: authUser
                ? this.getCannotPromoteCode(listing, authUser)
                : 'not_authenticated',
        };
    }
    async expireStalePromotionsForListing(listingId) {
        await this.prisma.promotion.updateMany({
            where: {
                listingId,
                status: client_1.PromotionStatus.ACTIVE,
                endsAt: {
                    lte: new Date(),
                },
            },
            data: {
                status: client_1.PromotionStatus.EXPIRED,
            },
        });
    }
    canPromoteListing(listing, authUser) {
        return this.getCannotPromoteCode(listing, authUser) == null;
    }
    getCannotPromoteCode(listing, authUser) {
        if (listing.ownerId !== authUser.userId) {
            return 'not_owner';
        }
        if (listing.deletedAt || listing.status === client_1.ListingStatus.DELETED) {
            return 'deleted';
        }
        if (listing.archivedAt || listing.status === client_1.ListingStatus.ARCHIVED) {
            return 'archived';
        }
        switch (listing.status) {
            case client_1.ListingStatus.PENDING:
                return 'pending';
            case client_1.ListingStatus.REJECTED:
                return 'rejected';
            case client_1.ListingStatus.SOLD:
                return 'sold';
            default:
                break;
        }
        if (!promotableStatuses.has(listing.status)) {
            return 'unpublished';
        }
        return null;
    }
    getCannotPromoteReason(listing, authUser) {
        switch (this.getCannotPromoteCode(listing, authUser)) {
            case 'not_owner':
                return 'Продвижение доступно только владельцу объявления.';
            case 'deleted':
                return 'Удалённые объявления нельзя продвигать.';
            case 'archived':
                return 'Архивные объявления нельзя продвигать.';
            case 'pending':
                return 'Объявление пока на модерации.';
            case 'rejected':
                return 'Отклонённые объявления нельзя продвигать.';
            case 'sold':
                return 'Проданное объявление нельзя продвигать.';
            case 'unpublished':
                return 'Это объявление сейчас нельзя продвигать.';
            default:
                return null;
        }
    }
    buildPromotionFlags(promotions) {
        const activeByType = new Map();
        for (const promotion of promotions) {
            if (promotion.status === client_1.PromotionStatus.ACTIVE &&
                promotion.endsAt.getTime() > Date.now() &&
                !activeByType.has(promotion.type)) {
                activeByType.set(promotion.type, promotion);
            }
        }
        return {
            activeShowcase: this.serializePromotion(activeByType.get(client_1.PromotionType.SHOWCASE)),
            activeBump: this.serializePromotion(activeByType.get(client_1.PromotionType.BUMP)),
            activeVip: this.serializePromotion(activeByType.get(client_1.PromotionType.VIP)),
            activeTurbo: this.serializePromotion(activeByType.get(client_1.PromotionType.TURBO)),
        };
    }
    serializePromotion(promotion) {
        if (!promotion) {
            return null;
        }
        const plan = promotion_plans_constants_1.PROMOTION_PLANS[promotion.type];
        return {
            id: promotion.id,
            type: (0, promotion_plans_constants_1.promotionTypeToResponse)(promotion.type),
            title: plan.title,
            endsAt: (0, serializers_1.toIsoString)(promotion.endsAt),
            startsAt: (0, serializers_1.toIsoString)(promotion.startsAt),
            status: promotion.status.toLowerCase(),
            costBonus: promotion.costBonus,
            impressionsCount: promotion.impressionsCount,
            clicksCount: promotion.clicksCount,
        };
    }
    parsePromotionType(inputType) {
        switch (inputType.trim().toLowerCase()) {
            case 'showcase':
                return client_1.PromotionType.SHOWCASE;
            case 'bump':
                return client_1.PromotionType.BUMP;
            case 'vip':
                return client_1.PromotionType.VIP;
            case 'turbo':
                return client_1.PromotionType.TURBO;
            default:
                throw new common_1.BadRequestException('Unsupported promotion type');
        }
    }
    async bumpMetric(promotionId, field) {
        const promotion = await this.prisma.promotion.findUnique({
            where: {
                id: promotionId,
            },
        });
        if (!promotion) {
            return { ok: true };
        }
        if (promotion.status !== client_1.PromotionStatus.ACTIVE ||
            promotion.endsAt.getTime() <= Date.now()) {
            if (promotion.status === client_1.PromotionStatus.ACTIVE &&
                promotion.endsAt.getTime() <= Date.now()) {
                await this.prisma.promotion.update({
                    where: {
                        id: promotionId,
                    },
                    data: {
                        status: client_1.PromotionStatus.EXPIRED,
                    },
                });
            }
            return { ok: true };
        }
        const updated = await this.prisma.promotion.update({
            where: {
                id: promotionId,
            },
            data: {
                [field]: {
                    increment: 1,
                },
            },
        });
        return {
            ok: true,
            promotionId: updated.id,
            impressionsCount: updated.impressionsCount,
            clicksCount: updated.clicksCount,
        };
    }
};
exports.PromotionsService = PromotionsService;
exports.PromotionsService = PromotionsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        wallet_service_1.WalletService])
], PromotionsService);
//# sourceMappingURL=promotions.service.js.map