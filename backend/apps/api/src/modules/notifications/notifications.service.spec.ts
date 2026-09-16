import { test } from 'node:test';
import assert from 'node:assert/strict';

import { NotificationScope, NotificationType } from '@prisma/client';

import { NotificationsService } from './notifications.service';

const baseDate = new Date('2026-06-30T10:00:00.000Z');

test('listInAppNotifications excludes chat message records', async () => {
  let capturedWhere: Record<string, unknown> | undefined;

  const service = new NotificationsService(
    {} as never,
    {
      userNotification: {
        count: async () => 2,
        findMany: async (args: Record<string, unknown>) => {
          capturedWhere = args['where'] as Record<string, unknown> | undefined;
          return [
            {
              id: 'notif-1',
              userId: 'user-1',
              scope: NotificationScope.PERSONAL,
              title: 'Поддержка',
              body: 'Ответ получен',
              isRead: false,
              createdAt: baseDate,
              type: NotificationType.SUPPORT,
              payload: {},
            },
          ];
        },
      },
      user: {
        findUnique: async () => ({
          lastNotificationsSeenAt: baseDate,
        }),
      },
    } as never,
    { emitNotificationNew: () => undefined } as never,
  );

  const result = await service.listInAppNotifications({
    userId: 'user-1',
    role: 'user',
  } as never);

  assert.deepEqual(capturedWhere, {
    OR: [
      { scope: NotificationScope.GLOBAL },
      { scope: NotificationScope.PERSONAL, userId: 'user-1' },
    ],
    type: {
      notIn: [NotificationType.CHAT_MESSAGE],
    },
  });
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].type, 'support');
});

test('markRead does not allow reading hidden chat notifications', async () => {
  let capturedWhere: Record<string, unknown> | undefined;

  const service = new NotificationsService(
    {} as never,
    {
      userNotification: {
        count: async () => 2,
        findFirst: async (args: Record<string, unknown>) => {
          capturedWhere = args['where'] as Record<string, unknown> | undefined;
          return null;
        },
      },
    } as never,
    { emitNotificationNew: () => undefined } as never,
  );

  await assert.rejects(
    () =>
      service.markRead(
        {
          userId: 'user-1',
          role: 'user',
        } as never,
        'chat-notif-1',
      ),
    /Notification not found/,
  );

  assert.deepEqual(capturedWhere, {
    id: 'chat-notif-1',
    OR: [
      { scope: NotificationScope.GLOBAL },
      { scope: NotificationScope.PERSONAL, userId: 'user-1' },
    ],
    type: {
      notIn: [NotificationType.CHAT_MESSAGE],
    },
  });
});

test('markAllSeen stores seen timestamp and returns updated counters', async () => {
  let userUpdateCalled = false;
  let updateManyCalled = false;

  const service = new NotificationsService(
    {} as never,
    {
      $transaction: async (items: Array<Promise<unknown>>) => Promise.all(items),
      user: {
        update: async () => {
          userUpdateCalled = true;
          return { id: 'user-1' };
        },
      },
      userNotification: {
        count: async () => 2,
        updateMany: async () => {
          updateManyCalled = true;
          return { count: 2 };
        },
      },
    } as never,
    { emitNotificationNew: () => undefined } as never,
  );

  const result = await service.markAllSeen({
    userId: 'user-1',
    role: 'user',
  } as never);

  assert.equal(userUpdateCalled, true);
  assert.equal(updateManyCalled, true);
  assert.equal(result.updated_personal, 2);
  assert.ok(typeof result.global_seen_at === 'string');
});

test('sendToAll keeps media and link payload in serialized notification', async () => {
  const service = new NotificationsService(
    {} as never,
    {
      userNotification: {
        count: async () => 2,
        create: async ({ data }: Record<string, any>) => ({
          id: 'global-1',
          userId: null,
          scope: NotificationScope.GLOBAL,
          title: data.title,
          body: data.body,
          isRead: false,
          createdAt: baseDate,
          type: NotificationType.GENERIC,
          payload: data.payload,
        }),
      },
      chat: { aggregate: async () => ({ _sum: { unreadForBuyer: 3, unreadForSeller: 4 } }) },
      user: { findUnique: async () => ({ lastNotificationsSeenAt: baseDate }) },
      userDevice: {
        findMany: async () => [],
      },
    } as never,
    { emitNotificationNew: () => undefined } as never,
  );

  const result = await service.sendToAll({
    title: 'Новость',
    body: 'Текст',
    payload: {
      description: 'Подробности',
      imageUrl: 'https://cdn.example.com/misc/notification.jpg',
      actionUrl: 'https://t.me/atta_app',
    },
  });

  assert.equal(result.item.payload.description, 'Подробности');
  assert.equal(result.item.payload.actionUrl, 'https://t.me/atta_app');
  assert.equal(
    result.item.payload.imageUrl,
    'https://cdn.example.com/misc/notification.jpg',
  );
});

test('createSystemNotification emits personal realtime event for recipient only', async () => {
  const emitted: Array<{ notification: Record<string, unknown>; userId?: string }> = [];
  const service = new NotificationsService(
    {} as never,
    {
      userNotification: {
        count: async () => 2,
        create: async ({ data }: Record<string, any>) => ({
          id: 'personal-1',
          userId: data.userId,
          scope: NotificationScope.PERSONAL,
          title: data.title,
          body: data.body,
          isRead: false,
          createdAt: baseDate,
          type: NotificationType.SUPPORT,
          payload: data.payload,
        }),
      },
      chat: { aggregate: async () => ({ _sum: { unreadForBuyer: 3, unreadForSeller: 4 } }) },
      user: { findUnique: async () => ({ lastNotificationsSeenAt: baseDate }) },
      userDevice: {
        findMany: async () => [],
      },
    } as never,
    {
      emitNotificationNew: (
        notification: Record<string, unknown>,
        userId?: string,
      ) => {
        emitted.push({ notification, userId });
      },
    } as never,
  );

  const item = await service.createSystemNotification({
    userId: 'user-42',
    title: 'Ответ поддержки',
    body: 'Новое сообщение',
    type: NotificationType.SUPPORT,
    payload: {
      actionType: 'support_reply',
      ticketId: 'ticket-1',
    },
  });

  assert.equal(item.userId, 'user-42');
  assert.equal(emitted.length, 1);
  assert.equal(emitted[0].userId, 'user-42');
  assert.equal(emitted[0].notification['scope'], 'personal');
});

test('chat message push sends absolute APNs badge count', async () => {
  const pushes: Array<Record<string, unknown>> = [];
  const service = new NotificationsService(
    {
      send: async (push: Record<string, unknown>) => {
        pushes.push(push);
        return { sent: true, status: 200 };
      },
    } as never,
    {
      userNotification: { count: async () => 2 },
      chat: { aggregate: async () => ({ _sum: { unreadForBuyer: 3, unreadForSeller: 4 } }) },
      user: { findUnique: async () => ({ lastNotificationsSeenAt: baseDate }) },
      userDevice: {
        findMany: async () => [
          {
            userId: 'user-1',
            deviceToken: 'ios-token-1',
          },
          {
            userId: 'user-1',
            deviceToken: 'ios-token-2',
          },
        ],
      },
    } as never,
    { emitNotificationNew: () => undefined } as never,
  );

  await service.sendChatMessagePush({
    recipientId: 'user-1',
    message: {
      id: 'message-1',
      chatId: 'chat-1',
      senderId: 'user-2',
      text: 'Привет',
      createdAt: baseDate.toISOString(),
    },
    chat: {
      id: 'chat-1',
    },
    unreadTotal: 7,
  });

  assert.equal(pushes.length, 2);
  assert.deepEqual(
    pushes.map((push) => push['badge']),
    [9, 9],
  );
});

test('createSystemNotification keeps in-app notification when APNs send throws', async () => {
  const warnings: string[] = [];
  let notificationCreated = false;
  const emitted: Array<{ notification: Record<string, unknown>; userId?: string }> = [];
  const service = new NotificationsService(
    {
      send: async () => {
        throw new Error('APNs unavailable');
      },
    } as never,
    {
      userNotification: {
        count: async () => 2,
        create: async ({ data }: Record<string, any>) => {
          notificationCreated = true;
          return {
            id: 'personal-apns-fail-1',
            userId: data.userId,
            scope: NotificationScope.PERSONAL,
            title: data.title,
            body: data.body,
            isRead: false,
            createdAt: baseDate,
            type: data.type,
            payload: data.payload,
          };
        },
      },
      chat: { aggregate: async () => ({ _sum: { unreadForBuyer: 3, unreadForSeller: 4 } }) },
      user: { findUnique: async () => ({ lastNotificationsSeenAt: baseDate }) },
      userDevice: {
        findMany: async () => [
          {
            userId: 'user-1',
            deviceToken: 'secret-device-token',
          },
        ],
      },
    } as never,
    {
      emitNotificationNew: (
        notification: Record<string, unknown>,
        userId?: string,
      ) => {
        emitted.push({ notification, userId });
      },
    } as never,
  );
  (service as unknown as { logger: { warn: (message: string) => void } }).logger = {
    warn: (message: string) => warnings.push(message),
  };

  const item = await service.createSystemNotification({
    userId: 'user-1',
    title: 'Модерация',
    body: 'Объявление одобрено',
    type: NotificationType.MODERATION,
    payload: {
      actionType: 'listing_approved',
      listingId: 'listing-1',
    },
  });

  assert.equal(notificationCreated, true);
  assert.equal(item.id, 'personal-apns-fail-1');
  assert.equal(emitted.length, 1);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /unexpected send failure/);
  assert.doesNotMatch(warnings[0], /secret-device-token/);
});

test('sendToAll returns success when APNs send throws', async () => {
  const warnings: string[] = [];
  const service = new NotificationsService(
    {
      send: async () => {
        throw new Error('APNs unavailable');
      },
    } as never,
    {
      userNotification: {
        count: async () => 2,
        create: async ({ data }: Record<string, any>) => ({
          id: 'global-apns-fail-1',
          userId: null,
          scope: NotificationScope.GLOBAL,
          title: data.title,
          body: data.body,
          isRead: false,
          createdAt: baseDate,
          type: NotificationType.GENERIC,
          payload: data.payload,
        }),
      },
      chat: { aggregate: async () => ({ _sum: { unreadForBuyer: 3, unreadForSeller: 4 } }) },
      user: { findUnique: async () => ({ lastNotificationsSeenAt: baseDate }) },
      userDevice: {
        findMany: async () => [
          {
            userId: 'user-1',
            deviceToken: 'secret-device-token-1',
          },
          {
            userId: 'user-2',
            deviceToken: 'secret-device-token-2',
          },
        ],
      },
    } as never,
    { emitNotificationNew: () => undefined } as never,
  );
  (service as unknown as { logger: { warn: (message: string) => void } }).logger = {
    warn: (message: string) => warnings.push(message),
  };

  const result = await service.sendToAll({
    title: 'Новость',
    body: 'Глобальное уведомление',
  });

  assert.equal(result.item.id, 'global-apns-fail-1');
  assert.equal(warnings.length, 1);
  assert.doesNotMatch(warnings[0], /secret-device-token/);
});

test('chat message push returns when APNs send throws', async () => {
  const warnings: string[] = [];
  const service = new NotificationsService(
    {
      send: async () => {
        throw new Error('APNs unavailable');
      },
    } as never,
    {
      userNotification: { count: async () => 2 },
      chat: { aggregate: async () => ({ _sum: { unreadForBuyer: 3, unreadForSeller: 4 } }) },
      user: { findUnique: async () => ({ lastNotificationsSeenAt: baseDate }) },
      userDevice: {
        findMany: async () => [
          {
            userId: 'user-1',
            deviceToken: 'secret-device-token',
          },
        ],
      },
    } as never,
    { emitNotificationNew: () => undefined } as never,
  );
  (service as unknown as { logger: { warn: (message: string) => void } }).logger = {
    warn: (message: string) => warnings.push(message),
  };

  await service.sendChatMessagePush({
    recipientId: 'user-1',
    message: {
      id: 'message-1',
      chatId: 'chat-1',
      senderId: 'user-2',
      text: 'Привет',
      createdAt: baseDate.toISOString(),
    },
    chat: {
      id: 'chat-1',
    },
    unreadTotal: 2,
  });

  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /unexpected send failure/);
  assert.doesNotMatch(warnings[0], /secret-device-token/);
});

test('canonical badge sums chat counters and non-chat unread notifications with per-user global cutoff', async () => {
  let where: any;
  const service = new NotificationsService({} as never, {
    chat: { aggregate: async ({ where }: any) => ({ _sum: where.buyerId ? { unreadForBuyer: 2 } : { unreadForSeller: 3 } }) },
    user: { findUnique: async () => ({ lastNotificationsSeenAt: baseDate }) },
    userNotification: { count: async (args: any) => { where = args.where; return 4; } },
  } as never, {} as never);
  assert.equal(await service.canonicalBadgeCount('A'), 9);
  assert.deepEqual(where.type, { notIn: [NotificationType.CHAT_MESSAGE] });
  assert.deepEqual(where.OR[0], { userId: 'A', scope: NotificationScope.PERSONAL, isRead: false });
  assert.equal(where.OR[1].createdAt.gt, baseDate);
});

test('token registration reassigns same device to B session; late A delete cannot deactivate B', async () => {
  let device: any;
  const prisma: any = {
    $queryRaw: async () => [],
    userSession: { findFirst: async ({ where }: any) => ({ id: where.id, createdAt: new Date(where.id === 'session-A' ? '2026-01-01' : '2026-02-01') }) },
    userDevice: {
      findUnique: async () => device ? { ...device, session: { createdAt: new Date(device.sessionId === 'session-A' ? '2026-01-01' : '2026-02-01') } } : null,
      upsert: async ({ update }: any) => { device = { ...update, id: 'd' }; return device; },
      updateMany: async ({ where, data }: any) => {
        if (device.userId !== where.userId) return { count: 0 };
        Object.assign(device, data); return { count: 1 };
      },
    },
  };
  prisma.$transaction = async (fn: any) => fn(prisma);
  const service = new NotificationsService({} as never, prisma, {} as never);
  await service.registerDevice({ userId: 'A', sessionId: 'session-A' } as never, { token: 'same', platform: 'ios' });
  assert.equal(device.sessionId, 'session-A');
  await service.registerDevice({ userId: 'B', sessionId: 'session-B' } as never, { token: 'same', platform: 'ios' });
  await service.unregisterDevice({ userId: 'A' } as never, 'same');
  await assert.rejects(() => service.registerDevice({ userId: 'A', sessionId: 'session-A' } as never, { token: 'same', platform: 'ios' }), /newer session/);
  assert.equal(device.userId, 'B'); assert.equal(device.sessionId, 'session-B'); assert.equal(device.isActive, true);
});
