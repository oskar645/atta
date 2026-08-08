import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { ChatsModule } from '../chats/chats.module';
import { FeedAdsModule } from '../feed-ads/feed-ads.module';
import { ListingsModule } from '../listings/listings.module';
import { PrismaModule } from '../prisma/prisma.module';
import { StorageModule } from '../storage/storage.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { UserBlocksModule } from '../user-blocks/user-blocks.module';
import { UsersModule } from '../users/users.module';
import { MediaController } from './media.controller';

@Module({
  imports: [
    AuthModule,
    ChatsModule,
    FeedAdsModule,
    ListingsModule,
    NotificationsModule,
    PrismaModule,
    StorageModule,
    UserBlocksModule,
    UsersModule,
  ],
  controllers: [MediaController],
})
export class MediaModule {}
