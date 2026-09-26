import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { StorageModule } from '../storage/storage.module';
import { UserBlocksModule } from '../user-blocks/user-blocks.module';
import { TopBannersController } from './top-banners.controller';
import { TopBannersService } from './top-banners.service';

@Module({
  imports: [AuthModule, PrismaModule, StorageModule, UserBlocksModule],
  controllers: [TopBannersController],
  providers: [TopBannersService],
  exports: [TopBannersService],
})
export class TopBannersModule {}
