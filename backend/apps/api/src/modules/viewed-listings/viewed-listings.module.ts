import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { ViewedListingsController } from './viewed-listings.controller';
import { ViewedListingsService } from './viewed-listings.service';

@Module({
  imports: [AuthModule, PrismaModule],
  controllers: [ViewedListingsController],
  providers: [ViewedListingsService],
  exports: [ViewedListingsService],
})
export class ViewedListingsModule {}
