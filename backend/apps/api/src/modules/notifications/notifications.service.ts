import { BadRequestException, ForbiddenException, Injectable, Logger, NotFoundException, OnModuleDestroy, OnModuleInit, Optional } from '@nestjs/common';
import {
  DevicePlatform,
  NotificationScope,
  NotificationType,
  Prisma,
  UserStatus,
} from '@prisma/client';

import { normalizeStoredMediaUrl } from '../../common/serializers';
import { AuthenticatedUser } from '../auth/auth.types';
import { ApnsService } from '../apns/apns.service';
import { ChatsGateway } from '../chats/chats.gateway';
import { FcmService } from '../fcm/fcm.service';
import { PrismaService } from '../prisma/prisma.service';

const excludedInAppNotificationTypes = [NotificationType.CHAT_MESSAGE];

@Injectable()
export class NotificationsService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(NotificationsService.name);
  private readonly adminEventNotificationsInFlight = new Map<string, Promise<void>>();
  private adminPushTimer?: ReturnType<typeof setInterval>;
  private adminPushDrainInFlight?: Promise<void>;
  private static readonly adminPushMaxAttempts = 5;

  constructor(
    private readonly apnsService: ApnsService,
    private readonly prisma: PrismaService,
    private readonly chatsGateway: ChatsGateway,
    @Optional() private readonly fcmService?: FcmService,
  ) {}

  onModuleInit() {
    this.adminPushTimer = setInterval(() => {
      void this.runAdminPushDrainSafely();
    }, 30_000);
    this.adminPushTimer.unref?.();
    void this.runAdminPushDrainSafely();
  }

  onModuleDestroy() {
    if (this.adminPushTimer) clearInterval(this.adminPushTimer);
  }

  private toType(type?: string) {
    switch ((type ?? '').trim().toLowerCase()) {
      case 'moderation':
        return NotificationType.MODERATION;
      case 'report':
        return NotificationType.GENERIC;
      case 'support':
        return NotificationType.SUPPORT;
      case 'update':
      default:
        return NotificationType.GENERIC;
    }
  }

  private toPlatform(platform?: string) {
    switch ((platform ?? '').trim().toLowerCase()) {
      case 'android':
        return DevicePlatform.ANDROID;
      case 'web':
        return DevicePlatform.WEB;
      case 'ios':
      default:
        return DevicePlatform.IOS;
    }
  }

  private serialize(item: {
    id: string;
    userId: string | null;
    scope: NotificationScope;
    title: string;
    body: string;
    isRead: boolean;
    createdAt: Date;
    type: NotificationType;
    payload?: Prisma.JsonValue | null;
  }) {
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
      sender_avatar_url:
        `${payload.senderAvatarUrl ?? ''}`.trim() || null,
      senderAvatarUrl:
        `${payload.senderAvatarUrl ?? ''}`.trim() || null,
    };
  }

  private normalizePayload(payload: Prisma.JsonValue | null | undefined) {
    const raw =
      payload && typeof payload === 'object' && !Array.isArray(payload)
        ? ({ ...(payload as Record<string, unknown>) } as Record<string, unknown>)
        : {};
    const imageUrl = `${raw.imageUrl ?? raw.image_url ?? ''}`.trim();
    const actionUrl = `${raw.actionUrl ?? raw.action_url ?? ''}`.trim();
    const description = `${raw.description ?? ''}`.trim();
    const actionLabel = `${raw.actionLabel ?? raw.action_label ?? ''}`.trim();
    if (imageUrl.length > 0) {
      raw.imageUrl = normalizeStoredMediaUrl(imageUrl, {
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

  private inAppWhereClause(authUser: AuthenticatedUser): Prisma.UserNotificationWhereInput {
    return {
      OR: [
        { scope: NotificationScope.GLOBAL },
        { scope: NotificationScope.PERSONAL, userId: authUser.userId },
      ],
      type: {
        notIn: excludedInAppNotificationTypes,
      },
    };
  }

  private sanitizePayload(payload?: Record<string, unknown>) {
    const normalized =
      payload && typeof payload === 'object' && !Array.isArray(payload)
        ? ({ ...(payload as Record<string, unknown>) } as Record<string, unknown>)
        : {};
    const description = `${normalized.description ?? ''}`.trim();
    const imageUrl = `${normalized.imageUrl ?? normalized.image_url ?? ''}`.trim();
    const actionUrl = `${normalized.actionUrl ?? normalized.action_url ?? ''}`.trim();
    const result: Record<string, unknown> = {};

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

  private ensureAdminNotificationHasContent(params: {
    title?: string;
    body?: string;
    payload?: Record<string, unknown>;
  }) {
    const title = params.title?.trim() ?? '';
    const body = params.body?.trim() ?? '';
    const payload = this.sanitizePayload(params.payload);
    const description = `${payload.description ?? ''}`.trim();
    const imageUrl = `${payload.imageUrl ?? ''}`.trim();

    if (
      title.length === 0 &&
      body.length === 0 &&
      description.length === 0 &&
      imageUrl.length === 0
    ) {
      throw new BadRequestException('Добавьте текст, описание или фото.');
    }

    return payload;
  }

  async listInAppNotifications(authUser: AuthenticatedUser) {
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

  private assertPushPreferenceOwner(authUser: AuthenticatedUser, userId?: string) {
    if (userId !== authUser.userId) {
      throw new ForbiddenException('Push preference belongs to another user');
    }
  }

  async getPushPreference(authUser: AuthenticatedUser, userId?: string) {
    this.assertPushPreferenceOwner(authUser, userId);
    const user = await this.prisma.user.findUnique({
      where: { id: authUser.userId },
      select: { pushNotificationsEnabled: true },
    });
    if (!user) throw new NotFoundException('User not found');
    return { enabled: user.pushNotificationsEnabled };
  }

  async setPushPreference(authUser: AuthenticatedUser, enabled?: boolean, userId?: string) {
    this.assertPushPreferenceOwner(authUser, userId);
    if (typeof enabled !== 'boolean') {
      throw new BadRequestException('enabled must be a boolean');
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

  async sendToUser(body: {
    userId?: string;
    title?: string;
    body?: string;
    type?: string;
    payload?: Record<string, unknown>;
  }) {
    const userId = body.userId?.trim() ?? '';
    if (!userId) {
      throw new NotFoundException('User with this user_id was not found');
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
      throw new NotFoundException('User with this user_id was not found');
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

  async sendToAll(body: {
    title?: string;
    body?: string;
    type?: string;
    payload?: Record<string, unknown>;
  }) {
    const payload = this.ensureAdminNotificationHasContent(body);
    const item = await this.prisma.userNotification.create({
      data: {
        userId: null,
        scope: NotificationScope.GLOBAL,
        title: body.title?.trim() ?? '',
        body: body.body?.trim() ?? '',
        type: this.toType(body.type),
        payload: payload as Prisma.InputJsonValue,
      },
    });
    this.chatsGateway.emitNotificationNew(this.serialize(item));
    await this.sendPushToAllUsers(this.serialize(item));

    return {
      source: 'timeweb',
      item: this.serialize(item),
    };
  }

  async createSystemNotification(params: {
    userId: string;
    title: string;
    body: string;
    type?: NotificationType;
    payload?: Record<string, unknown>;
  }) {
    const item = await this.prisma.userNotification.create({
      data: {
        userId: params.userId,
        scope: NotificationScope.PERSONAL,
        title: params.title.trim(),
        body: params.body.trim(),
        type: params.type ?? NotificationType.GENERIC,
        payload: (params.payload ?? {}) as Prisma.InputJsonValue,
      },
    });
    await this.publishNotification(item);
    return item;
  }

  async createAdminEventNotifications(params: {
    eventKey: string;
    title: string;
    body: string;
    type: NotificationType;
    payload: Record<string, unknown>;
  }) {
    const eventKey = params.eventKey.trim();
    if (!eventKey) return;
    const existing = this.adminEventNotificationsInFlight.get(eventKey);
    if (existing != null) return existing;

    const future = this.createAdminEventNotificationsInternal({
      ...params,
      eventKey,
    });
    this.adminEventNotificationsInFlight.set(eventKey, future);
    try {
      await future;
    } finally {
      if (this.adminEventNotificationsInFlight.get(eventKey) === future) {
        this.adminEventNotificationsInFlight.delete(eventKey);
      }
    }
  }

  private async createAdminEventNotificationsInternal(params: {
    eventKey: string;
    title: string;
    body: string;
    type: NotificationType;
    payload: Record<string, unknown>;
  }) {
    const admins = await this.prisma.user.findMany({
      where: {
        deletedAt: null,
        status: UserStatus.ACTIVE,
        adminProfile: { is: { isAdmin: true } },
      },
      select: { id: true },
    });
    await Promise.all(
      admins.map(async (admin) => {
        const result = await this.prisma.$transaction(async (tx) => {
          await tx.$executeRaw`
            SELECT pg_advisory_xact_lock(
              hashtext(${`admin_notification:${admin.id}:${params.eventKey}`})
            )
          `;
          let item = await tx.userNotification.findFirst({
            where: {
              userId: admin.id,
              scope: NotificationScope.PERSONAL,
              payload: { path: ['adminEventKey'], equals: params.eventKey },
            },
          });
          const created = item == null;
          if (item == null) {
            item = await tx.userNotification.create({ data: {
              userId: admin.id,
              scope: NotificationScope.PERSONAL,
              title: params.title.trim(),
              body: params.body.trim(),
              type: params.type,
              payload: {
                ...params.payload,
                adminEventKey: params.eventKey,
              } as Prisma.InputJsonValue,
            } });
          }
          const devices = await tx.userDevice.findMany({
            where: {
              userId: admin.id,
              isActive: true,
              platform: { in: [DevicePlatform.IOS, DevicePlatform.ANDROID] },
              session: { revokedAt: null, expiresAt: { gt: new Date() } },
            },
            select: { id: true },
          });
          if (devices.length > 0) {
            await tx.adminPushDelivery.createMany({
              data: devices.map((device) => ({
                notificationId: item!.id,
                userId: admin.id,
                deviceId: device.id,
              })),
              skipDuplicates: true,
            });
          }
          return { item, created };
        });
        if (result.created) {
          this.chatsGateway.emitNotificationNew(
            this.serialize(result.item),
            result.item.userId ?? undefined,
          );
        }
      }),
    );
    await this.runAdminPushDrainSafely();
  }

  private async runAdminPushDrainSafely() {
    try {
      await this.drainAdminPushDeliveries();
    } catch (error) {
      this.logger.warn(
        `Admin push delivery pass failed. error=${error instanceof Error ? error.name : 'unknown'}`,
      );
    }
  }

  async drainAdminPushDeliveries() {
    if (this.adminPushDrainInFlight) return this.adminPushDrainInFlight;
    const future = this.drainAdminPushDeliveriesInternal();
    this.adminPushDrainInFlight = future;
    try {
      await future;
    } finally {
      if (this.adminPushDrainInFlight === future) this.adminPushDrainInFlight = undefined;
    }
  }

  private async drainAdminPushDeliveriesInternal() {
    const claimed = await this.prisma.$transaction(async (tx) => {
      const rows = await tx.$queryRaw<Array<{ id: string }>>`
        SELECT "id"
        FROM "admin_push_deliveries"
        WHERE "status" = 'pending'
          AND "attempts" < ${NotificationsService.adminPushMaxAttempts}
          AND "next_attempt_at" <= NOW()
          AND ("locked_until" IS NULL OR "locked_until" < NOW())
        ORDER BY "next_attempt_at" ASC, "created_at" ASC
        FOR UPDATE SKIP LOCKED
        LIMIT 25
      `;
      if (rows.length === 0) return [];
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

  private async deliverAdminPush(id: string) {
    const delivery = await this.prisma.adminPushDelivery.findFirst({
      where: {
        id,
        status: 'pending',
        user: {
          is: {
            deletedAt: null,
            status: UserStatus.ACTIVE,
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
    let result: {
      sent: boolean;
      status: number;
      reason?: string;
      skipped?: boolean;
    };
    try {
      const badge = await this.canonicalBadgeCount(delivery.userId);
      result = await this.sendPushToDevice(delivery.device, serialized, badge);
    } catch {
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
    const exhausted = attempts >= NotificationsService.adminPushMaxAttempts;
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

  async publishNotification(item: Parameters<NotificationsService['serializeNotification']>[0]) {
    const serialized = this.serialize(item);
    this.chatsGateway.emitNotificationNew(serialized, item.userId ?? undefined);
    try {
      if (item.userId) await this.sendPushToUser(item.userId, serialized);
    } catch (error) {
      this.logger.warn(`Notification push failed notificationId=${item.id}`);
    }
  }

  async unreadNotificationCount(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId }, select: { lastNotificationsSeenAt: true },
    });
    return this.prisma.userNotification.count({
      where: {
        type: { notIn: excludedInAppNotificationTypes },
        OR: [
          { userId, scope: NotificationScope.PERSONAL, isRead: false },
          { scope: NotificationScope.GLOBAL,
            ...(user?.lastNotificationsSeenAt ? { createdAt: { gt: user.lastNotificationsSeenAt } } : {}) },
        ],
      },
    });
  }

  async canonicalBadgeCount(userId: string) {
    const [buyer, seller, notifications] = await Promise.all([
      this.prisma.chat.aggregate({ where: { buyerId: userId, deletedByBuyerAt: null }, _sum: { unreadForBuyer: true } }),
      this.prisma.chat.aggregate({ where: { sellerId: userId, deletedBySellerAt: null }, _sum: { unreadForSeller: true } }),
      this.unreadNotificationCount(userId),
    ]);
    return Math.max(0, (buyer._sum.unreadForBuyer ?? 0) + (seller._sum.unreadForSeller ?? 0) + notifications);
  }

  async registerDevice(
    authUser: AuthenticatedUser,
    body: {
      token?: string;
      platform?: string;
      deviceUid?: string;
      appVersion?: string;
      buildNumber?: string;
      locale?: string;
      supportsAndroidDataOnlyPush?: boolean;
    },
  ) {
    const token = body.token?.trim() ?? '';
    if (!token) {
      throw new BadRequestException('Device token is required');
    }
    const item = await this.prisma.$transaction(async tx => {
      // A delayed registration from a logged-out session must not steal the
      // device back after a newer login. Serialize registration for this token.
      await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtext(${token}))::text`;
      const session = await tx.userSession.findFirst({
        where: { id: authUser.sessionId, userId: authUser.userId,
          revokedAt: null, expiresAt: { gt: new Date() } },
      });
      if (!session) throw new ForbiddenException('Push session is not active');
      const user = await tx.user.findUnique({
        where: { id: authUser.userId },
        select: { pushNotificationsEnabled: true },
      });
      if (!user?.pushNotificationsEnabled) {
        throw new ForbiddenException('Push notifications are disabled');
      }
      const previous = await tx.userDevice.findUnique({
        where: { deviceToken: token }, include: { session: true },
      });
      if (previous?.session && previous.session.createdAt > session.createdAt) {
        throw new ForbiddenException('Push token belongs to a newer session');
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
        supportsAndroidDataOnlyPush:
          this.toPlatform(body.platform) === DevicePlatform.ANDROID
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
        supportsAndroidDataOnlyPush:
          this.toPlatform(body.platform) === DevicePlatform.ANDROID
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

  async unregisterDevice(authUser: AuthenticatedUser, token?: string) {
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

  async sendChatMessagePush(params: {
    recipientId: string;
    message: Record<string, unknown>;
    chat: Record<string, unknown>;
    unreadTotal?: number;
  }) {
    const message = params.message;
    const senderName =
      `${message['senderName'] ?? message['sender_name'] ?? ''}`.trim() ||
      'Новое сообщение';
    const isImage =
      `${message['type'] ?? message['messageType'] ?? ''}`.toLowerCase() ===
      'image';
    const text =
      `${message['text'] ?? message['body'] ?? message['content'] ?? ''}`.trim();
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

  async sendBadgeUpdate(userId: string) {
    try {
      const normalizedUserId = userId.trim();
      if (!normalizedUserId) return;
      const [badge, devices] = await Promise.all([
        this.canonicalBadgeCount(normalizedUserId),
        this.prisma.userDevice.findMany({
          where: {
            userId: normalizedUserId,
            isActive: true,
            platform: DevicePlatform.IOS,
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
        } catch (error) {
          this.logger.warn(
            `APNs badge update failed. error=${error instanceof Error ? error.name : 'unknown'}`,
          );
        }
      }));
    } catch (error) {
      this.logger.warn(
        `APNs badge update skipped. error=${error instanceof Error ? error.name : 'unknown'}`,
      );
    }
  }

  serializeNotification(item: {
    id: string;
    userId: string | null;
    scope: NotificationScope;
    title: string;
    body: string;
    isRead: boolean;
    createdAt: Date;
    type: NotificationType;
    payload?: Prisma.JsonValue | null;
  }) {
    return this.serialize(item);
  }

  async markRead(authUser: AuthenticatedUser, notificationId: string) {
    const notification = await this.prisma.userNotification.findFirst({
      where: {
        id: notificationId,
        ...this.inAppWhereClause(authUser),
      },
    });

    if (!notification) {
      throw new NotFoundException('Notification not found');
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

  async markAllRead(authUser: AuthenticatedUser) {
    const result = await this.prisma.userNotification.updateMany({
      where: {
        userId: authUser.userId,
        scope: NotificationScope.PERSONAL,
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

  async markAllSeen(authUser: AuthenticatedUser) {
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
          scope: NotificationScope.PERSONAL,
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

  async deleteNotification(
    authUser: AuthenticatedUser,
    notificationId: string,
  ) {
    const notification = await this.prisma.userNotification.findUnique({
      where: {
        id: notificationId,
      },
    });

    if (!notification) {
      throw new NotFoundException('Notification not found');
    }

    const isOwner = notification.userId === authUser.userId;
    const isAdmin = authUser.role === 'admin';
    const isGlobal = notification.scope === NotificationScope.GLOBAL;

    if (!isOwner && !isAdmin) {
      throw new ForbiddenException('No access to delete notification');
    }

    if (isGlobal && !isAdmin) {
      throw new ForbiddenException('Only admin can delete global notification');
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

  private async sendPushToAllUsers(notification: Record<string, unknown>) {
    const devices = await this.prisma.userDevice.findMany({
      where: {
        isActive: true,
        platform: { in: [DevicePlatform.IOS, DevicePlatform.ANDROID] },
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

  private async sendPushToUser(
    userId: string,
    notification: Record<string, unknown>,
  ) {
    const normalizedUserId = userId.trim();
    if (!normalizedUserId) return;
    const devices = await this.prisma.userDevice.findMany({
      where: {
        userId: normalizedUserId,
        isActive: true,
        platform: { in: [DevicePlatform.IOS, DevicePlatform.ANDROID] },
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

  private async sendPushToDevices(
    devices: Array<{
      id?: string;
      userId: string;
      deviceToken: string;
      platform: DevicePlatform;
      supportsAndroidDataOnlyPush?: boolean | null;
    }>,
    notification: Record<string, unknown>,
  ) {
    const badges = new Map<string, Promise<number>>();
    let unexpectedPushFailureLogged = false;
    await Promise.all(
      devices.map(async (device) => {
        try {
          let badge = badges.get(device.userId);
          if (!badge) {
            badge = this.canonicalBadgeCount(device.userId);
            badges.set(device.userId, badge);
          }
          const absoluteBadge = await badge;
          const result = await this.sendPushToDevice(
            device,
            notification,
            absoluteBadge,
          );
          if (!result.sent && this.isPermanentPushFailure(result)) {
            await this.deactivateDevice(device);
          }
        } catch (error) {
          if (!unexpectedPushFailureLogged) {
            this.logger.warn(
              `Push delivery skipped after unexpected send failure. error=${error instanceof Error ? error.name : 'unknown'}`,
            );
            unexpectedPushFailureLogged = true;
          }
        }
      }),
    );
  }

  private async sendPushToDevice(
    device: {
      userId: string;
      deviceToken: string;
      platform: DevicePlatform;
      supportsAndroidDataOnlyPush?: boolean | null;
    },
    notification: Record<string, unknown>,
    badge: number,
  ): Promise<{ sent: boolean; status: number; reason?: string; skipped?: boolean }> {
    const title = `${notification['title'] ?? ''}`.trim() || 'ATTA';
    const body = `${notification['body'] ?? ''}`.trim() || 'Новое уведомление';
    const actionType =
      `${(notification['payload'] as Record<string, unknown> | undefined)?.['actionType'] ?? ''}`.trim() ||
      `${notification['type'] ?? ''}`.trim();
    if (device.platform === DevicePlatform.ANDROID) {
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

  private isPermanentPushFailure(result: { status: number; reason?: string }) {
    return (
      ((result.status === 400 || result.status === 410) &&
        (result.reason === 'BadDeviceToken' ||
          result.reason === 'Unregistered' ||
          result.reason === 'DeviceTokenNotForTopic')) ||
      result.reason === 'UNREGISTERED' ||
      result.reason === 'INVALID_ARGUMENT'
    );
  }

  private async deactivateDevice(device: { userId: string; deviceToken: string }) {
    await this.prisma.userDevice.updateMany({
      where: { deviceToken: device.deviceToken, userId: device.userId },
      data: { isActive: false },
    });
  }

}
