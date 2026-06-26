import { Injectable } from '@nestjs/common';
import {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadBucketCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';

import { env } from '../../config/env';
import { StorageCategory, StorageHealthResult } from '../storage/storage.types';

type BucketAlias =
  | 'avatars'
  | 'listing-photos'
  | 'chat-images'
  | 'feed-ads'
  | 'support-images'
  | 'reports'
  | 'misc'
  | 'videos';

@Injectable()
export class S3Service {
  private readonly client = new S3Client({
    credentials: this.isConfigured()
      ? {
          accessKeyId: env.S3_ACCESS_KEY_ID || env.S3_ACCESS_KEY,
          secretAccessKey: env.S3_SECRET_ACCESS_KEY || env.S3_SECRET_KEY,
        }
      : undefined,
    endpoint: env.S3_ENDPOINT || undefined,
    forcePathStyle: env.S3_FORCE_PATH_STYLE ?? true,
    region: env.S3_REGION || undefined,
  });

  readonly buckets: Record<BucketAlias, string> = {
    avatars: env.S3_BUCKET_AVATARS || env.S3_BUCKET,
    'chat-images': env.S3_BUCKET_CHAT_IMAGES || env.S3_BUCKET,
    'feed-ads': env.S3_BUCKET_FEED_ADS || env.S3_BUCKET,
    'listing-photos': env.S3_BUCKET_LISTING_PHOTOS || env.S3_BUCKET,
    misc: env.S3_BUCKET_MISC || env.S3_BUCKET,
    reports: env.S3_BUCKET_REPORTS || env.S3_BUCKET,
    'support-images': env.S3_BUCKET_SUPPORT || env.S3_BUCKET,
    videos: env.S3_BUCKET_VIDEOS || env.S3_BUCKET,
  };

  isConfigured() {
    return Boolean(
      env.S3_ENDPOINT &&
        env.S3_REGION &&
        (env.S3_ACCESS_KEY_ID || env.S3_ACCESS_KEY) &&
        (env.S3_SECRET_ACCESS_KEY || env.S3_SECRET_KEY) &&
        env.S3_BUCKET,
    );
  }

  getBucketName(bucketAlias: BucketAlias) {
    return this.buckets[bucketAlias] || env.S3_BUCKET;
  }

  async uploadObject(params: {
    body: Buffer;
    bucket: string;
    contentType: string;
    key: string;
  }) {
    await this.client.send(
      new PutObjectCommand({
        Body: params.body,
        Bucket: params.bucket,
        ContentType: params.contentType,
        Key: params.key,
      }),
    );
  }

  async readObject(key: string) {
    const normalizedKey = this.normalizeObjectKey(key);
    const bucket = this.resolveBucketFromKey(normalizedKey);
    const response = await this.client.send(
      new GetObjectCommand({
        Bucket: bucket,
        Key: normalizedKey,
      }),
    );
    return Buffer.from(await response.Body!.transformToByteArray());
  }

  async deleteObject(bucket: string, key: string) {
    const normalizedKey = this.normalizeObjectKey(key);
    await this.client.send(
      new DeleteObjectCommand({
        Bucket: bucket,
        Key: normalizedKey,
      }),
    );
  }

  async getHealthStatus(): Promise<StorageHealthResult> {
    if (!this.isConfigured()) {
      return {
        status: 's3_error',
        message: 'S3 хранилище не настроено.',
      };
    }

    try {
      await this.client.send(
        new HeadBucketCommand({
          Bucket: env.S3_BUCKET,
        }),
      );
      return { status: 's3_ok' };
    } catch (error) {
      return {
        status: 's3_error',
        message: this.safeErrorMessage(error),
      };
    }
  }

  buildMediaUrl(params: { category: StorageCategory; key: string }) {
    const normalizedKey = this.normalizeObjectKey(params.key);
    if (params.category === 'chats') {
      return `/media/chats/file?key=${encodeURIComponent(normalizedKey)}`;
    }
    return `/media/object?category=${encodeURIComponent(params.category)}&key=${encodeURIComponent(normalizedKey)}`;
  }

  private resolveBucketFromKey(key: string) {
    const normalized = this.normalizeObjectKey(key).toLowerCase();
    if (normalized.startsWith('avatars/')) return this.getBucketName('avatars');
    if (
      normalized.startsWith('listings/') ||
      normalized.startsWith('listing-photos/')
    ) {
      return this.getBucketName('listing-photos');
    }
    if (
      normalized.startsWith('chats/') ||
      normalized.startsWith('chat-images/')
    ) {
      return this.getBucketName('chat-images');
    }
    if (
      normalized.startsWith('support/') ||
      normalized.startsWith('support-images/')
    ) {
      return this.getBucketName('support-images');
    }
    if (normalized.startsWith('feed-ads/')) return this.getBucketName('feed-ads');
    if (normalized.startsWith('reports/')) return this.getBucketName('reports');
    if (normalized.startsWith('videos/')) return this.getBucketName('videos');
    if (normalized.startsWith('misc/')) return this.getBucketName('misc');
    return this.getBucketName('feed-ads');
  }

  private normalizeObjectKey(key: string) {
    let normalized = decodeURIComponent(key.trim()).replace(/^\/+/, '');
    const bucket = env.S3_BUCKET.trim();
    while (
      bucket.length > 0 &&
      normalized.toLowerCase().startsWith(`${bucket.toLowerCase()}/`)
    ) {
      normalized = normalized.slice(bucket.length + 1);
    }
    return normalized;
  }

  private safeErrorMessage(error: unknown) {
    const message =
      error instanceof Error ? error.message.trim() : 'S3 недоступен.';
    return message.length === 0 ? 'S3 недоступен.' : message;
  }
}
