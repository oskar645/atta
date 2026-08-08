import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { UserBlocksModule } from '../user-blocks/user-blocks.module';
import { UserFollowsController } from './user-follows.controller';
import { UserFollowsService } from './user-follows.service';

@Module({
  imports: [AuthModule, PrismaModule, UserBlocksModule],
  controllers: [UserFollowsController],
  providers: [UserFollowsService],
  exports: [UserFollowsService],
})
export class UserFollowsModule {}
