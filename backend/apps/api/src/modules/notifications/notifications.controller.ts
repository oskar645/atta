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
  ) {}

  @Post('send-user')
  sendToUser(
    @Body()
    body: { user_id?: string; userId?: string; title?: string; body?: string; type?: string },
  ) {
    return this.notificationsService.sendToUser({
      userId: body.user_id ?? body.userId,
      title: body.title,
      body: body.body,
      type: body.type,
    });
  }

  @Post('send-all')
  sendToAll(
    @Body() body: { title?: string; body?: string; type?: string },
  ) {
    return this.notificationsService.sendToAll(body);
  }
}
