import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'crypto';

import { S3Service } from '../s3/s3.service';
import {
  buildScopedStorageKey,
  STORAGE_BUCKET_ALIAS,
  pickExtension,
} from './storage.constants';
import {
  SaveUploadedFileParams,
  StorageCategory,
  StorageHealthResult,
  StorageProvider,
  StoredMediaFile,
} from './storage.types';

@Injectable()
export class S3StorageProvider implements StorageProvider {
  constructor(private readonly s3Service: S3Service) {}

  getName() {
    return 's3' as const;
  }

  async ensureReady() {
    if (!this.s3Service.isConfigured()) {
      throw new ServiceUnavailableException('S3 хранилище не настроено.');
    }
  }

  async getHealth(): Promise<StorageHealthResult> {
    return this.s3Service.getHealthStatus();
  }

  async saveFile(params: SaveUploadedFileParams): Promise<StoredMediaFile> {
    await this.ensureReady();
    const mimeType = params.contentType.trim().toLowerCase();
    const extension = pickExtension(mimeType, params.originalName);
    const fileName = `${randomUUID()}${extension}`;
    const key = buildScopedStorageKey(params.category, fileName, params.context);
    const bucketAlias = STORAGE_BUCKET_ALIAS[params.category] as
      Parameters<S3Service['getBucketName']>[0];
    const bucketName = this.s3Service.getBucketName(bucketAlias);
    await this.s3Service.uploadObject({
      body: params.buffer,
      bucket: bucketName,
      contentType: mimeType,
      key,
    });
    return {
      bucket: bucketName,
      key,
      mimeType,
      provider: 's3',
      sizeBytes: params.buffer.byteLength,
      url: this.buildPublicUrl(params.category, key),
    };
  }

  buildPublicUrl(category: StorageCategory, key: string) {
    return this.s3Service.buildMediaUrl({
      category,
      key,
    });
  }

  async readFile(_category: StorageCategory, key: string) {
    return this.s3Service.readObject(key);
  }

  async deleteFile(category: StorageCategory, key: string) {
    const bucketAlias = STORAGE_BUCKET_ALIAS[category] as
      Parameters<S3Service['getBucketName']>[0];
    const bucketName = this.s3Service.getBucketName(bucketAlias);
    await this.s3Service.deleteObject(bucketName, key);
  }
}
