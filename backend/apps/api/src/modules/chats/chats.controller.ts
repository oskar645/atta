import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { NotificationsService } from '../notifications/notifications.service';
import { CreateChatDto } from './dto/create-chat.dto';
import { SendChatMessageDto } from './dto/send-chat-message.dto';
import { EditChatMessageDto } from './dto/edit-chat-message.dto';
import { ChatsGateway } from './chats.gateway';
import { ChatsService } from './chats.service';

@Controller('chats')
@UseGuards(JwtAuthGuard)
export class ChatsController {
  constructor(
    private readonly chatsService: ChatsService,
    private readonly chatsGateway: ChatsGateway,
    private readonly rateLimitService: RateLimitService,
    private readonly notificationsService: NotificationsService,
  ) {}

  @Get()
  listChats(
    @CurrentUser() authUser: AuthenticatedUser,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.chatsService.listChats(authUser, {
      limit: limit == null ? undefined : Number(limit),
      cursor,
    });
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
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.chatsService.listMessages(authUser, chatId, {
      limit: limit == null ? undefined : Number(limit),
      cursor,
    });
  }

  @Post(':id/messages')
  async sendMessage(
    @Req() request: any,
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) chatId: string,
    @Body() dto: SendChatMessageDto,
  ) {
    await this.rateLimitService.consumeOrThrow(
      `chat:${authUser.userId}:${request?.ip?.toString() ?? chatId}`,
      {
        limit: 30,
        windowMs: 60 * 1000,
      },
    );
    const result = await this.chatsService.sendMessage(authUser, chatId, dto);
    if (result.created !== false) {
      this.chatsGateway.emitOutgoingMessage(
        result.chat,
        result.recipientChat,
        result.message,
        result.recipientId,
        undefined,
        result.recipientUnreadTotal,
      );
      await this.notificationsService.sendChatMessagePush({
        recipientId: result.recipientId,
        message: result.message,
        chat: result.recipientChat,
        unreadTotal: result.recipientUnreadTotal,
      });
    }
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
      authUser.userId,
      result.unreadTotal,
    );
    this.chatsGateway.emitUnreadChanged(
      authUser.userId,
      result.chat,
      result.unreadTotal,
    );
    // Badge delivery is a best-effort side effect and must never roll back a
    // committed read or turn its HTTP response into a failure.
    await this.notificationsService.sendBadgeUpdate(authUser.userId);
    return result;
  }

  @Get(':id/peer-block')
  peerBlockStatus(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) chatId: string,
  ) {
    return this.chatsService.peerBlockStatus(authUser, chatId);
  }

  @Post(':id/peer-block')
  blockPeer(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) chatId: string,
  ) {
    return this.chatsService.blockPeer(authUser, chatId);
  }

  @Delete(':id/peer-block')
  unblockPeer(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) chatId: string,
  ) {
    return this.chatsService.unblockPeer(authUser, chatId);
  }

  @Post(':id/hide')
  async hideChatForMe(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) chatId: string,
  ) {
    const result = await this.chatsService.hideChatForMe(authUser, chatId);
    this.chatsGateway.emitUnreadChanged(authUser.userId, {
      id: chatId,
      unreadCount: 0,
    }, result.unreadTotal);
    await this.notificationsService.sendBadgeUpdate(authUser.userId);
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
      }, item.unreadTotal);
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
    if (result.published) this.chatsGateway.emitDelivered(result.message);
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
    const result = await this.chatsService.hideMessageForMe(authUser, messageId);
    this.chatsGateway.emitMessageHidden(result.messageId, result.chatId, result.userId);
    return result;
  }

  @Delete(':id/everyone')
  async deleteMessageForEveryone(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) messageId: string,
  ) {
    const result = await this.chatsService.deleteMessageForEveryone(authUser, messageId);
    this.chatsGateway.emitMessageUpdated(result.message, result.chatId, result.participantIds);
    return result;
  }

  @Patch(':id')
  async editMessage(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) messageId: string,
    @Body() dto: EditChatMessageDto,
  ) {
    const result = await this.chatsService.editMessage(authUser, messageId, dto.text);
    this.chatsGateway.emitMessageUpdated(result.message, result.chatId, result.participantIds);
    return result;
  }
}
