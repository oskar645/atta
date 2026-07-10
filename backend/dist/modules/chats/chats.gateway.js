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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
var ChatsGateway_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.ChatsGateway = void 0;
const websockets_1 = require("@nestjs/websockets");
const common_1 = require("@nestjs/common");
const jwt_1 = require("@nestjs/jwt");
const socket_io_1 = require("socket.io");
const env_1 = require("../../config/env");
const presence_service_1 = require("../presence/presence.service");
const prisma_service_1 = require("../prisma/prisma.service");
const send_chat_message_dto_1 = require("./dto/send-chat-message.dto");
const chats_service_1 = require("./chats.service");
let ChatsGateway = ChatsGateway_1 = class ChatsGateway {
    constructor(presenceService, chatsService, jwtService, prisma) {
        this.presenceService = presenceService;
        this.chatsService = chatsService;
        this.jwtService = jwtService;
        this.prisma = prisma;
        this.logger = new common_1.Logger(ChatsGateway_1.name);
    }
    async authenticate(client) {
        const rawAuth = client.handshake.auth?.['token'];
        const rawHeader = client.handshake.headers.authorization;
        const bearerHeader = typeof rawHeader === 'string' && rawHeader.startsWith('Bearer ')
            ? rawHeader.slice('Bearer '.length).trim()
            : '';
        const authToken = typeof rawAuth === 'string' ? rawAuth.trim() : '';
        const token = authToken.length > 0
            ? authToken
            : bearerHeader;
        if (!token) {
            throw new websockets_1.WsException('Access token is missing');
        }
        let payload;
        try {
            payload = await this.jwtService.verifyAsync(token, {
                secret: env_1.env.JWT_ACCESS_SECRET,
            });
        }
        catch {
            throw new websockets_1.WsException('Access token is invalid or expired');
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
            throw new websockets_1.WsException('Session is not active');
        }
        return {
            userId: session.userId,
            sessionId: payload.sessionId,
        };
    }
    async handleConnection(client) {
        try {
            const auth = await this.authenticate(client);
            client.data.userId = auth.userId;
            client.join(`user:${auth.userId}`);
            const presence = await this.presenceService.touchSocket(auth.userId, client.id);
            this.emitPresenceChanged(presence);
            this.logger.log(`Socket connected: ${client.id} user=${auth.userId}`);
        }
        catch (error) {
            this.logger.warn(`Socket rejected: ${client.id}`);
            client.emit('error', {
                message: error instanceof Error ? error.message : 'Socket authentication failed',
            });
            client.disconnect(true);
        }
    }
    async handleDisconnect(client) {
        const userId = (client.data.userId ?? '').toString();
        if (!userId)
            return;
        const presence = await this.presenceService.disconnectSocket(userId, client.id);
        this.emitPresenceChanged(presence);
    }
    async handleJoin(payload, client) {
        const userId = (client.data.userId ?? '').toString();
        await this.chatsService.getChat({
            userId,
            sessionId: '',
            role: 'user',
        }, payload.chatId);
        client.join(`chat:${payload.chatId}`);
        return {
            event: 'chat.join',
            chatId: payload.chatId,
            joined: true,
        };
    }
    handleLeave(payload, client) {
        client.leave(`chat:${payload.chatId}`);
        return {
            event: 'chat.leave',
            chatId: payload.chatId,
            left: true,
        };
    }
    async handleSendMessage(payload, client) {
        const userId = (client.data.userId ?? '').toString();
        if (!payload.chatId) {
            throw new websockets_1.WsException('chatId is required');
        }
        const result = await this.chatsService.sendMessage({
            userId,
            sessionId: '',
            role: 'user',
        }, payload.chatId, payload);
        this.emitOutgoingMessage(result.chat, result.recipientChat, result.message, result.recipientId);
        return result;
    }
    async handleDelivered(payload, client) {
        const result = await this.chatsService.markMessageDelivered({
            userId: (client.data.userId ?? '').toString(),
            sessionId: '',
            role: 'user',
        }, payload.messageId);
        this.emitDelivered(result.message);
        return result;
    }
    async handleRead(payload, client) {
        const result = await this.chatsService.markMessageRead({
            userId: (client.data.userId ?? '').toString(),
            sessionId: '',
            role: 'user',
        }, payload.messageId);
        this.emitRead(result.message);
        return result;
    }
    async handlePing(client) {
        const presence = await this.presenceService.touchHeartbeat((client.data.userId ?? '').toString());
        this.emitPresenceChanged(presence);
        return presence;
    }
    async handlePresence(payload, client) {
        const next = await this.presenceService.setPresence((client.data.userId ?? '').toString(), payload.isOnline);
        this.emitPresenceChanged(next);
        return next;
    }
    emitOutgoingMessage(senderChat, recipientChat, message, recipientId, notification) {
        const chatId = (senderChat['id'] ?? '').toString();
        this.server.to(`user:${recipientId}`).emit('message.new', {
            chat: recipientChat,
            message,
        });
        this.server.to(`chat:${chatId}`).emit('message.new', {
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
        this.emitChatUpdatedToUser((message['senderId'] ?? '').toString(), senderChat);
        this.emitChatUpdatedToUser(recipientId, recipientChat);
        this.emitUnreadChanged(recipientId, recipientChat);
    }
    emitChatUpdated(chat) {
        const buyerId = (chat['buyerId'] ?? '').toString();
        const sellerId = (chat['sellerId'] ?? '').toString();
        this.server.to(`user:${buyerId}`).emit('chat.updated', {
            chat,
        });
        this.server.to(`user:${sellerId}`).emit('chat.updated', {
            chat,
        });
    }
    emitChatUpdatedToUser(userId, chat) {
        const normalizedUserId = userId.trim();
        if (!normalizedUserId)
            return;
        this.server.to(`user:${normalizedUserId}`).emit('chat.updated', {
            chat,
        });
    }
    emitUnreadChanged(userId, chat) {
        this.server.to(`user:${userId}`).emit('unread.changed', {
            chatId: chat['id'],
            unreadCount: chat['unreadCount'],
        });
    }
    emitNotificationNew(notification, userId) {
        const normalizedUserId = (userId ?? '').trim();
        if (normalizedUserId.length > 0) {
            this.server.to(`user:${normalizedUserId}`).emit('notification.new', {
                notification,
            });
            return;
        }
        this.server.emit('notification.new', {
            notification,
        });
    }
    emitDelivered(message) {
        const chatId = (message['chatId'] ?? '').toString();
        const senderId = (message['senderId'] ?? '').toString();
        this.server.to(`chat:${chatId}`).emit('message.delivered', {
            message,
        });
        this.server.to(`user:${senderId}`).emit('message.delivered', {
            message,
        });
    }
    emitRead(message) {
        const chatId = (message['chatId'] ?? '').toString();
        const senderId = (message['senderId'] ?? '').toString();
        this.server.to(`chat:${chatId}`).emit('message.read', {
            message,
        });
        this.server.to(`user:${senderId}`).emit('message.read', {
            message,
        });
    }
    emitMessageDeleted(messageId, chatId, participantIds) {
        const payload = {
            messageId,
            chatId,
        };
        this.server.to(`chat:${chatId}`).emit('message.deleted', payload);
        for (const userId of participantIds) {
            this.server.to(`user:${userId}`).emit('message.deleted', payload);
        }
    }
    emitChatDeleted(chatId, participantIds) {
        const payload = {
            chatId,
        };
        this.server.to(`chat:${chatId}`).emit('chat.deleted', payload);
        for (const userId of participantIds) {
            this.server.to(`user:${userId}`).emit('chat.deleted', payload);
        }
    }
    emitChatRead(chat, messageIds, readAt, senderIds) {
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
    emitPresenceChanged(presence) {
        const userId = (presence['userId'] ?? '').toString();
        this.server.emit('presence.changed', presence);
        this.server.emit('user.presence.changed', presence);
        this.server.to(`user:${userId}`).emit('presence.changed', presence);
    }
};
exports.ChatsGateway = ChatsGateway;
__decorate([
    (0, websockets_1.WebSocketServer)(),
    __metadata("design:type", socket_io_1.Server)
], ChatsGateway.prototype, "server", void 0);
__decorate([
    (0, websockets_1.SubscribeMessage)('chat.join'),
    __param(0, (0, websockets_1.MessageBody)()),
    __param(1, (0, websockets_1.ConnectedSocket)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, socket_io_1.Socket]),
    __metadata("design:returntype", Promise)
], ChatsGateway.prototype, "handleJoin", null);
__decorate([
    (0, websockets_1.SubscribeMessage)('chat.leave'),
    __param(0, (0, websockets_1.MessageBody)()),
    __param(1, (0, websockets_1.ConnectedSocket)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, socket_io_1.Socket]),
    __metadata("design:returntype", void 0)
], ChatsGateway.prototype, "handleLeave", null);
__decorate([
    (0, websockets_1.SubscribeMessage)('message.send'),
    __param(0, (0, websockets_1.MessageBody)()),
    __param(1, (0, websockets_1.ConnectedSocket)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [send_chat_message_dto_1.SendChatMessageDto,
        socket_io_1.Socket]),
    __metadata("design:returntype", Promise)
], ChatsGateway.prototype, "handleSendMessage", null);
__decorate([
    (0, websockets_1.SubscribeMessage)('message.delivered'),
    __param(0, (0, websockets_1.MessageBody)()),
    __param(1, (0, websockets_1.ConnectedSocket)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, socket_io_1.Socket]),
    __metadata("design:returntype", Promise)
], ChatsGateway.prototype, "handleDelivered", null);
__decorate([
    (0, websockets_1.SubscribeMessage)('message.read'),
    __param(0, (0, websockets_1.MessageBody)()),
    __param(1, (0, websockets_1.ConnectedSocket)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, socket_io_1.Socket]),
    __metadata("design:returntype", Promise)
], ChatsGateway.prototype, "handleRead", null);
__decorate([
    (0, websockets_1.SubscribeMessage)('presence.ping'),
    __param(0, (0, websockets_1.ConnectedSocket)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [socket_io_1.Socket]),
    __metadata("design:returntype", Promise)
], ChatsGateway.prototype, "handlePing", null);
__decorate([
    (0, websockets_1.SubscribeMessage)('presence.set'),
    __param(0, (0, websockets_1.MessageBody)()),
    __param(1, (0, websockets_1.ConnectedSocket)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, socket_io_1.Socket]),
    __metadata("design:returntype", Promise)
], ChatsGateway.prototype, "handlePresence", null);
exports.ChatsGateway = ChatsGateway = ChatsGateway_1 = __decorate([
    (0, websockets_1.WebSocketGateway)({
        cors: {
            origin: (0, env_1.parseCorsOrigins)(),
            credentials: true,
        },
    }),
    __metadata("design:paramtypes", [presence_service_1.PresenceService,
        chats_service_1.ChatsService,
        jwt_1.JwtService,
        prisma_service_1.PrismaService])
], ChatsGateway);
//# sourceMappingURL=chats.gateway.js.map