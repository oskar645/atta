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
const phone_1 = require("../../common/phone");
const referral_code_1 = require("../../common/referral-code");
const serializers_1 = require("../../common/serializers");
const listing_publication_1 = require("../../common/listing-publication");
const app_visits_service_1 = require("../app-visits/app-visits.service");
const notifications_service_1 = require("../notifications/notifications.service");
const prisma_service_1 = require("../prisma/prisma.service");
const reviews_service_1 = require("../reviews/reviews.service");
const storage_service_1 = require("../storage/storage.service");
const user_blocks_service_1 = require("../user-blocks/user-blocks.service");
const promotion_plans_constants_1 = require("../promotions/promotion-plans.constants");
const listings_service_1 = require("../listings/listings.service");
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
const MOSCOW_OFFSET_MS = 3 * 60 * 60 * 1000;
const moscowCalendarBounds = (date) => {
    const shifted = new Date(date.getTime() + MOSCOW_OFFSET_MS);
    const year = shifted.getUTCFullYear();
    const monthIndex = shifted.getUTCMonth();
    const day = shifted.getUTCDate();
    const utcFromMoscow = (yearValue, monthIndexValue, dayValue) => new Date(Date.UTC(yearValue, monthIndexValue, dayValue) - MOSCOW_OFFSET_MS);
    return {
        year,
        month: monthIndex + 1,
        yearStart: utcFromMoscow(year, 0, 1),
        yearEnd: utcFromMoscow(year + 1, 0, 1),
        monthStart: utcFromMoscow(year, monthIndex, 1),
        nextMonthStart: utcFromMoscow(year, monthIndex + 1, 1),
        dayStart: utcFromMoscow(year, monthIndex, day),
        nextDayStart: utcFromMoscow(year, monthIndex, day + 1),
    };
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
const protectedAdminPhones = new Set([
    '79288888645',
    '79306939954',
]);
const moderationDiffFields = [
    'title',
    'description',
    'price',
    'city',
    'category',
    'subcategory',
    'address',
    'phone_hidden',
    'delivery',
    'car',
    'deal_type',
    'real_estate_type',
    'clothes_type',
    'clothes_size',
    'oem_part_number',
];
let AdminService = class AdminService {
    constructor(prisma, appVisitsService, notificationsService, reviewsService, storageService, userBlocksService) {
        this.prisma = prisma;
        this.appVisitsService = appVisitsService;
        this.notificationsService = notificationsService;
        this.reviewsService = reviewsService;
        this.storageService = storageService;
        this.userBlocksService = userBlocksService;
    }
    pageLimit(value, fallback, max = 100) {
        const parsed = Number(value ?? fallback);
        if (!Number.isFinite(parsed))
            return fallback;
        return Math.min(Math.max(Math.trunc(parsed), 1), max);
    }
    encodeAdminCursor(value) {
        return Buffer.from(JSON.stringify(value)).toString('base64url');
    }
    decodeAdminCursor(cursor) {
        const normalized = cursor?.trim();
        if (!normalized)
            return null;
        try {
            const parsed = JSON.parse(Buffer.from(normalized, 'base64url').toString('utf8'));
            if (!parsed || typeof parsed !== 'object')
                return null;
            return parsed;
        }
        catch {
            return null;
        }
    }
    dateIdCursorWhere(field, cursor) {
        const decoded = this.decodeAdminCursor(cursor);
        const rawDate = decoded?.[field];
        const id = decoded?.id;
        if (!rawDate || !id)
            return {};
        const date = new Date(rawDate);
        if (Number.isNaN(date.getTime()))
            return {};
        return {
            OR: [
                { [field]: { lt: date } },
                { [field]: date, id: { lt: id } },
            ],
        };
    }
    pageInfo(rows, limit, cursorFor) {
        const items = rows.slice(0, limit);
        const last = rows.length > limit ? items[items.length - 1] : null;
        return {
            items,
            hasMore: rows.length > limit,
            nextCursor: last ? this.encodeAdminCursor(cursorFor(last)) : null,
        };
    }
    async getDashboardStats() {
        const now = new Date();
        const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
        const days30 = new Date(now.getTime() - 30 * 86400000);
        const days14 = new Date(now.getTime() - 14 * 86400000);
        const onlineCutoff = new Date(now.getTime() - 2 * 60000);
        const [users, onlineUsers, todayVisits, listings, activeListings, pendingModeration, sold, sales30d, supportOpen, reportsOpen, activeAds, newListings14d, newListingsDaily, spentPoints30d, pointsPurchasesMonth] = await Promise.all([
            this.prisma.user.count({
                where: {
                    deletedAt: null,
                    status: {
                        not: client_1.UserStatus.DELETED,
                    },
                },
            }),
            this.prisma.userPresence.count({
                where: {
                    isOnline: true,
                    lastSeen: {
                        gte: onlineCutoff,
                    },
                },
            }),
            this.appVisitsService.countToday(now),
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
                    archivedAt: null,
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
            this.prisma.walletTransaction.aggregate({
                _sum: {
                    amount: true,
                },
                where: {
                    createdAt: {
                        gte: days30,
                        lte: now,
                    },
                    type: client_1.WalletTransactionType.SPEND,
                },
            }),
            this.getPointsPurchasesSummary({
                from: monthStart.toISOString(),
                to: now.toISOString(),
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
                todayVisits,
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
                spentPoints30d: spentPoints30d._sum.amount ?? 0,
                pointsPurchasesMonth,
            },
            daily: {
                listings: listingsDaily,
            },
        };
    }
    async listUsers(query = {}) {
        const limit = this.pageLimit(query.limit, 100);
        const search = query.search?.trim();
        const phoneDigits = (search ?? '').replace(/\D/g, '');
        const cursorWhere = this.dateIdCursorWhere('createdAt', query.cursor);
        const where = {
            deletedAt: null,
            status: {
                not: client_1.UserStatus.DELETED,
            },
            ...(Object.keys(cursorWhere).length > 0 ? { AND: [cursorWhere] } : {}),
            ...(search
                ? {
                    OR: [
                        ...(this.isUuid(search) ? [{ id: search }] : []),
                        { displayName: { contains: search, mode: 'insensitive' } },
                        { name: { contains: search, mode: 'insensitive' } },
                        { phone: { contains: search } },
                        ...(phoneDigits.length >= 4
                            ? [{ phone: { contains: phoneDigits } }]
                            : []),
                    ],
                }
                : {}),
        };
        const users = await this.prisma.user.findMany({
            where: {
                ...where,
            },
            include: {
                adminProfile: true,
            },
            orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
            take: limit + 1,
        });
        const page = this.pageInfo(users, limit, (user) => ({
            createdAt: user.createdAt.toISOString(),
            id: user.id,
        }));
        return {
            source: 'timeweb',
            items: page.items.map((user) => (0, serializers_1.serializeUser)(user, { includePrivate: true })),
            nextCursor: page.nextCursor,
            hasMore: page.hasMore,
            limit,
        };
    }
    async getUserRegistrationStats(query = {}) {
        const now = new Date();
        const currentBounds = moscowCalendarBounds(now);
        const currentYear = currentBounds.year;
        const currentMonth = currentBounds.month;
        const requestedYear = Number.isInteger(query.year) ? query.year : currentYear;
        const year = Math.min(Math.max(requestedYear, 2000), 2100);
        const yearBounds = moscowCalendarBounds(new Date(Date.UTC(year, 0, 1) - MOSCOW_OFFSET_MS));
        const activeUserWhere = {
            deletedAt: null,
            status: {
                not: client_1.UserStatus.DELETED,
            },
        };
        const [totalUsers, firstUser, currentMonthCount, todayCount, monthRows] = await Promise.all([
            this.prisma.user.count({ where: activeUserWhere }),
            this.prisma.user.findFirst({
                where: activeUserWhere,
                orderBy: { createdAt: 'asc' },
                select: { createdAt: true },
            }),
            this.prisma.user.count({
                where: {
                    ...activeUserWhere,
                    createdAt: {
                        gte: currentBounds.monthStart,
                        lt: currentBounds.nextMonthStart,
                    },
                },
            }),
            this.prisma.user.count({
                where: {
                    ...activeUserWhere,
                    createdAt: {
                        gte: currentBounds.dayStart,
                        lt: currentBounds.nextDayStart,
                    },
                },
            }),
            this.prisma.$queryRaw `
          SELECT
            EXTRACT(MONTH FROM u."created_at" AT TIME ZONE 'Europe/Moscow')::int AS month,
            COUNT(*)::bigint AS count
          FROM "users" u
          WHERE u."deleted_at" IS NULL
            AND u."status" <> ${client_1.UserStatus.DELETED}::"UserStatus"
            AND u."created_at" >= ${yearBounds.yearStart}
            AND u."created_at" < ${yearBounds.yearEnd}
          GROUP BY month
        `,
        ]);
        const firstYear = firstUser
            ? moscowCalendarBounds(firstUser.createdAt).year
            : currentYear;
        const availableYears = Array.from({ length: Math.max(currentYear - firstYear + 1, 0) }, (_, index) => firstYear + index);
        const countsByMonth = new Map();
        for (const row of monthRows) {
            countsByMonth.set(this.numberFromDb(row.month), this.numberFromDb(row.count));
        }
        const startMonth = year === firstYear && firstUser
            ? moscowCalendarBounds(firstUser.createdAt).month
            : 1;
        const endMonth = year === currentYear ? currentMonth : 12;
        const months = !firstUser || year < firstYear || year > currentYear || startMonth > endMonth
            ? []
            : Array.from({ length: endMonth - startMonth + 1 }, (_, index) => endMonth - index).map((month) => ({
                month,
                count: countsByMonth.get(month) ?? 0,
            }));
        return {
            source: 'timeweb',
            year,
            available_years: availableYears,
            total_users: totalUsers,
            todayCount,
            current_month_count: currentMonthCount,
            months,
        };
    }
    async listOnlineUsers() {
        const onlineCutoff = new Date(Date.now() - 2 * 60 * 1000);
        const users = await this.prisma.user.findMany({
            where: {
                deletedAt: null,
                status: {
                    not: client_1.UserStatus.DELETED,
                },
            },
            include: {
                presence: true,
            },
            take: 300,
        });
        const items = users
            .map((user) => {
            const lastSeenAt = user.presence?.lastSeen ?? null;
            const isOnline = user.presence?.isOnline === true &&
                lastSeenAt != null &&
                lastSeenAt >= onlineCutoff;
            return {
                id: user.id,
                display_name: user.displayName.trim() ||
                    user.name.trim() ||
                    user.phone?.trim() ||
                    'Пользователь',
                name: user.name.trim() || user.displayName.trim() || 'Пользователь',
                phone: user.phone?.trim() || null,
                avatar_url: (0, serializers_1.normalizeStoredMediaUrl)(user.avatarUrl, {
                    category: 'avatars',
                }),
                is_online: isOnline,
                last_seen_at: (0, serializers_1.toIsoString)(lastSeenAt),
            };
        })
            .filter((item) => item.is_online)
            .sort((left, right) => {
            const leftTime = Date.parse(left.last_seen_at ?? '1970-01-01T00:00:00.000Z');
            const rightTime = Date.parse(right.last_seen_at ?? '1970-01-01T00:00:00.000Z');
            return rightTime - leftTime;
        });
        return {
            source: 'timeweb',
            items,
        };
    }
    async listTodayVisits() {
        return this.appVisitsService.listToday();
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
    resolveBlockDuration(dto, now) {
        const duration = (dto.duration ?? '').trim().toLowerCase();
        if (duration === 'permanent' || duration === 'forever') {
            return {
                type: client_1.UserBlockType.PERMANENT,
                endsAt: null,
            };
        }
        if (duration === 'custom') {
            const endsAt = dto.ends_at ? new Date(dto.ends_at) : null;
            if (!endsAt || Number.isNaN(endsAt.getTime()) || endsAt <= now) {
                throw new common_1.BadRequestException('Укажите будущую дату окончания блокировки');
            }
            return {
                type: client_1.UserBlockType.TEMPORARY,
                endsAt,
            };
        }
        const daysByDuration = {
            one_day: 1,
            '1_day': 1,
            '1d': 1,
            seven_days: 7,
            '7_days': 7,
            '7d': 7,
            thirty_days: 30,
            '30_days': 30,
            '30d': 30,
        };
        const days = daysByDuration[duration];
        if (!days) {
            throw new common_1.BadRequestException('Неизвестный срок блокировки');
        }
        return {
            type: client_1.UserBlockType.TEMPORARY,
            endsAt: new Date(now.getTime() + days * 24 * 60 * 60 * 1000),
        };
    }
    serializeAdminBlock(block) {
        const user = block.user
            ? (0, serializers_1.serializeUser)(block.user, { includePrivate: true })
            : null;
        return {
            ...this.userBlocksService.serializeBlock(block),
            user,
            listing: block.listing ? (0, serializers_1.serializeListing)(block.listing) : null,
            admin: block.admin
                ? (0, serializers_1.serializeUser)(block.admin, { includePrivate: true })
                : null,
            support_tickets_count: block._count?.appeals ?? 0,
            previous_blocks_count: block.user?._count?.blocks ?? 0,
            violations_count: block.user?._count?.blocks ?? 0,
        };
    }
    async listBlocks(query = {}) {
        const status = typeof query === 'string' ? query : query.status;
        const limit = this.pageLimit(typeof query === 'string' ? undefined : query.limit, 100);
        const cursor = typeof query === 'string' ? undefined : query.cursor;
        const now = new Date();
        await this.prisma.userBlock.updateMany({
            where: {
                status: client_1.UserBlockStatus.ACTIVE,
                endsAt: {
                    not: null,
                    lte: now,
                },
            },
            data: {
                status: client_1.UserBlockStatus.EXPIRED,
            },
        });
        const normalized = (status ?? 'active').trim().toLowerCase();
        if (normalized === 'appeals') {
            const tickets = await this.prisma.supportTicket.findMany({
                where: {
                    isBlockAppeal: true,
                    ...this.dateIdCursorWhere('updatedAt', cursor),
                },
                include: {
                    userBlock: true,
                },
                orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }],
                take: limit + 1,
            });
            const page = this.pageInfo(tickets, limit, (ticket) => ({
                updatedAt: ticket.updatedAt.toISOString(),
                id: ticket.id,
            }));
            return {
                source: 'timeweb',
                items: page.items.map((ticket) => ({
                    id: ticket.id,
                    ticket_id: ticket.id,
                    user_id: ticket.userId,
                    block_id: ticket.userBlockId,
                    subject: ticket.subject,
                    status: ticket.status.toLowerCase(),
                    last_message: ticket.lastMessage,
                    unread_for_admin: ticket.unreadForAdmin,
                    created_at: ticket.createdAt.toISOString(),
                    updated_at: ticket.updatedAt.toISOString(),
                    block: this.userBlocksService.serializeBlock(ticket.userBlock),
                })),
                nextCursor: page.nextCursor,
                hasMore: page.hasMore,
                limit,
            };
        }
        const where = normalized === 'history'
            ? {}
            : normalized === 'temporary'
                ? { type: client_1.UserBlockType.TEMPORARY, status: client_1.UserBlockStatus.ACTIVE }
                : normalized === 'permanent'
                    ? { type: client_1.UserBlockType.PERMANENT, status: client_1.UserBlockStatus.ACTIVE }
                    : normalized === 'finished' || normalized === 'completed'
                        ? { status: { in: [client_1.UserBlockStatus.EXPIRED, client_1.UserBlockStatus.LIFTED] } }
                        : { status: client_1.UserBlockStatus.ACTIVE };
        const blocks = await this.prisma.userBlock.findMany({
            where: {
                ...where,
                ...this.dateIdCursorWhere('startsAt', cursor),
            },
            include: {
                user: {
                    include: {
                        adminProfile: true,
                        _count: {
                            select: {
                                blocks: true,
                            },
                        },
                    },
                },
                listing: {
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
                },
                admin: {
                    include: {
                        adminProfile: true,
                    },
                },
                _count: {
                    select: {
                        appeals: true,
                    },
                },
            },
            orderBy: [{ startsAt: 'desc' }, { id: 'desc' }],
            take: limit + 1,
        });
        const page = this.pageInfo(blocks, limit, (block) => ({
            startsAt: block.startsAt.toISOString(),
            id: block.id,
        }));
        return {
            source: 'timeweb',
            items: page.items.map((block) => this.serializeAdminBlock(block)),
            nextCursor: page.nextCursor,
            hasMore: page.hasMore,
            limit,
        };
    }
    async blockUser(userId, authUser, dto) {
        if (userId === authUser.userId) {
            throw new common_1.BadRequestException('Нельзя заблокировать текущий аккаунт администратора');
        }
        const reason = dto.reason?.trim() ?? '';
        if (!reason) {
            throw new common_1.BadRequestException('Причина блокировки обязательна');
        }
        const now = new Date();
        const duration = this.resolveBlockDuration(dto, now);
        const listingId = dto.listing_id?.trim() || undefined;
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            select: { id: true, phone: true, deletedAt: true, status: true },
        });
        if (!user || user.deletedAt || user.status === client_1.UserStatus.DELETED) {
            throw new common_1.NotFoundException('Пользователь не найден');
        }
        const existing = await this.userBlocksService.getActiveBlock(userId);
        if (existing) {
            throw new common_1.BadRequestException('У пользователя уже есть активная блокировка');
        }
        const block = await this.prisma.$transaction(async (tx) => {
            const created = await tx.userBlock.create({
                data: {
                    userId,
                    listingId,
                    adminId: authUser.userId,
                    type: duration.type,
                    status: client_1.UserBlockStatus.ACTIVE,
                    reason,
                    internalNote: dto.internal_note?.trim() || null,
                    startsAt: now,
                    endsAt: duration.endsAt,
                },
            });
            if (listingId) {
                await tx.listing.updateMany({
                    where: { id: listingId, ownerId: userId },
                    data: {
                        status: client_1.ListingStatus.REJECTED,
                        rejectionReason: reason,
                        moderationNote: dto.internal_note?.trim() || reason,
                        moderatedBy: authUser.userId,
                        moderatedAt: now,
                        publishedAt: null,
                        archivedAt: null,
                        deletedAt: null,
                    },
                });
            }
            await tx.listing.updateMany({
                where: {
                    ownerId: userId,
                    status: client_1.ListingStatus.APPROVED,
                },
                data: {
                    status: client_1.ListingStatus.ARCHIVED,
                    archivedAt: now,
                    publishedAt: null,
                    moderationNote: 'Скрыто из ленты на время блокировки пользователя.',
                },
            });
            await tx.user.update({
                where: { id: userId },
                data: {
                    status: client_1.UserStatus.BLOCKED,
                    blockedAt: now,
                    blockReason: reason,
                },
            });
            if (dto.ban_phone_identity === true && user.phone?.trim()) {
                await tx.blockedIdentity.create({
                    data: {
                        normalizedPhone: user.phone.trim(),
                        userBlockId: created.id,
                        bannedUntil: duration.endsAt,
                        permanent: duration.type === client_1.UserBlockType.PERMANENT,
                        reason,
                    },
                });
            }
            await tx.auditLog.create({
                data: {
                    actorUserId: authUser.userId,
                    actorRole: 'admin',
                    action: 'user.block',
                    entityType: 'user',
                    entityId: userId,
                    newData: {
                        blockId: created.id,
                        listingId: listingId ?? null,
                        duration: dto.duration,
                        endsAt: duration.endsAt?.toISOString() ?? null,
                    },
                },
            });
            return created;
        });
        await this.notificationsService.createSystemNotification({
            userId,
            title: 'Аккаунт заблокирован',
            body: reason,
            type: client_1.NotificationType.GENERIC,
            payload: {
                actionType: 'account_blocked',
                blockId: block.id,
                endsAt: duration.endsAt?.toISOString() ?? null,
                permanent: duration.type === client_1.UserBlockType.PERMANENT,
            },
        });
        return {
            source: 'timeweb',
            block: this.userBlocksService.serializeBlock(block),
        };
    }
    async unblockUserBlock(blockId, authUser, dto) {
        const block = await this.prisma.userBlock.findUnique({ where: { id: blockId } });
        if (!block) {
            throw new common_1.NotFoundException('Блокировка не найдена');
        }
        const now = new Date();
        const reason = dto?.reason?.trim() || 'Разблокировано администратором';
        const updated = await this.prisma.$transaction(async (tx) => {
            const lifted = await tx.userBlock.update({
                where: { id: blockId },
                data: {
                    status: client_1.UserBlockStatus.LIFTED,
                    liftedAt: now,
                    liftedByAdminId: authUser.userId,
                    liftReason: reason,
                },
            });
            await tx.blockedIdentity.updateMany({
                where: {
                    userBlockId: blockId,
                    liftedAt: null,
                },
                data: {
                    liftedAt: now,
                    liftedByAdminId: authUser.userId,
                },
            });
            const activeOther = await tx.userBlock.count({
                where: {
                    userId: block.userId,
                    id: { not: blockId },
                    status: client_1.UserBlockStatus.ACTIVE,
                    OR: [{ endsAt: null }, { endsAt: { gt: now } }],
                },
            });
            if (activeOther === 0) {
                await tx.user.update({
                    where: { id: block.userId },
                    data: {
                        status: client_1.UserStatus.ACTIVE,
                        blockedAt: null,
                        blockReason: null,
                    },
                });
            }
            await tx.auditLog.create({
                data: {
                    actorUserId: authUser.userId,
                    actorRole: 'admin',
                    action: 'user.unblock',
                    entityType: 'user',
                    entityId: block.userId,
                    newData: { blockId, reason },
                },
            });
            return lifted;
        });
        return {
            source: 'timeweb',
            block: this.userBlocksService.serializeBlock(updated),
        };
    }
    async updateUserBlock(blockId, authUser, dto) {
        const block = await this.prisma.userBlock.findUnique({ where: { id: blockId } });
        if (!block) {
            throw new common_1.NotFoundException('Блокировка не найдена');
        }
        if (block.status !== client_1.UserBlockStatus.ACTIVE) {
            throw new common_1.BadRequestException('Можно изменить только активную блокировку');
        }
        const now = new Date();
        const permanentRequested = dto.permanent === true;
        const temporaryRequested = dto.permanent === false || dto.ends_at != null;
        let nextType = block.type;
        let nextEndsAt = block.endsAt;
        if (permanentRequested) {
            nextType = client_1.UserBlockType.PERMANENT;
            nextEndsAt = null;
        }
        else if (temporaryRequested) {
            const endsAt = dto.ends_at ? new Date(dto.ends_at) : block.endsAt;
            if (!endsAt || Number.isNaN(endsAt.getTime()) || endsAt <= now) {
                throw new common_1.BadRequestException('Укажите будущую дату окончания блокировки');
            }
            nextType = client_1.UserBlockType.TEMPORARY;
            nextEndsAt = endsAt;
        }
        const changeReason = dto.reason?.trim() || 'Изменение срока блокировки';
        const internalNote = dto.internal_note === undefined
            ? block.internalNote
            : dto.internal_note.trim() || null;
        const updated = await this.prisma.$transaction(async (tx) => {
            const saved = await tx.userBlock.update({
                where: { id: blockId },
                data: {
                    type: nextType,
                    endsAt: nextEndsAt,
                    internalNote,
                },
            });
            await tx.blockedIdentity.updateMany({
                where: {
                    userBlockId: blockId,
                    liftedAt: null,
                },
                data: {
                    permanent: nextType === client_1.UserBlockType.PERMANENT,
                    bannedUntil: nextType === client_1.UserBlockType.PERMANENT ? null : nextEndsAt,
                },
            });
            await tx.user.update({
                where: { id: block.userId },
                data: {
                    status: client_1.UserStatus.BLOCKED,
                    blockedAt: block.startsAt,
                    blockReason: block.reason,
                },
            });
            await tx.auditLog.create({
                data: {
                    actorUserId: authUser.userId,
                    actorRole: 'admin',
                    action: 'user.block.update',
                    entityType: 'user',
                    entityId: block.userId,
                    newData: {
                        blockId,
                        reason: changeReason,
                        previousEndsAt: block.endsAt?.toISOString() ?? null,
                        nextEndsAt: nextEndsAt?.toISOString() ?? null,
                        previousType: block.type,
                        nextType,
                    },
                },
            });
            return saved;
        });
        return {
            source: 'timeweb',
            block: this.userBlocksService.serializeBlock(updated),
        };
    }
    async deleteUser(id, authUser) {
        if (id === authUser.userId) {
            return {
                source: 'timeweb',
                deleted: false,
                message: 'Нельзя удалить текущий аккаунт администратора',
            };
        }
        const user = await this.prisma.user.findUnique({
            where: { id },
            include: {
                adminProfile: true,
            },
        });
        if (!user) {
            throw new common_1.NotFoundException('Пользователь не найден');
        }
        if (protectedAdminPhones.has((user.phone ?? '').trim())) {
            return {
                source: 'timeweb',
                deleted: false,
                message: 'Этот администратор защищён от удаления',
            };
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
                    message: 'Нельзя удалить последнего администратора',
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
    async getModerationQueue(query = {}) {
        if (typeof query === 'string') {
            return this.listListings(query);
        }
        return this.listListings({ ...query, status: query.status ?? 'pending' });
    }
    async listListings(query = {}) {
        const status = typeof query === 'string' ? query : query.status;
        const limit = this.pageLimit(typeof query === 'string' ? undefined : query.limit, 100);
        const cursor = typeof query === 'string' ? undefined : query.cursor;
        const normalizedStatus = (status ?? '').trim().toLowerCase();
        const isPending = normalizedStatus === 'pending' || normalizedStatus.length === 0;
        const where = {
            deletedAt: null,
            ...(isPending ? { archivedAt: null } : {}),
            ...this.dateIdCursorWhere('createdAt', cursor),
            ...(normalizedStatus == 'all' || normalizedStatus.length === 0
                ? {}
                : { status: (0, serializers_1.listingStatusFromInput)(normalizedStatus) }),
            ...(isPending ? (0, listing_publication_1.listingPublicationReadyWhere)() : {}),
        };
        const [items, total, pendingModeration] = await Promise.all([
            this.prisma.listing.findMany({
                where,
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
                    moderationRevisions: {
                        where: {
                            resolvedAt: null,
                        },
                        orderBy: {
                            createdAt: 'asc',
                        },
                        take: 1,
                    },
                },
                orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
                take: limit + 1,
            }),
            this.prisma.listing.count({ where }),
            this.prisma.listing.count({
                where: {
                    deletedAt: null,
                    archivedAt: null,
                    status: client_1.ListingStatus.PENDING,
                    ...(0, listing_publication_1.listingPublicationReadyWhere)(),
                },
            }),
        ]);
        const page = this.pageInfo(items, limit, (listing) => ({
            createdAt: listing.createdAt.toISOString(),
            id: listing.id,
        }));
        return {
            source: 'timeweb',
            items: page.items
                .filter((listing) => !isPending || (0, listing_publication_1.isListingReadyForPublication)(listing))
                .map((listing) => this.serializeAdminListing(listing)),
            total,
            pendingModeration,
            pending_moderation: pendingModeration,
            nextCursor: page.nextCursor,
            hasMore: page.hasMore,
            limit,
            statuses: [
                'pending',
                'approved',
                'rejected',
                'sold',
                'deleted',
                'archived',
            ],
        };
    }
    serializeAdminListing(listing) {
        const serialized = (0, serializers_1.serializeListing)(listing);
        const revision = listing.moderationRevisions?.[0];
        const diff = revision ? this.buildModerationDiff(serialized, revision.snapshot) : null;
        return diff && diff.changed.length > 0
            ? {
                ...serialized,
                moderation_diff: diff,
            }
            : serialized;
    }
    buildModerationDiff(current, snapshot) {
        if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot)) {
            return null;
        }
        const before = snapshot;
        const fields = moderationDiffFields
            .map((field) => {
            const previous = this.normalizeModerationValue(before[field]);
            const next = this.normalizeModerationValue(current[field]);
            if (this.stableJson(previous) === this.stableJson(next)) {
                return null;
            }
            return {
                field,
                label: this.moderationFieldLabel(field),
                before: before[field] ?? null,
                after: current[field] ?? null,
            };
        })
            .filter((item) => item != null);
        const photoDiff = this.buildPhotoModerationDiff(before['photos'], current['photo_items']);
        return {
            changed: [
                ...fields,
                ...(photoDiff.changed ? [{
                        field: 'photos',
                        label: 'Фотографии',
                        before: photoDiff.before,
                        after: photoDiff.after,
                        added: photoDiff.added,
                        removed: photoDiff.removed,
                    }] : []),
            ],
        };
    }
    buildPhotoModerationDiff(beforeRaw, afterRaw) {
        const before = this.normalizePhotoSnapshot(beforeRaw);
        const after = this.normalizePhotoSnapshot(afterRaw);
        const beforeKeys = new Set(before.map((photo) => photo.key));
        const afterKeys = new Set(after.map((photo) => photo.key));
        const added = after.filter((photo) => !beforeKeys.has(photo.key));
        const removed = before.filter((photo) => !afterKeys.has(photo.key));
        const orderChanged = before.length === after.length &&
            before.some((photo, index) => photo.key !== after[index]?.key);
        return {
            changed: added.length > 0 || removed.length > 0 || orderChanged,
            before,
            after,
            added,
            removed,
        };
    }
    normalizePhotoSnapshot(value) {
        if (!Array.isArray(value))
            return [];
        return value
            .map((item, index) => {
            if (!item || typeof item !== 'object')
                return null;
            const row = item;
            const id = this.normalizeText(row['id']);
            const storageKey = this.normalizeText(row['storage_key']) || this.normalizeText(row['storageKey']);
            const url = this.normalizeText(row['url']);
            const key = id || storageKey || url;
            if (!key)
                return null;
            return {
                id,
                storage_key: storageKey,
                url,
                sort_order: Number(row['sort_order'] ?? row['sortOrder'] ?? index),
                key,
            };
        })
            .filter((item) => item != null)
            .sort((a, b) => a.sort_order - b.sort_order || a.key.localeCompare(b.key));
    }
    normalizeModerationValue(value) {
        if (value == null)
            return null;
        if (typeof value === 'string') {
            const trimmed = value.trim();
            return trimmed.length === 0 ? null : trimmed;
        }
        if (typeof value === 'bigint')
            return value.toString();
        if (typeof value === 'number')
            return Number.isFinite(value) ? value : null;
        if (typeof value === 'boolean')
            return value;
        if (Array.isArray(value)) {
            return value
                .map((item) => this.normalizeModerationValue(item))
                .filter((item) => item != null);
        }
        if (typeof value === 'object') {
            const entries = Object.entries(value)
                .map(([key, raw]) => [key, this.normalizeModerationValue(raw)])
                .filter(([, normalized]) => normalized != null)
                .sort(([left], [right]) => left.localeCompare(right));
            return Object.fromEntries(entries);
        }
        return String(value);
    }
    stableJson(value) {
        return JSON.stringify(value);
    }
    normalizeText(value) {
        return typeof value === 'string' ? value.trim() : '';
    }
    moderationFieldLabel(field) {
        const labels = {
            title: 'Название',
            description: 'Описание',
            price: 'Цена',
            city: 'Город',
            category: 'Категория',
            subcategory: 'Подкатегория',
            address: 'Адрес',
            phone_hidden: 'Телефон скрыт',
            delivery: 'Доставка',
            car: 'Характеристики',
            deal_type: 'Тип сделки',
            real_estate_type: 'Вид товара',
            clothes_type: 'Тип одежды',
            clothes_size: 'Размер одежды',
            oem_part_number: 'Номер детали (OEM)',
        };
        return labels[field] ?? field;
    }
    priceReductionDataOnApproval(listing, now) {
        const revision = listing.moderationRevisions?.[0];
        if (!revision || typeof revision.snapshot !== 'object' || Array.isArray(revision.snapshot)) {
            return {};
        }
        const snapshot = revision.snapshot;
        if (!Object.prototype.hasOwnProperty.call(snapshot, 'price')) {
            return {};
        }
        const previous = this.parseModerationPrice(snapshot['price']);
        const next = typeof listing.price === 'bigint'
            ? listing.price
            : BigInt(Math.trunc(Number(listing.price) || 0));
        if (previous == null || previous === next) {
            return {};
        }
        if (previous > next) {
            return {
                previousPrice: previous,
                priceReducedAt: now,
            };
        }
        return {
            previousPrice: null,
            priceReducedAt: null,
        };
    }
    parseModerationPrice(value) {
        if (typeof value === 'bigint')
            return value;
        if (typeof value === 'number' && Number.isFinite(value)) {
            return BigInt(Math.trunc(value));
        }
        if (typeof value === 'string') {
            const normalized = value.trim();
            if (/^\d+$/.test(normalized)) {
                return BigInt(normalized);
            }
        }
        return null;
    }
    async resolveModerationRevisions(listingId, resolvedAt) {
        const revisions = this.prisma.listingModerationRevision;
        if (!revisions) {
            return;
        }
        await revisions.updateMany({
            where: {
                listingId,
                resolvedAt: null,
            },
            data: {
                resolvedAt,
            },
        });
    }
    async listPromotions(query) {
        await this.expirePromotionsByTime();
        const limit = this.pageLimit(query.limit, 50);
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
                ...this.dateIdCursorWhere('createdAt', query.cursor),
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
            orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
            take: limit + 1,
        });
        const page = this.pageInfo(items, limit, (promotion) => ({
            createdAt: promotion.createdAt.toISOString(),
            id: promotion.id,
        }));
        const now = Date.now();
        return {
            source: 'timeweb',
            items: page.items.map((promotion) => ({
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
            nextCursor: page.nextCursor,
            hasMore: page.hasMore,
            limit,
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
    async listWallets(query = {}) {
        const limit = this.pageLimit(query.limit, 100);
        const wallets = await this.prisma.wallet.findMany({
            where: {
                ...this.dateIdCursorWhere('updatedAt', query.cursor),
            },
            include: {
                user: {
                    include: {
                        adminProfile: true,
                    },
                },
            },
            orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }],
            take: limit + 1,
        });
        const page = this.pageInfo(wallets, limit, (wallet) => ({
            updatedAt: wallet.updatedAt.toISOString(),
            id: wallet.id,
        }));
        return {
            source: 'timeweb',
            items: page.items.map((wallet) => ({
                userId: wallet.userId,
                userName: wallet.user.displayName || wallet.user.name,
                userPhone: wallet.user.phone,
                bonusBalance: wallet.bonusBalance,
                lastBonusAccrualAt: (0, serializers_1.toIsoString)(wallet.lastBonusAccrualAt),
                createdAt: wallet.createdAt.toISOString(),
            })),
            nextCursor: page.nextCursor,
            hasMore: page.hasMore,
            limit,
        };
    }
    async listWalletTransactions(query) {
        const limit = this.pageLimit(query.limit, 50);
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
                ...this.dateIdCursorWhere('createdAt', query.cursor),
            },
            include: {
                user: {
                    include: {
                        adminProfile: true,
                    },
                },
            },
            orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
            take: limit + 1,
        });
        const page = this.pageInfo(items, limit, (item) => ({
            createdAt: item.createdAt.toISOString(),
            id: item.id,
        }));
        return {
            source: 'timeweb',
            items: page.items.map((item) => ({
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
            nextCursor: page.nextCursor,
            hasMore: page.hasMore,
            limit,
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
    async getPointsPurchasesSummary(query) {
        const { fromDate, toDate } = this.resolvePointsPurchasesRange(query);
        const search = (query.search ?? '').trim();
        const filters = this.buildPointsPurchaseFilters({ fromDate, toDate, search });
        const whereSql = client_1.Prisma.join(filters, ' AND ');
        const rows = await this.prisma.$queryRaw `
      SELECT
        COALESCE(SUM(p."amount_rub"), 0)::text AS total_amount_rub,
        COALESCE(SUM(p."points_amount"), 0)::bigint AS total_points,
        COUNT(DISTINCT p."id")::bigint AS purchases_count,
        COUNT(DISTINCT p."user_id")::bigint AS unique_buyers_count
      FROM "payments" p
      JOIN "users" u ON u."id" = p."user_id"
      WHERE ${whereSql}
    `;
        const row = rows[0] ?? {
            total_amount_rub: 0,
            total_points: 0,
            purchases_count: 0,
            unique_buyers_count: 0,
        };
        return {
            source: 'timeweb',
            from: fromDate.toISOString(),
            to: toDate.toISOString(),
            totalAmountRub: this.numberFromDb(row.total_amount_rub),
            totalPoints: this.numberFromDb(row.total_points),
            purchasesCount: this.numberFromDb(row.purchases_count),
            uniqueBuyersCount: this.numberFromDb(row.unique_buyers_count),
        };
    }
    async listPointsPurchases(query) {
        const { fromDate, toDate } = this.resolvePointsPurchasesRange(query);
        const limit = Math.min(Math.max(query.limit ?? 30, 1), 100);
        const search = (query.search ?? '').trim();
        const cursor = this.decodePointsPurchaseCursor(query.cursor);
        const filters = this.buildPointsPurchaseFilters({ fromDate, toDate, search });
        if (cursor) {
            filters.push(client_1.Prisma.sql `(p."created_at", p."id") < (${cursor.createdAt}, ${cursor.id}::uuid)`);
        }
        const whereSql = client_1.Prisma.join(filters, ' AND ');
        const rows = await this.prisma.$queryRaw `
      SELECT
        p."id"::text AS payment_id,
        p."user_id"::text AS user_id,
        u."display_name" AS display_name,
        NULLIF(u."name", '') AS username,
        u."phone" AS phone,
        p."amount_rub"::text AS amount_rub,
        p."points_amount" AS points,
        p."status"::text AS status,
        p."created_at" AS created_at
      FROM "payments" p
      JOIN "users" u ON u."id" = p."user_id"
      WHERE ${whereSql}
      ORDER BY p."created_at" DESC, p."id" DESC
      LIMIT ${limit + 1}
    `;
        const pageRows = rows.slice(0, limit);
        const next = rows.length > limit ? pageRows[pageRows.length - 1] : null;
        return {
            source: 'timeweb',
            from: fromDate.toISOString(),
            to: toDate.toISOString(),
            limit,
            nextCursor: next
                ? this.encodePointsPurchaseCursor({
                    createdAt: next.created_at,
                    id: next.payment_id,
                })
                : null,
            items: pageRows.map((row) => ({
                paymentId: row.payment_id,
                userId: row.user_id,
                displayName: row.display_name?.trim() ||
                    row.username?.trim() ||
                    row.phone?.trim() ||
                    'Пользователь',
                username: row.username?.trim() || null,
                phone: row.phone?.trim() ? (0, phone_1.maskPhone)(row.phone) : null,
                amountRub: this.numberFromDb(row.amount_rub),
                points: this.numberFromDb(row.points),
                status: 'Оплачено',
                createdAt: row.created_at.toISOString(),
            })),
        };
    }
    async getReferralSummary(query) {
        const range = this.resolveAnalyticsRange(query);
        const [referrals, purchased, spent, daily] = await Promise.all([
            this.prisma.referral.findMany({
                where: {
                    createdAt: range,
                },
            }),
            this.prisma.walletTransaction.aggregate({
                _sum: { amount: true },
                where: {
                    createdAt: range,
                    reason: client_1.WalletTransactionReason.POINTS_PURCHASE,
                    type: client_1.WalletTransactionType.ACCRUAL,
                },
            }),
            this.prisma.walletTransaction.aggregate({
                _sum: { amount: true },
                where: {
                    createdAt: range,
                    type: client_1.WalletTransactionType.SPEND,
                },
            }),
            this.prisma.walletTransaction.aggregate({
                _sum: { amount: true },
                where: {
                    createdAt: range,
                    reason: client_1.WalletTransactionReason.DAILY_LOGIN_BONUS,
                    type: client_1.WalletTransactionType.ACCRUAL,
                },
            }),
        ]);
        const rewarded = referrals.filter((item) => item.rewardStatus === client_1.ReferralRewardStatus.REWARDED);
        return {
            source: 'timeweb',
            period: (query.period ?? 'month').trim().toLowerCase() || 'month',
            from: this.dateFilterValueToIso(range.gte),
            to: this.dateFilterValueToIso(range.lte),
            newRegistrationsByInvite: referrals.filter((item) => item.registeredAt)
                .length,
            rewardedReferralBonuses: rewarded.length,
            referralPointsAwarded: rewarded.reduce((sum, item) => sum + item.rewardAmount, 0),
            unfinishedInvites: referrals.filter((item) => !item.registeredAt).length,
            rewardFailures: referrals.filter((item) => item.rewardStatus === client_1.ReferralRewardStatus.NOT_REWARDED ||
                item.rewardStatus === client_1.ReferralRewardStatus.FAILED_RETRYABLE).length,
            pointsPurchased: purchased._sum.amount ?? 0,
            pointsSpent: spent._sum.amount ?? 0,
            dailyBonusesAwarded: daily._sum.amount ?? 0,
        };
    }
    async listReferrals(query) {
        const range = this.resolveAnalyticsRange(query);
        const search = query.search?.trim();
        const userId = query.userId?.trim();
        if (search || userId) {
            return this.listReferralUsers(query, range);
        }
        const limit = this.pageLimit(query.limit, 50);
        const referrals = await this.prisma.referral.findMany({
            where: {
                createdAt: range,
                ...this.dateIdCursorWhere('createdAt', query.cursor),
            },
            include: {
                inviter: {
                    include: {
                        adminProfile: true,
                    },
                },
                invited: {
                    include: {
                        adminProfile: true,
                    },
                },
            },
            orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
            take: limit + 1,
        });
        const page = this.pageInfo(referrals, limit, (referral) => ({
            createdAt: referral.createdAt.toISOString(),
            id: referral.id,
        }));
        return {
            source: 'timeweb',
            period: (query.period ?? 'month').trim().toLowerCase() || 'month',
            from: this.dateFilterValueToIso(range.gte),
            to: this.dateFilterValueToIso(range.lte),
            items: this.buildReferralUserItemsFromReferrals(page.items),
            nextCursor: page.nextCursor,
            hasMore: page.hasMore,
            limit,
        };
    }
    async getUserReferrals(userId, query) {
        const normalizedUserId = userId.trim();
        if (!this.isUuid(normalizedUserId)) {
            throw new common_1.NotFoundException('User not found');
        }
        const user = await this.prisma.user.findFirst({
            where: {
                id: normalizedUserId,
                deletedAt: null,
                status: {
                    not: client_1.UserStatus.DELETED,
                },
            },
            include: {
                adminProfile: true,
            },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        const range = this.resolveAnalyticsRange(query);
        return {
            source: 'timeweb',
            period: (query.period ?? 'month').trim().toLowerCase() || 'month',
            from: this.dateFilterValueToIso(range.gte),
            to: this.dateFilterValueToIso(range.lte),
            item: await this.buildReferralUserItem(user, range),
        };
    }
    async listReferralUsers(query, range) {
        const search = query.search?.trim();
        const userId = query.userId?.trim();
        const searchLooksLikeUuid = search ? this.isUuid(search) : false;
        const decodedReferralUserId = search ? (0, referral_code_1.resolveReferralUserId)(search) : null;
        const phoneDigits = (search ?? '').replace(/\D/g, '');
        const cursorWhere = this.dateIdCursorWhere('createdAt', query.cursor);
        const userSearchOr = [
            ...(userId && this.isUuid(userId) ? [{ id: userId }] : []),
            ...(searchLooksLikeUuid ? [{ id: search }] : []),
            ...(decodedReferralUserId ? [{ id: decodedReferralUserId }] : []),
            ...(search
                ? [
                    { displayName: { contains: search, mode: 'insensitive' } },
                    { name: { contains: search, mode: 'insensitive' } },
                    { phone: { contains: search } },
                ]
                : []),
            ...(phoneDigits.length >= 4 ? [{ phone: { contains: phoneDigits } }] : []),
        ];
        const limit = this.pageLimit(query.limit, 25);
        const matchingUsers = await this.prisma.user.findMany({
            where: {
                deletedAt: null,
                status: {
                    not: client_1.UserStatus.DELETED,
                },
                ...(Object.keys(cursorWhere).length > 0 ? { AND: [cursorWhere] } : {}),
                ...(userSearchOr.length > 0
                    ? { OR: userSearchOr }
                    : { id: '00000000-0000-0000-0000-000000000000' }),
            },
            include: {
                adminProfile: true,
            },
            orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
            take: limit + 1,
        });
        const page = this.pageInfo(matchingUsers, limit, (user) => ({
            createdAt: user.createdAt.toISOString(),
            id: user.id,
        }));
        return {
            source: 'timeweb',
            period: (query.period ?? 'month').trim().toLowerCase() || 'month',
            from: this.dateFilterValueToIso(range.gte),
            to: this.dateFilterValueToIso(range.lte),
            items: await Promise.all(page.items.map((user) => this.buildReferralUserItem(user, range))),
            nextCursor: page.nextCursor,
            hasMore: page.hasMore,
            limit,
        };
    }
    buildReferralUserItemsFromReferrals(referrals) {
        const users = new Map();
        for (const referral of referrals) {
            const key = referral.inviterUserId;
            const existing = users.get(key);
            const inviter = this.serializeReferralUser(referral.inviter);
            const item = existing ?? {
                inviter,
                referralCode: (0, referral_code_1.buildReferralCode)(referral.inviterUserId),
                inviteLink: this.buildInviteLink((0, referral_code_1.buildReferralCode)(referral.inviterUserId)),
                openedCount: 0,
                registeredCount: 0,
                rewardedCount: 0,
                referralPoints: 0,
                unfinishedCount: 0,
                invitations: [],
            };
            if (referral.openedAt || referral.appOpenedAt)
                item.openedCount += 1;
            if (referral.registeredAt || referral.invitedUserId)
                item.registeredCount += 1;
            if (referral.rewardStatus === client_1.ReferralRewardStatus.REWARDED) {
                item.rewardedCount += 1;
                item.referralPoints += referral.rewardAmount;
            }
            if (!referral.registeredAt && !referral.invitedUserId) {
                item.unfinishedCount += 1;
            }
            item.invitations.push(this.serializeReferral(referral));
            users.set(key, item);
        }
        return Array.from(users.values());
    }
    async buildReferralUserItem(user, range) {
        const referrals = await this.prisma.referral.findMany({
            where: {
                inviterUserId: user.id,
                createdAt: range,
            },
            include: {
                inviter: {
                    include: {
                        adminProfile: true,
                    },
                },
                invited: {
                    include: {
                        adminProfile: true,
                    },
                },
            },
            orderBy: {
                createdAt: 'desc',
            },
            take: 500,
        });
        const referralCode = (0, referral_code_1.buildReferralCode)(user.id);
        const item = {
            inviter: this.serializeReferralUser(user),
            referralCode,
            inviteLink: this.buildInviteLink(referralCode),
            openedCount: 0,
            registeredCount: 0,
            rewardedCount: 0,
            referralPoints: 0,
            unfinishedCount: 0,
            rejectedCount: 0,
            invitations: [],
        };
        for (const referral of referrals) {
            if (referral.openedAt || referral.appOpenedAt)
                item.openedCount += 1;
            if (referral.registeredAt || referral.invitedUserId)
                item.registeredCount += 1;
            if (referral.rewardStatus === client_1.ReferralRewardStatus.REWARDED) {
                item.rewardedCount += 1;
                item.referralPoints += referral.rewardAmount;
            }
            if (!referral.registeredAt && !referral.invitedUserId) {
                item.unfinishedCount += 1;
            }
            if (referral.rewardStatus === client_1.ReferralRewardStatus.NOT_REWARDED ||
                referral.rewardStatus === client_1.ReferralRewardStatus.FAILED_RETRYABLE) {
                item.rejectedCount += 1;
            }
            item.invitations.push(this.serializeReferral(referral));
        }
        return item;
    }
    async getReferralById(id) {
        const referral = await this.prisma.referral.findUnique({
            where: {
                id,
            },
            include: {
                inviter: {
                    include: {
                        adminProfile: true,
                    },
                },
                invited: {
                    include: {
                        adminProfile: true,
                    },
                },
            },
        });
        if (!referral) {
            throw new common_1.NotFoundException('Referral not found');
        }
        return {
            source: 'timeweb',
            item: this.serializeReferral(referral),
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
                moderationRevisions: {
                    where: {
                        resolvedAt: null,
                    },
                    orderBy: {
                        createdAt: 'asc',
                    },
                    take: 1,
                },
            },
        });
        if (!listing) {
            throw new common_1.NotFoundException('Listing not found');
        }
        if (listing.photos.length === 0) {
            throw new common_1.BadRequestException(listings_service_1.LISTING_PHOTO_REQUIRED);
        }
        if (!(0, listing_publication_1.isListingReadyForPublication)(listing)) {
            throw new common_1.BadRequestException(listing_publication_1.LISTING_PUBLICATION_NOT_READY);
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
                ...this.priceReductionDataOnApproval(listing, now),
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
        await this.resolveModerationRevisions(id, now);
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
        const now = new Date();
        const updated = await this.prisma.listing.update({
            where: { id },
            data: {
                status: client_1.ListingStatus.REJECTED,
                rejectionReason: params?.reason?.trim() || 'Rejected by moderator',
                moderationNote: params?.moderationNote?.trim() || null,
                moderatedBy: authUser.userId,
                moderatedAt: now,
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
        await this.resolveModerationRevisions(id, now);
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
    resolvePointsPurchasesRange(query) {
        const explicit = this.resolveRange({
            from: query.from,
            to: query.to,
        });
        const now = new Date();
        const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
        return {
            fromDate: explicit?.gte ?? monthStart,
            toDate: explicit?.lte ?? now,
        };
    }
    buildPointsPurchaseFilters({ fromDate, toDate, search, }) {
        const filters = [
            client_1.Prisma.sql `p."provider" = ${client_1.PaymentProvider.YOOKASSA}::"PaymentProvider"`,
            client_1.Prisma.sql `p."status" = ${client_1.PaymentStatus.SUCCEEDED}::"PaymentStatus"`,
            client_1.Prisma.sql `p."credited_at" IS NOT NULL`,
            client_1.Prisma.sql `p."created_at" >= ${fromDate}`,
            client_1.Prisma.sql `p."created_at" <= ${toDate}`,
            client_1.Prisma.sql `EXISTS (
        SELECT 1
        FROM "wallet_transactions" wt
        WHERE wt."user_id" = p."user_id"
          AND wt."type" = ${client_1.WalletTransactionType.ACCRUAL}::"WalletTransactionType"
          AND wt."reason" = ${client_1.WalletTransactionReason.POINTS_PURCHASE}::"WalletTransactionReason"
          AND wt."amount" = p."points_amount"
          AND wt."metadata"->>'paymentId' = p."id"::text
      )`,
        ];
        const normalizedSearch = search.trim();
        if (normalizedSearch.length > 0) {
            const like = `%${normalizedSearch}%`;
            const digits = normalizedSearch.replace(/\D/g, '');
            filters.push(client_1.Prisma.sql `(
        p."user_id"::text ILIKE ${like}
        OR u."display_name" ILIKE ${like}
        OR u."name" ILIKE ${like}
        OR u."phone" ILIKE ${like}
        ${digits ? client_1.Prisma.sql `OR regexp_replace(COALESCE(u."phone", ''), '\\D', '', 'g') ILIKE ${`%${digits}%`}` : client_1.Prisma.empty}
      )`);
        }
        return filters;
    }
    encodePointsPurchaseCursor(value) {
        return Buffer.from(JSON.stringify({
            createdAt: value.createdAt.toISOString(),
            id: value.id,
        }), 'utf8').toString('base64url');
    }
    decodePointsPurchaseCursor(cursor) {
        const raw = (cursor ?? '').trim();
        if (!raw)
            return null;
        try {
            const decoded = JSON.parse(Buffer.from(raw, 'base64url').toString('utf8'));
            const createdAt = new Date(String(decoded.createdAt ?? ''));
            const id = String(decoded.id ?? '').trim();
            if (Number.isNaN(createdAt.getTime()) || !this.isUuid(id)) {
                return null;
            }
            return { createdAt, id };
        }
        catch {
            return null;
        }
    }
    numberFromDb(value) {
        if (typeof value === 'bigint')
            return Number(value);
        if (typeof value === 'number')
            return value;
        const parsed = Number((value ?? '0').toString());
        return Number.isFinite(parsed) ? parsed : 0;
    }
    parseWalletReason(value) {
        const normalized = (value ?? '').trim().toUpperCase();
        if (!normalized) {
            return undefined;
        }
        return Object.values(client_1.WalletTransactionReason).find((item) => item === normalized);
    }
    dateFilterValueToIso(value) {
        return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
    }
    serializeReferral(referral) {
        return {
            id: referral.id,
            inviter: this.serializeReferralUser(referral.inviter),
            invited: referral.invited ? this.serializeReferralUser(referral.invited) : null,
            inviterUserId: referral.inviterUserId,
            invitedUserId: referral.invitedUserId,
            referralCode: referral.referralCode,
            inviteLink: this.buildInviteLink(referral.referralCode),
            openedAt: (0, serializers_1.toIsoString)(referral.openedAt),
            appOpenedAt: (0, serializers_1.toIsoString)(referral.appOpenedAt),
            signupStartedAt: (0, serializers_1.toIsoString)(referral.signupStartedAt),
            registeredAt: (0, serializers_1.toIsoString)(referral.registeredAt),
            registrationCompleted: Boolean(referral.registeredAt || referral.invitedUserId),
            isNewUser: referral.isNewUser,
            rewardStatus: referral.rewardStatus.toLowerCase(),
            rewardAmount: referral.rewardAmount,
            rewardedAt: (0, serializers_1.toIsoString)(referral.rewardedAt),
            bonusAwarded: referral.rewardStatus === client_1.ReferralRewardStatus.REWARDED,
            failureReason: referral.failureReason,
            failureText: this.referralFailureText(referral),
            walletTransactionId: referral.walletTransactionId,
            createdAt: referral.createdAt.toISOString(),
        };
    }
    serializeReferralUser(user) {
        const displayName = user.displayName?.trim() ||
            user.name?.trim() ||
            user.phone?.trim() ||
            'Пользователь';
        return {
            id: user.id,
            name: displayName,
            displayName: user.displayName?.trim() || displayName,
            username: user.displayName?.trim() || null,
            phone: this.safePhone(user.phone),
            avatarUrl: (0, serializers_1.normalizeStoredMediaUrl)(user.avatarUrl ?? user.photoUrl, {
                category: 'avatars',
            }),
            referralCode: (0, referral_code_1.buildReferralCode)(user.id),
            profilePath: `/admin/users/${user.id}`,
        };
    }
    buildInviteLink(referralCode) {
        return `https://attamarket.online/invite?ref=${encodeURIComponent(referralCode)}`;
    }
    safePhone(phone) {
        const digits = (phone ?? '').replace(/\D/g, '');
        if (digits.length < 4)
            return phone?.trim() || null;
        return `${digits.slice(0, 1)}***${digits.slice(-4)}`;
    }
    isUuid(value) {
        return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
    }
    referralFailureText(referral) {
        if (referral.rewardStatus === client_1.ReferralRewardStatus.REWARDED) {
            return null;
        }
        if (!referral.registeredAt && !referral.invitedUserId) {
            return 'Ссылка открыта, но регистрация не завершена';
        }
        switch (referral.failureReason) {
            case 'APP_OPENED_WITHOUT_REFERRAL_CODE':
                return 'После установки приложение открыто без реферального кода';
            case 'USER_ALREADY_REGISTERED':
                return 'Пользователь уже был зарегистрирован';
            case 'SELF_REFERRAL':
                return 'Самоприглашение';
            case 'BONUS_ALREADY_AWARDED_FOR_INVITED_USER':
                return 'Бонус уже начислялся за этого пользователя';
            case 'REWARD_ERROR_RETRYABLE':
                return 'Ошибка начисления — требуется проверка';
            case 'INVALID_REFERRAL_CODE':
                return 'Реферальный код не распознан';
            case 'INVITER_NOT_FOUND':
                return 'Аккаунт пригласившего не найден';
            default:
                return referral.failureReason ? 'Бонус не начислен' : null;
        }
    }
};
exports.AdminService = AdminService;
exports.AdminService = AdminService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        app_visits_service_1.AppVisitsService,
        notifications_service_1.NotificationsService,
        reviews_service_1.ReviewsService,
        storage_service_1.StorageService,
        user_blocks_service_1.UserBlocksService])
], AdminService);
//# sourceMappingURL=admin.service.js.map