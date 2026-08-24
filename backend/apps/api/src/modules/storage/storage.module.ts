import { forwardRef, Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { S3Module } from '../s3/s3.module';
import { UserBlocksModule } from '../user-blocks/user-blocks.module';
import { LocalStorageProvider } from './local-storage.provider';
import { MediaStorageService } from './media-storage.service';
import { S3StorageProvider } from './s3-storage.provider';
import { StorageController } from './storage.controller';
import { StorageService } from './storage.service';

@Module({
  imports: [
    forwardRef(() => AuthModule),
    S3Module,
    PrismaModule,
    UserBlocksModule,
  ],
  controllers: [StorageController],
  providers: [
    LocalStorageProvider,
    S3StorageProvider,
    MediaStorageService,
    StorageService,
  ],
  exports: [StorageService],
})
export class StorageModule {}
