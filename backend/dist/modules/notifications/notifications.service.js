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
exports.NotificationsService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const serializers_1 = require("../../common/serializers");
const apns_service_1 = require("../apns/apns.service");
const chats_gateway_1 = require("../chats/chats.gateway");
const prisma_service_1 = require("../prisma/prisma.service");
const excludedInAppNotificationTypes = [client_1.NotificationType.CHAT_MESSAGE];
let NotificationsService = class NotificationsService {
    constructor(apnsService, prisma, chatsGateway) {
        this.apnsService = apnsService;
        this.prisma = prisma;
        this.chatsGateway = chatsGateway;
    }
    toType(type) {
        switch ((type ?? '').trim().toLowerCase()) {
            case 'moderation':
                return client_1.NotificationType.MODERATION;
            case 'report':
                return client_1.NotificationType.GENERIC;
            case 'support':
                return client_1.NotificationType.SUPPORT;
            case 'update':
            default:
                return client_1.NotificationType.GENERIC;
        }
    }
    serialize(item) {
        const payload = this.normalizePayload(item.payload);
        return {
            id: item.id,
            user_id: item.userId,
            scope: item.scope.toLowerCase(),
            title: item.title,
            body: item.body,
            is_read: item.isRead,
            type: item.type.toLowerCase(),
            created_at: item.createdAt.toISOString(),
            payload,
            chat_id: `${payload.chatId ?? ''}`.trim() || null,
            chatId: `${payload.chatId ?? ''}`.trim() || null,
            sender_id: `${payload.senderId ?? ''}`.trim() || null,
            senderId: `${payload.senderId ?? ''}`.trim() || null,
            sender_name: `${payload.senderName ?? ''}`.trim() || null,
            senderName: `${payload.senderName ?? ''}`.trim() || null,
            sender_avatar_url: `${payload.senderAvatarUrl ?? ''}`.trim() || null,
            senderAvatarUrl: `${payload.senderAvatarUrl ?? ''}`.trim() || null,
        };
    }
    normalizePayload(payload) {
        const raw = payload && typeof payload === 'object' && !Array.isArray(payload)
            ? { ...payload }
            : {};
        const imageUrl = `${raw.imageUrl ?? raw.image_url ?? ''}`.trim();
        const actionUrl = `${raw.actionUrl ?? raw.action_url ?? ''}`.trim();
        const description = `${raw.description ?? ''}`.trim();
        const actionLabel = `${raw.actionLabel ?? raw.action_label ?? ''}`.trim();
        if (imageUrl.length > 0) {
            raw.imageUrl = (0, serializers_1.normalizeStoredMediaUrl)(imageUrl, {
                category: 'misc',
            });
            raw.image_url = raw.imageUrl;
        }
        if (actionUrl.length > 0) {
            raw.actionUrl = actionUrl;
            raw.action_url = actionUrl;
        }
        if (description.length > 0) {
            raw.description = description;
        }
        if (actionLabel.length > 0) {
            raw.actionLabel = actionLabel;
            raw.action_label = actionLabel;
        }
        return raw;
    }
    inAppWhereClause(authUser) {
        return {
            OR: [
                { scope: client_1.NotificationScope.GLOBAL },
                { scope: client_1.NotificationScope.PERSONAL, userId: authUser.userId },
            ],
            type: {
                notIn: excludedInAppNotificationTypes,
            },
        };
    }
    sanitizePayload(payload) {
        const normalized = payload && typeof payload === 'object' && !Array.isArray(payload)
            ? { ...payload }
            : {};
        const description = `${normalized.description ?? ''}`.trim();
        const imageUrl = `${normalized.imageUrl ?? normalized.image_url ?? ''}`.trim();
        const actionUrl = `${normalized.actionUrl ?? normalized.action_url ?? ''}`.trim();
        const result = {};
        if (description.length > 0) {
            result.description = description;
        }
        if (imageUrl.length > 0) {
            result.imageUrl = imageUrl;
        }
        if (actionUrl.length > 0) {
            result.actionUrl = actionUrl;
        }
        return result;
    }
    ensureAdminNotificationHasContent(params) {
        const title = params.title?.trim() ?? '';
        const body = params.body?.trim() ?? '';
        const payload = this.sanitizePayload(params.payload);
        const description = `${payload.description ?? ''}`.trim();
        const imageUrl = `${payload.imageUrl ?? ''}`.trim();
        if (title.length === 0 &&
            body.length === 0 &&
            description.length === 0 &&
            imageUrl.length === 0) {
            throw new common_1.BadRequestException('Добавьте текст, описание или фото.');
        }
        return payload;
    }
    async listInAppNotifications(authUser) {
        const [items, user] = await Promise.all([
            this.prisma.userNotification.findMany({
                where: this.inAppWhereClause(authUser),
                orderBy: {
                    createdAt: 'desc',
                },
                take: 200,
            }),
            this.prisma.user.findUnique({
                where: {
                    id: authUser.userId,
                },
                select: {
                    lastNotificationsSeenAt: true,
                },
            }),
        ]);
        return {
            source: 'timeweb',
            global_seen_at: user?.lastNotificationsSeenAt?.toISOString() ?? null,
            items: items.map((item) => this.serialize(item)),
        };
    }
    async sendToUser(body) {
        const userId = body.userId?.trim() ?? '';
        if (!userId) {
            throw new common_1.NotFoundException('User with this user_id was not found');
        }
        const user = await this.prisma.user.findUnique({
            where: {
                id: userId,
            },
            select: {
                id: true,
            },
        });
        if (!user) {
            throw new common_1.NotFoundException('User with this user_id was not found');
        }
        const payload = this.ensureAdminNotificationHasContent(body);
        const item = await this.createSystemNotification({
            userId,
            title: body.title?.trim() ?? '',
            body: body.body?.trim() ?? '',
            type: this.toType(body.type),
            payload,
        });
        return {
            source: 'timeweb',
            item: this.serialize(item),
        };
    }
    async sendToAll(body) {
        const payload = this.ensureAdminNotificationHasContent(body);
        const item = await this.prisma.userNotification.create({
            data: {
                userId: null,
                scope: client_1.NotificationScope.GLOBAL,
                title: body.title?.trim() ?? '',
                body: body.body?.trim() ?? '',
                type: this.toType(body.type),
                payload: payload,
            },
        });
        return {
            source: 'timeweb',
            item: this.serialize(item),
        };
    }
    async createSystemNotification(params) {
        const item = await this.prisma.userNotification.create({
            data: {
                userId: params.userId,
                scope: client_1.NotificationScope.PERSONAL,
                title: params.title.trim(),
                body: params.body.trim(),
                type: params.type ?? client_1.NotificationType.GENERIC,
                payload: (params.payload ?? {}),
            },
        });
        this.chatsGateway.emitNotificationNew(this.serialize(item), params.userId.trim());
        return item;
    }
    serializeNotification(item) {
        return this.serialize(item);
    }
    async markRead(authUser, notificationId) {
        const notification = await this.prisma.userNotification.findFirst({
            where: {
                id: notificationId,
                ...this.inAppWhereClause(authUser),
            },
        });
        if (!notification) {
            throw new common_1.NotFoundException('Notification not found');
        }
        const item = await this.prisma.userNotification.update({
            where: {
                id: notificationId,
            },
            data: {
                isRead: true,
            },
        });
        return {
            source: 'timeweb',
            item: this.serialize(item),
        };
    }
    async markAllRead(authUser) {
        const result = await this.prisma.userNotification.updateMany({
            where: {
                userId: authUser.userId,
                scope: client_1.NotificationScope.PERSONAL,
                isRead: false,
            },
            data: {
                isRead: true,
            },
        });
        return {
            source: 'timeweb',
            updated: result.count,
        };
    }
    async markAllSeen(authUser) {
        const seenAt = new Date();
        const [, personalResult] = await this.prisma.$transaction([
            this.prisma.user.update({
                where: {
                    id: authUser.userId,
                },
                data: {
                    lastNotificationsSeenAt: seenAt,
                },
                select: {
                    id: true,
                },
            }),
            this.prisma.userNotification.updateMany({
                where: {
                    userId: authUser.userId,
                    scope: client_1.NotificationScope.PERSONAL,
                    isRead: false,
                },
                data: {
                    isRead: true,
                },
            }),
        ]);
        return {
            source: 'timeweb',
            global_seen_at: seenAt.toISOString(),
            updated_personal: personalResult.count,
        };
    }
    async deleteNotification(authUser, notificationId) {
        const notification = await this.prisma.userNotification.findUnique({
            where: {
                id: notificationId,
            },
        });
        if (!notification) {
            throw new common_1.NotFoundException('Notification not found');
        }
        const isOwner = notification.userId === authUser.userId;
        const isAdmin = authUser.role === 'admin';
        const isGlobal = notification.scope === client_1.NotificationScope.GLOBAL;
        if (!isOwner && !isAdmin) {
            throw new common_1.ForbiddenException('No access to delete notification');
        }
        if (isGlobal && !isAdmin) {
            throw new common_1.ForbiddenException('Only admin can delete global notification');
        }
        await this.prisma.userNotification.delete({
            where: {
                id: notificationId,
            },
        });
        return {
            source: 'timeweb',
            deleted: true,
            id: notificationId,
        };
    }
    sendPushPlaceholder() {
        return this.apnsService.sendPlaceholder();
    }
};
exports.NotificationsService = NotificationsService;
exports.NotificationsService = NotificationsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [apns_service_1.ApnsService,
        prisma_service_1.PrismaService,
        chats_gateway_1.ChatsGateway])
], NotificationsService);
//# sourceMappingURL=notifications.service.js.map