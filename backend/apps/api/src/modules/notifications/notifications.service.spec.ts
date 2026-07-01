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
        findFirst: async (args: Record<string, unknown>) => {
          capturedWhere = args['where'] as Record<string, unknown> | undefined;
          return null;
        },
      },
    } as never,
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
        updateMany: async () => {
          updateManyCalled = true;
          return { count: 2 };
        },
      },
    } as never,
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
