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
var ReportsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.ReportsService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const notifications_service_1 = require("../notifications/notifications.service");
const prisma_service_1 = require("../prisma/prisma.service");
let ReportsService = ReportsService_1 = class ReportsService {
    constructor(prisma, notificationsService) {
        this.prisma = prisma;
        this.notificationsService = notificationsService;
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
        const items = await this.prisma.report.findMany({
            where: {
                status: {
                    notIn: [...ReportsService_1.hiddenStatuses],
                },
                ...(cursorDate && !Number.isNaN(cursorDate.getTime()) && cursorId
                    ? {
                        OR: [
                            { createdAt: { lt: cursorDate } },
                            { createdAt: cursorDate, id: { lt: cursorId } },
                        ],
                    }
                    : {}),
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
            orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
            take: limit + 1,
        });
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
        };
    }
    async create(authUser, body) {
        const listingId = body.listingId?.trim() || null;
        const reportedUserId = body.reportedUserId?.trim() || body.listingOwnerId?.trim() || null;
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
        return {
            source: 'timeweb',
            item: this.serialize(report),
            admin_notifications: adminNotifications.map((item) => this.notificationsService.serializeNotification(item)),
        };
    }
    async resolve(reportId, authUser, comment) {
        const exists = await this.prisma.report.findUnique({
            where: {
                id: reportId,
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
                status: 'resolved',
                decision: 'resolved',
                adminUid: authUser.userId,
                adminComment: comment?.trim() || null,
                handledBy: authUser.userId,
                handledAt: new Date(),
                closedAt: new Date(),
            },
        });
        return {
            source: 'timeweb',
            item: this.serialize(report),
        };
    }
    async reject(reportId, authUser, comment) {
        const exists = await this.prisma.report.findUnique({
            where: {
                id: reportId,
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
                status: 'rejected',
                decision: 'rejected',
                adminUid: authUser.userId,
                adminComment: comment?.trim() || null,
                handledBy: authUser.userId,
                handledAt: new Date(),
                closedAt: new Date(),
            },
        });
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
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        notifications_service_1.NotificationsService])
], ReportsService);
//# sourceMappingURL=reports.service.js.map