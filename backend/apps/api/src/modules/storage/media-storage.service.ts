import { Injectable } from '@nestjs/common';

import { env } from '../../config/env';
import { LocalStorageProvider } from './local-storage.provider';
import { S3StorageProvider } from './s3-storage.provider';
import { StorageProvider, StorageProviderName } from './storage.types';

@Injectable()
export class MediaStorageService {
  constructor(
    private readonly localStorageProvider: LocalStorageProvider,
    private readonly s3StorageProvider: S3StorageProvider,
  ) {}

  getProviderName(): StorageProviderName {
    return env.STORAGE_DRIVER;
  }

  getProvider(): StorageProvider {
    return this.getProviderName() === 's3'
      ? this.s3StorageProvider
      : this.localStorageProvider;
  }

  getLocalProvider() {
    return this.localStorageProvider;
  }

  getS3Provider() {
    return this.s3StorageProvider;
  }
}
