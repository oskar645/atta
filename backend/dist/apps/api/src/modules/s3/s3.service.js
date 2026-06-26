"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.S3Service = void 0;
const common_1 = require("@nestjs/common");
const client_s3_1 = require("@aws-sdk/client-s3");
const env_1 = require("../../config/env");
let S3Service = class S3Service {
    constructor() {
        this.client = new client_s3_1.S3Client({
            credentials: this.isConfigured()
                ? {
                    accessKeyId: env_1.env.S3_ACCESS_KEY_ID || env_1.env.S3_ACCESS_KEY,
                    secretAccessKey: env_1.env.S3_SECRET_ACCESS_KEY || env_1.env.S3_SECRET_KEY,
                }
                : undefined,
            endpoint: env_1.env.S3_ENDPOINT || undefined,
            forcePathStyle: env_1.env.S3_FORCE_PATH_STYLE ?? true,
            region: env_1.env.S3_REGION || undefined,
        });
        this.buckets = {
            avatars: env_1.env.S3_BUCKET_AVATARS || env_1.env.S3_BUCKET,
            'chat-images': env_1.env.S3_BUCKET_CHAT_IMAGES || env_1.env.S3_BUCKET,
            'feed-ads': env_1.env.S3_BUCKET_FEED_ADS || env_1.env.S3_BUCKET,
            'listing-photos': env_1.env.S3_BUCKET_LISTING_PHOTOS || env_1.env.S3_BUCKET,
            misc: env_1.env.S3_BUCKET_MISC || env_1.env.S3_BUCKET,
            reports: env_1.env.S3_BUCKET_REPORTS || env_1.env.S3_BUCKET,
            'support-images': env_1.env.S3_BUCKET_SUPPORT || env_1.env.S3_BUCKET,
            videos: env_1.env.S3_BUCKET_VIDEOS || env_1.env.S3_BUCKET,
        };
    }
    isConfigured() {
        return Boolean(env_1.env.S3_ENDPOINT &&
            env_1.env.S3_REGION &&
            (env_1.env.S3_ACCESS_KEY_ID || env_1.env.S3_ACCESS_KEY) &&
            (env_1.env.S3_SECRET_ACCESS_KEY || env_1.env.S3_SECRET_KEY) &&
            env_1.env.S3_BUCKET);
    }
    getBucketName(bucketAlias) {
        return this.buckets[bucketAlias] || env_1.env.S3_BUCKET;
    }
    async uploadObject(params) {
        await this.client.send(new client_s3_1.PutObjectCommand({
            Body: params.body,
            Bucket: params.bucket,
            ContentType: params.contentType,
            Key: params.key,
        }));
    }
    async readObject(key) {
        const bucket = this.resolveBucketFromKey(key);
        const response = await this.client.send(new client_s3_1.GetObjectCommand({
            Bucket: bucket,
            Key: key,
        }));
        return Buffer.from(await response.Body.transformToByteArray());
    }
    async deleteObject(bucket, key) {
        await this.client.send(new client_s3_1.DeleteObjectCommand({
            Bucket: bucket,
            Key: key,
        }));
    }
    async getHealthStatus() {
        if (!this.isConfigured()) {
            return {
                status: 's3_error',
                message: 'S3 хранилище не настроено.',
            };
        }
        try {
            await this.client.send(new client_s3_1.HeadBucketCommand({
                Bucket: env_1.env.S3_BUCKET,
            }));
            return { status: 's3_ok' };
        }
        catch (error) {
            return {
                status: 's3_error',
                message: this.safeErrorMessage(error),
            };
        }
    }
    buildMediaUrl(params) {
        const publicBase = env_1.env.S3_PUBLIC_BASE_URL.trim();
        if (publicBase.length > 0) {
            return `${publicBase.replace(/\/+$/, '')}/${params.key}`;
        }
        if (params.category === 'chats') {
            return `/media/chats/file?key=${encodeURIComponent(params.key)}`;
        }
        return `/media/object?category=${encodeURIComponent(params.category)}&key=${encodeURIComponent(params.key)}`;
    }
    resolveBucketFromKey(key) {
        const normalized = key.trim().toLowerCase();
        if (normalized.startsWith('avatars/'))
            return this.getBucketName('avatars');
        if (normalized.startsWith('listings/'))
            return this.getBucketName('listing-photos');
        if (normalized.startsWith('chats/'))
            return this.getBucketName('chat-images');
        if (normalized.startsWith('support/'))
            return this.getBucketName('support-images');
        if (normalized.startsWith('reports/'))
            return this.getBucketName('reports');
        if (normalized.startsWith('videos/'))
            return this.getBucketName('videos');
        if (normalized.startsWith('misc/'))
            return this.getBucketName('misc');
        return this.getBucketName('feed-ads');
    }
    safeErrorMessage(error) {
        const message = error instanceof Error ? error.message.trim() : 'S3 недоступен.';
        return message.length === 0 ? 'S3 недоступен.' : message;
    }
};
exports.S3Service = S3Service;
exports.S3Service = S3Service = __decorate([
    (0, common_1.Injectable)()
], S3Service);
//# sourceMappingURL=s3.service.js.map