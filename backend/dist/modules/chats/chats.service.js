"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.ChatsService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const serializers_1 = require("../../common/serializers");
const presence_service_1 = require("../presence/presence.service");
const prisma_service_1 = require("../prisma/prisma.service");
const storage_service_1 = require("../storage/storage.service");
const user_blocks_service_1 = require("../user-blocks/user-blocks.service");
const chatInclude = {
    listing: {
        include: {
            photos: {
                orderBy: {
                    sortOrder: 'asc',
                },
                take: 1,
            },
        },
    },
    buyer: true,
    seller: true,
};
const messageInclude = {
    chat: {
        include: chatInclude,
    },
};
let ChatsService = class ChatsService {
    constructor(prisma, presenceService, storageService, userBlocksService = {
        assertNotBlocked: async () => undefined,
    }) {
        this.prisma = prisma;
        this.presenceService = presenceService;
        this.storageService = storageService;
        this.userBlocksService = userBlocksService;
    }
    async ensureChatParticipant(chatId, userId) {
        const chat = await this.prisma.chat.findUnique({
            where: {
                id: chatId,
            },
            include: chatInclude,
        });
        if (!chat) {
            throw new common_1.NotFoundException('Чат не найден');
        }
        if (chat.buyerId !== userId && chat.sellerId !== userId) {
            throw new common_1.ForbiddenException('Нет доступа к этому чату');
        }
        return chat;
    }
    messageStatus(message) {
        if (message.readAt)
            return 'read';
        if (message.deliveredAt)
            return 'delivered';
        return 'sent';
    }
    cacheBustedAvatarUrl(url, updatedAt) {
        const trimmedUrl = url?.trim();
        if (!trimmedUrl) {
            return '';
        }
        if (!updatedAt || trimmedUrl.includes('v=')) {
            return trimmedUrl;
        }
        const separator = trimmedUrl.includes('?') ? '&' : '?';
        return `${trimmedUrl}${separator}v=${encodeURIComponent(updatedAt.toISOString())}`;
    }
    participantPreview(user, presence) {
        return {
            id: user.id,
            displayName: user.displayName || user.name || user.email || 'Пользователь',
            avatarUrl: this.cacheBustedAvatarUrl((0, serializers_1.normalizeStoredMediaUrl)(user.avatarUrl || user.photoUrl || '', {
                category: 'avatars',
            }) || '', user.updatedAt),
            isOnline: presence?.isOnline ?? false,
            lastSeen: presence?.lastSeen ?? null,
        };
    }
    async serializeChat(chat, viewerId) {
        const presenceMap = await this.presenceService.getPresenceMap([
            chat.buyerId,
            chat.sellerId,
        ]);
        return {
            id: chat.id,
            listingId: chat.listingId,
            buyerId: chat.buyerId,
            sellerId: chat.sellerId,
            lastMessage: chat.lastMessage,
            lastMessageAt: chat.lastMessageAt?.toISOString() ?? null,
            unreadCount: viewerId === chat.buyerId ? chat.unreadForBuyer : chat.unreadForSeller,
            createdAt: chat.createdAt.toISOString(),
            updatedAt: chat.updatedAt.toISOString(),
            listingPreview: {
                id: chat.listing?.id ?? chat.listingId,
                title: chat.listing?.title || chat.listingTitle || 'Объявление',
                photoUrl: (0, serializers_1.normalizeStoredMediaUrl)(chat.listing?.photos[0]?.publicUrl ?? '', {
                    category: 'listings',
                    providerHint: chat.listing?.photos[0]?.storageBucket,
                    storageKey: chat.listing?.photos[0]?.storageKey,
                }) ?? '',
            },
            buyerPreview: this.participantPreview(chat.buyer, presenceMap.get(chat.buyerId)),
            sellerPreview: this.participantPreview(chat.seller, presenceMap.get(chat.sellerId)),
        };
    }
    async unreadTotalForUser(userId) {
        const normalizedUserId = userId.trim();
        if (!normalizedUserId)
            return 0;
        const [buyerUnread, sellerUnread] = await Promise.all([
            this.prisma.chat.aggregate({
                where: {
                    buyerId: normalizedUserId,
                    deletedByBuyerAt: null,
                },
                _sum: {
                    unreadForBuyer: true,
                },
            }),
            this.prisma.chat.aggregate({
                where: {
                    sellerId: normalizedUserId,
                    deletedBySellerAt: null,
                },
                _sum: {
                    unreadForSeller: true,
                },
            }),
        ]);
        return ((buyerUnread._sum.unreadForBuyer ?? 0) +
            (sellerUnread._sum.unreadForSeller ?? 0));
    }
    serializeMessage(message) {
        const imageUrl = message.messageType === client_1.ChatMessageType.IMAGE && message.imageKey
            ? this.storageService.buildProtectedChatUrl(message.id)
            : (0, serializers_1.normalizeStoredMediaUrl)(message.imageUrl, {
                category: 'chats',
                providerHint: message.imageBucket,
                storageKey: message.imageKey,
            });
        return {
            id: message.id,
            chatId: message.chatId,
            chat_id: message.chatId,
            senderId: message.senderId,
            sender_id: message.senderId,
            receiverId: message.chat.buyerId === message.senderId
                ? message.chat.sellerId
                : message.chat.buyerId,
            participants: [message.chat.buyerId, message.chat.sellerId],
            text: message.text,
            body: message.text,
            content: message.text,
            message: message.text,
            type: message.messageType === client_1.ChatMessageType.TEXT ? 'text' : 'image',
            messageType: message.messageType === client_1.ChatMessageType.TEXT ? 'text' : 'image',
            imageUrl,
            image_url: imageUrl,
            mediaUrl: imageUrl,
            media_url: imageUrl,
            attachmentUrl: imageUrl,
            attachment_url: imageUrl,
            clientMessageId: message.clientMessageId,
            client_message_id: message.clientMessageId,
            status: this.messageStatus(message),
            createdAt: message.createdAt.toISOString(),
            created_at: message.createdAt.toISOString(),
            updatedAt: message.createdAt.toISOString(),
            updated_at: message.createdAt.toISOString(),
            deliveredAt: message.deliveredAt?.toISOString() ?? null,
            delivered_at: message.deliveredAt?.toISOString() ?? null,
            readAt: message.readAt?.toISOString() ?? null,
            read_at: message.readAt?.toISOString() ?? null,
        };
    }
    async listChats(authUser) {
        const chats = await this.prisma.chat.findMany({
            where: {
                OR: [
                    {
                        buyerId: authUser.userId,
                        deletedByBuyerAt: null,
                    },
                    {
                        sellerId: authUser.userId,
                        deletedBySellerAt: null,
                    },
                ],
            },
            include: chatInclude,
        });
        chats.sort((a, b) => {
            const aHasMessages = a.lastMessageAt != null;
            const bHasMessages = b.lastMessageAt != null;
            if (aHasMessages !== bHasMessages) {
                return aHasMessages ? -1 : 1;
            }
            if (a.lastMessageAt != null && b.lastMessageAt != null) {
                const diff = b.lastMessageAt.getTime() - a.lastMessageAt.getTime();
                if (diff !== 0)
                    return diff;
            }
            const createdDiff = b.createdAt.getTime() - a.createdAt.getTime();
            if (createdDiff !== 0)
                return createdDiff;
            return b.updatedAt.getTime() - a.updatedAt.getTime();
        });
        return {
            items: await Promise.all(chats.map((chat) => this.serializeChat(chat, authUser.userId))),
            unreadTotal: await this.unreadTotalForUser(authUser.userId),
        };
    }
    async createOrGetChat(authUser, dto) {
        await this.userBlocksService.assertNotBlocked(authUser.userId);
        if (authUser.userId === dto.sellerId) {
            throw new common_1.BadRequestException('Нельзя написать самому себе');
        }
        const listing = await this.prisma.listing.findUnique({
            where: {
                id: dto.listingId,
            },
            include: {
                photos: {
                    orderBy: {
                        sortOrder: 'asc',
                    },
                    take: 1,
                },
            },
        });
        if (!listing || listing.deletedAt) {
            throw new common_1.NotFoundException('Объявление не найдено');
        }
        if (listing.ownerId !== dto.sellerId) {
            throw new common_1.BadRequestException('Продавец не совпадает с владельцем объявления');
        }
        const chat = await this.prisma.chat.upsert({
            where: {
                listingId_buyerId_sellerId: {
                    listingId: dto.listingId,
                    buyerId: authUser.userId,
                    sellerId: dto.sellerId,
                },
            },
            update: {
                deletedByBuyerAt: null,
                deletedBySellerAt: null,
            },
            create: {
                listingId: listing.id,
                listingTitle: listing.title,
                buyerId: authUser.userId,
                sellerId: dto.sellerId,
            },
            include: chatInclude,
        });
        return {
            chat: await this.serializeChat(chat, authUser.userId),
        };
    }
    async getChat(authUser, chatId) {
        const chat = await this.ensureChatParticipant(chatId, authUser.userId);
        return {
            chat: await this.serializeChat(chat, authUser.userId),
        };
    }
    async listMessages(authUser, chatId) {
        const chat = await this.ensureChatParticipant(chatId, authUser.userId);
        const messages = await this.prisma.chatMessage.findMany({
            where: {
                chatId,
                deletedAt: null,
            },
            include: messageInclude,
            orderBy: {
                createdAt: 'desc',
            },
        });
        return {
            chat: await this.serializeChat(chat, authUser.userId),
            items: messages.map((message) => this.serializeMessage(message)),
        };
    }
    async sendMessage(authUser, chatId, dto) {
        await this.userBlocksService.assertNotBlocked(authUser.userId);
        const chat = await this.ensureChatParticipant(chatId, authUser.userId);
        const text = dto.text.trim();
        if (!text) {
            throw new common_1.BadRequestException('Текст сообщения пустой');
        }
        const clientMessageId = dto.clientMessageId?.trim() || null;
        const recipientId = chat.buyerId === authUser.userId ? chat.sellerId : chat.buyerId;
        if (clientMessageId) {
            const existing = await this.prisma.chatMessage.findFirst({
                where: {
                    chatId,
                    senderId: authUser.userId,
                    clientMessageId,
                    deletedAt: null,
                },
                include: messageInclude,
            });
            if (existing) {
                return {
                    chat: await this.serializeChat(existing.chat, authUser.userId),
                    recipientChat: await this.serializeChat(existing.chat, recipientId),
                    message: this.serializeMessage(existing),
                    recipientId,
                    recipientUnreadTotal: await this.unreadTotalForUser(recipientId),
                    created: false,
                };
            }
        }
        const result = await this.prisma.$transaction(async (tx) => {
            const message = await tx.chatMessage.create({
                data: {
                    chatId,
                    senderId: authUser.userId,
                    clientMessageId,
                    messageType: client_1.ChatMessageType.TEXT,
                    text,
                },
                include: messageInclude,
            });
            await tx.chat.update({
                where: {
                    id: chatId,
                },
                data: {
                    lastMessage: text,
                    lastMessageType: client_1.ChatMessageType.TEXT,
                    lastMessageAt: message.createdAt,
                    unreadForBuyer: authUser.userId === chat.sellerId ? { increment: 1 } : undefined,
                    unreadForSeller: authUser.userId === chat.buyerId ? { increment: 1 } : undefined,
                    deletedByBuyerAt: null,
                    deletedBySellerAt: null,
                },
            });
            const nextChat = await tx.chat.findUniqueOrThrow({
                where: {
                    id: chatId,
                },
                include: chatInclude,
            });
            return {
                chat: nextChat,
                message,
            };
        });
        return {
            chat: await this.serializeChat(result.chat, authUser.userId),
            recipientChat: await this.serializeChat(result.chat, recipientId),
            message: this.serializeMessage(result.message),
            recipientId,
            recipientUnreadTotal: await this.unreadTotalForUser(recipientId),
            created: true,
        };
    }
    async deleteChat(authUser, chatId) {
        const chat = await this.ensureChatParticipant(chatId, authUser.userId);
        const participantIds = [chat.buyerId, chat.sellerId];
        const now = new Date();
        await this.storageService.deleteChatImagesForChats([chatId]);
        await this.prisma.$transaction(async (tx) => {
            await tx.chatMessage.updateMany({
                where: {
                    chatId,
                    deletedAt: null,
                },
                data: {
                    deletedAt: now,
                },
            });
            await tx.chat.update({
                where: {
                    id: chatId,
                },
                data: {
                    deletedByBuyerAt: now,
                    deletedBySellerAt: now,
                    unreadForBuyer: 0,
                    unreadForSeller: 0,
                    lastMessage: '',
                },
            });
        });
        return {
            source: 'timeweb',
            deleted: true,
            chatId,
            participantIds,
            unreadUpdates: participantIds.map((userId) => ({
                userId,
                chatId,
                unreadCount: 0,
            })),
        };
    }
    async deleteMessage(authUser, messageId) {
        const message = await this.prisma.chatMessage.findUnique({
            where: {
                id: messageId,
            },
            include: messageInclude,
        });
        if (!message || message.deletedAt) {
            throw new common_1.NotFoundException('Сообщение не найдено');
        }
        const chat = message.chat;
        if (chat.buyerId !== authUser.userId && chat.sellerId !== authUser.userId) {
            throw new common_1.ForbiddenException('Нет доступа к сообщению');
        }
        await this.storageService.deleteChatImageForMessage(messageId);
        const result = await this.prisma.$transaction(async (tx) => {
            await tx.chatMessage.update({
                where: {
                    id: messageId,
                },
                data: {
                    deletedAt: new Date(),
                },
            });
            const lastVisible = await tx.chatMessage.findFirst({
                where: {
                    chatId: chat.id,
                    deletedAt: null,
                },
                orderBy: {
                    createdAt: 'desc',
                },
            });
            const unreadForBuyer = await tx.chatMessage.count({
                where: {
                    chatId: chat.id,
                    deletedAt: null,
                    senderId: chat.sellerId,
                    readAt: null,
                },
            });
            const unreadForSeller = await tx.chatMessage.count({
                where: {
                    chatId: chat.id,
                    deletedAt: null,
                    senderId: chat.buyerId,
                    readAt: null,
                },
            });
            const nextChat = await tx.chat.update({
                where: {
                    id: chat.id,
                },
                data: {
                    lastMessage: lastVisible?.text ?? '',
                    lastMessageType: lastVisible?.messageType ?? client_1.ChatMessageType.TEXT,
                    lastMessageAt: lastVisible?.createdAt ?? chat.createdAt,
                    unreadForBuyer,
                    unreadForSeller,
                },
                include: chatInclude,
            });
            return {
                chat: nextChat,
            };
        });
        return {
            source: 'timeweb',
            deleted: true,
            messageId,
            chatId: chat.id,
            participantIds: [chat.buyerId, chat.sellerId],
            senderChat: await this.serializeChat(result.chat, chat.buyerId),
            recipientChat: await this.serializeChat(result.chat, chat.sellerId),
            unreadUpdates: [
                {
                    userId: chat.buyerId,
                    chatId: chat.id,
                    unreadCount: result.chat.unreadForBuyer,
                },
                {
                    userId: chat.sellerId,
                    chatId: chat.id,
                    unreadCount: result.chat.unreadForSeller,
                },
            ],
        };
    }
    async uploadImage(authUser, chatId, file) {
        const chat = await this.ensureChatParticipant(chatId, authUser.userId);
        const recipientId = chat.buyerId === authUser.userId ? chat.sellerId : chat.buyerId;
        const uploaded = await this.storageService.saveUploadedFile({
            buffer: file.buffer,
            category: 'chats',
            contentType: file.mimetype,
            context: {
                chatId,
                userId: authUser.userId,
            },
            originalName: file.originalname,
        });
        const result = await this.prisma.$transaction(async (tx) => {
            const message = await tx.chatMessage.create({
                data: {
                    chatId,
                    senderId: authUser.userId,
                    messageType: client_1.ChatMessageType.IMAGE,
                    text: '',
                    imageBucket: uploaded.bucket ?? 'local',
                    imageKey: uploaded.key,
                    imageUrl: uploaded.url,
                },
                include: messageInclude,
            });
            await tx.chat.update({
                where: {
                    id: chatId,
                },
                data: {
                    lastMessage: 'Фото',
                    lastMessageType: client_1.ChatMessageType.IMAGE,
                    lastMessageAt: message.createdAt,
                    unreadForBuyer: authUser.userId === chat.sellerId ? { increment: 1 } : undefined,
                    unreadForSeller: authUser.userId === chat.buyerId ? { increment: 1 } : undefined,
                    deletedByBuyerAt: null,
                    deletedBySellerAt: null,
                },
            });
            const nextChat = await tx.chat.findUniqueOrThrow({
                where: {
                    id: chatId,
                },
                include: chatInclude,
            });
            return {
                chat: nextChat,
                message,
            };
        });
        return {
            source: 'timeweb',
            chat: await this.serializeChat(result.chat, authUser.userId),
            recipientChat: await this.serializeChat(result.chat, recipientId),
            message: this.serializeMessage(result.message),
            recipientId,
            recipientUnreadTotal: await this.unreadTotalForUser(recipientId),
            created: true,
        };
    }
    async getChatImageAccess(authUser, messageId) {
        const message = await this.prisma.chatMessage.findUnique({
            where: {
                id: messageId,
            },
            include: {
                chat: true,
            },
        });
        if (!message || !message.imageKey || message.deletedAt) {
            throw new common_1.NotFoundException('Chat image not found');
        }
        if (message.chat.buyerId !== authUser.userId &&
            message.chat.sellerId !== authUser.userId) {
            throw new common_1.ForbiddenException('No access to chat image');
        }
        return {
            bucket: message.imageBucket,
            key: message.imageKey,
            mimeType: message.imageKey.endsWith('.png')
                ? 'image/png'
                : message.imageKey.endsWith('.webp')
                    ? 'image/webp'
                    : message.imageKey.endsWith('.heic')
                        ? 'image/heic'
                        : message.imageKey.endsWith('.heif')
                            ? 'image/heif'
                            : 'image/jpeg',
        };
    }
    async getChatImageAccessByKey(authUser, key) {
        const message = await this.prisma.chatMessage.findFirst({
            where: {
                imageKey: key,
                deletedAt: null,
                chat: {
                    OR: [
                        { buyerId: authUser.userId },
                        { sellerId: authUser.userId },
                    ],
                },
            },
            include: {
                chat: true,
            },
        });
        if (!message?.imageKey) {
            throw new common_1.NotFoundException('Chat image not found');
        }
        return {
            bucket: message.imageBucket,
            key: message.imageKey,
            mimeType: message.imageKey.endsWith('.png')
                ? 'image/png'
                : message.imageKey.endsWith('.webp')
                    ? 'image/webp'
                    : message.imageKey.endsWith('.heic')
                        ? 'image/heic'
                        : message.imageKey.endsWith('.heif')
                            ? 'image/heif'
                            : 'image/jpeg',
        };
    }
    async markChatRead(authUser, chatId) {
        const chat = await this.ensureChatParticipant(chatId, authUser.userId);
        const now = new Date();
        const incoming = await this.prisma.chatMessage.findMany({
            where: {
                chatId,
                senderId: {
                    not: authUser.userId,
                },
                deletedAt: null,
                OR: [
                    {
                        deliveredAt: null,
                    },
                    {
                        readAt: null,
                    },
                ],
            },
            include: messageInclude,
        });
        if (incoming.length > 0) {
            await this.prisma.chatMessage.updateMany({
                where: {
                    id: {
                        in: incoming.map((message) => message.id),
                    },
                },
                data: {
                    deliveredAt: now,
                    readAt: now,
                },
            });
        }
        const updatedChat = await this.prisma.chat.update({
            where: {
                id: chatId,
            },
            data: authUser.userId === chat.buyerId
                ? {
                    unreadForBuyer: 0,
                }
                : {
                    unreadForSeller: 0,
                },
            include: chatInclude,
        });
        return {
            chat: await this.serializeChat(updatedChat, authUser.userId),
            messageIds: incoming.map((message) => message.id),
            readAt: now.toISOString(),
            senderIds: [...new Set(incoming.map((message) => message.senderId))],
        };
    }
    async markMessageDelivered(authUser, messageId) {
        const message = await this.prisma.chatMessage.findUnique({
            where: {
                id: messageId,
            },
            include: messageInclude,
        });
        if (!message || message.deletedAt) {
            throw new common_1.NotFoundException('Сообщение не найдено');
        }
        const chat = message.chat;
        if (chat.buyerId !== authUser.userId && chat.sellerId !== authUser.userId) {
            throw new common_1.ForbiddenException('Нет доступа к сообщению');
        }
        if (message.senderId === authUser.userId ||
            message.deliveredAt ||
            message.readAt) {
            return {
                message: this.serializeMessage(message),
                recipientId: authUser.userId,
            };
        }
        const deliveredAt = new Date();
        const updated = await this.prisma.chatMessage.update({
            where: {
                id: messageId,
            },
            data: {
                deliveredAt,
            },
            include: messageInclude,
        });
        return {
            message: this.serializeMessage(updated),
            recipientId: authUser.userId,
        };
    }
    async markMessageRead(authUser, messageId) {
        const message = await this.prisma.chatMessage.findUnique({
            where: {
                id: messageId,
            },
            include: messageInclude,
        });
        if (!message || message.deletedAt) {
            throw new common_1.NotFoundException('Сообщение не найдено');
        }
        const chat = message.chat;
        if (chat.buyerId !== authUser.userId && chat.sellerId !== authUser.userId) {
            throw new common_1.ForbiddenException('Нет доступа к сообщению');
        }
        if (message.senderId === authUser.userId) {
            return {
                message: this.serializeMessage(message),
                recipientId: authUser.userId,
            };
        }
        const now = new Date();
        const updated = await this.prisma.chatMessage.update({
            where: {
                id: messageId,
            },
            data: {
                deliveredAt: message.deliveredAt ?? now,
                readAt: message.readAt ?? now,
            },
            include: messageInclude,
        });
        await this.prisma.chat.update({
            where: {
                id: chat.id,
            },
            data: authUser.userId === chat.buyerId
                ? {
                    unreadForBuyer: 0,
                }
                : {
                    unreadForSeller: 0,
                },
        });
        return {
            message: this.serializeMessage(updated),
            recipientId: authUser.userId,
        };
    }
};
exports.ChatsService = ChatsService;
exports.ChatsService = ChatsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        presence_service_1.PresenceService,
        storage_service_1.StorageService,
        user_blocks_service_1.UserBlocksService])
], ChatsService);
//# sourceMappingURL=chats.service.js.map