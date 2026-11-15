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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
var ReportsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.ReportsService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const notifications_service_1 = require("../notifications/notifications.service");
const prisma_service_1 = require("../prisma/prisma.service");
const admin_dashboard_signal_1 = require("../../common/admin-dashboard-signal");
let ReportsService = ReportsService_1 = class ReportsService {
    constructor(prisma, notificationsService, adminDashboardSignal) {
        this.prisma = prisma;
        this.notificationsService = notificationsService;
        this.adminDashboardSignal = adminDashboardSignal;
    }
    pageLimit(value, fallback = 50) {
        const parsed = Number(value ?? fallback);
        if (!Number.isFinite(parsed))
            return fallback;
        return Math.min(Math.max(Math.trunc(parsed), 1), 100);
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
    serialize(report) {
        const listingPhotos = report.listing?.photos?.map((photo) => ({
            id: photo.id ?? null,
            url: photo.url ?? photo.publicUrl ?? null,
            publicUrl: photo.publicUrl ?? photo.url ?? null,
            storageKey: photo.storageKey ?? null,
            sortOrder: photo.sortOrder ?? null,
        })) ?? [];
        const targetType = report.listingId ? 'listing' : 'user';
        const listingPhotoUrl = listingPhotos[0]?.url ?? null;
        return {
            id: report.id,
            listing_id: report.listingId,
            listing_owner_id: report.listingOwnerId,
            reported_user_id: report.listingOwnerId,
            reporter_id: report.reporterId,
            reason: report.reason,
            comment: report.comment,
            status: report.status,
            decision: report.decision,
            admin_uid: report.adminUid,
            admin_comment: report.adminComment,
            admin_note: report.adminNote ?? null,
            handled_by: report.handledBy ?? null,
            handled_by_name: report.handledByUser?.displayName?.trim() ||
                report.handledByUser?.name?.trim() ||
                null,
            created_at: report.createdAt.toISOString(),
            handled_at: report.handledAt?.toISOString() ?? null,
            closed_at: report.closedAt?.toISOString() ?? null,
            target_type: targetType,
            listing_title: report.listing?.title ?? null,
            listing_photo_url: listingPhotoUrl,
            listing_photos: listingPhotos,
            listing_seller_id: report.listing?.ownerId ?? report.listingOwnerId,
            listing_seller_name: report.listing?.owner?.displayName?.trim() ||
                report.listing?.owner?.name?.trim() ||
                report.listingOwner?.displayName?.trim() ||
                report.listingOwner?.name?.trim() ||
                null,
            reporter_name: report.reporter?.displayName?.trim() ||
                report.reporter?.name?.trim() ||
                null,
            reporter_avatar_url: report.reporter?.avatarUrl?.trim() ||
                report.reporter?.photoUrl?.trim() ||
                null,
            reported_user_name: report.listingOwner?.displayName?.trim() ||
                report.listingOwner?.name?.trim() ||
                null,
            reported_user_avatar_url: report.listingOwner?.avatarUrl?.trim() ||
                report.listingOwner?.photoUrl?.trim() ||
                null,
        };
    }
    async listForAdmin(query = {}) {
        const limit = this.pageLimit(query.limit);
        const decoded = this.decodeAdminCursor(query.cursor);
        const rawCreatedAt = decoded?.createdAt;
        const cursorDate = rawCreatedAt ? new Date(rawCreatedAt) : null;
        const cursorId = decoded?.id;
        const oldestFirst = query.sort === 'oldest';
        const search = query.search?.trim() ?? '';
        const reason = query.reason?.trim() ?? '';
        const statusFilter = (() => {
            switch (query.status) {
                case 'open':
                    return ['open'];
                case 'in_progress':
                    return ['in_progress'];
                case 'completed':
                    return ['resolved', 'rejected'];
                case 'resolved':
                    return ['resolved'];
                case 'rejected':
                    return ['rejected'];
                default:
                    return null;
            }
        })();
        const commonWhere = {
            ...(reason
                ? { reason: { equals: reason, mode: client_1.Prisma.QueryMode.insensitive } }
                : {}),
            ...(query.dateFrom || query.dateTo
                ? {
                    createdAt: {
                        ...(query.dateFrom ? { gte: new Date(query.dateFrom) } : {}),
                        ...(query.dateTo ? { lte: new Date(query.dateTo) } : {}),
                    },
                }
                : {}),
            ...(search
                ? {
                    OR: [
                        { reason: { contains: search, mode: client_1.Prisma.QueryMode.insensitive } },
                        { comment: { contains: search, mode: client_1.Prisma.QueryMode.insensitive } },
                        { listing: { is: { title: { contains: search, mode: client_1.Prisma.QueryMode.insensitive } } } },
                        { reporter: { is: { displayName: { contains: search, mode: client_1.Prisma.QueryMode.insensitive } } } },
                        { reporter: { is: { name: { contains: search, mode: client_1.Prisma.QueryMode.insensitive } } } },
                        { listingOwner: { is: { displayName: { contains: search, mode: client_1.Prisma.QueryMode.insensitive } } } },
                        { listingOwner: { is: { name: { contains: search, mode: client_1.Prisma.QueryMode.insensitive } } } },
                    ],
                }
                : {}),
        };
        const baseWhere = {
            AND: [
                commonWhere,
                {
                    status: statusFilter
                        ? { in: statusFilter }
                        : { notIn: [...ReportsService_1.hiddenStatuses] },
                },
            ],
        };
        const cursorWhere = cursorDate && !Number.isNaN(cursorDate.getTime()) && cursorId
            ? {
                OR: oldestFirst
                    ? [
                        { createdAt: { gt: cursorDate } },
                        { createdAt: cursorDate, id: { gt: cursorId } },
                    ]
                    : [
                        { createdAt: { lt: cursorDate } },
                        { createdAt: cursorDate, id: { lt: cursorId } },
                    ],
            }
            : {};
        const [items, newCount, reviewCount, completedCount] = await Promise.all([
            this.prisma.report.findMany({
                where: {
                    AND: [baseWhere, cursorWhere],
                },
                include: {
                    listing: {
                        include: {
                            owner: true,
                            photos: {
                                orderBy: {
                                    sortOrder: 'asc',
                                },
                                take: 1,
                            },
                        },
                    },
                    listingOwner: true,
                    reporter: true,
                    handledByUser: true,
                },
                orderBy: [
                    { createdAt: oldestFirst ? 'asc' : 'desc' },
                    { id: oldestFirst ? 'asc' : 'desc' },
                ],
                take: limit + 1,
            }),
            this.prisma.report.count({
                where: { AND: [commonWhere, { status: 'open' }] },
            }),
            this.prisma.report.count({
                where: { AND: [commonWhere, { status: 'in_progress' }] },
            }),
            this.prisma.report.count({
                where: { AND: [commonWhere, { status: { in: ['resolved', 'rejected'] } }] },
            }),
        ]);
        const pageItems = items.slice(0, limit);
        const last = items.length > limit ? pageItems[pageItems.length - 1] : null;
        return {
            source: 'timeweb',
            items: pageItems.map((report) => this.serialize(report)),
            nextCursor: last
                ? this.encodeAdminCursor({
                    createdAt: last.createdAt.toISOString(),
                    id: last.id,
                })
                : null,
            hasMore: items.length > limit,
            limit,
            counts: {
                open: newCount,
                in_progress: reviewCount,
                completed: completedCount,
            },
        };
    }
    async create(authUser, body) {
        const listingId = body.listingId?.trim() || null;
        let reportedUserId = body.reportedUserId?.trim() || body.listingOwnerId?.trim() || null;
        if (listingId) {
            const listing = await this.prisma.listing.findUnique({
                where: {
                    id: listingId,
                },
                select: {
                    ownerId: true,
                },
            });
            if (!listing) {
                throw new common_1.BadRequestException('Объявление для жалобы не найдено');
            }
            reportedUserId = listing.ownerId;
        }
        if (!listingId && !reportedUserId) {
            throw new common_1.BadRequestException('Нужно указать объявление или пользователя для жалобы');
        }
        const report = await this.prisma.report.create({
            data: {
                listingId,
                listingOwnerId: reportedUserId,
                reporterId: authUser.userId,
                reason: body.reason?.trim() || 'Жалоба',
                comment: body.comment?.trim() || '',
                status: 'open',
            },
            include: {
                listing: {
                    include: {
                        owner: true,
                        photos: {
                            orderBy: {
                                sortOrder: 'asc',
                            },
                            take: 1,
                        },
                    },
                },
                listingOwner: true,
                reporter: true,
            },
        });
        const admins = await this.prisma.adminUser.findMany({
            select: {
                userId: true,
            },
        });
        const adminNotifications = await Promise.all(admins.map(({ userId }) => this.notificationsService.createSystemNotification({
            userId,
            title: 'Новая жалоба',
            body: report.reason.trim().length > 0
                ? `Поступила новая жалоба: ${report.reason.trim()}.`
                : 'Поступила новая жалоба.',
            type: client_1.NotificationType.GENERIC,
            payload: {
                actionType: 'admin_report_new',
                reportId: report.id,
            },
        })));
        this.adminDashboardSignal?.changed('reports');
        return {
            source: 'timeweb',
            item: this.serialize(report),
            admin_notifications: adminNotifications.map((item) => this.notificationsService.serializeNotification(item)),
        };
    }
    async startReview(reportId, authUser) {
        const exists = await this.prisma.report.findUnique({
            where: { id: reportId },
        });
        if (!exists)
            throw new common_1.NotFoundException('Report not found');
        if (ReportsService_1.hiddenStatuses.includes(exists.status)) {
            throw new common_1.BadRequestException('Скрытую жалобу нельзя взять на проверку');
        }
        if (exists.status === 'in_progress') {
            return { source: 'timeweb', item: this.serialize(exists) };
        }
        if (exists.status !== 'open') {
            throw new common_1.BadRequestException('Завершённую жалобу нужно сначала открыть повторно');
        }
        const report = await this.prisma.report.update({
            where: { id: reportId },
            data: {
                status: 'in_progress',
                decision: null,
                adminUid: authUser.userId,
                handledBy: authUser.userId,
                handledAt: new Date(),
                closedAt: null,
            },
        });
        this.adminDashboardSignal?.changed('reports');
        return { source: 'timeweb', item: this.serialize(report) };
    }
    async notifyReporterOfDecision(report) {
        const noViolation = report.decision === 'no_violation';
        try {
            await this.notificationsService.createSystemNotification({
                userId: report.reporterId,
                title: 'Ваша жалоба рассмотрена',
                body: noViolation
                    ? 'Мы проверили информацию. Нарушений правил не обнаружено.'
                    : 'Мы проверили информацию и приняли необходимые меры.',
                type: client_1.NotificationType.GENERIC,
                payload: {
                    actionType: 'report_update',
                    reportId: report.id,
                    status: 'completed',
                },
            });
        }
        catch {
            // Решение уже сохранено; временная ошибка уведомления не должна
            // возвращать жалобу в работу или провоцировать повторное решение.
        }
    }
    async resolve(reportId, authUser, comment, decision = 'resolved') {
        const exists = await this.prisma.report.findUnique({
            where: {
                id: reportId,
            },
        });
        if (!exists) {
            throw new common_1.NotFoundException('Report not found');
        }
        if (exists.status === 'resolved' && exists.decision === decision) {
            return { source: 'timeweb', item: this.serialize(exists) };
        }
        if (exists.status === 'resolved' || exists.status === 'rejected') {
            throw new common_1.BadRequestException('Для изменения решения сначала откройте жалобу повторно');
        }
        const report = await this.prisma.report.update({
            where: {
                id: reportId,
            },
            data: {
                status: 'resolved',
                decision,
                adminUid: authUser.userId,
                adminComment: comment?.trim() || null,
                handledBy: authUser.userId,
                handledAt: new Date(),
                closedAt: new Date(),
            },
        });
        this.adminDashboardSignal?.changed('reports');
        await this.notifyReporterOfDecision(report);
        return {
            source: 'timeweb',
            item: this.serialize(report),
        };
    }
    async reject(reportId, authUser, comment, decision = 'no_violation') {
        const exists = await this.prisma.report.findUnique({
            where: {
                id: reportId,
            },
        });
        if (!exists) {
            throw new common_1.NotFoundException('Report not found');
        }
        if (exists.status === 'rejected' && exists.decision === decision) {
            return { source: 'timeweb', item: this.serialize(exists) };
        }
        if (exists.status === 'resolved' || exists.status === 'rejected') {
            throw new common_1.BadRequestException('Для изменения решения сначала откройте жалобу повторно');
        }
        const report = await this.prisma.report.update({
            where: {
                id: reportId,
            },
            data: {
                status: 'rejected',
                decision,
                adminUid: authUser.userId,
                adminComment: comment?.trim() || null,
                handledBy: authUser.userId,
                handledAt: new Date(),
                closedAt: new Date(),
            },
        });
        this.adminDashboardSignal?.changed('reports');
        await this.notifyReporterOfDecision(report);
        return {
            source: 'timeweb',
            item: this.serialize(report),
        };
    }
    async reopen(reportId, authUser) {
        const exists = await this.prisma.report.findUnique({
            where: {
                id: reportId,
            },
            include: {
                listing: {
                    include: {
                        owner: true,
                        photos: {
                            orderBy: {
                                sortOrder: 'asc',
                            },
                            take: 1,
                        },
                    },
                },
                listingOwner: true,
                reporter: true,
            },
        });
        if (!exists) {
            throw new common_1.NotFoundException('Report not found');
        }
        const report = await this.prisma.report.update({
            where: {
                id: reportId,
            },
            data: {
                status: 'open',
                decision: null,
                adminUid: authUser.userId,
                adminComment: null,
                handledBy: authUser.userId,
                handledAt: new Date(),
                closedAt: null,
            },
            include: {
                listing: {
                    include: {
                        owner: true,
                        photos: {
                            orderBy: {
                                sortOrder: 'asc',
                            },
                            take: 1,
                        },
                    },
                },
                listingOwner: true,
                reporter: true,
            },
        });
        this.adminDashboardSignal?.changed('reports');
        return {
            source: 'timeweb',
            item: this.serialize(report),
        };
    }
    async hide(reportId, authUser) {
        const exists = await this.prisma.report.findUnique({
            where: {
                id: reportId,
            },
        });
        if (!exists) {
            throw new common_1.NotFoundException('Жалоба не найдена');
        }
        const report = await this.prisma.report.update({
            where: {
                id: reportId,
            },
            data: {
                status: 'hidden',
                decision: exists.decision ?? 'hidden',
                adminUid: authUser.userId,
                handledBy: authUser.userId,
                handledAt: exists.handledAt ?? new Date(),
                closedAt: exists.closedAt ?? new Date(),
            },
        });
        this.adminDashboardSignal?.changed('reports');
        return {
            source: 'timeweb',
            hidden: true,
            item: this.serialize(report),
        };
    }
};
exports.ReportsService = ReportsService;
ReportsService.hiddenStatuses = ['hidden', 'deleted'];
exports.ReportsService = ReportsService = ReportsService_1 = __decorate([
    (0, common_1.Injectable)(),
    __param(2, (0, common_1.Optional)()),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        notifications_service_1.NotificationsService,
        admin_dashboard_signal_1.AdminDashboardSignal])
], ReportsService);
//# sourceMappingURL=reports.service.js.map