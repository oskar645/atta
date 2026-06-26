"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.StorageService = void 0;
const common_1 = require("@nestjs/common");
const path_1 = require("path");
const env_1 = require("../../config/env");
const prisma_service_1 = require("../prisma/prisma.service");
const s3_service_1 = require("../s3/s3.service");
const media_storage_service_1 = require("./media-storage.service");
const storage_constants_1 = require("./storage.constants");
let StorageService = class StorageService {
    constructor(prisma, s3Service, mediaStorageService) {
        this.prisma = prisma;
        this.s3Service = s3Service;
        this.mediaStorageService = mediaStorageService;
    }
    getProvider() {
        return this.mediaStorageService.getProviderName();
    }
    isLocalProvider() {
        return this.getProvider() === 'local';
    }
    getUploadsRoot() {
        return env_1.env.LOCAL_UPLOADS_DIR;
    }
    async ensureUploadsDirs() {
        await this.mediaStorageService.getLocalProvider().ensureReady();
    }
    async getHealthStatus() {
        return this.mediaStorageService.getProvider().getHealth();
    }
    createUploadUrl(dto) {
        const bucketAlias = dto.bucket;
        const key = `${bucketAlias}/${Date.now()}-${(0, path_1.basename)(dto.fileName.trim() || 'file.bin')}`;
        return {
            bucket: this.s3Service.getBucketName(bucketAlias),
            bucket_alias: bucketAlias,
            key,
            public_url: env_1.env.S3_PUBLIC_BASE_URL
                ? `${env_1.env.S3_PUBLIC_BASE_URL.replace(/\/+$/, '')}/${key}`
                : `/media/object?category=${encodeURIComponent(this.mapBucketAliasToCategory(bucketAlias))}&key=${encodeURIComponent(key)}`,
            content_type: dto.contentType?.trim() || 'application/octet-stream',
            provider: this.getProvider(),
        };
    }
    createAvatarUpload(fileName, contentType) {
        return this.createUploadUrl({
            bucket: 'avatars',
            fileName,
            contentType,
        });
    }
    createListingPhotoUpload(fileName, contentType) {
        return this.createUploadUrl({
            bucket: 'listing-photos',
            fileName,
            contentType,
        });
    }
    createChatImageUpload(fileName, contentType) {
        return this.createUploadUrl({
            bucket: 'chat-images',
            fileName,
            contentType,
        });
    }
    async deleteObject(dto) {
        await this.deleteStoredFile(this.mapBucketAliasToCategory(dto.bucket), dto.key, dto.bucket === 'avatars' ||
            dto.bucket === 'listing-photos' ||
            dto.bucket === 'chat-images' ||
            dto.bucket === 'feed-ads'
            ? 's3'
            : undefined);
        return {
            bucket_alias: dto.bucket,
            deleted: true,
            key: dto.key,
            provider: this.getProvider(),
        };
    }
    async saveUploadedFile(params) {
        try {
            return await this.mediaStorageService.getProvider().saveFile(params);
        }
        catch (error) {
            throw this.wrapStorageError(error);
        }
    }
    buildPublicUrl(category, key) {
        return this.mediaStorageService.getProvider().buildPublicUrl(category, key);
    }
    buildProtectedChatUrl(messageId) {
        return `/media/chats/${messageId}`;
    }
    async readChatFile(key, providerHint) {
        return this.readStoredFile('chats', key, providerHint);
    }
    async readStoredFile(category, key, providerHint) {
        const provider = this.resolveProvider(providerHint, key);
        if (provider === 'local') {
            return this.mediaStorageService.getLocalProvider().readFile(category, key);
        }
        return this.mediaStorageService.getS3Provider().readFile(category, key);
    }
    async deleteStoredFile(category, key, providerHint) {
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
    async deleteAvatarUrl(avatarUrl) {
        const location = this.extractStoredLocation('avatars', avatarUrl);
        if (!location) {
            return;
        }
        await this.deleteStoredFile('avatars', location.key, location.provider);
    }
    async deleteListingPhotosForListings(listingIds) {
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
        await Promise.all(photos.map((photo) => this.deleteStoredFile('listings', photo.storageKey, photo.storageBucket)));
        await this.prisma.listingPhoto.deleteMany({
            where: {
                id: {
                    in: photos.map((photo) => photo.id),
                },
            },
        });
    }
    async deleteChatImagesForChats(chatIds) {
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
        await Promise.all(messages.map((message) => this.deleteStoredFile('chats', message.imageKey, message.imageBucket)));
    }
    async deleteChatImageForMessage(messageId) {
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
    async deleteFeedAdImage(feedAdId) {
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
        const location = feedAd.imageKey != null
            ? { key: feedAd.imageKey, provider: feedAd.imageBucket ?? 'local' }
            : this.extractStoredLocation('feed-ads', feedAd.imageUrl);
        if (!location) {
            return;
        }
        await this.deleteStoredFile('feed-ads', location.key, location.provider);
    }
    async deleteMediaByEntityId(id) {
        const listingPhoto = await this.prisma.listingPhoto.findUnique({
            where: { id },
            select: { storageBucket: true, storageKey: true },
        });
        if (listingPhoto) {
            await this.deleteStoredFile('listings', listingPhoto.storageKey, listingPhoto.storageBucket);
            await this.prisma.listingPhoto.delete({ where: { id } });
            return { deleted: true, entity: 'listing_photo', id };
        }
        const chatMessage = await this.prisma.chatMessage.findUnique({
            where: { id },
            select: { imageBucket: true, imageKey: true },
        });
        if (chatMessage?.imageKey) {
            await this.deleteStoredFile('chats', chatMessage.imageKey, chatMessage.imageBucket);
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
        throw new common_1.NotFoundException('Media not found');
    }
    extractLocalKey(category, rawUrl) {
        const location = this.extractStoredLocation(category, rawUrl);
        if (location?.provider !== 'local') {
            return null;
        }
        return location.key;
    }
    extractStoredLocation(category, rawUrl) {
        const value = rawUrl?.trim() ?? '';
        if (!value) {
            return null;
        }
        const base = env_1.env.MEDIA_PUBLIC_BASE_URL.replace(/\/+$/, '');
        const localPrefix = `${base}/${storage_constants_1.STORAGE_CATEGORY_DIR[category]}/`;
        if (value.startsWith(localPrefix) || value.includes(`/${storage_constants_1.STORAGE_CATEGORY_DIR[category]}/`)) {
            return {
                key: (0, path_1.basename)(value),
                provider: 'local',
            };
        }
        const publicBase = env_1.env.S3_PUBLIC_BASE_URL.replace(/\/+$/, '');
        if (publicBase && value.startsWith(`${publicBase}/`)) {
            return {
                key: decodeURIComponent(value.slice(publicBase.length + 1)),
                provider: 's3',
            };
        }
        const keyParam = this.extractKeyFromProxyUrl(value, category);
        if (keyParam) {
            return {
                key: keyParam,
                provider: 's3',
            };
        }
        return null;
    }
    extractKeyFromProxyUrl(url, category) {
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
        }
        catch {
            return null;
        }
    }
    resolveProvider(providerHint, key) {
        const normalizedHint = providerHint?.trim().toLowerCase() ?? '';
        if (normalizedHint === 'local') {
            return 'local';
        }
        if (normalizedHint && normalizedHint !== 'local') {
            return 's3';
        }
        return key?.includes('/') ? 's3' : 'local';
    }
    wrapStorageError(error) {
        const message = error instanceof Error ? error.message.trim() : 'Не удалось загрузить файл.';
        if (message.startsWith('Н')) {
            return error;
        }
        return new common_1.ServiceUnavailableException('Не удалось загрузить файл. Попробуйте позже.');
    }
    mapBucketAliasToCategory(bucketAlias) {
        const entry = Object.entries(storage_constants_1.STORAGE_BUCKET_ALIAS).find(([, value]) => value === bucketAlias);
        return entry?.[0] ?? 'misc';
    }
};
exports.StorageService = StorageService;
exports.StorageService = StorageService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        s3_service_1.S3Service,
        media_storage_service_1.MediaStorageService])
], StorageService);
//# sourceMappingURL=storage.service.js.map