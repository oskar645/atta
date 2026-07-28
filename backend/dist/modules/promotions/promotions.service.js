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
var PromotionsService_1;
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
const MIN_RAISE_DAYS = 1;
const MAX_RAISE_DAYS = 30;
const RAISE_INTERVAL_MS = 24 * 60 * 60 * 1000;
const RAISE_WORKER_INTERVAL_MS = 60 * 1000;
const RAISE_WORKER_BATCH_SIZE = 10;
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
let PromotionsService = PromotionsService_1 = class PromotionsService {
    constructor(prisma, walletService) {
        this.prisma = prisma;
        this.walletService = walletService;
        this.logger = new common_1.Logger(PromotionsService_1.name);
        this.workerTimer = null;
        this.workerRunning = false;
    }
    onModuleInit() {
        this.workerTimer = setInterval(() => {
            void this.processDueRaiseCampaigns().catch((error) => {
                this.logger.error(`Listing raise worker failed: ${error instanceof Error ? error.message : String(error)}`);
            });
        }, RAISE_WORKER_INTERVAL_MS);
        this.workerTimer.unref?.();
    }
    onModuleDestroy() {
        if (this.workerTimer) {
            clearInterval(this.workerTimer);
            this.workerTimer = null;
        }
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
    async promoteListing(listingId, authUser, input) {
        const inputType = typeof input === 'string' ? input : input.type;
        const type = this.parsePromotionType(inputType);
        const plan = promotion_plans_constants_1.PROMOTION_PLANS[type];
        const days = this.parseRaiseDays(type, typeof input === 'string' ? undefined : input.days);
        const requestIdempotencyKey = typeof input === 'string' ? undefined : input.idempotencyKey;
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
        if (type === client_1.PromotionType.BUMP) {
            return this.purchaseRaiseCampaign({
                listingId,
                authUser,
                days,
                requestIdempotencyKey,
            });
        }
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
                message: 'Недостаточно бонусов',
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
    async processDueRaiseCampaigns(now = new Date()) {
        if (this.workerRunning) {
            return { processed: 0 };
        }
        this.workerRunning = true;
        let processed = 0;
        try {
            const dueCampaigns = await this.prisma.listingRaiseCampaign.findMany({
                where: {
                    status: client_1.ListingRaiseCampaignStatus.ACTIVE,
                    nextRaiseAt: {
                        lte: now,
                    },
                },
                orderBy: {
                    nextRaiseAt: 'asc',
                },
                take: RAISE_WORKER_BATCH_SIZE,
            });
            for (const campaign of dueCampaigns) {
                const didProcess = await this.processOneRaiseCampaign(campaign.id, now);
                if (didProcess) {
                    processed += 1;
                }
            }
            return { processed };
        }
        finally {
            this.workerRunning = false;
        }
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
    async purchaseRaiseCampaign(params) {
        const { listingId, authUser, days } = params;
        const plan = promotion_plans_constants_1.PROMOTION_PLANS[client_1.PromotionType.BUMP];
        const totalPrice = plan.costBonus * days;
        const idempotencyKey = this.buildRaisePurchaseIdempotencyKey(authUser.userId, listingId, days, params.requestIdempotencyKey);
        const existingCampaign = await this.prisma.listingRaiseCampaign.findUnique({
            where: {
                idempotencyKey,
            },
        });
        if (existingCampaign) {
            const freshListing = await this.prisma.listing.findUniqueOrThrow({
                where: {
                    id: listingId,
                },
                include: listingInclude,
            });
            return {
                message: `Поднятие подключено на ${existingCampaign.purchasedRaises} ${this.dayWord(existingCampaign.purchasedRaises)}`,
                listing: (0, serializers_1.serializeListing)(freshListing),
                promotion: this.serializePromotion(await this.prisma.promotion.findFirst({
                    where: {
                        listingId,
                        userId: authUser.userId,
                        type: client_1.PromotionType.BUMP,
                        status: client_1.PromotionStatus.ACTIVE,
                    },
                    orderBy: {
                        createdAt: 'desc',
                    },
                })),
                walletBalance: (await this.walletService.getWallet(authUser)).balance,
                days: existingCampaign.purchasedRaises,
            };
        }
        const wallet = await this.walletService.ensureWalletAndBonuses(authUser.userId);
        if (wallet.bonusBalance < totalPrice) {
            throw new common_1.BadRequestException({
                message: 'Недостаточно бонусов',
                currentBalance: wallet.bonusBalance,
                requiredBalance: totalPrice,
            });
        }
        const walletReason = await this.walletService.resolveSpendReason(plan.walletReason);
        const { promotion, updatedWallet } = await this.prisma.$transaction(async (tx) => {
            await tx.$executeRaw `
          SELECT pg_advisory_xact_lock(
            hashtext(${`raise:${authUser.userId}:${listingId}:${idempotencyKey}`})
          )
        `;
            const existing = await tx.listingRaiseCampaign.findUnique({
                where: {
                    idempotencyKey,
                },
            });
            if (existing) {
                return {
                    promotion: await tx.promotion.findFirst({
                        where: {
                            listingId,
                            userId: authUser.userId,
                            type: client_1.PromotionType.BUMP,
                            status: client_1.PromotionStatus.ACTIVE,
                        },
                        orderBy: {
                            createdAt: 'desc',
                        },
                    }),
                    updatedWallet: await tx.wallet.findUniqueOrThrow({
                        where: {
                            userId: authUser.userId,
                        },
                    }),
                };
            }
            const lockedListing = await tx.listing.findUnique({
                where: {
                    id: listingId,
                },
                select: {
                    id: true,
                    ownerId: true,
                    status: true,
                    deletedAt: true,
                    archivedAt: true,
                },
            });
            if (!lockedListing) {
                throw new common_1.NotFoundException('Listing not found');
            }
            const cannotPromoteReason = this.getCannotPromoteReason(lockedListing, authUser);
            if (cannotPromoteReason) {
                throw new common_1.BadRequestException(cannotPromoteReason);
            }
            const updatedWallet = await this.walletService.spendBonus(authUser.userId, totalPrice, walletReason, {
                listingId,
                promotionType: (0, promotion_plans_constants_1.promotionTypeToResponse)(client_1.PromotionType.BUMP),
                days,
                pricePerRaise: plan.costBonus,
                totalPrice,
                requestedWalletReason: plan.walletReason.toLowerCase(),
                walletReasonFallbackApplied: walletReason !== plan.walletReason,
            }, tx, `promotion_raise:${idempotencyKey}`);
            const now = new Date();
            const promotion = await this.createBumpPromotion(tx, listingId, authUser.userId, plan.costBonus, now);
            await tx.listingRaiseCampaign.create({
                data: {
                    listingId,
                    userId: authUser.userId,
                    purchasedRaises: days,
                    completedRaises: 1,
                    pricePerRaise: plan.costBonus,
                    totalPrice,
                    startedAt: now,
                    lastRaiseAt: now,
                    nextRaiseAt: days > 1 ? new Date(now.getTime() + RAISE_INTERVAL_MS) : null,
                    status: days > 1
                        ? client_1.ListingRaiseCampaignStatus.ACTIVE
                        : client_1.ListingRaiseCampaignStatus.COMPLETED,
                    idempotencyKey,
                },
            });
            return {
                promotion,
                updatedWallet,
            };
        });
        const freshListing = await this.prisma.listing.findUniqueOrThrow({
            where: {
                id: listingId,
            },
            include: listingInclude,
        });
        return {
            message: `Поднятие подключено на ${days} ${this.dayWord(days)}`,
            listing: (0, serializers_1.serializeListing)(freshListing),
            promotion: this.serializePromotion(promotion),
            walletBalance: updatedWallet.bonusBalance,
            days,
        };
    }
    async processOneRaiseCampaign(campaignId, now) {
        return this.prisma.$transaction(async (tx) => {
            const locked = await tx.$queryRaw `
        SELECT "id"
        FROM "listing_raise_campaigns"
        WHERE "id" = ${campaignId}::uuid
          AND "status" = 'ACTIVE'::"ListingRaiseCampaignStatus"
          AND "next_raise_at" <= ${now}
        FOR UPDATE SKIP LOCKED
      `;
            if (locked.length === 0) {
                return false;
            }
            const campaign = await tx.listingRaiseCampaign.findUnique({
                where: {
                    id: campaignId,
                },
            });
            if (!campaign ||
                campaign.status !== client_1.ListingRaiseCampaignStatus.ACTIVE ||
                campaign.nextRaiseAt == null ||
                campaign.nextRaiseAt.getTime() > now.getTime()) {
                return false;
            }
            const listing = await tx.listing.findUnique({
                where: {
                    id: campaign.listingId,
                },
                select: {
                    id: true,
                    ownerId: true,
                    status: true,
                    deletedAt: true,
                    archivedAt: true,
                },
            });
            if (!listing ||
                listing.ownerId !== campaign.userId ||
                this.getCannotPromoteCode(listing, {
                    userId: campaign.userId,
                    sessionId: '',
                    role: 'user',
                }) != null) {
                await tx.listingRaiseCampaign.update({
                    where: {
                        id: campaign.id,
                    },
                    data: {
                        status: client_1.ListingRaiseCampaignStatus.CANCELLED,
                        nextRaiseAt: null,
                        cancelReason: 'listing_not_promotable',
                    },
                });
                return true;
            }
            await this.createBumpPromotion(tx, campaign.listingId, campaign.userId, campaign.pricePerRaise, campaign.nextRaiseAt);
            const completedRaises = campaign.completedRaises + 1;
            const hasMore = completedRaises < campaign.purchasedRaises;
            await tx.listingRaiseCampaign.update({
                where: {
                    id: campaign.id,
                },
                data: {
                    completedRaises,
                    lastRaiseAt: campaign.nextRaiseAt,
                    nextRaiseAt: hasMore
                        ? new Date(campaign.nextRaiseAt.getTime() + RAISE_INTERVAL_MS)
                        : null,
                    status: hasMore
                        ? client_1.ListingRaiseCampaignStatus.ACTIVE
                        : client_1.ListingRaiseCampaignStatus.COMPLETED,
                    cancelReason: null,
                },
            });
            return true;
        });
    }
    async createBumpPromotion(tx, listingId, userId, costBonus, startsAt) {
        return tx.promotion.create({
            data: {
                listingId,
                userId,
                type: client_1.PromotionType.BUMP,
                costBonus,
                startsAt,
                endsAt: new Date(startsAt.getTime() + RAISE_INTERVAL_MS),
                status: client_1.PromotionStatus.ACTIVE,
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
    parseRaiseDays(type, rawDays) {
        if (type !== client_1.PromotionType.BUMP) {
            return 1;
        }
        const days = rawDays ?? 1;
        if (!Number.isInteger(days) || days < MIN_RAISE_DAYS || days > MAX_RAISE_DAYS) {
            throw new common_1.BadRequestException('days must be an integer from 1 to 30');
        }
        return days;
    }
    buildRaisePurchaseIdempotencyKey(userId, listingId, days, requestIdempotencyKey) {
        const requestKey = requestIdempotencyKey?.trim();
        if (requestKey && requestKey.length <= 120) {
            return `raise_purchase:${userId}:${requestKey}`;
        }
        return `raise_purchase:${userId}:${listingId}:${days}:${Date.now()}`;
    }
    dayWord(days) {
        const mod100 = days % 100;
        const mod10 = days % 10;
        if (mod100 >= 11 && mod100 <= 14) {
            return 'дней';
        }
        if (mod10 === 1) {
            return 'день';
        }
        if (mod10 >= 2 && mod10 <= 4) {
            return 'дня';
        }
        return 'дней';
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
exports.PromotionsService = PromotionsService = PromotionsService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        wallet_service_1.WalletService])
], PromotionsService);
//# sourceMappingURL=promotions.service.js.map