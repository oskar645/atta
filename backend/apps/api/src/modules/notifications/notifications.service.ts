import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { NotificationScope, NotificationType, Prisma } from '@prisma/client';

import { normalizeStoredMediaUrl } from '../../common/serializers';
import { AuthenticatedUser } from '../auth/auth.types';
import { ApnsService } from '../apns/apns.service';
import { ChatsGateway } from '../chats/chats.gateway';
import { PrismaService } from '../prisma/prisma.service';

const excludedInAppNotificationTypes = [NotificationType.CHAT_MESSAGE];

@Injectable()
export class NotificationsService {
  constructor(
    private readonly apnsService: ApnsService,
    private readonly prisma: PrismaService,
    private readonly chatsGateway: ChatsGateway,
  ) {}

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
    this.chatsGateway.emitNotificationNew(
      this.serialize(item),
      params.userId.trim(),
    );
    return item;
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
}
