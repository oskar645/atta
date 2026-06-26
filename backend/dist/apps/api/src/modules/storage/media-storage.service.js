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
exports.MediaStorageService = void 0;
const common_1 = require("@nestjs/common");
const env_1 = require("../../config/env");
const local_storage_provider_1 = require("./local-storage.provider");
const s3_storage_provider_1 = require("./s3-storage.provider");
let MediaStorageService = class MediaStorageService {
    constructor(localStorageProvider, s3StorageProvider) {
        this.localStorageProvider = localStorageProvider;
        this.s3StorageProvider = s3StorageProvider;
    }
    getProviderName() {
        return env_1.env.STORAGE_DRIVER;
    }
    getProvider() {
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
};
exports.MediaStorageService = MediaStorageService;
exports.MediaStorageService = MediaStorageService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [local_storage_provider_1.LocalStorageProvider,
        s3_storage_provider_1.S3StorageProvider])
], MediaStorageService);
//# sourceMappingURL=media-storage.service.js.map