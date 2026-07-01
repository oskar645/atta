import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';

import { AdminGuard } from '../auth/admin.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ChatsGateway } from '../chats/chats.gateway';
import { NotificationsService } from './notifications.service';

@Controller('notifications')
@UseGuards(JwtAuthGuard)
export class NotificationsController {
  constructor(
    private readonly notificationsService: NotificationsService,
  ) {}

  @Get()
  listInAppNotifications(@CurrentUser() authUser: AuthenticatedUser) {
    return this.notificationsService.listInAppNotifications(authUser);
  }

  @Patch(':id/read')
  markRead(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id') notificationId: string,
  ) {
    return this.notificationsService.markRead(authUser, notificationId);
  }

  @Patch('read-all')
  markAllRead(@CurrentUser() authUser: AuthenticatedUser) {
    return this.notificationsService.markAllRead(authUser);
  }

  @Patch('seen-all')
  markAllSeen(@CurrentUser() authUser: AuthenticatedUser) {
    return this.notificationsService.markAllSeen(authUser);
  }

  @Delete(':id')
  deleteNotification(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id') notificationId: string,
  ) {
    return this.notificationsService.deleteNotification(authUser, notificationId);
  }

  @Post('push/test')
  sendPushPlaceholder() {
    return this.notificationsService.sendPushPlaceholder();
  }
}

@Controller('admin/notifications')
@UseGuards(JwtAuthGuard, AdminGuard)
export class AdminNotificationsController {
  constructor(
    private readonly notificationsService: NotificationsService,
    private readonly chatsGateway: ChatsGateway,
  ) {}

  @Post('send-user')
  async sendToUser(
    @Body()
    body: { user_id?: string; userId?: string; title?: string; body?: string; type?: string },
  ) {
    const result = await this.notificationsService.sendToUser({
      userId: body.user_id ?? body.userId,
      title: body.title,
      body: body.body,
      type: body.type,
    });
    this.chatsGateway.emitNotificationNew(
      result.item,
      (result.item.user_id ?? '').toString(),
    );
    return result;
  }

  @Post('send-all')
  async sendToAll(
    @Body() body: { title?: string; body?: string; type?: string },
  ) {
    const result = await this.notificationsService.sendToAll(body);
    this.chatsGateway.emitNotificationNew(result.item);
    return result;
  }
}
