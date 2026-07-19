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

  @Post('devices')
  registerDevice(
    @CurrentUser() authUser: AuthenticatedUser,
    @Body()
    body: {
      token?: string;
      platform?: string;
      device_uid?: string;
      deviceUid?: string;
      app_version?: string;
      appVersion?: string;
      build_number?: string;
      buildNumber?: string;
      locale?: string;
    },
  ) {
    return this.notificationsService.registerDevice(authUser, {
      token: body.token,
      platform: body.platform,
      deviceUid: body.device_uid ?? body.deviceUid,
      appVersion: body.app_version ?? body.appVersion,
      buildNumber: body.build_number ?? body.buildNumber,
      locale: body.locale,
    });
  }

  @Delete('devices')
  unregisterDevice(
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() body: { token?: string },
  ) {
    return this.notificationsService.unregisterDevice(authUser, body.token);
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
    body: {
      user_id?: string;
      userId?: string;
      title?: string;
      body?: string;
      type?: string;
      payload?: Record<string, unknown>;
    },
  ) {
    return this.notificationsService.sendToUser({
      userId: body.user_id ?? body.userId,
      title: body.title,
      body: body.body,
      type: body.type,
      payload: body.payload,
    });
  }

  @Post('send-all')
  async sendToAll(
    @Body()
    body: {
      title?: string;
      body?: string;
      type?: string;
      payload?: Record<string, unknown>;
    },
  ) {
    const result = await this.notificationsService.sendToAll(body);
    this.chatsGateway.emitNotificationNew(result.item);
    return result;
  }
}
