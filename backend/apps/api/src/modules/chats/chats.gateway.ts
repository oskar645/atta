import {
  ConnectedSocket,
  MessageBody,
  OnGatewayDisconnect,
  OnGatewayConnection,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
  WsException,
} from '@nestjs/websockets';
import { Logger } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Server, Socket } from 'socket.io';

import { env } from '../../config/env';
import { AuthTokenPayload } from '../auth/auth.types';
import { PresenceService } from '../presence/presence.service';
import { PrismaService } from '../prisma/prisma.service';
import { SendChatMessageDto } from './dto/send-chat-message.dto';
import { ChatsService } from './chats.service';

@WebSocketGateway({
  cors: {
    origin: '*',
  },
})
export class ChatsGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(ChatsGateway.name);

  constructor(
    private readonly presenceService: PresenceService,
    private readonly chatsService: ChatsService,
    private readonly jwtService: JwtService,
    private readonly prisma: PrismaService,
  ) {}

  private async authenticate(client: Socket) {
    const rawAuth = client.handshake.auth?.['token'];
    const rawHeader = client.handshake.headers.authorization;
    const bearerHeader =
      typeof rawHeader === 'string' && rawHeader.startsWith('Bearer ')
        ? rawHeader.slice('Bearer '.length).trim()
        : '';
    const authToken = typeof rawAuth === 'string' ? rawAuth.trim() : '';
    const token = authToken.length > 0
      ? authToken
      : bearerHeader;

    if (!token) {
      throw new WsException('Access token is missing');
    }

    let payload: AuthTokenPayload;
    try {
      payload = await this.jwtService.verifyAsync<AuthTokenPayload>(token, {
        secret: env.JWT_ACCESS_SECRET,
      });
    } catch {
      throw new WsException('Access token is invalid or expired');
    }

    const session = await this.prisma.userSession.findFirst({
      where: {
        id: payload.sessionId,
        userId: payload.sub,
        revokedAt: null,
      },
      select: {
        userId: true,
        expiresAt: true,
      },
    });

    if (!session || session.expiresAt.getTime() <= Date.now()) {
      throw new WsException('Session is not active');
    }

    return {
      userId: session.userId,
      sessionId: payload.sessionId,
    };
  }

  async handleConnection(client: Socket) {
    try {
      const auth = await this.authenticate(client);
      client.data.userId = auth.userId;
      client.join(`user:${auth.userId}`);
      const presence = await this.presenceService.touchSocket(auth.userId, client.id);
      this.emitPresenceChanged(presence);
      this.logger.log(`Socket connected: ${client.id} user=${auth.userId}`);
    } catch (error) {
      this.logger.warn(`Socket rejected: ${client.id}`);
      client.emit('error', {
        message: error instanceof Error ? error.message : 'Socket authentication failed',
      });
      client.disconnect(true);
    }
  }

  async handleDisconnect(client: Socket) {
    const userId = (client.data.userId ?? '').toString();
    if (!userId) return;
    const presence = await this.presenceService.disconnectSocket(userId, client.id);
    this.emitPresenceChanged(presence);
  }

  @SubscribeMessage('chat.join')
  async handleJoin(
    @MessageBody() payload: { chatId: string },
    @ConnectedSocket() client: Socket,
  ) {
    const userId = (client.data.userId ?? '').toString();
    await this.chatsService.getChat(
      {
        userId,
        sessionId: '',
        role: 'user',
      },
      payload.chatId,
    );
    client.join(`chat:${payload.chatId}`);

    return {
      event: 'chat.join',
      chatId: payload.chatId,
      joined: true,
    };
  }

  @SubscribeMessage('chat.leave')
  handleLeave(
    @MessageBody() payload: { chatId: string },
    @ConnectedSocket() client: Socket,
  ) {
    client.leave(`chat:${payload.chatId}`);
    return {
      event: 'chat.leave',
      chatId: payload.chatId,
      left: true,
    };
  }

  @SubscribeMessage('message.send')
  async handleSendMessage(
    @MessageBody() payload: SendChatMessageDto,
    @ConnectedSocket() client: Socket,
  ) {
    const userId = (client.data.userId ?? '').toString();
    if (!payload.chatId) {
      throw new WsException('chatId is required');
    }

    const result = await this.chatsService.sendMessage(
      {
        userId,
        sessionId: '',
        role: 'user',
      },
      payload.chatId,
      payload,
    );

    this.emitOutgoingMessage(
      result.chat,
      result.recipientChat,
      result.message,
      result.recipientId,
    );
    return result;
  }

  @SubscribeMessage('message.delivered')
  async handleDelivered(
    @MessageBody() payload: { messageId: string },
    @ConnectedSocket() client: Socket,
  ) {
    const result = await this.chatsService.markMessageDelivered(
      {
        userId: (client.data.userId ?? '').toString(),
        sessionId: '',
        role: 'user',
      },
      payload.messageId,
    );

    this.emitDelivered(result.message);
    return result;
  }

  @SubscribeMessage('message.read')
  async handleRead(
    @MessageBody() payload: { messageId: string },
    @ConnectedSocket() client: Socket,
  ) {
    const result = await this.chatsService.markMessageRead(
      {
        userId: (client.data.userId ?? '').toString(),
        sessionId: '',
        role: 'user',
      },
      payload.messageId,
    );

    this.emitRead(result.message);
    return result;
  }

  @SubscribeMessage('presence.ping')
  async handlePing(@ConnectedSocket() client: Socket) {
    const presence = await this.presenceService.touchHeartbeat(
      (client.data.userId ?? '').toString(),
    );
    this.emitPresenceChanged(presence);
    return presence;
  }

  @SubscribeMessage('presence.set')
  async handlePresence(
    @MessageBody() payload: { isOnline: boolean },
    @ConnectedSocket() client: Socket,
  ) {
    const next = await this.presenceService.setPresence(
      (client.data.userId ?? '').toString(),
      payload.isOnline,
    );

    this.emitPresenceChanged(next);
    return next;
  }

  emitOutgoingMessage(
    senderChat: Record<string, unknown>,
    recipientChat: Record<string, unknown>,
    message: Record<string, unknown>,
    recipientId: string,
    notification?: Record<string, unknown>,
  ) {
    const chatId = (senderChat['id'] ?? '').toString();
    this.server.to(`user:${recipientId}`).emit('message.new', {
      chat: recipientChat,
      message,
    });
    this.server.to(`chat:${chatId}`).emit('message.new', {
      chat: recipientChat,
      message,
    });
    this.server.to(`user:${message['senderId']}`).emit('message.sent', {
      chat: senderChat,
      message,
    });
    if (notification) {
      this.server.to(`user:${recipientId}`).emit('notification.new', {
        notification,
      });
    }
    this.emitChatUpdated(senderChat);
    this.server.to(`user:${recipientId}`).emit('chat.updated', {
      chat: recipientChat,
    });
    this.emitUnreadChanged(recipientId, recipientChat);
  }

  emitChatUpdated(chat: Record<string, unknown>) {
    const buyerId = (chat['buyerId'] ?? '').toString();
    const sellerId = (chat['sellerId'] ?? '').toString();
    this.server.to(`user:${buyerId}`).emit('chat.updated', {
      chat,
    });
    this.server.to(`user:${sellerId}`).emit('chat.updated', {
      chat,
    });
  }

  emitUnreadChanged(userId: string, chat: Record<string, unknown>) {
    this.server.to(`user:${userId}`).emit('unread.changed', {
      chatId: chat['id'],
      unreadCount: chat['unreadCount'],
    });
  }

  emitDelivered(message: Record<string, unknown>) {
    const chatId = (message['chatId'] ?? '').toString();
    const senderId = (message['senderId'] ?? '').toString();
    this.server.to(`chat:${chatId}`).emit('message.delivered', {
      message,
    });
    this.server.to(`user:${senderId}`).emit('message.delivered', {
      message,
    });
  }

  emitRead(message: Record<string, unknown>) {
    const chatId = (message['chatId'] ?? '').toString();
    const senderId = (message['senderId'] ?? '').toString();
    this.server.to(`chat:${chatId}`).emit('message.read', {
      message,
    });
    this.server.to(`user:${senderId}`).emit('message.read', {
      message,
    });
  }

  emitMessageDeleted(
    messageId: string,
    chatId: string,
    participantIds: string[],
  ) {
    const payload = {
      messageId,
      chatId,
    };
    this.server.to(`chat:${chatId}`).emit('message.deleted', payload);
    for (const userId of participantIds) {
      this.server.to(`user:${userId}`).emit('message.deleted', payload);
    }
  }

  emitChatDeleted(chatId: string, participantIds: string[]) {
    const payload = {
      chatId,
    };
    this.server.to(`chat:${chatId}`).emit('chat.deleted', payload);
    for (const userId of participantIds) {
      this.server.to(`user:${userId}`).emit('chat.deleted', payload);
    }
  }

  emitChatRead(
    chat: Record<string, unknown>,
    messageIds: string[],
    readAt: string,
    senderIds: string[],
  ) {
    this.emitChatUpdated(chat);
    const chatId = (chat['id'] ?? '').toString();
    for (const messageId of messageIds) {
      this.server.to(`chat:${chatId}`).emit('message.read', {
        message: {
          id: messageId,
          chatId,
          readAt,
          deliveredAt: readAt,
          status: 'read',
        },
      });
      for (const senderId of senderIds) {
        this.server.to(`user:${senderId}`).emit('message.read', {
          message: {
            id: messageId,
            chatId,
            readAt,
            deliveredAt: readAt,
            status: 'read',
          },
        });
      }
    }
  }

  emitPresenceChanged(presence: Record<string, unknown>) {
    const userId = (presence['userId'] ?? '').toString();
    this.server.emit('presence.changed', presence);
    this.server.emit('user.presence.changed', presence);
    this.server.to(`user:${userId}`).emit('presence.changed', presence);
  }
}
