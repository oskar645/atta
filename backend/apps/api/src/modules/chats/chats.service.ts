import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ChatMessageType, Prisma } from '@prisma/client';

import { normalizeStoredMediaUrl } from '../../common/serializers';
import { AuthenticatedUser } from '../auth/auth.types';
import { PresenceService } from '../presence/presence.service';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { UserBlocksService } from '../user-blocks/user-blocks.service';
import { UploadedImageFile } from '../storage/uploaded-image-file.type';
import { CreateChatDto } from './dto/create-chat.dto';
import { SendChatMessageDto } from './dto/send-chat-message.dto';

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
} satisfies Prisma.ChatInclude;

const messageInclude = {
  chat: {
    include: chatInclude,
  },
} satisfies Prisma.ChatMessageInclude;

type ChatCursorPayload = {
  lastMessageAt: string | null;
  createdAt: string;
  updatedAt: string;
  id: string;
};

type MessageCursorPayload = {
  createdAt: string;
  id: string;
};

const pageLimit = (value: number | undefined, fallback: number, max: number) =>
  Math.max(1, Math.min(Number.isFinite(value ?? NaN) ? value! : fallback, max));

const encodeCursor = (payload: Record<string, unknown>) =>
  Buffer.from(JSON.stringify(payload)).toString('base64url');

const decodeCursor = <T extends Record<string, unknown>>(cursor?: string) => {
  const raw = cursor?.trim();
  if (!raw) return null;
  try {
    const decoded = JSON.parse(Buffer.from(raw, 'base64url').toString('utf8'));
    return decoded && typeof decoded === 'object' ? (decoded as T) : null;
  } catch {
    return null;
  }
};

const chatCursorWhere = (
  cursor: ChatCursorPayload | null,
): Prisma.ChatWhereInput | null => {
  if (cursor == null) return null;
  const createdAt = new Date(cursor.createdAt);
  const updatedAt = new Date(cursor.updatedAt);
  if (Number.isNaN(createdAt.getTime()) || Number.isNaN(updatedAt.getTime())) {
    return null;
  }
  const tail = [
    { createdAt: { lt: createdAt } },
    { createdAt, updatedAt: { lt: updatedAt } },
    { createdAt, updatedAt, id: { lt: cursor.id } },
  ];
  if (cursor.lastMessageAt == null) {
    return {
      lastMessageAt: null,
      OR: tail,
    };
  }
  const lastMessageAt = new Date(cursor.lastMessageAt);
  if (Number.isNaN(lastMessageAt.getTime())) return null;
  return {
    OR: [
      { lastMessageAt: { lt: lastMessageAt } },
      {
        lastMessageAt,
        OR: tail,
      },
      { lastMessageAt: null },
    ],
  };
};

const messageCursorWhere = (
  cursor: MessageCursorPayload | null,
): Prisma.ChatMessageWhereInput | null => {
  if (cursor == null) return null;
  const createdAt = new Date(cursor.createdAt);
  if (Number.isNaN(createdAt.getTime())) return null;
  return {
    OR: [
      { createdAt: { lt: createdAt } },
      { createdAt, id: { lt: cursor.id } },
    ],
  };
};

const compareChatsForList = (
  a: Prisma.ChatGetPayload<{ include: typeof chatInclude }>,
  b: Prisma.ChatGetPayload<{ include: typeof chatInclude }>,
) => {
  const aLast = a.lastMessageAt?.getTime();
  const bLast = b.lastMessageAt?.getTime();
  if (aLast != null || bLast != null) {
    if (aLast == null) return 1;
    if (bLast == null) return -1;
    if (aLast !== bLast) return bLast - aLast;
  }

  const createdDiff = b.createdAt.getTime() - a.createdAt.getTime();
  if (createdDiff !== 0) return createdDiff;
  const updatedDiff = b.updatedAt.getTime() - a.updatedAt.getTime();
  if (updatedDiff !== 0) return updatedDiff;
  return b.id.localeCompare(a.id);
};

@Injectable()
export class ChatsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly presenceService: PresenceService,
    private readonly storageService: StorageService,
    private readonly userBlocksService: UserBlocksService = {
      assertNotBlocked: async () => undefined,
    } as unknown as UserBlocksService,
  ) {}

  private async ensureChatParticipant(chatId: string, userId: string) {
    const chat = await this.prisma.chat.findUnique({
      where: {
        id: chatId,
      },
      include: chatInclude,
    });

    if (!chat) {
      throw new NotFoundException('Чат не найден');
    }

    if (chat.buyerId !== userId && chat.sellerId !== userId) {
      throw new ForbiddenException('Нет доступа к этому чату');
    }

    return chat;
  }

  private otherParticipantId(
    chat: { buyerId: string; sellerId: string },
    userId: string,
  ) {
    return chat.buyerId === userId ? chat.sellerId : chat.buyerId;
  }

  private async findPeerBlock(userAId: string, userBId: string) {
    const peerBlocks = (this.prisma as any).chatPeerBlock;
    if (!peerBlocks) return null;
    return peerBlocks.findFirst({
      where: {
        OR: [
          {
            blockerUserId: userAId,
            blockedUserId: userBId,
          },
          {
            blockerUserId: userBId,
            blockedUserId: userAId,
          },
        ],
      },
    });
  }

  private async assertNoPeerBlock(userAId: string, userBId: string) {
    const block = await this.findPeerBlock(userAId, userBId);
    if (block) {
      throw new ForbiddenException('Пользователь заблокирован');
    }
  }

  private async isBlockedByViewer(
    chat: { buyerId: string; sellerId: string },
    viewerId: string,
  ) {
    const otherUserId = this.otherParticipantId(chat, viewerId);
    const peerBlocks = (this.prisma as any).chatPeerBlock;
    if (!peerBlocks) return false;
    const block = await peerBlocks.findUnique({
      where: {
        blockerUserId_blockedUserId: {
          blockerUserId: viewerId,
          blockedUserId: otherUserId,
        },
      },
      select: {
        id: true,
      },
    });
    return block != null;
  }

  private messageStatus(message: {
    readAt: Date | null;
    deliveredAt: Date | null;
  }) {
    if (message.readAt) return 'read';
    if (message.deliveredAt) return 'delivered';
    return 'sent';
  }

  private cacheBustedAvatarUrl(
    url: string | null | undefined,
    updatedAt: Date | null | undefined,
  ) {
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

  private participantPreview(
    user: {
      id: string;
      displayName: string;
      name: string;
      email: string | null;
      avatarUrl: string | null;
      photoUrl: string | null;
      updatedAt?: Date | null;
    },
    presence: { isOnline: boolean; lastSeen: string | null } | undefined,
  ) {
    return {
      id: user.id,
      displayName:
        user.displayName || user.name || user.email || 'Пользователь',
      avatarUrl: this.cacheBustedAvatarUrl(
        normalizeStoredMediaUrl(user.avatarUrl || user.photoUrl || '', {
          category: 'avatars',
        }) || '',
        user.updatedAt,
      ),
      isOnline: presence?.isOnline ?? false,
      lastSeen: presence?.lastSeen ?? null,
    };
  }

  private async serializeChat(
    chat: Prisma.ChatGetPayload<{ include: typeof chatInclude }>,
    viewerId: string,
  ) {
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
      blockedByMe: await this.isBlockedByViewer(chat, viewerId),
      listingPreview: {
        id: chat.listing?.id ?? chat.listingId,
        title: chat.listing?.title || chat.listingTitle || 'Объявление',
        photoUrl:
          normalizeStoredMediaUrl(chat.listing?.photos[0]?.publicUrl ?? '', {
            category: 'listings',
            providerHint: chat.listing?.photos[0]?.storageBucket,
            storageKey: chat.listing?.photos[0]?.storageKey,
          }) ?? '',
      },
      buyerPreview: this.participantPreview(
        chat.buyer,
        presenceMap.get(chat.buyerId),
      ),
      sellerPreview: this.participantPreview(
        chat.seller,
        presenceMap.get(chat.sellerId),
      ),
    };
  }

  async unreadTotalForUser(userId: string) {
    const normalizedUserId = userId.trim();
    if (!normalizedUserId) return 0;
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
    return (
      (buyerUnread._sum.unreadForBuyer ?? 0) +
      (sellerUnread._sum.unreadForSeller ?? 0)
    );
  }

  private serializeMessage(
    message: Prisma.ChatMessageGetPayload<{ include: typeof messageInclude }>,
  ) {
    const imageUrl =
      message.messageType === ChatMessageType.IMAGE && message.imageKey
        ? this.storageService.buildProtectedChatUrl(message.id)
        : normalizeStoredMediaUrl(message.imageUrl, {
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
      receiverId:
        message.chat.buyerId === message.senderId
          ? message.chat.sellerId
          : message.chat.buyerId,
      participants: [message.chat.buyerId, message.chat.sellerId],
      text: message.text,
      body: message.text,
      content: message.text,
      message: message.text,
      type: message.messageType === ChatMessageType.TEXT ? 'text' : 'image',
      messageType: message.messageType === ChatMessageType.TEXT ? 'text' : 'image',
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

  async listChats(
    authUser: AuthenticatedUser,
    params?: { limit?: number; cursor?: string },
  ) {
    const limit = pageLimit(params?.limit, 30, 50);
    const cursorWhere = chatCursorWhere(
      decodeCursor<ChatCursorPayload>(params?.cursor),
    );
    const chats = await this.prisma.chat.findMany({
      where: {
        AND: [
          {
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
          ...(cursorWhere ? [cursorWhere] : []),
        ],
      },
      include: chatInclude,
      orderBy: [
        { lastMessageAt: { sort: 'desc', nulls: 'last' } },
        { createdAt: 'desc' },
        { updatedAt: 'desc' },
        { id: 'desc' },
      ],
      take: limit + 1,
    });
    const orderedChats = chats.sort(compareChatsForList);
    const pageItems = orderedChats.slice(0, limit);
    const hasMore = orderedChats.length > limit;
    const last = hasMore ? pageItems[pageItems.length - 1] : null;

    return {
      items: await Promise.all(
        pageItems.map((chat) => this.serializeChat(chat, authUser.userId)),
      ),
      unreadTotal: await this.unreadTotalForUser(authUser.userId),
      nextCursor: last
        ? encodeCursor({
            lastMessageAt: last.lastMessageAt?.toISOString() ?? null,
            createdAt: last.createdAt.toISOString(),
            updatedAt: last.updatedAt.toISOString(),
            id: last.id,
          })
        : null,
      hasMore,
      limit,
    };
  }

  async createOrGetChat(authUser: AuthenticatedUser, dto: CreateChatDto) {
    await this.userBlocksService.assertNotBlocked(authUser.userId);

    if (authUser.userId === dto.sellerId) {
      throw new BadRequestException('Нельзя написать самому себе');
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
      throw new NotFoundException('Объявление не найдено');
    }

    if (listing.ownerId !== dto.sellerId) {
      throw new BadRequestException('Продавец не совпадает с владельцем объявления');
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

  async getChat(authUser: AuthenticatedUser, chatId: string) {
    const chat = await this.ensureChatParticipant(chatId, authUser.userId);
    return {
      chat: await this.serializeChat(chat, authUser.userId),
    };
  }

  async listMessages(
    authUser: AuthenticatedUser,
    chatId: string,
    params?: { limit?: number; cursor?: string },
  ) {
    const chat = await this.ensureChatParticipant(chatId, authUser.userId);
    const limit = pageLimit(params?.limit, 30, 100);
    const cursorWhere = messageCursorWhere(
      decodeCursor<MessageCursorPayload>(params?.cursor),
    );
    const messages = await this.prisma.chatMessage.findMany({
      where: {
        chatId,
        deletedAt: null,
        ...(cursorWhere ?? {}),
      },
      include: messageInclude,
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const pageItems = messages.slice(0, limit);
    const hasMore = messages.length > limit;
    const last = hasMore ? pageItems[pageItems.length - 1] : null;

    return {
      chat: await this.serializeChat(chat, authUser.userId),
      items: pageItems.map((message) => this.serializeMessage(message)),
      nextCursor: last
        ? encodeCursor({
            createdAt: last.createdAt.toISOString(),
            id: last.id,
          })
        : null,
      hasMore,
      limit,
    };
  }

  async sendMessage(
    authUser: AuthenticatedUser,
    chatId: string,
    dto: SendChatMessageDto,
  ) {
    await this.userBlocksService.assertNotBlocked(authUser.userId);

    const chat = await this.ensureChatParticipant(chatId, authUser.userId);
    const text = dto.text.trim();
    if (!text) {
      throw new BadRequestException('Текст сообщения пустой');
    }
    const clientMessageId = dto.clientMessageId?.trim() || null;

    const recipientId = this.otherParticipantId(chat, authUser.userId);
    await this.assertNoPeerBlock(authUser.userId, recipientId);

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
          messageType: ChatMessageType.TEXT,
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
          lastMessageType: ChatMessageType.TEXT,
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

  async deleteChat(authUser: AuthenticatedUser, chatId: string) {
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

  async hideChatForMe(authUser: AuthenticatedUser, chatId: string) {
    const chat = await this.ensureChatParticipant(chatId, authUser.userId);
    const now = new Date();
    const isBuyer = chat.buyerId === authUser.userId;

    const nextChat = await this.prisma.chat.update({
      where: {
        id: chatId,
      },
      data: isBuyer
        ? {
            deletedByBuyerAt: now,
            unreadForBuyer: 0,
          }
        : {
            deletedBySellerAt: now,
            unreadForSeller: 0,
          },
      include: chatInclude,
    });

    return {
      source: 'timeweb',
      hidden: true,
      chatId,
      viewerId: authUser.userId,
      unreadCount: 0,
      unreadTotal: await this.unreadTotalForUser(authUser.userId),
      chat: await this.serializeChat(nextChat, authUser.userId),
    };
  }

  async peerBlockStatus(authUser: AuthenticatedUser, chatId: string) {
    const chat = await this.ensureChatParticipant(chatId, authUser.userId);
    return {
      chatId,
      blocked: await this.isBlockedByViewer(chat, authUser.userId),
    };
  }

  async blockPeer(authUser: AuthenticatedUser, chatId: string) {
    const chat = await this.ensureChatParticipant(chatId, authUser.userId);
    const otherUserId = this.otherParticipantId(chat, authUser.userId);
    await (this.prisma as any).chatPeerBlock.upsert({
      where: {
        blockerUserId_blockedUserId: {
          blockerUserId: authUser.userId,
          blockedUserId: otherUserId,
        },
      },
      update: {},
      create: {
        blockerUserId: authUser.userId,
        blockedUserId: otherUserId,
      },
    });

    return {
      chatId,
      blocked: true,
    };
  }

  async unblockPeer(authUser: AuthenticatedUser, chatId: string) {
    const chat = await this.ensureChatParticipant(chatId, authUser.userId);
    const otherUserId = this.otherParticipantId(chat, authUser.userId);
    await (this.prisma as any).chatPeerBlock.deleteMany({
      where: {
        blockerUserId: authUser.userId,
        blockedUserId: otherUserId,
      },
    });

    return {
      chatId,
      blocked: false,
    };
  }

  async deleteMessage(authUser: AuthenticatedUser, messageId: string) {
    const message = await this.prisma.chatMessage.findUnique({
      where: {
        id: messageId,
      },
      include: messageInclude,
    });

    if (!message || message.deletedAt) {
      throw new NotFoundException('Сообщение не найдено');
    }

    const chat = message.chat;
    if (chat.buyerId !== authUser.userId && chat.sellerId !== authUser.userId) {
      throw new ForbiddenException('Нет доступа к сообщению');
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
          lastMessageType: lastVisible?.messageType ?? ChatMessageType.TEXT,
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

  async uploadImage(
    authUser: AuthenticatedUser,
    chatId: string,
    file: UploadedImageFile,
  ) {
    const chat = await this.ensureChatParticipant(chatId, authUser.userId);
    const recipientId = this.otherParticipantId(chat, authUser.userId);
    await this.assertNoPeerBlock(authUser.userId, recipientId);
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
          messageType: ChatMessageType.IMAGE,
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
          lastMessageType: ChatMessageType.IMAGE,
          lastMessageAt: message.createdAt,
          unreadForBuyer:
            authUser.userId === chat.sellerId ? { increment: 1 } : undefined,
          unreadForSeller:
            authUser.userId === chat.buyerId ? { increment: 1 } : undefined,
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

  async getChatImageAccess(authUser: AuthenticatedUser, messageId: string) {
    const message = await this.prisma.chatMessage.findUnique({
      where: {
        id: messageId,
      },
      include: {
        chat: true,
      },
    });

    if (!message || !message.imageKey || message.deletedAt) {
      throw new NotFoundException('Chat image not found');
    }

    if (
      message.chat.buyerId !== authUser.userId &&
      message.chat.sellerId !== authUser.userId
    ) {
      throw new ForbiddenException('No access to chat image');
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

  async getChatImageAccessByKey(authUser: AuthenticatedUser, key: string) {
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
      throw new NotFoundException('Chat image not found');
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

  async markChatRead(authUser: AuthenticatedUser, chatId: string) {
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

  async markMessageDelivered(authUser: AuthenticatedUser, messageId: string) {
    const message = await this.prisma.chatMessage.findUnique({
      where: {
        id: messageId,
      },
      include: messageInclude,
    });

    if (!message || message.deletedAt) {
      throw new NotFoundException('Сообщение не найдено');
    }

    const chat = message.chat;
    if (chat.buyerId !== authUser.userId && chat.sellerId !== authUser.userId) {
      throw new ForbiddenException('Нет доступа к сообщению');
    }

    if (
      message.senderId === authUser.userId ||
      message.deliveredAt ||
      message.readAt
    ) {
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

  async markMessageRead(authUser: AuthenticatedUser, messageId: string) {
    const message = await this.prisma.chatMessage.findUnique({
      where: {
        id: messageId,
      },
      include: messageInclude,
    });

    if (!message || message.deletedAt) {
      throw new NotFoundException('Сообщение не найдено');
    }

    const chat = message.chat;
    if (chat.buyerId !== authUser.userId && chat.sellerId !== authUser.userId) {
      throw new ForbiddenException('Нет доступа к сообщению');
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
}
