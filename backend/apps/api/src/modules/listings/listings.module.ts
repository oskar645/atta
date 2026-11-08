import { SavedSearchesModule } from '../saved-searches/saved-searches.module';
import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { PromotionsModule } from '../promotions/promotions.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { StorageModule } from '../storage/storage.module';
import { UserBlocksModule } from '../user-blocks/user-blocks.module';
import { ListingsController } from './listings.controller';
import { ListingsService } from './listings.service';

@Module({
  imports: [SavedSearchesModule, AuthModule, StorageModule, PromotionsModule, NotificationsModule, UserBlocksModule],
  controllers: [ListingsController],
  providers: [ListingsService],
  exports: [ListingsService],
})
export class ListingsModule {}
