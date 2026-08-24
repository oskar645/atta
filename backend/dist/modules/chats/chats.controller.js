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
Object.defineProperty(exports, "__esModule", { value: true });
exports.MessagesController = exports.ChatsController = void 0;
const common_1 = require("@nestjs/common");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const rate_limit_service_1 = require("../rate-limit/rate-limit.service");
const notifications_service_1 = require("../notifications/notifications.service");
const create_chat_dto_1 = require("./dto/create-chat.dto");
const send_chat_message_dto_1 = require("./dto/send-chat-message.dto");
const chats_gateway_1 = require("./chats.gateway");
const chats_service_1 = require("./chats.service");
let ChatsController = class ChatsController {
    constructor(chatsService, chatsGateway, rateLimitService, notificationsService) {
        this.chatsService = chatsService;
        this.chatsGateway = chatsGateway;
        this.rateLimitService = rateLimitService;
        this.notificationsService = notificationsService;
    }
    listChats(authUser, limit, cursor) {
        return this.chatsService.listChats(authUser, {
            limit: limit == null ? undefined : Number(limit),
            cursor,
        });
    }
    async createChat(authUser, dto) {
        const result = await this.chatsService.createOrGetChat(authUser, dto);
        this.chatsGateway.emitChatUpdated(result.chat);
        return result;
    }
    getChat(authUser, chatId) {
        return this.chatsService.getChat(authUser, chatId);
    }
    listMessages(authUser, chatId, limit, cursor) {
        return this.chatsService.listMessages(authUser, chatId, {
            limit: limit == null ? undefined : Number(limit),
            cursor,
        });
    }
    async sendMessage(request, authUser, chatId, dto) {
        await this.rateLimitService.consumeOrThrow(`chat:${authUser.userId}:${request?.ip?.toString() ?? chatId}`, {
            limit: 30,
            windowMs: 60 * 1000,
        });
        const result = await this.chatsService.sendMessage(authUser, chatId, dto);
        if (result.created !== false) {
            this.chatsGateway.emitOutgoingMessage(result.chat, result.recipientChat, result.message, result.recipientId, undefined, result.recipientUnreadTotal);
            await this.notificationsService.sendChatMessagePush({
                recipientId: result.recipientId,
                message: result.message,
                chat: result.recipientChat,
                unreadTotal: result.recipientUnreadTotal,
            });
        }
        return result;
    }
    async markChatRead(authUser, chatId) {
        const result = await this.chatsService.markChatRead(authUser, chatId);
        this.chatsGateway.emitChatRead(result.chat, result.messageIds, result.readAt, result.senderIds);
        return result;
    }
    peerBlockStatus(authUser, chatId) {
        return this.chatsService.peerBlockStatus(authUser, chatId);
    }
    blockPeer(authUser, chatId) {
        return this.chatsService.blockPeer(authUser, chatId);
    }
    unblockPeer(authUser, chatId) {
        return this.chatsService.unblockPeer(authUser, chatId);
    }
    async hideChatForMe(authUser, chatId) {
        const result = await this.chatsService.hideChatForMe(authUser, chatId);
        this.chatsGateway.emitUnreadChanged(authUser.userId, {
            id: chatId,
            unreadCount: 0,
        });
        return result;
    }
    async deleteChat(authUser, chatId) {
        const result = await this.chatsService.deleteChat(authUser, chatId);
        this.chatsGateway.emitChatDeleted(result.chatId, result.participantIds);
        result.unreadUpdates.forEach((item) => {
            this.chatsGateway.emitUnreadChanged(item.userId, {
                id: item.chatId,
                unreadCount: item.unreadCount,
            });
        });
        return result;
    }
};
exports.ChatsController = ChatsController;
__decorate([
    (0, common_1.Get)(),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Query)('limit')),
    __param(2, (0, common_1.Query)('cursor')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, String]),
    __metadata("design:returntype", void 0)
], ChatsController.prototype, "listChats", null);
__decorate([
    (0, common_1.Post)(),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, create_chat_dto_1.CreateChatDto]),
    __metadata("design:returntype", Promise)
], ChatsController.prototype, "createChat", null);
__decorate([
    (0, common_1.Get)(':id'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], ChatsController.prototype, "getChat", null);
__decorate([
    (0, common_1.Get)(':id/messages'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __param(2, (0, common_1.Query)('limit')),
    __param(3, (0, common_1.Query)('cursor')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, String, String]),
    __metadata("design:returntype", void 0)
], ChatsController.prototype, "listMessages", null);
__decorate([
    (0, common_1.Post)(':id/messages'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __param(3, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object, String, send_chat_message_dto_1.SendChatMessageDto]),
    __metadata("design:returntype", Promise)
], ChatsController.prototype, "sendMessage", null);
__decorate([
    (0, common_1.Post)(':id/read'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], ChatsController.prototype, "markChatRead", null);
__decorate([
    (0, common_1.Get)(':id/peer-block'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], ChatsController.prototype, "peerBlockStatus", null);
__decorate([
    (0, common_1.Post)(':id/peer-block'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], ChatsController.prototype, "blockPeer", null);
__decorate([
    (0, common_1.Delete)(':id/peer-block'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], ChatsController.prototype, "unblockPeer", null);
__decorate([
    (0, common_1.Post)(':id/hide'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], ChatsController.prototype, "hideChatForMe", null);
__decorate([
    (0, common_1.Delete)(':id'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], ChatsController.prototype, "deleteChat", null);
exports.ChatsController = ChatsController = __decorate([
    (0, common_1.Controller)('chats'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [chats_service_1.ChatsService,
        chats_gateway_1.ChatsGateway,
        rate_limit_service_1.RateLimitService,
        notifications_service_1.NotificationsService])
], ChatsController);
let MessagesController = class MessagesController {
    constructor(chatsService, chatsGateway) {
        this.chatsService = chatsService;
        this.chatsGateway = chatsGateway;
    }
    async markDelivered(authUser, messageId) {
        const result = await this.chatsService.markMessageDelivered(authUser, messageId);
        this.chatsGateway.emitDelivered(result.message);
        return result;
    }
    async markRead(authUser, messageId) {
        const result = await this.chatsService.markMessageRead(authUser, messageId);
        this.chatsGateway.emitRead(result.message);
        return result;
    }
    async deleteMessage(authUser, messageId) {
        const result = await this.chatsService.deleteMessage(authUser, messageId);
        this.chatsGateway.emitMessageDeleted(result.messageId, result.chatId, result.participantIds);
        this.chatsGateway.emitChatUpdatedToUser(authUser.userId, result.senderChat);
        this.chatsGateway.emitChatUpdatedToUser(result.recipientChat['buyerId'] == authUser.userId
            ? result.recipientChat['sellerId'].toString()
            : result.recipientChat['buyerId'].toString(), result.recipientChat);
        result.unreadUpdates.forEach((item) => {
            this.chatsGateway.emitUnreadChanged(item.userId, {
                id: item.chatId,
                unreadCount: item.unreadCount,
            });
        });
        return result;
    }
};
exports.MessagesController = MessagesController;
__decorate([
    (0, common_1.Post)(':id/delivered'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], MessagesController.prototype, "markDelivered", null);
__decorate([
    (0, common_1.Post)(':id/read'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], MessagesController.prototype, "markRead", null);
__decorate([
    (0, common_1.Delete)(':id'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], MessagesController.prototype, "deleteMessage", null);
exports.MessagesController = MessagesController = __decorate([
    (0, common_1.Controller)('messages'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [chats_service_1.ChatsService,
        chats_gateway_1.ChatsGateway])
], MessagesController);
//# sourceMappingURL=chats.controller.js.map