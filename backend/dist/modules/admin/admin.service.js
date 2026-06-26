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
exports.AdminService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const serializers_1 = require("../../common/serializers");
const notifications_service_1 = require("../notifications/notifications.service");
const prisma_service_1 = require("../prisma/prisma.service");
const reviews_service_1 = require("../reviews/reviews.service");
const storage_service_1 = require("../storage/storage.service");
const promotion_plans_constants_1 = require("../promotions/promotion-plans.constants");
const promotionStatusFromInput = (value) => {
    switch ((value ?? '').trim().toLowerCase()) {
        case 'active':
            return client_1.PromotionStatus.ACTIVE;
        case 'expired':
            return client_1.PromotionStatus.EXPIRED;
        case 'cancelled':
            return client_1.PromotionStatus.CANCELLED;
        default:
            return undefined;
    }
};
const promotionTypeFromInput = (value) => {
    switch ((value ?? '').trim().toLowerCase()) {
        case 'showcase':
            return client_1.PromotionType.SHOWCASE;
        case 'bump':
            return client_1.PromotionType.BUMP;
        case 'vip':
            return client_1.PromotionType.VIP;
        case 'turbo':
            return client_1.PromotionType.TURBO;
        default:
            return undefined;
    }
};
const walletTransactionTypeFromInput = (value) => {
    switch ((value ?? '').trim().toLowerCase()) {
        case 'accrual':
            return client_1.WalletTransactionType.ACCRUAL;
        case 'spend':
            return client_1.WalletTransactionType.SPEND;
        case 'refund':
            return client_1.WalletTransactionType.REFUND;
        default:
            return undefined;
    }
};
let AdminService = class AdminService {
    constructor(prisma, notificationsService, reviewsService, storageService) {
        this.prisma = prisma;
        this.notificationsService = notificationsService;
        this.reviewsService = reviewsService;
        this.storageService = storageService;
    }
    async getDashboardStats() {
        const now = new Date();
        const days30 = new Date(now.getTime() - 30 * 86400000);
        const days14 = new Date(now.getTime() - 14 * 86400000);
        const onlineCutoff = new Date(now.getTime() - 2 * 60000);
        const [users, onlineUsers, listings, activeListings, pendingModeration, sold, sales30d, supportOpen, reportsOpen, activeAds, newListings14d, newListingsDaily] = await Promise.all([
            this.prisma.user.count(),
            this.prisma.userPresence.count({
                where: {
                    isOnline: true,
                    lastSeen: {
                        gte: onlineCutoff,
                    },
                },
            }),
            this.prisma.listing.count({
                where: { deletedAt: null },
            }),
            this.prisma.listing.count({
                where: {
                    deletedAt: null,
                    status: client_1.ListingStatus.APPROVED,
                },
            }),
            this.prisma.listing.count({
                where: {
                    deletedAt: null,
                    status: client_1.ListingStatus.PENDING,
                },
            }),
            this.prisma.listing.count({
                where: {
                    deletedAt: null,
                    status: client_1.ListingStatus.SOLD,
                },
            }),
            this.prisma.listing.count({
                where: {
                    deletedAt: null,
                    status: client_1.ListingStatus.SOLD,
                    updatedAt: {
                        gte: days30,
                    },
                },
            }),
            this.prisma.supportTicket.count(),
            this.prisma.report.count({
                where: { status: 'open' },
            }),
            this.prisma.feedAd.count({
                where: {
                    placement: client_1.FeedAdPlacement.HOME,
                    isActive: true,
                    OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
                },
            }),
            this.prisma.listing.count({
                where: {
                    createdAt: {
                        gte: days14,
                    },
                },
            }),
            this.prisma.listing.findMany({
                where: {
                    createdAt: {
                        gte: days14,
                    },
                },
                select: {
                    createdAt: true,
                },
            }),
        ]);
        const dailyMap = new Map();
        for (let index = 13; index >= 0; index -= 1) {
            const day = new Date(now.getTime() - index * 86400000);
            const key = day.toISOString().slice(0, 10);
            dailyMap.set(key, 0);
        }
        for (const item of newListingsDaily) {
            const key = item.createdAt.toISOString().slice(0, 10);
            dailyMap.set(key, (dailyMap.get(key) ?? 0) + 1);
        }
        const listingsDaily = Array.from(dailyMap.entries()).map(([day, count]) => ({
            day,
            listings_new: count,
        }));
        return {
            source: 'timeweb',
            stats: {
                users,
                onlineUsers,
                listings,
                activeListings,
                pendingModeration,
                sold,
                sales30d,
                supportTickets: supportOpen,
                supportOpen,
                reportsOpen,
                activeAds,
                newListings14d,
            },
            daily: {
                listings: listingsDaily,
            },
        };
    }
    async listUsers() {
        const users = await this.prisma.user.findMany({
            include: {
                adminProfile: true,
            },
            orderBy: {
                createdAt: 'desc',
            },
            take: 100,
        });
        return {
            source: 'timeweb',
            items: users.map((user) => (0, serializers_1.serializeUser)(user, { includePrivate: true })),
        };
    }
    async getUserById(id) {
        const user = await this.prisma.user.findUnique({
            where: { id },
            include: {
                adminProfile: true,
            },
        });
        return {
            source: 'timeweb',
            user: user ? (0, serializers_1.serializeUser)(user, { includePrivate: true }) : null,
        };
    }
    async deleteUser(id, authUser) {
        if (id === authUser.userId) {
            return {
                source: 'timeweb',
                deleted: false,
                message: 'Cannot delete current admin account',
            };
        }
        const user = await this.prisma.user.findUnique({
            where: { id },
            include: {
                adminProfile: true,
            },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        if (user.adminProfile?.isAdmin === true) {
            const adminsCount = await this.prisma.adminUser.count({
                where: {
                    isAdmin: true,
                },
            });
            if (adminsCount <= 1) {
                return {
                    source: 'timeweb',
                    deleted: false,
                    message: 'Cannot delete the last admin account',
                };
            }
        }
        await this.performSoftDeleteUser(id, {
            actorUserId: authUser.userId,
            reason: 'Deleted by admin',
        });
        return {
            source: 'timeweb',
            deleted: true,
            user_id: id,
        };
    }
    async getModerationQueue(status) {
        return this.listListings(status);
    }
    async listListings(status) {
        const normalizedStatus = (status ?? '').trim().toLowerCase();
        const items = await this.prisma.listing.findMany({
            where: {
                ...(normalizedStatus == 'all' || normalizedStatus.length === 0
                    ? {}
                    : { status: (0, serializers_1.listingStatusFromInput)(normalizedStatus) }),
            },
            include: {
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
            },
            orderBy: {
                createdAt: 'desc',
            },
            take: 100,
        });
        return {
            source: 'timeweb',
            items: items.map((listing) => (0, serializers_1.serializeListing)(listing)),
            statuses: ['pending', 'approved', 'rejected', 'sold', 'deleted', 'archived'],
        };
    }
    async listPromotions(query) {
        await this.expirePromotionsByTime();
        const range = this.resolveRange({
            from: query.from,
            to: query.to,
        });
        const status = promotionStatusFromInput(query.status);
        const type = promotionTypeFromInput(query.type);
        const items = await this.prisma.promotion.findMany({
            where: {
                ...(status ? { status } : {}),
                ...(type ? { type } : {}),
                ...(query.userId?.trim() ? { userId: query.userId.trim() } : {}),
                ...(query.listingId?.trim()
                    ? { listingId: query.listingId.trim() }
                    : {}),
                ...(range ? { createdAt: range } : {}),
            },
            include: {
                listing: {
                    include: {
                        photos: {
                            orderBy: {
                                sortOrder: 'asc',
                            },
                        },
                    },
                },
                user: {
                    include: {
                        adminProfile: true,
                    },
                },
            },
            orderBy: {
                createdAt: 'desc',
            },
            take: 200,
        });
        const now = Date.now();
        return {
            source: 'timeweb',
            items: items.map((promotion) => ({
                promotionId: promotion.id,
                type: (0, promotion_plans_constants_1.promotionTypeToResponse)(promotion.type),
                status: promotion.status.toLowerCase(),
                listingId: promotion.listingId,
                listingTitle: promotion.listing.title,
                listingPrice: Number(promotion.listing.price),
                listingPhoto: promotion.listing.photos[0]?.publicUrl ?? null,
                userId: promotion.userId,
                userName: promotion.user.displayName || promotion.user.name,
                userPhone: promotion.user.phone,
                costBonus: promotion.costBonus,
                startsAt: promotion.startsAt.toISOString(),
                endsAt: promotion.endsAt.toISOString(),
                timeRemainingSeconds: Math.max(0, Math.ceil((promotion.endsAt.getTime() - now) / 1000)),
                impressionsCount: promotion.impressionsCount,
                clicksCount: promotion.clicksCount,
                createdAt: promotion.createdAt.toISOString(),
            })),
        };
    }
    async getPromotionsSummary() {
        await this.expirePromotionsByTime();
        const now = new Date();
        const startToday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
        const startMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
        const [activeShowcaseCount, activeBumpCount, activeVipCount, activeTurboCount, expiredTodayCount, spentToday, spentThisMonth, showcaseTotals,] = await Promise.all([
            this.prisma.promotion.count({
                where: { status: client_1.PromotionStatus.ACTIVE, type: client_1.PromotionType.SHOWCASE },
            }),
            this.prisma.promotion.count({
                where: { status: client_1.PromotionStatus.ACTIVE, type: client_1.PromotionType.BUMP },
            }),
            this.prisma.promotion.count({
                where: { status: client_1.PromotionStatus.ACTIVE, type: client_1.PromotionType.VIP },
            }),
            this.prisma.promotion.count({
                where: { status: client_1.PromotionStatus.ACTIVE, type: client_1.PromotionType.TURBO },
            }),
            this.prisma.promotion.count({
                where: {
                    status: client_1.PromotionStatus.EXPIRED,
                    endsAt: {
                        gte: startToday,
                        lte: now,
                    },
                },
            }),
            this.prisma.promotion.aggregate({
                _sum: {
                    costBonus: true,
                },
                where: {
                    createdAt: {
                        gte: startToday,
                        lte: now,
                    },
                },
            }),
            this.prisma.promotion.aggregate({
                _sum: {
                    costBonus: true,
                },
                where: {
                    createdAt: {
                        gte: startMonth,
                        lte: now,
                    },
                },
            }),
            this.prisma.promotion.aggregate({
                _sum: {
                    impressionsCount: true,
                    clicksCount: true,
                },
                where: {
                    type: client_1.PromotionType.SHOWCASE,
                },
            }),
        ]);
        return {
            source: 'timeweb',
            activeShowcaseCount,
            activeBumpCount,
            activeVipCount,
            activeTurboCount,
            expiredTodayCount,
            totalBonusSpentToday: spentToday._sum.costBonus ?? 0,
            totalBonusSpentThisMonth: spentThisMonth._sum.costBonus ?? 0,
            totalShowcaseImpressions: showcaseTotals._sum.impressionsCount ?? 0,
            totalShowcaseClicks: showcaseTotals._sum.clicksCount ?? 0,
        };
    }
    async cancelPromotion(id, authUser) {
        const promotion = await this.prisma.promotion.findUnique({
            where: {
                id,
            },
        });
        if (!promotion) {
            throw new common_1.NotFoundException('Promotion not found');
        }
        const updated = await this.prisma.promotion.update({
            where: {
                id,
            },
            data: {
                status: client_1.PromotionStatus.CANCELLED,
            },
        });
        return {
            source: 'timeweb',
            promotionId: updated.id,
            status: updated.status.toLowerCase(),
            cancelledBy: authUser.userId,
        };
    }
    async listWallets() {
        const wallets = await this.prisma.wallet.findMany({
            include: {
                user: {
                    include: {
                        adminProfile: true,
                    },
                },
            },
            orderBy: {
                updatedAt: 'desc',
            },
            take: 200,
        });
        return {
            source: 'timeweb',
            items: wallets.map((wallet) => ({
                userId: wallet.userId,
                userName: wallet.user.displayName || wallet.user.name,
                userPhone: wallet.user.phone,
                bonusBalance: wallet.bonusBalance,
                lastBonusAccrualAt: (0, serializers_1.toIsoString)(wallet.lastBonusAccrualAt),
                createdAt: wallet.createdAt.toISOString(),
            })),
        };
    }
    async listWalletTransactions(query) {
        const range = this.resolveRange({
            from: query.from,
            to: query.to,
        });
        const type = walletTransactionTypeFromInput(query.type);
        const reason = this.parseWalletReason(query.reason);
        const items = await this.prisma.walletTransaction.findMany({
            where: {
                ...(type ? { type } : {}),
                ...(reason ? { reason } : {}),
                ...(query.userId?.trim() ? { userId: query.userId.trim() } : {}),
                ...(range ? { createdAt: range } : {}),
            },
            include: {
                user: {
                    include: {
                        adminProfile: true,
                    },
                },
            },
            orderBy: {
                createdAt: 'desc',
            },
            take: 300,
        });
        return {
            source: 'timeweb',
            items: items.map((item) => ({
                transactionId: item.id,
                userId: item.userId,
                userName: item.user.displayName || item.user.name,
                userPhone: item.user.phone,
                type: item.type.toLowerCase(),
                amount: item.amount,
                reason: item.reason.toLowerCase(),
                metadata: item.metadata,
                createdAt: item.createdAt.toISOString(),
            })),
        };
    }
    async getBonusAnalytics(query) {
        const range = this.resolveAnalyticsRange(query);
        const transactions = await this.prisma.walletTransaction.findMany({
            where: {
                createdAt: range,
            },
            orderBy: {
                createdAt: 'desc',
            },
        });
        const totalBonusAccrued = transactions
            .filter((item) => item.type === client_1.WalletTransactionType.ACCRUAL)
            .reduce((sum, item) => sum + item.amount, 0);
        const totalBonusSpent = transactions
            .filter((item) => item.type === client_1.WalletTransactionType.SPEND)
            .reduce((sum, item) => sum + item.amount, 0);
        const totalBonusRefunded = transactions
            .filter((item) => item.type === client_1.WalletTransactionType.REFUND)
            .reduce((sum, item) => sum + item.amount, 0);
        const spentByReason = {
            promotion_showcase: 0,
            promotion_bump: 0,
            promotion_vip: 0,
            promotion_turbo: 0,
        };
        const spendingUsers = new Set();
        for (const item of transactions) {
            if (item.type === client_1.WalletTransactionType.SPEND) {
                spendingUsers.add(item.userId);
            }
            switch (item.reason) {
                case client_1.WalletTransactionReason.PROMOTION_SHOWCASE:
                    spentByReason.promotion_showcase += item.amount;
                    break;
                case client_1.WalletTransactionReason.PROMOTION_BUMP:
                    spentByReason.promotion_bump += item.amount;
                    break;
                case client_1.WalletTransactionReason.PROMOTION_VIP:
                    spentByReason.promotion_vip += item.amount;
                    break;
                case client_1.WalletTransactionReason.PROMOTION_TURBO:
                    spentByReason.promotion_turbo += item.amount;
                    break;
                default:
                    break;
            }
        }
        const activeUsersWithWallet = await this.prisma.wallet.count({
            where: {
                bonusBalance: {
                    gt: 0,
                },
            },
        });
        const fromDate = range.gte instanceof Date ? range.gte : new Date(range.gte);
        const toDate = range.lte instanceof Date ? range.lte : new Date(range.lte);
        return {
            source: 'timeweb',
            period: (query.period ?? 'month').trim().toLowerCase() || 'month',
            from: fromDate.toISOString(),
            to: toDate.toISOString(),
            totalBonusAccrued,
            totalBonusSpent,
            totalBonusRefunded,
            spentByReason,
            activeUsersWithWallet,
            usersSpentBonusesCount: spendingUsers.size,
            note: 'Реальные платежи не подключены. Сейчас учитываются только бонусы.',
        };
    }
    async approveListing(id, authUser) {
        const listing = await this.prisma.listing.findUnique({
            where: { id },
            include: {
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
            },
        });
        if (!listing) {
            throw new common_1.NotFoundException('Listing not found');
        }
        const now = new Date();
        const updated = await this.prisma.listing.update({
            where: { id },
            data: {
                status: client_1.ListingStatus.APPROVED,
                rejectionReason: null,
                moderationNote: null,
                moderatedBy: authUser.userId,
                moderatedAt: now,
                publishedAt: listing.publishedAt ?? now,
                archivedAt: null,
                deletedAt: null,
            },
            include: {
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
            },
        });
        await this.notificationsService.createSystemNotification({
            userId: updated.ownerId,
            title: 'Объявление одобрено',
            body: `Объявление "${updated.title}" прошло модерацию.`,
            type: client_1.NotificationType.MODERATION,
            payload: {
                listingId: updated.id,
                status: 'approved',
            },
        });
        return {
            source: 'timeweb',
            listing: (0, serializers_1.serializeListing)(updated),
        };
    }
    async rejectListing(id, authUser, params) {
        await this.ensureListingExists(id);
        const updated = await this.prisma.listing.update({
            where: { id },
            data: {
                status: client_1.ListingStatus.REJECTED,
                rejectionReason: params?.reason?.trim() || 'Rejected by moderator',
                moderationNote: params?.moderationNote?.trim() || null,
                moderatedBy: authUser.userId,
                moderatedAt: new Date(),
                publishedAt: null,
                archivedAt: null,
                deletedAt: null,
            },
            include: {
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
            },
        });
        await this.notificationsService.createSystemNotification({
            userId: updated.ownerId,
            title: 'Объявление отклонено',
            body: updated.rejectionReason ?? 'Объявление не прошло модерацию.',
            type: client_1.NotificationType.MODERATION,
            payload: {
                listingId: updated.id,
                status: 'rejected',
            },
        });
        return {
            source: 'timeweb',
            listing: (0, serializers_1.serializeListing)(updated),
        };
    }
    async archiveListing(id, authUser, dto) {
        await this.ensureListingExists(id);
        const nextStatus = dto?.status?.trim().toLowerCase() === 'sold'
            ? client_1.ListingStatus.SOLD
            : client_1.ListingStatus.ARCHIVED;
        const nextReason = dto?.note?.trim();
        const updated = await this.prisma.listing.update({
            where: { id },
            data: {
                status: nextStatus,
                rejectionReason: nextReason && nextReason.length > 0
                    ? nextReason
                    : nextStatus === client_1.ListingStatus.SOLD
                        ? 'Объявление отмечено как проданное администратором.'
                        : 'Объявление снято с публикации администратором.',
                moderatedBy: authUser.userId,
                moderatedAt: new Date(),
                archivedAt: new Date(),
            },
            include: {
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
            },
        });
        return {
            source: 'timeweb',
            listing: (0, serializers_1.serializeListing)(updated),
            status_after_archive: nextStatus.toLowerCase(),
        };
    }
    async deleteListing(id, authUser, params) {
        await this.ensureListingExists(id);
        const updated = await this.prisma.listing.update({
            where: { id },
            data: {
                status: client_1.ListingStatus.DELETED,
                rejectionReason: params?.reason?.trim() || 'Deleted by moderator',
                moderationNote: params?.moderationNote?.trim() || null,
                moderatedBy: authUser.userId,
                moderatedAt: new Date(),
                deletedAt: new Date(),
                publishedAt: null,
            },
            include: {
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
            },
        });
        await this.notificationsService.createSystemNotification({
            userId: updated.ownerId,
            title: 'Объявление удалено',
            body: updated.rejectionReason ?? 'Объявление удалено модератором.',
            type: client_1.NotificationType.MODERATION,
            payload: {
                listingId: updated.id,
                status: 'deleted',
            },
        });
        await this.storageService.deleteListingPhotosForListings([id]);
        return {
            source: 'timeweb',
            listing: (0, serializers_1.serializeListing)(updated),
        };
    }
    async deleteReview(id, authUser) {
        return this.reviewsService.deleteReviewAsAdmin(authUser, id);
    }
    async getReportsPlaceholder() {
        const items = await this.prisma.report.findMany({
            orderBy: {
                createdAt: 'desc',
            },
            take: 100,
        });
        return {
            source: 'timeweb',
            items: items.map((report) => ({
                id: report.id,
                listing_id: report.listingId,
                listing_owner_id: report.listingOwnerId,
                reporter_id: report.reporterId,
                reason: report.reason,
                comment: report.comment,
                status: report.status,
                created_at: report.createdAt.toISOString(),
            })),
        };
    }
    async getSupportTicketsPlaceholder() {
        const items = await this.prisma.supportTicket.findMany({
            orderBy: {
                updatedAt: 'desc',
            },
            take: 100,
        });
        return {
            source: 'timeweb',
            items: items.map((ticket) => ({
                id: ticket.id,
                user_id: ticket.userId,
                name: ticket.name,
                subject: ticket.subject,
                status: ticket.status.toLowerCase(),
                unread_for_admin: ticket.unreadForAdmin,
                unread_for_user: ticket.unreadForUser,
                last_message: ticket.lastMessage,
                created_at: ticket.createdAt.toISOString(),
                updated_at: ticket.updatedAt.toISOString(),
            })),
        };
    }
    async ensureListingExists(id) {
        const listing = await this.prisma.listing.findUnique({
            where: { id },
            select: { id: true },
        });
        if (!listing) {
            throw new common_1.NotFoundException('Listing not found');
        }
    }
    async performSoftDeleteUser(userId, params) {
        const user = await this.prisma.user.findUnique({
            where: {
                id: userId,
            },
            select: {
                avatarUrl: true,
            },
        });
        const now = new Date();
        const deletedEmail = `deleted+${userId}@atta.local`;
        const listingIds = (await this.prisma.listing.findMany({
            where: {
                ownerId: userId,
            },
            select: {
                id: true,
            },
        })).map((item) => item.id);
        const chatIds = (await this.prisma.chat.findMany({
            where: {
                OR: [{ buyerId: userId }, { sellerId: userId }],
            },
            select: {
                id: true,
            },
        })).map((item) => item.id);
        await this.storageService.deleteAvatarUrl(user?.avatarUrl ?? null);
        await this.storageService.deleteListingPhotosForListings(listingIds);
        await this.storageService.deleteChatImagesForChats(chatIds);
        await this.prisma.$transaction(async (tx) => {
            if (chatIds.length > 0) {
                await tx.chatMessage.updateMany({
                    where: {
                        chatId: {
                            in: chatIds,
                        },
                        deletedAt: null,
                    },
                    data: {
                        deletedAt: now,
                    },
                });
                await tx.chat.updateMany({
                    where: {
                        id: {
                            in: chatIds,
                        },
                    },
                    data: {
                        deletedByBuyerAt: now,
                        deletedBySellerAt: now,
                        unreadForBuyer: 0,
                        unreadForSeller: 0,
                        lastMessage: '',
                    },
                });
            }
            await tx.favorite.deleteMany({
                where: {
                    userId,
                },
            });
            await tx.savedSearch.deleteMany({
                where: {
                    userId,
                },
            });
            await tx.viewedListing.deleteMany({
                where: {
                    userId,
                },
            });
            await tx.userFollow.deleteMany({
                where: {
                    OR: [{ followerId: userId }, { sellerId: userId }],
                },
            });
            await tx.review.updateMany({
                where: {
                    reviewerId: userId,
                    deletedAt: null,
                },
                data: {
                    deletedAt: now,
                    updatedAt: now,
                },
            });
            await tx.userNotification.deleteMany({
                where: {
                    userId,
                },
            });
            await tx.supportMessage.updateMany({
                where: {
                    senderUserId: userId,
                },
                data: {
                    senderUserId: null,
                },
            });
            await tx.supportTicket.updateMany({
                where: {
                    userId,
                },
                data: {
                    name: 'Удалённый пользователь',
                },
            });
            await tx.listing.updateMany({
                where: {
                    ownerId: userId,
                    deletedAt: null,
                },
                data: {
                    status: client_1.ListingStatus.DELETED,
                    deletedAt: now,
                    publishedAt: null,
                    moderatedBy: params.actorUserId,
                    moderatedAt: now,
                    rejectionReason: params.reason,
                },
            });
            await tx.userSession.updateMany({
                where: {
                    userId,
                    revokedAt: null,
                },
                data: {
                    revokedAt: now,
                },
            });
            await tx.user.update({
                where: {
                    id: userId,
                },
                data: {
                    status: client_1.UserStatus.DELETED,
                    deletedAt: now,
                    blockedAt: now,
                    blockReason: params.reason,
                    phoneVerified: false,
                    phone: null,
                    email: deletedEmail,
                    displayName: 'Удалённый пользователь',
                    name: 'Удалённый пользователь',
                    avatarUrl: null,
                    photoUrl: null,
                },
            });
            if (listingIds.length > 0) {
                await tx.report.updateMany({
                    where: {
                        listingId: {
                            in: listingIds,
                        },
                    },
                    data: {
                        listingOwnerId: null,
                    },
                });
            }
        });
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
    resolveRange(params) {
        const from = params.from ? new Date(params.from) : null;
        const to = params.to ? new Date(params.to) : null;
        const hasFrom = from != null && !Number.isNaN(from.getTime());
        const hasTo = to != null && !Number.isNaN(to.getTime());
        if (!hasFrom && !hasTo) {
            return undefined;
        }
        return {
            ...(hasFrom ? { gte: from } : {}),
            ...(hasTo ? { lte: to } : {}),
        };
    }
    resolveAnalyticsRange(query) {
        const explicit = this.resolveRange({
            from: query.from,
            to: query.to,
        });
        if (explicit?.gte && explicit.lte) {
            return explicit;
        }
        const now = new Date();
        const period = (query.period ?? 'month').trim().toLowerCase();
        let start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
        if (period === 'day') {
            start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
        }
        else if (period === 'week') {
            start = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
        }
        return {
            gte: explicit?.gte ?? start,
            lte: explicit?.lte ?? now,
        };
    }
    parseWalletReason(value) {
        const normalized = (value ?? '').trim().toUpperCase();
        if (!normalized) {
            return undefined;
        }
        return Object.values(client_1.WalletTransactionReason).find((item) => item === normalized);
    }
};
exports.AdminService = AdminService;
exports.AdminService = AdminService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        notifications_service_1.NotificationsService,
        reviews_service_1.ReviewsService,
        storage_service_1.StorageService])
], AdminService);
//# sourceMappingURL=admin.service.js.map