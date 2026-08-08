import { Module } from '@nestjs/common';

import { PrismaModule } from '../prisma/prisma.module';
import { UserBlocksService } from './user-blocks.service';

@Module({
  imports: [PrismaModule],
  providers: [UserBlocksService],
  exports: [UserBlocksService],
})
export class UserBlocksModule {}
