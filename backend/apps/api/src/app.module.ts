import { Module } from '@nestjs/common';

import { AppController } from './app.controller';
import { AdminModule } from './modules/admin/admin.module';
import { ApnsModule } from './modules/apns/apns.module';
import { AuthModule } from './modules/auth/auth.module';
import { ChatsModule } from './modules/chats/chats.module';
import { FavoritesModule } from './modules/favorites/favorites.module';
import { ListingsModule } from './modules/listings/listings.module';
import { MediaModule } from './modules/media/media.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { FeedAdsModule } from './modules/feed-ads/feed-ads.module';
import { PhoneVerificationModule } from './modules/phone-verification/phone-verification.module';
import { PaymentsModule } from './modules/payments/payments.module';
import { PresenceModule } from './modules/presence/presence.module';
import { PrismaModule } from './modules/prisma/prisma.module';
import { PromotionsModule } from './modules/promotions/promotions.module';
import { RedisModule } from './modules/redis/redis.module';
import { RateLimitModule } from './modules/rate-limit/rate-limit.module';
import { ReportsModule } from './modules/reports/reports.module';
import { ReviewsModule } from './modules/reviews/reviews.module';
import { S3Module } from './modules/s3/s3.module';
import { StorageModule } from './modules/storage/storage.module';
import { SupportModule } from './modules/support/support.module';
import { UsersModule } from './modules/users/users.module';
import { UserBlocksModule } from './modules/user-blocks/user-blocks.module';
import { UserFollowsModule } from './modules/user-follows/user-follows.module';
import { SavedSearchesModule } from './modules/saved-searches/saved-searches.module';
import { ViewedListingsModule } from './modules/viewed-listings/viewed-listings.module';
import { WalletModule } from './modules/wallet/wallet.module';

@Module({
  imports: [
    PrismaModule,
    RateLimitModule,
    RedisModule,
    S3Module,
    ApnsModule,
    AuthModule,
    UsersModule,
    UserBlocksModule,
    WalletModule,
    UserFollowsModule,
    SavedSearchesModule,
    ViewedListingsModule,
    PhoneVerificationModule,
    PaymentsModule,
    ListingsModule,
    PromotionsModule,
    MediaModule,
    StorageModule,
    FavoritesModule,
    ChatsModule,
    PresenceModule,
    NotificationsModule,
    FeedAdsModule,
    AdminModule,
    ReportsModule,
    ReviewsModule,
    SupportModule,
  ],
  controllers: [AppController],
})
export class AppModule {}
