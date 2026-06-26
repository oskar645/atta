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
exports.S3StorageProvider = void 0;
const common_1 = require("@nestjs/common");
const crypto_1 = require("crypto");
const s3_service_1 = require("../s3/s3.service");
const storage_constants_1 = require("./storage.constants");
let S3StorageProvider = class S3StorageProvider {
    constructor(s3Service) {
        this.s3Service = s3Service;
    }
    getName() {
        return 's3';
    }
    async ensureReady() {
        if (!this.s3Service.isConfigured()) {
            throw new common_1.ServiceUnavailableException('S3 хранилище не настроено.');
        }
    }
    async getHealth() {
        return this.s3Service.getHealthStatus();
    }
    async saveFile(params) {
        await this.ensureReady();
        const mimeType = params.contentType.trim().toLowerCase();
        const extension = (0, storage_constants_1.pickExtension)(mimeType, params.originalName);
        const fileName = `${(0, crypto_1.randomUUID)()}${extension}`;
        const key = (0, storage_constants_1.buildScopedStorageKey)(params.category, fileName, params.context);
        const bucketAlias = storage_constants_1.STORAGE_BUCKET_ALIAS[params.category];
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
    buildPublicUrl(category, key) {
        return this.s3Service.buildMediaUrl({
            category,
            key,
        });
    }
    async readFile(_category, key) {
        return this.s3Service.readObject(key);
    }
    async deleteFile(category, key) {
        const bucketAlias = storage_constants_1.STORAGE_BUCKET_ALIAS[category];
        const bucketName = this.s3Service.getBucketName(bucketAlias);
        await this.s3Service.deleteObject(bucketName, key);
    }
};
exports.S3StorageProvider = S3StorageProvider;
exports.S3StorageProvider = S3StorageProvider = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [s3_service_1.S3Service])
], S3StorageProvider);
//# sourceMappingURL=s3-storage.provider.js.map