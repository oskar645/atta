import { Module } from '@nestjs/common';

import { PrismaModule } from '../prisma/prisma.module';
import { S3Module } from '../s3/s3.module';
import { LocalStorageProvider } from './local-storage.provider';
import { MediaStorageService } from './media-storage.service';
import { S3StorageProvider } from './s3-storage.provider';
import { StorageController } from './storage.controller';
import { StorageService } from './storage.service';

@Module({
  imports: [S3Module, PrismaModule],
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
