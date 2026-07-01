import { Module } from '@nestjs/common';

import { ApnsModule } from '../apns/apns.module';
import { AuthModule } from '../auth/auth.module';
import { ChatsModule } from '../chats/chats.module';
import { PrismaModule } from '../prisma/prisma.module';
import {
  AdminNotificationsController,
  NotificationsController,
} from './notifications.controller';
import { NotificationsService } from './notifications.service';

@Module({
  imports: [ApnsModule, AuthModule, PrismaModule, ChatsModule],
  controllers: [NotificationsController, AdminNotificationsController],
  providers: [NotificationsService],
  exports: [NotificationsService],
})
export class NotificationsModule {}
