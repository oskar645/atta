import { Module } from '@nestjs/common';

import { PrismaModule } from '../prisma/prisma.module';
import { AppVisitsService } from './app-visits.service';

@Module({
  imports: [PrismaModule],
  providers: [AppVisitsService],
  exports: [AppVisitsService],
})
export class AppVisitsModule {}
