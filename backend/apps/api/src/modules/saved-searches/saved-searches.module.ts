import { NotificationsModule } from '../notifications/notifications.module';
import { SavedSearchAlertsService } from './saved-search-alerts.service';
import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { UserBlocksModule } from '../user-blocks/user-blocks.module';
import { SavedSearchesController } from './saved-searches.controller';
import { SavedSearchesService } from './saved-searches.service';

@Module({
  imports: [AuthModule, PrismaModule, UserBlocksModule, NotificationsModule],
  controllers: [SavedSearchesController],
  providers: [SavedSearchesService, SavedSearchAlertsService],
  exports: [SavedSearchesService, SavedSearchAlertsService],
})
export class SavedSearchesModule {}
