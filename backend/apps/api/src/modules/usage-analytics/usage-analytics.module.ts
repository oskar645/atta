import { Global, Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { UserBlocksModule } from '../user-blocks/user-blocks.module';
import { AnalyticsSignal } from './analytics-signal';
import { UsageAnalyticsService } from './usage-analytics.service';
import { UsageAnalyticsController } from './usage-analytics.controller';
@Global()
@Module({
  imports: [AuthModule, PrismaModule, UserBlocksModule],
  providers: [AnalyticsSignal, UsageAnalyticsService],
  controllers: [UsageAnalyticsController],
  exports: [AnalyticsSignal],
})
export class UsageAnalyticsModule {}
