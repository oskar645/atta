import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { CreateChatDto } from './dto/create-chat.dto';
import { SendChatMessageDto } from './dto/send-chat-message.dto';
import { ChatsGateway } from './chats.gateway';
import { ChatsService } from './chats.service';

@Controller('chats')
@UseGuards(JwtAuthGuard)
export class ChatsController {
  constructor(
    private readonly chatsService: ChatsService,
    private readonly chatsGateway: ChatsGateway,
    private readonly rateLimitService: RateLimitService,
  ) {}

  @Get()
  listChats(@CurrentUser() authUser: AuthenticatedUser) {
    return this.chatsService.listChats(authUser);
  }

  @Post()
  async createChat(
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: CreateChatDto,
  ) {
    const result = await this.chatsService.createOrGetChat(authUser, dto);
    this.chatsGateway.emitChatUpdated(result.chat);
    return result;
  }

  @Get(':id')
  getChat(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) chatId: string,
  ) {
    return this.chatsService.getChat(authUser, chatId);
  }

  @Get(':id/messages')
  listMessages(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) chatId: string,
  ) {
    return this.chatsService.listMessages(authUser, chatId);
  }

  @Post(':id/messages')
  async sendMessage(
    @Req() request: any,
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) chatId: string,
    @Body() dto: SendChatMessageDto,
  ) {
    this.rateLimitService.consumeOrThrow(
      `chat:${authUser.userId}:${request?.ip?.toString() ?? chatId}`,
      {
        limit: 30,
        windowMs: 60 * 1000,
      },
    );
    const result = await this.chatsService.sendMessage(authUser, chatId, dto);
    this.chatsGateway.emitOutgoingMessage(
      result.chat,
      result.recipientChat,
      result.message,
      result.recipientId,
    );
    return result;
  }

  @Post(':id/read')
  async markChatRead(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) chatId: string,
  ) {
    const result = await this.chatsService.markChatRead(authUser, chatId);
    this.chatsGateway.emitChatRead(
      result.chat,
      result.messageIds,
      result.readAt,
      result.senderIds,
    );
    return result;
  }

  @Delete(':id')
  async deleteChat(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) chatId: string,
  ) {
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
}

@Controller('messages')
@UseGuards(JwtAuthGuard)
export class MessagesController {
  constructor(
    private readonly chatsService: ChatsService,
    private readonly chatsGateway: ChatsGateway,
  ) {}

  @Post(':id/delivered')
  async markDelivered(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) messageId: string,
  ) {
    const result = await this.chatsService.markMessageDelivered(authUser, messageId);
    this.chatsGateway.emitDelivered(result.message);
    return result;
  }

  @Post(':id/read')
  async markRead(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) messageId: string,
  ) {
    const result = await this.chatsService.markMessageRead(authUser, messageId);
    this.chatsGateway.emitRead(result.message);
    return result;
  }

  @Delete(':id')
  async deleteMessage(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) messageId: string,
  ) {
    const result = await this.chatsService.deleteMessage(authUser, messageId);
    this.chatsGateway.emitMessageDeleted(
      result.messageId,
      result.chatId,
      result.participantIds,
    );
    this.chatsGateway.emitChatUpdatedToUser(authUser.userId, result.senderChat);
    this.chatsGateway.emitChatUpdatedToUser(
      result.recipientChat['buyerId'] == authUser.userId
        ? result.recipientChat['sellerId'].toString()
        : result.recipientChat['buyerId'].toString(),
      result.recipientChat,
    );
    result.unreadUpdates.forEach((item) => {
      this.chatsGateway.emitUnreadChanged(item.userId, {
        id: item.chatId,
        unreadCount: item.unreadCount,
      });
    });
    return result;
  }
}
