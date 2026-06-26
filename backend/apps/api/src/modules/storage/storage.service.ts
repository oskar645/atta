import {
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { basename } from 'path';

import { env } from '../../config/env';
import { PrismaService } from '../prisma/prisma.service';
import { S3Service } from '../s3/s3.service';
import { MediaStorageService } from './media-storage.service';
import {
  STORAGE_BUCKET_ALIAS,
  STORAGE_CATEGORY_DIR,
} from './storage.constants';
import { CreateUploadUrlDto } from './dto/create-upload-url.dto';
import { DeleteObjectDto } from './dto/delete-object.dto';
import {
  SaveUploadedFileParams,
  StorageCategory,
  StorageHealthResult,
  StorageProviderName,
  StoredMediaFile,
} from './storage.types';

@Injectable()
export class StorageService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly s3Service: S3Service,
    private readonly mediaStorageService: MediaStorageService,
  ) {}

  getProvider(): StorageProviderName {
    return this.mediaStorageService.getProviderName();
  }

  isLocalProvider() {
    return this.getProvider() === 'local';
  }

  getUploadsRoot() {
    return env.LOCAL_UPLOADS_DIR;
  }

  async ensureUploadsDirs() {
    await this.mediaStorageService.getLocalProvider().ensureReady();
  }

  async getHealthStatus(): Promise<StorageHealthResult> {
    return this.mediaStorageService.getProvider().getHealth();
  }

  createUploadUrl(dto: CreateUploadUrlDto) {
    const bucketAlias = dto.bucket;
    const key = `${bucketAlias}/${Date.now()}-${basename(dto.fileName.trim() || 'file.bin')}`;
    return {
      bucket: this.s3Service.getBucketName(bucketAlias as never),
      bucket_alias: bucketAlias,
      key,
      public_url: env.S3_PUBLIC_BASE_URL
        ? `${env.S3_PUBLIC_BASE_URL.replace(/\/+$/, '')}/${key}`
        : `/media/object?category=${encodeURIComponent(this.mapBucketAliasToCategory(bucketAlias))}&key=${encodeURIComponent(key)}`,
      content_type: dto.contentType?.trim() || 'application/octet-stream',
      provider: this.getProvider(),
    };
  }

  createAvatarUpload(fileName: string, contentType?: string) {
    return this.createUploadUrl({
      bucket: 'avatars',
      fileName,
      contentType,
    });
  }

  createListingPhotoUpload(fileName: string, contentType?: string) {
    return this.createUploadUrl({
      bucket: 'listing-photos',
      fileName,
      contentType,
    });
  }

  createChatImageUpload(fileName: string, contentType?: string) {
    return this.createUploadUrl({
      bucket: 'chat-images',
      fileName,
      contentType,
    });
  }

  async deleteObject(dto: DeleteObjectDto) {
    await this.deleteStoredFile(
      this.mapBucketAliasToCategory(dto.bucket),
      dto.key,
      dto.bucket === 'avatars' ||
              dto.bucket === 'listing-photos' ||
              dto.bucket === 'chat-images' ||
              dto.bucket === 'feed-ads'
          ? 's3'
          : undefined,
    );
    return {
      bucket_alias: dto.bucket,
      deleted: true,
      key: dto.key,
      provider: this.getProvider(),
    };
  }

  async saveUploadedFile(
    params: SaveUploadedFileParams,
  ): Promise<StoredMediaFile> {
    try {
      return await this.mediaStorageService.getProvider().saveFile(params);
    } catch (error) {
      throw this.wrapStorageError(error);
    }
  }

  buildPublicUrl(category: StorageCategory, key: string) {
    return this.mediaStorageService.getProvider().buildPublicUrl(category, key);
  }

  buildProtectedChatUrl(messageId: string) {
    return `/media/chats/${messageId}`;
  }

  async readChatFile(key: string, providerHint?: string | null) {
    return this.readStoredFile('chats', key, providerHint);
  }

  async readStoredFile(
    category: StorageCategory,
    key: string,
    providerHint?: string | null,
  ) {
    const provider = this.resolveProvider(providerHint, key);
    if (provider === 'local') {
      return this.mediaStorageService.getLocalProvider().readFile(category, key);
    }
    return this.mediaStorageService.getS3Provider().readFile(category, key);
  }

  async deleteStoredFile(
    category: StorageCategory,
    key?: string | null,
    providerHint?: string | null,
  ) {
    const normalizedKey = key?.trim() ?? '';
    if (!normalizedKey) {
      return;
    }

    const provider = this.resolveProvider(providerHint, normalizedKey);
    if (provider === 'local') {
      if (this.getProvider() !== 'local') {
        return;
      }
      await this.mediaStorageService
        .getLocalProvider()
        .deleteFile(category, normalizedKey);
      return;
    }

    if (this.getProvider() !== 's3') {
      return;
    }

    await this.mediaStorageService
      .getS3Provider()
      .deleteFile(category, normalizedKey);
  }

  async deleteAvatarUrl(avatarUrl?: string | null) {
    const location = this.extractStoredLocation('avatars', avatarUrl);
    if (!location) {
      return;
    }
    await this.deleteStoredFile('avatars', location.key, location.provider);
  }

  async deleteListingPhotosForListings(listingIds: string[]) {
    if (listingIds.length === 0) {
      return;
    }
    const photos = await this.prisma.listingPhoto.findMany({
      where: {
        listingId: {
          in: listingIds,
        },
      },
      select: {
        id: true,
        storageBucket: true,
        storageKey: true,
      },
    });
    await Promise.all(
      photos.map((photo) =>
        this.deleteStoredFile(
          'listings',
          photo.storageKey,
          photo.storageBucket,
        ),
      ),
    );
    await this.prisma.listingPhoto.deleteMany({
      where: {
        id: {
          in: photos.map((photo) => photo.id),
        },
      },
    });
  }

  async deleteChatImagesForChats(chatIds: string[]) {
    if (chatIds.length === 0) {
      return;
    }
    const messages = await this.prisma.chatMessage.findMany({
      where: {
        chatId: {
          in: chatIds,
        },
        imageKey: {
          not: null,
        },
      },
      select: {
        id: true,
        imageBucket: true,
        imageKey: true,
      },
    });
    await Promise.all(
      messages.map((message) =>
        this.deleteStoredFile('chats', message.imageKey, message.imageBucket),
      ),
    );
  }

  async deleteChatImageForMessage(messageId: string) {
    const message = await this.prisma.chatMessage.findUnique({
      where: {
        id: messageId,
      },
      select: {
        imageBucket: true,
        imageKey: true,
      },
    });
    if (!message?.imageKey) {
      return;
    }
    await this.deleteStoredFile('chats', message.imageKey, message.imageBucket);
  }

  async deleteFeedAdImage(feedAdId: string) {
    const feedAd = await this.prisma.feedAd.findUnique({
      where: {
        id: feedAdId,
      },
      select: {
        imageBucket: true,
        imageKey: true,
        imageUrl: true,
      },
    });
    if (!feedAd) {
      return;
    }
    const location =
      feedAd.imageKey != null
        ? { key: feedAd.imageKey, provider: feedAd.imageBucket ?? 'local' }
        : this.extractStoredLocation('feed-ads', feedAd.imageUrl);
    if (!location) {
      return;
    }
    await this.deleteStoredFile('feed-ads', location.key, location.provider);
  }

  async deleteMediaByEntityId(id: string) {
    const listingPhoto = await this.prisma.listingPhoto.findUnique({
      where: { id },
      select: { storageBucket: true, storageKey: true },
    });
    if (listingPhoto) {
      await this.deleteStoredFile(
        'listings',
        listingPhoto.storageKey,
        listingPhoto.storageBucket,
      );
      await this.prisma.listingPhoto.delete({ where: { id } });
      return { deleted: true, entity: 'listing_photo', id };
    }

    const chatMessage = await this.prisma.chatMessage.findUnique({
      where: { id },
      select: { imageBucket: true, imageKey: true },
    });
    if (chatMessage?.imageKey) {
      await this.deleteStoredFile(
        'chats',
        chatMessage.imageKey,
        chatMessage.imageBucket,
      );
      await this.prisma.chatMessage.update({
        where: { id },
        data: {
          imageKey: null,
          imageUrl: null,
          imageBucket: null,
        },
      });
      return { deleted: true, entity: 'chat_image', id };
    }

    const feedAd = await this.prisma.feedAd.findUnique({
      where: { id },
      select: { imageBucket: true, imageKey: true },
    });
    if (feedAd?.imageKey) {
      await this.deleteStoredFile('feed-ads', feedAd.imageKey, feedAd.imageBucket);
      await this.prisma.feedAd.update({
        where: { id },
        data: {
          imageKey: null,
          imageUrl: '',
        },
      });
      return { deleted: true, entity: 'feed_ad_image', id };
    }

    throw new NotFoundException('Media not found');
  }

  extractLocalKey(category: StorageCategory, rawUrl?: string | null) {
    const location = this.extractStoredLocation(category, rawUrl);
    if (location?.provider !== 'local') {
      return null;
    }
    return location.key;
  }

  extractStoredLocation(category: StorageCategory, rawUrl?: string | null) {
    const value = rawUrl?.trim() ?? '';
    if (!value) {
      return null;
    }

    const base = env.MEDIA_PUBLIC_BASE_URL.replace(/\/+$/, '');
    const localPrefix = `${base}/${STORAGE_CATEGORY_DIR[category]}/`;
    if (value.startsWith(localPrefix) || value.includes(`/${STORAGE_CATEGORY_DIR[category]}/`)) {
      return {
        key: basename(value),
        provider: 'local' as const,
      };
    }

    const publicBase = env.S3_PUBLIC_BASE_URL.replace(/\/+$/, '');
    if (publicBase && value.startsWith(`${publicBase}/`)) {
      return {
        key: decodeURIComponent(value.slice(publicBase.length + 1)),
        provider: 's3' as const,
      };
    }

    const keyParam = this.extractKeyFromProxyUrl(value, category);
    if (keyParam) {
      return {
        key: keyParam,
        provider: 's3' as const,
      };
    }

    return null;
  }

  private extractKeyFromProxyUrl(url: string, category: StorageCategory) {
    try {
      const parsed = new URL(url, 'http://atta.local');
      const key = parsed.searchParams.get('key')?.trim() ?? '';
      if (!key) {
        return null;
      }
      const routeCategory = parsed.searchParams.get('category')?.trim() ?? '';
      if (routeCategory && routeCategory !== category) {
        return null;
      }
      return key;
    } catch {
      return null;
    }
  }

  private resolveProvider(providerHint?: string | null, key?: string | null) {
    const normalizedHint = providerHint?.trim().toLowerCase() ?? '';
    if (normalizedHint === 'local') {
      return 'local';
    }
    if (normalizedHint && normalizedHint !== 'local') {
      return 's3';
    }
    return key?.includes('/') ? 's3' : 'local';
  }

  private wrapStorageError(error: unknown) {
    const message =
      error instanceof Error ? error.message.trim() : 'Не удалось загрузить файл.';
    if (message.startsWith('Н')) {
      return error;
    }
    return new ServiceUnavailableException('Не удалось загрузить файл. Попробуйте позже.');
  }

  private mapBucketAliasToCategory(bucketAlias: string): StorageCategory {
    const entry = Object.entries(STORAGE_BUCKET_ALIAS).find(
      ([, value]) => value === bucketAlias,
    );
    return (entry?.[0] as StorageCategory | undefined) ?? 'misc';
  }
}
