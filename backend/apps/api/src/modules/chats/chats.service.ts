import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ChatMessageType, NotificationType, Prisma } from '@prisma/client';

import { normalizeStoredMediaUrl } from '../../common/serializers';
import { AuthenticatedUser } from '../auth/auth.types';
import { NotificationsService } from '../notifications/notifications.service';
import { PresenceService } from '../presence/presence.service';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
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

@Injectable()
export class ChatsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly presenceService: PresenceService,
    private readonly notificationsService: NotificationsService,
    private readonly storageService: StorageService,
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

  private buildMessageNotificationPayload(params: {
    chatId: string;
    messageId: string;
    senderId: string;
    senderName: string;
    senderAvatarUrl: string;
  }) {
    return {
      chatId: params.chatId,
      senderId: params.senderId,
      senderName: params.senderName.trim(),
      senderAvatarUrl: params.senderAvatarUrl.trim(),
      messageId: params.messageId,
    };
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

  async listChats(authUser: AuthenticatedUser) {
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
        if (diff !== 0) return diff;
      }

      const createdDiff = b.createdAt.getTime() - a.createdAt.getTime();
      if (createdDiff !== 0) return createdDiff;
      return b.updatedAt.getTime() - a.updatedAt.getTime();
    });

    return {
      items: await Promise.all(chats.map((chat) => this.serializeChat(chat, authUser.userId))),
    };
  }

  async createOrGetChat(authUser: AuthenticatedUser, dto: CreateChatDto) {
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

  async listMessages(authUser: AuthenticatedUser, chatId: string) {
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

  async sendMessage(
    authUser: AuthenticatedUser,
    chatId: string,
    dto: SendChatMessageDto,
  ) {
    const chat = await this.ensureChatParticipant(chatId, authUser.userId);
    const text = dto.text.trim();
    if (!text) {
      throw new BadRequestException('Текст сообщения пустой');
    }

    const recipientId = chat.buyerId === authUser.userId ? chat.sellerId : chat.buyerId;

    const result = await this.prisma.$transaction(async (tx) => {
      const message = await tx.chatMessage.create({
        data: {
          chatId,
          senderId: authUser.userId,
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

    const senderPreview =
      authUser.userId === chat.buyerId
        ? result.chat.buyer
        : result.chat.seller;
    const notification = await this.notificationsService.createSystemNotification({
      userId: recipientId,
      title: `Новое сообщение от ${senderPreview.displayName || senderPreview.name || 'пользователя'}`,
      body: text,
      type: NotificationType.CHAT_MESSAGE,
      payload: this.buildMessageNotificationPayload({
        chatId,
        messageId: result.message.id,
        senderId: authUser.userId,
        senderName:
          senderPreview.displayName || senderPreview.name || 'Новое сообщение',
        senderAvatarUrl:
          senderPreview.avatarUrl || senderPreview.photoUrl || '',
      }),
    });

    return {
      chat: await this.serializeChat(result.chat, authUser.userId),
      recipientChat: await this.serializeChat(result.chat, recipientId),
      message: this.serializeMessage(result.message),
      notification: this.notificationsService.serializeNotification(notification),
      recipientId,
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
    const recipientId =
      chat.buyerId === authUser.userId ? chat.sellerId : chat.buyerId;
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

    const senderPreview =
      authUser.userId === chat.buyerId
        ? result.chat.buyer
        : result.chat.seller;
    const notification = await this.notificationsService.createSystemNotification({
      userId: recipientId,
      title: `Новое сообщение от ${senderPreview.displayName || senderPreview.name || 'пользователя'}`,
      body: 'Фото',
      type: NotificationType.CHAT_MESSAGE,
      payload: this.buildMessageNotificationPayload({
        chatId,
        messageId: result.message.id,
        senderId: authUser.userId,
        senderName:
          senderPreview.displayName || senderPreview.name || 'Новое сообщение',
        senderAvatarUrl:
          senderPreview.avatarUrl || senderPreview.photoUrl || '',
      }),
    });

    return {
      source: 'timeweb',
      chat: await this.serializeChat(result.chat, authUser.userId),
      recipientChat: await this.serializeChat(result.chat, recipientId),
      message: this.serializeMessage(result.message),
      notification: this.notificationsService.serializeNotification(notification),
      recipientId,
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

    if (message.senderId === authUser.userId || message.deliveredAt) {
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
