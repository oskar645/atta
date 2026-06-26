import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { NotificationScope, NotificationType, Prisma } from '@prisma/client';

import { AuthenticatedUser } from '../auth/auth.types';
import { ApnsService } from '../apns/apns.service';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class NotificationsService {
  constructor(
    private readonly apnsService: ApnsService,
    private readonly prisma: PrismaService,
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
    const payload =
      item.payload && typeof item.payload === 'object' && !Array.isArray(item.payload)
        ? (item.payload as Record<string, unknown>)
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
      sender_avatar_url:
        `${payload.senderAvatarUrl ?? ''}`.trim() || null,
      senderAvatarUrl:
        `${payload.senderAvatarUrl ?? ''}`.trim() || null,
    };
  }

  async listInAppNotifications(authUser: AuthenticatedUser) {
    const items = await this.prisma.userNotification.findMany({
      where: {
        OR: [
          { scope: NotificationScope.GLOBAL },
          { scope: NotificationScope.PERSONAL, userId: authUser.userId },
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

  async sendToUser(body: {
    userId?: string;
    title?: string;
    body?: string;
    type?: string;
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

  async sendToAll(body: { title?: string; body?: string; type?: string }) {
    const item = await this.prisma.userNotification.create({
      data: {
        userId: null,
        scope: NotificationScope.GLOBAL,
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

  async createSystemNotification(params: {
    userId: string;
    title: string;
    body: string;
    type?: NotificationType;
    payload?: Record<string, unknown>;
  }) {
    return this.prisma.userNotification.create({
      data: {
        userId: params.userId,
        scope: NotificationScope.PERSONAL,
        title: params.title.trim(),
        body: params.body.trim(),
        type: params.type ?? NotificationType.GENERIC,
        payload: (params.payload ?? {}) as Prisma.InputJsonValue,
      },
    });
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
        OR: [
          { userId: authUser.userId },
          { scope: NotificationScope.GLOBAL },
        ],
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
