import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { AppVisitsModule } from '../app-visits/app-visits.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { ReviewsModule } from '../reviews/reviews.module';
import { StorageModule } from '../storage/storage.module';
import { UserBlocksModule } from '../user-blocks/user-blocks.module';
import { SupportModule } from '../support/support.module';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';

@Module({
  imports: [
    AppVisitsModule,
    AuthModule,
    NotificationsModule,
    ReviewsModule,
    StorageModule,
    SupportModule,
    UserBlocksModule,
  ],
  controllers: [AdminController],
  providers: [AdminService],
  exports: [AdminService],
})
export class AdminModule {}
