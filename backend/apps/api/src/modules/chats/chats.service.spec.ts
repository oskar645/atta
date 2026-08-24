import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ChatsService } from './chats.service';

const baseDate = new Date('2026-06-19T10:00:00.000Z');

function createChat() {
  return {
    id: 'chat-1',
    listingId: 'listing-1',
    listingTitle: 'Объявление',
    buyerId: 'buyer-1',
    sellerId: 'seller-1',
    lastMessage: '',
    lastMessageType: 'TEXT',
    lastMessageAt: baseDate,
    unreadForBuyer: 0,
    unreadForSeller: 0,
    deletedByBuyerAt: null,
    deletedBySellerAt: null,
    createdAt: baseDate,
    updatedAt: baseDate,
    listing: {
      id: 'listing-1',
      title: 'Объявление',
      photos: [],
    },
    buyer: {
      id: 'buyer-1',
      displayName: 'Покупатель',
      name: 'Покупатель',
      email: 'buyer@example.com',
      avatarUrl: null,
      photoUrl: null,
    },
    seller: {
      id: 'seller-1',
      displayName: 'Иван',
      name: 'Иван Продавец',
      email: 'seller@example.com',
      avatarUrl: 'https://cdn.example.com/avatar.jpg',
      photoUrl: null,
    },
  };
}

function createMessage() {
  return {
    id: 'message-1',
    chatId: 'chat-1',
    senderId: 'seller-1',
    clientMessageId: null,
    messageType: 'TEXT',
    text: 'Здравствуйте',
    imageBucket: null,
    imageKey: null,
    imageUrl: null,
    deliveredAt: null,
    readAt: null,
    deletedAt: null,
    createdAt: baseDate,
    updatedAt: baseDate,
    chat: createChat(),
  };
}

function chatAggregate(sum: Record<string, number | null> = {}) {
  return async () => ({
    _sum: {
      unreadForBuyer: sum.unreadForBuyer ?? null,
      unreadForSeller: sum.unreadForSeller ?? null,
    },
  });
}

test('sendMessage updates chats without creating in-app notification', async () => {
  const chatUpdateCalls: Array<Record<string, unknown>> = [];
  const prisma = {
    chat: {
      findUnique: async () => createChat(),
      aggregate: chatAggregate({ unreadForBuyer: 1, unreadForSeller: 0 }),
    },
    $transaction: async (
      callback: (tx: {
        chatMessage: { create: () => Promise<ReturnType<typeof createMessage>> };
        chat: {
          update: (args: Record<string, unknown>) => Promise<void>;
          findUniqueOrThrow: () => Promise<ReturnType<typeof createChat>>;
        };
      }) => Promise<unknown>,
    ) =>
      callback({
        chatMessage: {
          create: async () => createMessage(),
        },
        chat: {
          update: async (args: Record<string, unknown>) => {
            chatUpdateCalls.push(args);
            return undefined;
          },
          findUniqueOrThrow: async () => createChat(),
        },
      }),
  };

  const service = new ChatsService(
    prisma as never,
    {
      getPresenceMap: async () => new Map(),
    } as never,
    {
      buildProtectedChatUrl: () => '',
    } as never,
    {
      assertNotBlocked: async () => undefined,
    } as never,
  );

  const result = await service.sendMessage(
    {
      userId: 'seller-1',
      role: 'user',
    } as never,
    'chat-1',
    {
      text: 'Здравствуйте',
    },
  );

  assert.equal(result.recipientId, 'buyer-1');
  assert.equal(result.message.id, 'message-1');
  assert.equal(result.recipientUnreadTotal, 1);
  assert.equal(result.created, true);
  assert.deepEqual(chatUpdateCalls[0]?.['data'], {
    lastMessage: 'Здравствуйте',
    lastMessageType: 'TEXT',
    lastMessageAt: baseDate,
    unreadForBuyer: { increment: 1 },
    unreadForSeller: undefined,
    deletedByBuyerAt: null,
    deletedBySellerAt: null,
  });
});

test('sendMessage with duplicate clientMessageId returns existing message once', async () => {
  const existingMessage = {
    ...createMessage(),
    clientMessageId: '7d1b7418-8080-4dde-bdb8-64551a986d53',
  };
  let createCalled = false;

  const service = new ChatsService(
    {
      chat: {
        findUnique: async () => createChat(),
        aggregate: chatAggregate(),
      },
      chatMessage: {
        findFirst: async () => existingMessage,
        create: async () => {
          createCalled = true;
          return existingMessage;
        },
      },
      $transaction: async () => {
        throw new Error('transaction should not run for duplicate clientMessageId');
      },
    } as never,
    {
      getPresenceMap: async () => new Map(),
    } as never,
    {
      buildProtectedChatUrl: () => '',
    } as never,
  );

  const result = await service.sendMessage(
    {
      userId: 'seller-1',
      role: 'user',
    } as never,
    'chat-1',
    {
      text: 'Здравствуйте',
      clientMessageId: '7d1b7418-8080-4dde-bdb8-64551a986d53',
    },
  );

  assert.equal(result.message.id, 'message-1');
  assert.equal(result.created, false);
  assert.equal(
    result.message.clientMessageId,
    '7d1b7418-8080-4dde-bdb8-64551a986d53',
  );
  assert.equal(createCalled, false);
});

test('sendMessage allows repeated identical text without content-based spam blocking', async () => {
  let createCount = 0;
  const service = new ChatsService(
    {
      chat: {
        findUnique: async () => createChat(),
        aggregate: chatAggregate({ unreadForBuyer: 0, unreadForSeller: 0 }),
      },
      $transaction: async (
        callback: (tx: {
          chatMessage: { create: () => Promise<ReturnType<typeof createMessage>> };
          chat: {
            update: () => Promise<void>;
            findUniqueOrThrow: () => Promise<ReturnType<typeof createChat>>;
          };
        }) => Promise<unknown>,
      ) =>
        callback({
          chatMessage: {
            create: async () => ({
              ...createMessage(),
              id: `message-${++createCount}`,
            }),
          },
          chat: {
            update: async () => undefined,
            findUniqueOrThrow: async () => createChat(),
          },
        }),
    } as never,
    {
      getPresenceMap: async () => new Map(),
    } as never,
    {} as never,
  );

  for (let index = 0; index < 10; index += 1) {
    const result = await service.sendMessage(
      {
        userId: 'seller-1',
        role: 'user',
      } as never,
      'chat-1',
      {
        text: 'Здравствуйте',
      },
    );
    assert.equal(result.created, true);
  }

  assert.equal(createCount, 10);
});

test('sendMessage rejects when either participant has peer-blocked the other', async () => {
  let createCalled = false;
  const service = new ChatsService(
    {
      chat: {
        findUnique: async () => createChat(),
      },
      chatPeerBlock: {
        findFirst: async () => ({
          id: 'block-1',
          blockerUserId: 'buyer-1',
          blockedUserId: 'seller-1',
          createdAt: baseDate,
        }),
      },
      $transaction: async () => {
        createCalled = true;
      },
    } as never,
    {
      getPresenceMap: async () => new Map(),
    } as never,
    {} as never,
  );

  await assert.rejects(
    () =>
      service.sendMessage(
        {
          userId: 'seller-1',
          role: 'user',
        } as never,
        'chat-1',
        {
          text: 'Здравствуйте',
        },
      ),
    /Пользователь заблокирован/,
  );
  assert.equal(createCalled, false);
});

test('hideChatForMe only marks the current participant deleted marker', async () => {
  const updates: Array<Record<string, unknown>> = [];
  const service = new ChatsService(
    {
      chat: {
        findUnique: async () => createChat(),
        update: async (args: Record<string, unknown>) => {
          updates.push(args);
          return {
            ...createChat(),
            deletedByBuyerAt: new Date('2026-08-20T12:00:00.000Z'),
          };
        },
        aggregate: chatAggregate({ unreadForBuyer: 0, unreadForSeller: 0 }),
      },
    } as never,
    {
      getPresenceMap: async () => new Map(),
    } as never,
    {
      buildProtectedChatUrl: () => '',
    } as never,
  );

  const result = await service.hideChatForMe(
    {
      userId: 'buyer-1',
      role: 'user',
    } as never,
    'chat-1',
  );

  assert.equal(result.hidden, true);
  assert.equal(result.viewerId, 'buyer-1');
  assert.equal(updates.length, 1);
  assert.deepEqual(Object.keys(updates[0]?.['data'] as Record<string, unknown>), [
    'deletedByBuyerAt',
    'unreadForBuyer',
  ]);
});

test('listChats sorts by lastMessageAt desc and keeps empty chats below', async () => {
  const oldChat = {
    ...createChat(),
    id: 'chat-old',
    lastMessageAt: new Date('2026-06-19T09:00:00.000Z'),
    updatedAt: new Date('2026-06-19T11:30:00.000Z'),
  };
  const freshChat = {
    ...createChat(),
    id: 'chat-fresh',
    lastMessageAt: new Date('2026-06-19T11:00:00.000Z'),
    updatedAt: new Date('2026-06-19T11:00:00.000Z'),
  };
  const emptyChat = {
    ...createChat(),
    id: 'chat-empty',
    lastMessageAt: null,
    createdAt: new Date('2026-06-19T12:00:00.000Z'),
    updatedAt: new Date('2026-06-19T12:30:00.000Z'),
  };

  const service = new ChatsService(
    {
      chat: {
        findMany: async () => [oldChat, emptyChat, freshChat],
        aggregate: chatAggregate({ unreadForBuyer: 0, unreadForSeller: 0 }),
      },
    } as never,
    {
      getPresenceMap: async () => new Map(),
    } as never,
    {} as never,
  );

  const result = await service.listChats({
    userId: 'buyer-1',
    role: 'user',
  } as never);

  assert.deepEqual(
    result.items.map((item: { id: string }) => item.id),
    ['chat-fresh', 'chat-old', 'chat-empty'],
  );
  assert.equal(result.items[2].lastMessageAt, null);
  assert.equal(result.unreadTotal, 0);
});

test('markChatRead resets only current participant unread and marks incoming messages read', async () => {
  const incomingMessage = createMessage();
  const chatUpdateCalls: Array<Record<string, unknown>> = [];
  const chatMessageUpdateManyCalls: Array<Record<string, unknown>> = [];

  const service = new ChatsService(
    {
      chat: {
        findUnique: async () => createChat(),
        update: async (args: Record<string, unknown>) => {
          chatUpdateCalls.push(args);
          return {
            ...createChat(),
            unreadForBuyer: 0,
            unreadForSeller: 4,
          };
        },
      },
      chatMessage: {
        findMany: async () => [incomingMessage],
        updateMany: async (args: Record<string, unknown>) => {
          chatMessageUpdateManyCalls.push(args);
          return { count: 1 };
        },
      },
    } as never,
    {
      getPresenceMap: async () => new Map(),
    } as never,
    {
      buildProtectedChatUrl: () => '',
    } as never,
  );

  const result = await service.markChatRead(
    {
      userId: 'buyer-1',
      role: 'user',
    } as never,
    'chat-1',
  );

  assert.deepEqual(result.messageIds, ['message-1']);
  assert.deepEqual(result.senderIds, ['seller-1']);
  assert.equal(result.chat.unreadCount, 0);
  assert.equal(result.chat.buyerId, 'buyer-1');
  assert.deepEqual(chatMessageUpdateManyCalls[0]?.['where'], {
    id: {
      in: ['message-1'],
    },
  });
  assert.deepEqual(chatUpdateCalls[0]?.['data'], {
    unreadForBuyer: 0,
  });
  assert.ok(
    (chatMessageUpdateManyCalls[0]?.['data'] as Record<string, unknown>)
      ?.['readAt'] instanceof Date,
  );
});

test('listMessages does not mark chat as read or reset unread counters', async () => {
  const chatMessageFindManyCalls: Array<Record<string, unknown>> = [];
  let chatUpdateCalled = false;

  const service = new ChatsService(
    {
      chat: {
        findUnique: async () => ({
          ...createChat(),
          unreadForBuyer: 2,
        }),
        update: async () => {
          chatUpdateCalled = true;
          return createChat();
        },
      },
      chatMessage: {
        findMany: async (args: Record<string, unknown>) => {
          chatMessageFindManyCalls.push(args);
          return [createMessage()];
        },
      },
    } as never,
    {
      getPresenceMap: async () => new Map(),
    } as never,
    {
      buildProtectedChatUrl: () => '',
    } as never,
  );

  const result = await service.listMessages(
    {
      userId: 'buyer-1',
      role: 'user',
    } as never,
    'chat-1',
  );

  assert.equal(result.chat.unreadCount, 2);
  assert.equal(result.items.length, 1);
  assert.equal(chatUpdateCalled, false);
  assert.equal(chatMessageFindManyCalls.length, 1);
});

test('createOrGetChat uses listingId with buyerId and sellerId for chat identity', async () => {
  const upsertCalls: Array<Record<string, unknown>> = [];
  const service = new ChatsService(
    {
      listing: {
        findUnique: async ({ where }: { where: { id: string } }) => ({
          id: where.id,
          ownerId: 'seller-1',
          title: where.id === 'listing-2' ? 'Mercedes' : 'BMW',
          deletedAt: null,
          photos: [],
        }),
      },
      chat: {
        upsert: async (args: Record<string, unknown>) => {
          upsertCalls.push(args);
          const where =
            ((args['where'] as Record<string, unknown>)
              ['listingId_buyerId_sellerId'] as Record<string, string>);
          return {
            ...createChat(),
            id: where['listingId'] === 'listing-2' ? 'chat-2' : 'chat-1',
            listingId: where['listingId'],
            listingTitle: where['listingId'] === 'listing-2' ? 'Mercedes' : 'BMW',
            listing: {
              id: where['listingId'],
              title: where['listingId'] === 'listing-2' ? 'Mercedes' : 'BMW',
              photos: [],
            },
          };
        },
      },
    } as never,
    {
      getPresenceMap: async () => new Map(),
    } as never,
    {} as never,
  );

  const first = await service.createOrGetChat(
    { userId: 'buyer-1', role: 'user' } as never,
    { listingId: 'listing-1', sellerId: 'seller-1' },
  );
  const second = await service.createOrGetChat(
    { userId: 'buyer-1', role: 'user' } as never,
    { listingId: 'listing-2', sellerId: 'seller-1' },
  );

  assert.equal(first.chat.id, 'chat-1');
  assert.equal(second.chat.id, 'chat-2');
  assert.deepEqual(upsertCalls[0]?.['where'], {
    listingId_buyerId_sellerId: {
      listingId: 'listing-1',
      buyerId: 'buyer-1',
      sellerId: 'seller-1',
    },
  });
  assert.deepEqual(upsertCalls[1]?.['where'], {
    listingId_buyerId_sellerId: {
      listingId: 'listing-2',
      buyerId: 'buyer-1',
      sellerId: 'seller-1',
    },
  });
});

test('listChats returns separate chats for same participants with different listings', async () => {
  const service = new ChatsService(
    {
      chat: {
        findMany: async () => [
          {
            ...createChat(),
            id: 'chat-bmw',
            listingId: 'listing-bmw',
            listingTitle: 'BMW',
            unreadForBuyer: 1,
            listing: {
              id: 'listing-bmw',
              title: 'BMW',
              photos: [],
            },
          },
          {
            ...createChat(),
            id: 'chat-mercedes',
            listingId: 'listing-mercedes',
            listingTitle: 'Mercedes',
            unreadForBuyer: 2,
            listing: {
              id: 'listing-mercedes',
              title: 'Mercedes',
              photos: [],
            },
          },
        ],
        aggregate: chatAggregate({ unreadForBuyer: 3, unreadForSeller: 0 }),
      },
    } as never,
    {
      getPresenceMap: async () => new Map(),
    } as never,
    {} as never,
  );

  const result = await service.listChats({
    userId: 'buyer-1',
    role: 'user',
  } as never);

  assert.equal(result.items.length, 2);
  const byId = new Map(result.items.map((item) => [item.id, item]));
  assert.equal(byId.get('chat-bmw')?.listingId, 'listing-bmw');
  assert.equal(byId.get('chat-bmw')?.listingPreview.title, 'BMW');
  assert.equal(byId.get('chat-mercedes')?.listingId, 'listing-mercedes');
  assert.equal(byId.get('chat-mercedes')?.listingPreview.title, 'Mercedes');
  assert.equal(result.unreadTotal, 3);
});

test('markMessageDelivered does not convert message to read', async () => {
  const service = new ChatsService(
    {
      chatMessage: {
        findUnique: async () => createMessage(),
        update: async ({ data }: { data: Record<string, unknown> }) => ({
          ...createMessage(),
          deliveredAt: data['deliveredAt'],
          readAt: null,
        }),
      },
    } as never,
    {
      getPresenceMap: async () => new Map(),
    } as never,
    {
      buildProtectedChatUrl: () => '',
    } as never,
  );

  const result = await service.markMessageDelivered(
    {
      userId: 'buyer-1',
      role: 'user',
    } as never,
    'message-1',
  );

  assert.equal(result.message.status, 'delivered');
  assert.equal(result.message.readAt, null);
  assert.ok(result.message.deliveredAt);
});
