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
const apns_service_1 = require("../apns/apns.service");
const prisma_service_1 = require("../prisma/prisma.service");
let NotificationsService = class NotificationsService {
    constructor(apnsService, prisma) {
        this.apnsService = apnsService;
        this.prisma = prisma;
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
        const payload = item.payload && typeof item.payload === 'object' && !Array.isArray(item.payload)
            ? item.payload
            : {};
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
    async listInAppNotifications(authUser) {
        const items = await this.prisma.userNotification.findMany({
            where: {
                OR: [
                    { scope: client_1.NotificationScope.GLOBAL },
                    { scope: client_1.NotificationScope.PERSONAL, userId: authUser.userId },
                ],
            },
            orderBy: {
                createdAt: 'desc',
            },
            take: 200,
        });
        return {
            source: 'timeweb',
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
        const item = await this.createSystemNotification({
            userId,
            title: body.title?.trim() ?? '',
            body: body.body?.trim() ?? '',
            type: this.toType(body.type),
        });
        return {
            source: 'timeweb',
            item: this.serialize(item),
        };
    }
    async sendToAll(body) {
        const item = await this.prisma.userNotification.create({
            data: {
                userId: null,
                scope: client_1.NotificationScope.GLOBAL,
                title: body.title?.trim() ?? '',
                body: body.body?.trim() ?? '',
                type: this.toType(body.type),
            },
        });
        return {
            source: 'timeweb',
            item: this.serialize(item),
        };
    }
    async createSystemNotification(params) {
        return this.prisma.userNotification.create({
            data: {
                userId: params.userId,
                scope: client_1.NotificationScope.PERSONAL,
                title: params.title.trim(),
                body: params.body.trim(),
                type: params.type ?? client_1.NotificationType.GENERIC,
                payload: (params.payload ?? {}),
            },
        });
    }
    serializeNotification(item) {
        return this.serialize(item);
    }
    async markRead(authUser, notificationId) {
        const notification = await this.prisma.userNotification.findFirst({
            where: {
                id: notificationId,
                OR: [
                    { userId: authUser.userId },
                    { scope: client_1.NotificationScope.GLOBAL },
                ],
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
        prisma_service_1.PrismaService])
], NotificationsService);
//# sourceMappingURL=notifications.service.js.map