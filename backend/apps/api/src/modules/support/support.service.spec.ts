import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SupportSenderType, SupportTicketStatus } from '@prisma/client';

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
    createdAt: now,
    ...overrides,
  };
}

function createService(prisma: Record<string, unknown>, notifications: Record<string, unknown> = {}) {
  return new SupportService(
    prisma as never,
    {
      createSystemNotification: async () => undefined,
      ...notifications,
    } as never,
    {} as never,
  );
}

test('admin first message creates support ticket, message and notification payload', async () => {
  const notifications: Array<Record<string, unknown>> = [];
  const ticket = createTicket();
  const message = createMessage();
  let ticketCreateCalls = 0;
  let messageCreateCalls = 0;

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
