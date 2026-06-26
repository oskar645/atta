import { Module } from '@nestjs/common';

import { FeedAdsController } from './feed-ads.controller';
import { FeedAdsService } from './feed-ads.service';
import { PrismaModule } from '../prisma/prisma.module';
import { AuthModule } from '../auth/auth.module';
import { StorageModule } from '../storage/storage.module';

@Module({
  imports: [PrismaModule, AuthModule, StorageModule],
  controllers: [FeedAdsController],
  providers: [FeedAdsService],
  exports: [FeedAdsService],
})
export class FeedAdsModule {}
