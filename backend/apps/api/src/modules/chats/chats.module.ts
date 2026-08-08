import { forwardRef, Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { PresenceModule } from '../presence/presence.module';
import { PrismaModule } from '../prisma/prisma.module';
import { StorageModule } from '../storage/storage.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { UserBlocksModule } from '../user-blocks/user-blocks.module';
import { ChatsController, MessagesController } from './chats.controller';
import { ChatsGateway } from './chats.gateway';
import { ChatsService } from './chats.service';

@Module({
  imports: [
    PresenceModule,
    PrismaModule,
    AuthModule,
    StorageModule,
    forwardRef(() => NotificationsModule),
    UserBlocksModule,
  ],
  controllers: [ChatsController, MessagesController],
  providers: [ChatsService, ChatsGateway],
  exports: [ChatsService, ChatsGateway],
})
export class ChatsModule {}
