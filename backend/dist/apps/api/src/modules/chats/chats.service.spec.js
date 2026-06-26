"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const strict_1 = __importDefault(require("node:assert/strict"));
const client_1 = require("@prisma/client");
const chats_service_1 = require("./chats.service");
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
(0, node_test_1.test)('sendMessage builds chat notification payload with sender metadata', async () => {
    const notificationCalls = [];
    const notificationRecord = {
        id: 'notification-1',
        userId: 'buyer-1',
        scope: client_1.NotificationScope.PERSONAL,
        title: 'Новое сообщение от Иван',
        body: 'Здравствуйте',
        isRead: false,
        type: client_1.NotificationType.CHAT_MESSAGE,
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
        $transaction: async (callback) => callback({
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
        createSystemNotification: async (payload) => {
            notificationCalls.push(payload);
            return notificationRecord;
        },
        serializeNotification: (item) => ({
            id: item.id,
            title: item.title,
            body: item.body,
            chatId: item.payload.chatId,
            senderName: item.payload.senderName,
            senderAvatarUrl: item.payload.senderAvatarUrl,
        }),
    };
    const service = new chats_service_1.ChatsService(prisma, {
        getPresenceMap: async () => new Map(),
    }, notificationsService, {
        buildProtectedChatUrl: () => '',
    });
    const result = await service.sendMessage({
        userId: 'seller-1',
        role: 'user',
    }, 'chat-1', {
        text: 'Здравствуйте',
    });
    strict_1.default.equal(notificationCalls.length, 1);
    strict_1.default.deepEqual(notificationCalls[0], {
        userId: 'buyer-1',
        title: 'Новое сообщение от Иван',
        body: 'Здравствуйте',
        type: client_1.NotificationType.CHAT_MESSAGE,
        payload: {
            chatId: 'chat-1',
            messageId: 'message-1',
            senderId: 'seller-1',
            senderName: 'Иван',
            senderAvatarUrl: 'https://cdn.example.com/avatar.jpg',
        },
    });
    strict_1.default.equal(result.notification.chatId, 'chat-1');
    strict_1.default.equal(result.notification.senderName, 'Иван');
    strict_1.default.equal(result.notification.senderAvatarUrl, 'https://cdn.example.com/avatar.jpg');
});
(0, node_test_1.test)('listChats sorts by lastMessageAt desc and keeps empty chats below', async () => {
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
    const service = new chats_service_1.ChatsService({
        chat: {
            findMany: async () => [oldChat, emptyChat, freshChat],
        },
    }, {
        getPresenceMap: async () => new Map(),
    }, {}, {});
    const result = await service.listChats({
        userId: 'buyer-1',
        role: 'user',
    });
    strict_1.default.deepEqual(result.items.map((item) => item.id), ['chat-fresh', 'chat-old', 'chat-empty']);
    strict_1.default.equal(result.items[2].lastMessageAt, null);
});
//# sourceMappingURL=chats.service.spec.js.map