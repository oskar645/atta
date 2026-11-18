import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { Prisma, SupportSenderType, SupportTicketStatus } from '@prisma/client';

import { SupportService } from './support.service';

const now = new Date('2026-08-04T10:00:00.000Z');

function createTicket(overrides: Record<string, unknown> = {}) {
  return {
    id: 'ticket-1',
    userId: 'user-1',
    name: 'Иван',
    subject: 'Обращение в поддержку',
    status: SupportTicketStatus.OPEN,
    lastMessage: '',
    unreadForAdmin: false,
    unreadForUser: false,
    userBlockId: null,
    isBlockAppeal: false,
    createdAt: now,
    updatedAt: now,
    ...overrides,
  };
}

function createMessage(overrides: Record<string, unknown> = {}) {
  return {
    id: 'message-1',
    ticketId: 'ticket-1',
    sender: SupportSenderType.ADMIN,
    senderUserId: null,
    text: 'Здравствуйте',
    idempotencyKey: 'support_admin_contact:user-1:req-1',
    readAt: null,
    editedAt: null,
    editedByUserId: null,
    deletedAt: null,
    deletedByUserId: null,
    createdAt: now,
    ...overrides,
  };
}

function createService(
  prisma: Record<string, unknown>,
  notifications: Record<string, unknown> = {},
  dashboardSignal?: { changed: (...scopes: string[]) => void },
) {
  return new SupportService(
    prisma as never,
    {
      createSystemNotification: async () => undefined,
      ...notifications,
    } as never,
    {} as never,
    dashboardSignal as never,
  );
}

test('support image validation accepts real JPEG, PNG and WebP signatures', () => {
  const service = createService({});
  const cases = [
    { mimetype: 'image/jpeg', buffer: Buffer.from([0xff, 0xd8, 0xff]) },
    { mimetype: 'image/png', buffer: Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) },
    { mimetype: 'image/webp', buffer: Buffer.from('RIFFxxxxWEBP', 'ascii') },
  ];

  for (const item of cases) {
    const file = { ...item, size: item.buffer.length, originalname: 'image' };
    assert.equal(service.requireImage(file, 1024), file);
  }
});

test('support image validation rejects a forged image MIME type', () => {
  const service = createService({});
  assert.throws(
    () => service.requireImage({
      buffer: Buffer.from('not an image'),
      mimetype: 'image/jpeg',
      size: 12,
      originalname: 'payload.jpg',
    }, 1024),
    (error: unknown) =>
      error instanceof BadRequestException &&
      error.message === 'Файл не является корректным изображением',
  );
});

test('admin first message creates support ticket, message and notification payload', async () => {
  const notifications: Array<Record<string, unknown>> = [];
  const ticket = createTicket();
  const message = createMessage();
  let ticketCreateCalls = 0;
  let messageCreateCalls = 0;
  const dashboardScopes: string[][] = [];

  const tx = {
    $executeRaw: async () => undefined,
    supportMessage: {
      findUnique: async () => null,
      create: async () => {
        messageCreateCalls += 1;
        return message;
      },
    },
    supportTicket: {
      findFirst: async () => null,
      create: async () => {
        ticketCreateCalls += 1;
        return ticket;
      },
      update: async () => ({
        ...ticket,
        lastMessage: 'Здравствуйте',
        unreadForUser: true,
      }),
    },
  };

  const service = createService(
    {
      user: {
        findUnique: async () => ({
          id: 'user-1',
          displayName: 'Иван',
          name: '',
          phone: '79990000000',
        }),
      },
      supportMessage: {
        findUnique: async () => null,
      },
      $transaction: async (callback: (txArg: typeof tx) => Promise<unknown>) =>
        callback(tx),
    },
    {
      createSystemNotification: async (params: Record<string, unknown>) => {
        notifications.push(params);
      },
    },
    { changed: (...scopes) => dashboardScopes.push(scopes) },
  );

  const result = await service.openTicketForAdminContact({
    userId: 'user-1',
    text: '  Здравствуйте  ',
    idempotencyKey: 'req-1',
  });

  assert.equal(result.ticketId, 'ticket-1');
  assert.equal(result.messageId, 'message-1');
  assert.equal(result.created, true);
  assert.equal(ticketCreateCalls, 1);
  assert.equal(messageCreateCalls, 1);
  assert.equal(notifications.length, 1);
  assert.deepEqual(notifications[0]?.['payload'], {
    type: 'support_message',
    actionType: 'support_message',
    ticketId: 'ticket-1',
    userId: 'user-1',
    messageId: 'message-1',
  });
  assert.deepEqual(dashboardScopes, [['support']]);
});

test('admin message reuses existing OPEN support ticket', async () => {
  const existingTicket = createTicket({ id: 'ticket-open' });
  let ticketCreateCalls = 0;

  const tx = {
    $executeRaw: async () => undefined,
    supportMessage: {
      findUnique: async () => null,
      create: async () => createMessage({ ticketId: 'ticket-open' }),
    },
    supportTicket: {
      findFirst: async () => existingTicket,
      create: async () => {
        ticketCreateCalls += 1;
        return existingTicket;
      },
      update: async () => existingTicket,
    },
  };

  const service = createService({
    user: {
      findUnique: async () => ({ id: 'user-1', displayName: 'Иван' }),
    },
    supportMessage: {
      findUnique: async () => null,
    },
    $transaction: async (callback: (txArg: typeof tx) => Promise<unknown>) =>
      callback(tx),
  });

  const result = await service.openTicketForAdminContact({
    userId: 'user-1',
    text: 'Повторное сообщение',
    idempotencyKey: 'req-2',
  });

  assert.equal(result.ticketId, 'ticket-open');
  assert.equal(result.created, false);
  assert.equal(ticketCreateCalls, 0);
});

test('admin duplicate idempotency key returns existing support message without notification', async () => {
  const existing = {
    ...createMessage(),
    ticket: createTicket(),
  };
  let transactionCalled = false;
  let notificationCalls = 0;

  const service = createService(
    {
      user: {
        findUnique: async () => ({ id: 'user-1', displayName: 'Иван' }),
      },
      supportMessage: {
        findUnique: async () => existing,
      },
      $transaction: async () => {
        transactionCalled = true;
      },
    },
    {
      createSystemNotification: async () => {
        notificationCalls += 1;
      },
    },
  );

  const result = await service.openTicketForAdminContact({
    userId: 'user-1',
    text: 'Здравствуйте',
    idempotencyKey: 'req-1',
  });

  assert.equal(result.ticketId, 'ticket-1');
  assert.equal(result.messageId, 'message-1');
  assert.equal(result.created, false);
  assert.equal(transactionCalled, false);
  assert.equal(notificationCalls, 0);
});

test('user message marks ticket unread and notifies admins once', async () => {
  const dashboardScopes: string[][] = [];
  const adminNotifications: Array<Record<string, unknown>> = [];
  const ticket = createTicket();
  const message = createMessage({
    id: 'user-message-1',
    sender: SupportSenderType.USER,
    senderUserId: 'user-1',
  });
  let updateData: Record<string, unknown> | undefined;
  const tx = {
    supportMessage: { create: async () => message },
    supportTicket: {
      update: async ({ data }: { data: Record<string, unknown> }) => {
        updateData = data;
        return { ...ticket, ...data };
      },
    },
  };
  const service = createService(
    {
      supportTicket: {
        findFirst: async () => ticket,
      },
      supportMessage: { findUnique: async () => null },
      $transaction: async (callback: (value: typeof tx) => Promise<unknown>) =>
        callback(tx),
    },
    {
      createAdminEventNotifications: async (params: Record<string, unknown>) => {
        adminNotifications.push(params);
      },
    },
    { changed: (...scopes) => dashboardScopes.push(scopes) },
  );

  await service.sendMessageAsUser(
    { userId: 'user-1' } as never,
    'ticket-1',
    'Нужна помощь',
  );

  assert.equal(updateData?.['unreadForAdmin'], true);
  assert.deepEqual(dashboardScopes, [['support']]);
  assert.equal(adminNotifications.length, 1);
  assert.equal(adminNotifications[0]?.['eventKey'], 'admin_support:message:user-message-1');
  assert.deepEqual(adminNotifications[0]?.['payload'], {
    actionType: 'admin_support_new',
    ticketId: 'ticket-1',
  });
});

test('markReadByAdmin clears server unread state and invalidates support', async () => {
  const dashboardScopes: string[][] = [];
  let updateData: Record<string, unknown> | undefined;
  const service = createService(
    {
      supportTicket: {
        update: async ({ data }: { data: Record<string, unknown> }) => {
          updateData = data;
          return createTicket({ ...data, unreadForAdmin: false });
        },
      },
    },
    {},
    { changed: (...scopes) => dashboardScopes.push(scopes) },
  );

  const result = await service.markReadByAdmin('ticket-1');

  assert.equal(updateData?.['unreadForAdmin'], false);
  assert.equal(result.ticket.unread_for_admin, false);
  assert.deepEqual(dashboardScopes, [['support']]);
});

test('duplicate user idempotency key returns original message without another transaction', async () => {
  const ticket = createTicket();
  const existing = createMessage({
    sender: SupportSenderType.USER,
    senderUserId: 'user-1',
    text: 'Повтор',
    idempotencyKey: 'operation-1',
  });
  let transactionCalls = 0;
  const service = createService({
    supportTicket: { findFirst: async () => ticket },
    supportMessage: { findUnique: async () => existing },
    $transaction: async () => {
      transactionCalls += 1;
    },
  });

  const result = await service.sendMessageAsUser(
    { userId: 'user-1' } as never,
    'ticket-1',
    'Повтор',
    undefined,
    'operation-1',
  );

  assert.equal(result.item.id, existing.id);
  assert.equal(transactionCalls, 0);
});

test('concurrent user requests recover from the unique-key race without a duplicate', async () => {
  const ticket = createTicket();
  const existing = createMessage({
    sender: SupportSenderType.USER,
    senderUserId: 'user-1',
    text: 'Одновременная отправка',
    idempotencyKey: 'operation-race',
  });
  let lookupCalls = 0;
  let notificationCalls = 0;
  const service = createService(
    {
      supportTicket: { findFirst: async () => ticket },
      supportMessage: {
        findUnique: async () => (++lookupCalls === 1 ? null : existing),
      },
      $transaction: async () => {
        throw new Prisma.PrismaClientKnownRequestError('duplicate key', {
          code: 'P2002',
          clientVersion: 'test',
        });
      },
    },
    {
      createSystemNotification: async () => {
        notificationCalls += 1;
      },
    },
  );

  const result = await service.sendMessageAsUser(
    { userId: 'user-1' } as never,
    'ticket-1',
    'Одновременная отправка',
    undefined,
    'operation-race',
  );

  assert.equal(result.item.id, existing.id);
  assert.equal(lookupCalls, 2);
  assert.equal(notificationCalls, 0);
});

test('same idempotency key with different content is rejected', async () => {
  const ticket = createTicket();
  const existing = createMessage({
    sender: SupportSenderType.USER,
    senderUserId: 'user-1',
    text: 'Первый текст',
    idempotencyKey: 'operation-1',
  });
  const service = createService({
    supportTicket: { findFirst: async () => ticket },
    supportMessage: { findUnique: async () => existing },
  });

  await assert.rejects(
    service.sendMessageAsUser(
      { userId: 'user-1' } as never,
      'ticket-1',
      'Другой текст',
      undefined,
      'operation-1',
    ),
    ConflictException,
  );
});

test('admin message stays successful when user notification fails after commit', async () => {
  const ticket = createTicket();
  const message = createMessage({
    senderUserId: 'admin-1',
    idempotencyKey: 'admin-operation-1',
  });
  const tx = {
    supportMessage: { create: async () => message },
    supportTicket: { update: async () => ticket },
  };
  const service = createService(
    {
      supportTicket: { findUnique: async () => ticket },
      supportMessage: { findUnique: async () => null },
      $transaction: async (callback: (value: typeof tx) => Promise<unknown>) =>
        callback(tx),
    },
    {
      createSystemNotification: async () => {
        throw new Error('push unavailable');
      },
    },
  );

  const result = await service.sendMessageAsAdmin(
    { userId: 'admin-1' } as never,
    'ticket-1',
    'Здравствуйте',
    undefined,
    'admin-operation-1',
  );

  assert.equal(result.item.id, message.id);
});

test('admin cannot edit legacy or foreign support message', async () => {
  const tx = {
    $executeRaw: async () => 1,
    supportMessage: {
      findFirst: async () => createMessage({ senderUserId: null }),
    },
  };
  const service = createService({
    $transaction: async (callback: (value: typeof tx) => Promise<unknown>) =>
      callback(tx),
  });

  await assert.rejects(
    service.editMessageAsAdmin(
      { userId: 'admin-1' } as never,
      'ticket-1',
      'message-1',
      'Исправление',
    ),
    NotFoundException,
  );
});

test('user marks a concrete admin support message as read', async () => {
  const ticket = createTicket({ unreadForUser: true });
  const message = createMessage();
  let ticketReadCleared = false;
  const tx = {
    $executeRaw: async () => 1,
    supportMessage: {
      findFirst: async () => message,
      update: async () => ({ ...message, readAt: now }),
      count: async () => 0,
    },
    supportTicket: {
      update: async () => {
        ticketReadCleared = true;
        return ticket;
      },
    },
  };
  const service = createService({
    supportTicket: { findFirst: async () => ticket },
    supportMessage: { findFirst: async () => message },
    $transaction: async (callback: (value: typeof tx) => Promise<unknown>) =>
      callback(tx),
  });

  const result = await service.markMessageReadByUser(
    { userId: 'user-1' } as never,
    'ticket-1',
    'message-1',
  );

  assert.equal(result.item.read_at, now.toISOString());
  assert.equal(ticketReadCleared, true);
});

test('own admin message is edited with an audit revision', async () => {
  const ticket = createTicket();
  const message = createMessage({ senderUserId: 'admin-1' });
  let revisionText = '';
  const updated = { ...message, text: 'Исправлено', editedAt: now };
  const tx = {
    $executeRaw: async () => 1,
    supportMessageRevision: {
      create: async ({ data }: { data: { previousText: string } }) => {
        revisionText = data.previousText;
      },
    },
    supportMessage: {
      update: async () => updated,
      findFirst: (() => {
        let calls = 0;
        return async () => (calls++ === 0 ? message : updated);
      })(),
    },
    supportTicket: { update: async () => ticket },
  };
  const service = createService({
    supportMessage: { findFirst: async () => message },
    supportTicket: { findUnique: async () => ticket },
    $transaction: async (callback: (value: typeof tx) => Promise<unknown>) =>
      callback(tx),
  });

  const result = await service.editMessageAsAdmin(
    { userId: 'admin-1' } as never,
    'ticket-1',
    'message-1',
    'Исправлено',
  );

  assert.equal(revisionText, 'Здравствуйте');
  assert.equal(result.item.text, 'Исправлено');
  assert.equal(result.item.edited_at, now.toISOString());
});

test('own admin message is soft deleted without exposing old text', async () => {
  const ticket = createTicket();
  const message = createMessage({ senderUserId: 'admin-1' });
  const deleted = { ...message, deletedAt: now, deletedByUserId: 'admin-1' };
  const tx = {
    $executeRaw: async () => 1,
    supportMessageRevision: { create: async () => undefined },
    supportMessage: {
      update: async () => deleted,
      findFirst: (() => {
        let calls = 0;
        return async () => (calls++ === 0 ? message : null);
      })(),
    },
    supportTicket: { update: async () => ticket },
  };
  const service = createService({
    supportMessage: { findFirst: async () => message },
    supportTicket: { findUnique: async () => ticket },
    $transaction: async (callback: (value: typeof tx) => Promise<unknown>) =>
      callback(tx),
  });

  const result = await service.deleteMessageAsAdmin(
    { userId: 'admin-1' } as never,
    'ticket-1',
    'message-1',
  );

  assert.equal(result.item.text, '');
  assert.equal(result.item.deleted_at, now.toISOString());
});
