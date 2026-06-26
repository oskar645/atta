"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.LocalStorageProvider = void 0;
const common_1 = require("@nestjs/common");
const crypto_1 = require("crypto");
const fs_1 = require("fs");
const path_1 = require("path");
const env_1 = require("../../config/env");
const storage_constants_1 = require("./storage.constants");
let LocalStorageProvider = class LocalStorageProvider {
    getName() {
        return 'local';
    }
    async ensureReady() {
        await Promise.all(Object.values(storage_constants_1.STORAGE_CATEGORY_DIR).map((dir) => fs_1.promises.mkdir((0, path_1.join)(env_1.env.LOCAL_UPLOADS_DIR, dir), { recursive: true })));
    }
    async getHealth() {
        try {
            await this.ensureReady();
            return { status: 'local_ok' };
        }
        catch {
            return {
                status: 'local_error',
                message: 'Локальное хранилище недоступно.',
            };
        }
    }
    async saveFile(params) {
        await this.ensureReady();
        const mimeType = params.contentType.trim().toLowerCase();
        const extension = (0, storage_constants_1.pickExtension)(mimeType, params.originalName);
        const fileName = `${(0, crypto_1.randomUUID)()}${extension}`;
        const absolutePath = (0, path_1.join)(env_1.env.LOCAL_UPLOADS_DIR, storage_constants_1.STORAGE_CATEGORY_DIR[params.category], fileName);
        await fs_1.promises.writeFile(absolutePath, params.buffer);
        return {
            bucket: null,
            key: fileName,
            mimeType,
            provider: 'local',
            sizeBytes: params.buffer.byteLength,
            url: this.buildPublicUrl(params.category, fileName),
        };
    }
    buildPublicUrl(category, key) {
        const base = env_1.env.MEDIA_PUBLIC_BASE_URL.replace(/\/+$/, '');
        return `${base}/${storage_constants_1.STORAGE_CATEGORY_DIR[category]}/${(0, path_1.basename)(key)}`;
    }
    async readFile(category, key) {
        const filePath = (0, path_1.join)(env_1.env.LOCAL_UPLOADS_DIR, storage_constants_1.STORAGE_CATEGORY_DIR[category], (0, path_1.basename)(key));
        return fs_1.promises.readFile(filePath);
    }
    async deleteFile(category, key) {
        const filePath = (0, path_1.join)(env_1.env.LOCAL_UPLOADS_DIR, storage_constants_1.STORAGE_CATEGORY_DIR[category], (0, path_1.basename)(key));
        await fs_1.promises.rm(filePath, { force: true });
    }
};
exports.LocalStorageProvider = LocalStorageProvider;
exports.LocalStorageProvider = LocalStorageProvider = __decorate([
    (0, common_1.Injectable)()
], LocalStorageProvider);
//# sourceMappingURL=local-storage.provider.js.map