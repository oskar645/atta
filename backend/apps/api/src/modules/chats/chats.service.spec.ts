import { test } from 'node:test';
import assert from 'node:assert/strict';

import { NotificationScope, NotificationType } from '@prisma/client';

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

test('sendMessage builds chat notification payload with sender metadata', async () => {
  const notificationCalls: Array<Record<string, unknown>> = [];
  const notificationRecord = {
    id: 'notification-1',
    userId: 'buyer-1',
    scope: NotificationScope.PERSONAL,
    title: 'Новое сообщение от Иван',
    body: 'Здравствуйте',
    isRead: false,
    type: NotificationType.CHAT_MESSAGE,
    createdAt: baseDate,
    payload: {
      chatId: 'chat-1',
      messageId: 'message-1',
      senderId: 'seller-1',
      senderName: 'Иван',
      senderAvatarUrl: 'https://cdn.example.com/avatar.jpg',
    },
  };

  const prisma = {
    chat: {
      findUnique: async () => createChat(),
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
          create: async () => createMessage(),
        },
        chat: {
          update: async () => undefined,
          findUniqueOrThrow: async () => createChat(),
        },
      }),
  };

  const notificationsService = {
    createSystemNotification: async (payload: Record<string, unknown>) => {
      notificationCalls.push(payload);
      return notificationRecord;
    },
    serializeNotification: (item: typeof notificationRecord) => ({
      id: item.id,
      title: item.title,
      body: item.body,
      chatId: (item.payload as Record<string, string>).chatId,
      senderName: (item.payload as Record<string, string>).senderName,
      senderAvatarUrl: (item.payload as Record<string, string>).senderAvatarUrl,
    }),
  };

  const service = new ChatsService(
    prisma as never,
    {
      getPresenceMap: async () => new Map(),
    } as never,
    notificationsService as never,
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
    },
  );

  assert.equal(notificationCalls.length, 1);
  assert.deepEqual(notificationCalls[0], {
    userId: 'buyer-1',
    title: 'Новое сообщение от Иван',
    body: 'Здравствуйте',
    type: NotificationType.CHAT_MESSAGE,
    payload: {
      chatId: 'chat-1',
      messageId: 'message-1',
      senderId: 'seller-1',
      senderName: 'Иван',
      senderAvatarUrl: 'https://cdn.example.com/avatar.jpg',
    },
  });
  assert.equal(result.notification.chatId, 'chat-1');
  assert.equal(result.notification.senderName, 'Иван');
  assert.equal(
    result.notification.senderAvatarUrl,
    'https://cdn.example.com/avatar.jpg',
  );
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
      },
    } as never,
    {
      getPresenceMap: async () => new Map(),
    } as never,
    {} as never,
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
});
