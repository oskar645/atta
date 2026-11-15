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
var NotificationsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.NotificationsService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const serializers_1 = require("../../common/serializers");
const apns_service_1 = require("../apns/apns.service");
const chats_gateway_1 = require("../chats/chats.gateway");
const fcm_service_1 = require("../fcm/fcm.service");
const prisma_service_1 = require("../prisma/prisma.service");
const excludedInAppNotificationTypes = [client_1.NotificationType.CHAT_MESSAGE];
let NotificationsService = NotificationsService_1 = class NotificationsService {
    constructor(apnsService, prisma, chatsGateway, fcmService) {
        this.apnsService = apnsService;
        this.prisma = prisma;
        this.chatsGateway = chatsGateway;
        this.fcmService = fcmService;
        this.logger = new common_1.Logger(NotificationsService_1.name);
        this.adminEventNotificationsInFlight = new Map();
    }
    onModuleInit() {
        this.adminPushTimer = setInterval(() => {
            void this.runAdminPushDrainSafely();
        }, 30_000);
        this.adminPushTimer.unref?.();
        void this.runAdminPushDrainSafely();
    }
    onModuleDestroy() {
        if (this.adminPushTimer)
            clearInterval(this.adminPushTimer);
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
    toPlatform(platform) {
        switch ((platform ?? '').trim().toLowerCase()) {
            case 'android':
                return client_1.DevicePlatform.ANDROID;
            case 'web':
                return client_1.DevicePlatform.WEB;
            case 'ios':
            default:
                return client_1.DevicePlatform.IOS;
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
    assertPushPreferenceOwner(authUser, userId) {
        if (userId !== authUser.userId) {
            throw new common_1.ForbiddenException('Push preference belongs to another user');
        }
    }
    async getPushPreference(authUser, userId) {
        this.assertPushPreferenceOwner(authUser, userId);
        const user = await this.prisma.user.findUnique({
            where: { id: authUser.userId },
            select: { pushNotificationsEnabled: true },
        });
        if (!user)
            throw new common_1.NotFoundException('User not found');
        return { enabled: user.pushNotificationsEnabled };
    }
    async setPushPreference(authUser, enabled, userId) {
        this.assertPushPreferenceOwner(authUser, userId);
        if (typeof enabled !== 'boolean') {
            throw new common_1.BadRequestException('enabled must be a boolean');
        }
        const user = await this.prisma.user.update({
            where: { id: authUser.userId },
            data: { pushNotificationsEnabled: enabled },
            select: { pushNotificationsEnabled: true },
        });
        if (!enabled) {
            await this.prisma.userDevice.updateMany({
                where: { userId: authUser.userId },
                data: { isActive: false },
            });
        }
        return { enabled: user.pushNotificationsEnabled };
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
        this.chatsGateway.emitNotificationNew(this.serialize(item));
        await this.sendPushToAllUsers(this.serialize(item));
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
        await this.publishNotification(item);
        return item;
    }
    async createAdminEventNotifications(params) {
        const eventKey = params.eventKey.trim();
        if (!eventKey)
            return;
        const existing = this.adminEventNotificationsInFlight.get(eventKey);
        if (existing != null)
            return existing;
        const future = this.createAdminEventNotificationsInternal({
            ...params,
            eventKey,
        });
        this.adminEventNotificationsInFlight.set(eventKey, future);
        try {
            await future;
        }
        finally {
            if (this.adminEventNotificationsInFlight.get(eventKey) === future) {
                this.adminEventNotificationsInFlight.delete(eventKey);
            }
        }
    }
    async createAdminEventNotificationsInternal(params) {
        const admins = await this.prisma.user.findMany({
            where: {
                deletedAt: null,
                status: client_1.UserStatus.ACTIVE,
                adminProfile: { is: { isAdmin: true } },
            },
            select: { id: true },
        });
        await Promise.all(admins.map(async (admin) => {
            const result = await this.prisma.$transaction(async (tx) => {
                await tx.$executeRaw `
            SELECT pg_advisory_xact_lock(
              hashtext(${`admin_notification:${admin.id}:${params.eventKey}`})
            )
          `;
                let item = await tx.userNotification.findFirst({
                    where: {
                        userId: admin.id,
                        scope: client_1.NotificationScope.PERSONAL,
                        payload: { path: ['adminEventKey'], equals: params.eventKey },
                    },
                });
                const created = item == null;
                if (item == null) {
                    item = await tx.userNotification.create({ data: {
                            userId: admin.id,
                            scope: client_1.NotificationScope.PERSONAL,
                            title: params.title.trim(),
                            body: params.body.trim(),
                            type: params.type,
                            payload: {
                                ...params.payload,
                                adminEventKey: params.eventKey,
                            },
                        } });
                }
                const devices = await tx.userDevice.findMany({
                    where: {
                        userId: admin.id,
                        isActive: true,
                        platform: { in: [client_1.DevicePlatform.IOS, client_1.DevicePlatform.ANDROID] },
                        session: { revokedAt: null, expiresAt: { gt: new Date() } },
                    },
                    select: { id: true },
                });
                if (devices.length > 0) {
                    await tx.adminPushDelivery.createMany({
                        data: devices.map((device) => ({
                            notificationId: item.id,
                            userId: admin.id,
                            deviceId: device.id,
                        })),
                        skipDuplicates: true,
                    });
                }
                return { item, created };
            });
            if (result.created) {
                this.chatsGateway.emitNotificationNew(this.serialize(result.item), result.item.userId ?? undefined);
            }
        }));
        await this.runAdminPushDrainSafely();
    }
    async runAdminPushDrainSafely() {
        try {
            await this.drainAdminPushDeliveries();
        }
        catch (error) {
            this.logger.warn(`Admin push delivery pass failed. error=${error instanceof Error ? error.name : 'unknown'}`);
        }
    }
    async drainAdminPushDeliveries() {
        if (this.adminPushDrainInFlight)
            return this.adminPushDrainInFlight;
        const future = this.drainAdminPushDeliveriesInternal();
        this.adminPushDrainInFlight = future;
        try {
            await future;
        }
        finally {
            if (this.adminPushDrainInFlight === future)
                this.adminPushDrainInFlight = undefined;
        }
    }
    async drainAdminPushDeliveriesInternal() {
        const claimed = await this.prisma.$transaction(async (tx) => {
            const rows = await tx.$queryRaw `
        SELECT "id"
        FROM "admin_push_deliveries"
        WHERE "status" = 'pending'
          AND "attempts" < ${NotificationsService_1.adminPushMaxAttempts}
          AND "next_attempt_at" <= NOW()
          AND ("locked_until" IS NULL OR "locked_until" < NOW())
        ORDER BY "next_attempt_at" ASC, "created_at" ASC
        FOR UPDATE SKIP LOCKED
        LIMIT 25
      `;
            if (rows.length === 0)
                return [];
            const ids = rows.map((row) => row.id);
            await tx.adminPushDelivery.updateMany({
                where: { id: { in: ids } },
                data: {
                    attempts: { increment: 1 },
                    lockedUntil: new Date(Date.now() + 60_000),
                },
            });
            return ids;
        });
        await Promise.all(claimed.map((id) => this.deliverAdminPush(id)));
    }
    async deliverAdminPush(id) {
        const delivery = await this.prisma.adminPushDelivery.findFirst({
            where: {
                id,
                status: 'pending',
                user: {
                    is: {
                        deletedAt: null,
                        status: client_1.UserStatus.ACTIVE,
                        pushNotificationsEnabled: true,
                        adminProfile: { is: { isAdmin: true } },
                    },
                },
                device: {
                    is: {
                        isActive: true,
                        session: { is: { revokedAt: null, expiresAt: { gt: new Date() } } },
                    },
                },
            },
            include: { notification: true, device: true },
        });
        if (!delivery) {
            await this.prisma.adminPushDelivery.updateMany({
                where: { id, status: 'pending' },
                data: { status: 'cancelled', lockedUntil: null, lastError: 'recipient_ineligible' },
            });
            return;
        }
        const serialized = this.serialize(delivery.notification);
        let result;
        try {
            const badge = await this.canonicalBadgeCount(delivery.userId);
            result = await this.sendPushToDevice(delivery.device, serialized, badge);
        }
        catch {
            result = { sent: false, status: 0, reason: 'unexpected_delivery_error' };
        }
        if (result.sent) {
            await this.prisma.adminPushDelivery.update({
                where: { id },
                data: { status: 'delivered', deliveredAt: new Date(), lockedUntil: null, lastError: null },
            });
            return;
        }
        if (this.isPermanentPushFailure(result)) {
            await this.deactivateDevice(delivery.device);
            await this.prisma.adminPushDelivery.update({
                where: { id },
                data: { status: 'failed', lockedUntil: null, lastError: result.reason ?? `http_${result.status}` },
            });
            return;
        }
        const attempts = delivery.attempts;
        const exhausted = attempts >= NotificationsService_1.adminPushMaxAttempts;
        const delays = [30, 120, 600, 1800, 3600];
        await this.prisma.adminPushDelivery.update({
            where: { id },
            data: {
                status: exhausted ? 'failed' : 'pending',
                lockedUntil: null,
                nextAttemptAt: new Date(Date.now() + delays[Math.min(attempts - 1, delays.length - 1)] * 1000),
                lastError: result.reason ?? `http_${result.status}`,
            },
        });
    }
    async publishNotification(item) {
        const serialized = this.serialize(item);
        this.chatsGateway.emitNotificationNew(serialized, item.userId ?? undefined);
        try {
            if (item.userId)
                await this.sendPushToUser(item.userId, serialized);
        }
        catch (error) {
            this.logger.warn(`Notification push failed notificationId=${item.id}`);
        }
    }
    async unreadNotificationCount(userId) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId }, select: { lastNotificationsSeenAt: true },
        });
        return this.prisma.userNotification.count({
            where: {
                type: { notIn: excludedInAppNotificationTypes },
                OR: [
                    { userId, scope: client_1.NotificationScope.PERSONAL, isRead: false },
                    { scope: client_1.NotificationScope.GLOBAL,
                        ...(user?.lastNotificationsSeenAt ? { createdAt: { gt: user.lastNotificationsSeenAt } } : {}) },
                ],
            },
        });
    }
    async canonicalBadgeCount(userId) {
        const [buyer, seller, notifications] = await Promise.all([
            this.prisma.chat.aggregate({ where: { buyerId: userId, deletedByBuyerAt: null }, _sum: { unreadForBuyer: true } }),
            this.prisma.chat.aggregate({ where: { sellerId: userId, deletedBySellerAt: null }, _sum: { unreadForSeller: true } }),
            this.unreadNotificationCount(userId),
        ]);
        return Math.max(0, (buyer._sum.unreadForBuyer ?? 0) + (seller._sum.unreadForSeller ?? 0) + notifications);
    }
    async registerDevice(authUser, body) {
        const token = body.token?.trim() ?? '';
        if (!token) {
            throw new common_1.BadRequestException('Device token is required');
        }
        const item = await this.prisma.$transaction(async (tx) => {
            // A delayed registration from a logged-out session must not steal the
            // device back after a newer login. Serialize registration for this token.
            await tx.$queryRaw `SELECT pg_advisory_xact_lock(hashtext(${token}))::text`;
            const session = await tx.userSession.findFirst({
                where: { id: authUser.sessionId, userId: authUser.userId,
                    revokedAt: null, expiresAt: { gt: new Date() } },
            });
            if (!session)
                throw new common_1.ForbiddenException('Push session is not active');
            const user = await tx.user.findUnique({
                where: { id: authUser.userId },
                select: { pushNotificationsEnabled: true },
            });
            if (!user?.pushNotificationsEnabled) {
                throw new common_1.ForbiddenException('Push notifications are disabled');
            }
            const previous = await tx.userDevice.findUnique({
                where: { deviceToken: token }, include: { session: true },
            });
            if (previous?.session && previous.session.createdAt > session.createdAt) {
                throw new common_1.ForbiddenException('Push token belongs to a newer session');
            }
            return tx.userDevice.upsert({
                where: {
                    deviceToken: token,
                },
                update: {
                    userId: authUser.userId,
                    sessionId: authUser.sessionId,
                    platform: this.toPlatform(body.platform),
                    deviceUid: body.deviceUid?.trim() || null,
                    appVersion: body.appVersion?.trim() || null,
                    buildNumber: body.buildNumber?.trim() || null,
                    locale: body.locale?.trim() || null,
                    supportsAndroidDataOnlyPush: this.toPlatform(body.platform) === client_1.DevicePlatform.ANDROID
                        ? body.supportsAndroidDataOnlyPush === true
                        : null,
                    isActive: true,
                    lastSeenAt: new Date(),
                },
                create: {
                    userId: authUser.userId,
                    sessionId: authUser.sessionId,
                    platform: this.toPlatform(body.platform),
                    deviceToken: token,
                    deviceUid: body.deviceUid?.trim() || null,
                    appVersion: body.appVersion?.trim() || null,
                    buildNumber: body.buildNumber?.trim() || null,
                    locale: body.locale?.trim() || null,
                    supportsAndroidDataOnlyPush: this.toPlatform(body.platform) === client_1.DevicePlatform.ANDROID
                        ? body.supportsAndroidDataOnlyPush === true
                        : null,
                },
            });
        });
        return {
            source: 'timeweb',
            item: {
                id: item.id,
                platform: item.platform.toLowerCase(),
                is_active: item.isActive,
            },
        };
    }
    async unregisterDevice(authUser, token) {
        const normalizedToken = token?.trim() ?? '';
        if (!normalizedToken) {
            return {
                source: 'timeweb',
                updated: 0,
            };
        }
        const result = await this.prisma.userDevice.updateMany({
            where: {
                userId: authUser.userId,
                deviceToken: normalizedToken,
            },
            data: {
                isActive: false,
            },
        });
        return {
            source: 'timeweb',
            updated: result.count,
        };
    }
    async sendChatMessagePush(params) {
        const message = params.message;
        const senderName = `${message['senderName'] ?? message['sender_name'] ?? ''}`.trim() ||
            'Новое сообщение';
        const isImage = `${message['type'] ?? message['messageType'] ?? ''}`.toLowerCase() ===
            'image';
        const text = `${message['text'] ?? message['body'] ?? message['content'] ?? ''}`.trim();
        const serialized = {
            id: `${message['id'] ?? ''}`.trim(),
            scope: 'personal',
            type: 'chat_message',
            title: senderName,
            body: isImage ? 'Фото' : text || 'Новое сообщение',
            is_read: false,
            created_at: `${message['createdAt'] ?? new Date().toISOString()}`,
            payload: {
                actionType: 'chat_message',
                chatId: `${message['chatId'] ?? message['chat_id'] ?? params.chat['id'] ?? ''}`,
                messageId: `${message['id'] ?? ''}`,
                senderId: `${message['senderId'] ?? message['sender_id'] ?? ''}`,
            },
            chat_id: `${message['chatId'] ?? message['chat_id'] ?? params.chat['id'] ?? ''}`,
            chatId: `${message['chatId'] ?? message['chat_id'] ?? params.chat['id'] ?? ''}`,
            unreadTotal: Math.max(0, Math.trunc(params.unreadTotal ?? 0)),
        };
        await this.sendPushToUser(params.recipientId, serialized);
    }
    async sendBadgeUpdate(userId) {
        try {
            const normalizedUserId = userId.trim();
            if (!normalizedUserId)
                return;
            const [badge, devices] = await Promise.all([
                this.canonicalBadgeCount(normalizedUserId),
                this.prisma.userDevice.findMany({
                    where: {
                        userId: normalizedUserId,
                        isActive: true,
                        platform: client_1.DevicePlatform.IOS,
                        user: { pushNotificationsEnabled: true },
                        session: { revokedAt: null, expiresAt: { gt: new Date() } },
                    },
                    select: { userId: true, deviceToken: true, platform: true },
                }),
            ]);
            await Promise.all(devices.map(async (device) => {
                try {
                    const result = await this.apnsService.sendBadge({
                        token: device.deviceToken,
                        badge,
                    });
                    if (!result.sent && (result.status === 400 || result.status === 410) &&
                        (result.reason === 'BadDeviceToken' || result.reason === 'Unregistered' ||
                            result.reason === 'DeviceTokenNotForTopic')) {
                        await this.deactivateDevice(device);
                    }
                }
                catch (error) {
                    this.logger.warn(`APNs badge update failed. error=${error instanceof Error ? error.name : 'unknown'}`);
                }
            }));
        }
        catch (error) {
            this.logger.warn(`APNs badge update skipped. error=${error instanceof Error ? error.name : 'unknown'}`);
        }
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
    async sendPushToAllUsers(notification) {
        const devices = await this.prisma.userDevice.findMany({
            where: {
                isActive: true,
                platform: { in: [client_1.DevicePlatform.IOS, client_1.DevicePlatform.ANDROID] },
                user: { pushNotificationsEnabled: true },
                session: { revokedAt: null, expiresAt: { gt: new Date() } },
            },
            select: {
                id: true,
                userId: true,
                deviceToken: true,
                platform: true,
                supportsAndroidDataOnlyPush: true,
            },
            take: 5000,
        });
        await this.sendPushToDevices(devices, notification);
    }
    async sendPushToUser(userId, notification) {
        const normalizedUserId = userId.trim();
        if (!normalizedUserId)
            return;
        const devices = await this.prisma.userDevice.findMany({
            where: {
                userId: normalizedUserId,
                isActive: true,
                platform: { in: [client_1.DevicePlatform.IOS, client_1.DevicePlatform.ANDROID] },
                user: { pushNotificationsEnabled: true },
                session: { revokedAt: null, expiresAt: { gt: new Date() } },
            },
            select: {
                id: true,
                userId: true,
                deviceToken: true,
                platform: true,
                supportsAndroidDataOnlyPush: true,
            },
        });
        await this.sendPushToDevices(devices, notification);
    }
    async sendPushToDevices(devices, notification) {
        const badges = new Map();
        let unexpectedPushFailureLogged = false;
        await Promise.all(devices.map(async (device) => {
            try {
                let badge = badges.get(device.userId);
                if (!badge) {
                    badge = this.canonicalBadgeCount(device.userId);
                    badges.set(device.userId, badge);
                }
                const absoluteBadge = await badge;
                const result = await this.sendPushToDevice(device, notification, absoluteBadge);
                if (!result.sent && this.isPermanentPushFailure(result)) {
                    await this.deactivateDevice(device);
                }
            }
            catch (error) {
                if (!unexpectedPushFailureLogged) {
                    this.logger.warn(`Push delivery skipped after unexpected send failure. error=${error instanceof Error ? error.name : 'unknown'}`);
                    unexpectedPushFailureLogged = true;
                }
            }
        }));
    }
    async sendPushToDevice(device, notification, badge) {
        const title = `${notification['title'] ?? ''}`.trim() || 'ATTA';
        const body = `${notification['body'] ?? ''}`.trim() || 'Новое уведомление';
        const actionType = `${notification['payload']?.['actionType'] ?? ''}`.trim() ||
            `${notification['type'] ?? ''}`.trim();
        if (device.platform === client_1.DevicePlatform.ANDROID) {
            return this.fcmService?.send({
                token: device.deviceToken,
                title,
                body,
                notification,
                recipientId: device.userId,
                actionType,
                supportsDataOnly: device.supportsAndroidDataOnlyPush === true,
            }) ?? { sent: false, status: 0, reason: 'fcm_unavailable', skipped: true };
        }
        return this.apnsService.send({
            token: device.deviceToken,
            title,
            body,
            payload: { notification, actionType, recipientId: device.userId },
            badge,
        });
    }
    isPermanentPushFailure(result) {
        return (((result.status === 400 || result.status === 410) &&
            (result.reason === 'BadDeviceToken' ||
                result.reason === 'Unregistered' ||
                result.reason === 'DeviceTokenNotForTopic')) ||
            result.reason === 'UNREGISTERED' ||
            result.reason === 'INVALID_ARGUMENT');
    }
    async deactivateDevice(device) {
        await this.prisma.userDevice.updateMany({
            where: { deviceToken: device.deviceToken, userId: device.userId },
            data: { isActive: false },
        });
    }
};
exports.NotificationsService = NotificationsService;
NotificationsService.adminPushMaxAttempts = 5;
exports.NotificationsService = NotificationsService = NotificationsService_1 = __decorate([
    (0, common_1.Injectable)(),
    __param(3, (0, common_1.Optional)()),
    __metadata("design:paramtypes", [apns_service_1.ApnsService,
        prisma_service_1.PrismaService,
        chats_gateway_1.ChatsGateway,
        fcm_service_1.FcmService])
], NotificationsService);
//# sourceMappingURL=notifications.service.js.map