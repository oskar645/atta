"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const promises_1 = require("node:fs/promises");
const node_path_1 = require("node:path");
const node_os_1 = require("node:os");
const node_test_1 = require("node:test");
const common_1 = require("@nestjs/common");
const env_1 = require("../../config/env");
const app_controller_1 = require("../../app.controller");
const local_storage_provider_1 = require("./local-storage.provider");
const s3_storage_provider_1 = require("./s3-storage.provider");
const storage_service_1 = require("./storage.service");
(0, node_test_1.test)('local storage still works when STORAGE_DRIVER=local', async () => {
    const previousDriver = env_1.env.STORAGE_DRIVER;
    const previousProvider = env_1.env.STORAGE_PROVIDER;
    const previousUploadsDir = env_1.env.LOCAL_UPLOADS_DIR;
    const previousBaseUrl = env_1.env.MEDIA_PUBLIC_BASE_URL;
    const root = await (0, promises_1.mkdtemp)((0, node_path_1.join)((0, node_os_1.tmpdir)(), 'atta-local-storage-'));
    env_1.env.STORAGE_DRIVER = 'local';
    env_1.env.STORAGE_PROVIDER = 'local';
    env_1.env.LOCAL_UPLOADS_DIR = root;
    env_1.env.MEDIA_PUBLIC_BASE_URL = 'https://atta.local/uploads';
    try {
        const provider = new local_storage_provider_1.LocalStorageProvider();
        const saved = await provider.saveFile({
            buffer: Buffer.from('hello'),
            category: 'avatars',
            contentType: 'image/png',
            originalName: 'avatar.png',
        });
        strict_1.default.equal(saved.provider, 'local');
        strict_1.default.match(saved.url, /\/uploads\/avatars\//);
        const bytes = await (0, promises_1.readFile)((0, node_path_1.join)(root, 'avatars', saved.key));
        strict_1.default.equal(bytes.toString(), 'hello');
    }
    finally {
        env_1.env.STORAGE_DRIVER = previousDriver;
        env_1.env.STORAGE_PROVIDER = previousProvider;
        env_1.env.LOCAL_UPLOADS_DIR = previousUploadsDir;
        env_1.env.MEDIA_PUBLIC_BASE_URL = previousBaseUrl;
        await (0, promises_1.rm)(root, { recursive: true, force: true });
    }
});
(0, node_test_1.test)('S3 provider builds correct key and url', async () => {
    const uploads = [];
    const provider = new s3_storage_provider_1.S3StorageProvider({
        buildMediaUrl: ({ category, key }) => `https://cdn.example.com/${category}/${key}`,
        deleteObject: async () => undefined,
        getBucketName: () => 'atta-media-prod',
        getHealthStatus: async () => ({ status: 's3_ok' }),
        isConfigured: () => true,
        readObject: async () => Buffer.from(''),
        uploadObject: async (payload) => {
            uploads.push({
                bucket: String(payload.bucket),
                key: String(payload.key),
            });
        },
    });
    const avatar = await provider.saveFile({
        buffer: Buffer.from('avatar'),
        category: 'avatars',
        contentType: 'image/jpeg',
        context: { userId: 'user-1' },
        originalName: 'avatar.jpg',
    });
    const listing = await provider.saveFile({
        buffer: Buffer.from('listing'),
        category: 'listings',
        contentType: 'image/png',
        context: { listingId: 'listing-1' },
        originalName: 'photo.png',
    });
    strict_1.default.match(uploads[0].key, /^avatars\/user-1\/.+\.jpg$/);
    strict_1.default.match(uploads[1].key, /^listings\/listing-1\/.+\.png$/);
    strict_1.default.match(avatar.url, /^https:\/\/cdn\.example\.com\/avatars\//);
    strict_1.default.match(listing.url, /^https:\/\/cdn\.example\.com\/listings\//);
});
(0, node_test_1.test)('old /uploads url remains unchanged', () => {
    const storage = new storage_service_1.StorageService({}, {}, {
        getLocalProvider: () => new local_storage_provider_1.LocalStorageProvider(),
        getProvider: () => new local_storage_provider_1.LocalStorageProvider(),
        getProviderName: () => 'local',
        getS3Provider: () => ({}),
    });
    const key = storage.extractLocalKey('avatars', 'https://atta.local/uploads/avatars/legacy.jpg');
    strict_1.default.equal(key, 'legacy.jpg');
});
(0, node_test_1.test)('failed S3 upload returns Russian error', async () => {
    const storage = new storage_service_1.StorageService({}, {}, {
        getLocalProvider: () => new local_storage_provider_1.LocalStorageProvider(),
        getProvider: () => ({
            buildPublicUrl: () => '',
            deleteFile: async () => undefined,
            ensureReady: async () => undefined,
            getHealth: async () => ({ status: 's3_error' }),
            getName: () => 's3',
            readFile: async () => Buffer.from(''),
            saveFile: async () => {
                throw new Error('boom');
            },
        }),
        getProviderName: () => 's3',
        getS3Provider: () => ({}),
    });
    await strict_1.default.rejects(storage.saveUploadedFile({
        buffer: Buffer.from('x'),
        category: 'avatars',
        contentType: 'image/png',
        originalName: 'x.png',
    }), (error) => error instanceof common_1.ServiceUnavailableException &&
        error.message === 'Не удалось загрузить файл. Попробуйте позже.');
});
(0, node_test_1.test)('health dependencies returns s3_ok and s3_error', async () => {
    const controllerOk = new app_controller_1.AppController({ $queryRaw: async () => 1 }, { ping: async () => 'PONG' }, { getHealthStatus: async () => ({ status: 's3_ok' }) });
    const controllerError = new app_controller_1.AppController({ $queryRaw: async () => 1 }, { ping: async () => 'PONG' }, {
        getHealthStatus: async () => ({
            status: 's3_error',
            message: 'S3 недоступен.',
        }),
    });
    const ok = await controllerOk.getDependenciesHealth();
    const error = await controllerError.getDependenciesHealth();
    strict_1.default.equal(ok.storage, 's3_ok');
    strict_1.default.equal(ok.storage_message, null);
    strict_1.default.equal(error.storage, 's3_error');
    strict_1.default.equal(error.storage_message, 'S3 недоступен.');
});
//# sourceMappingURL=storage.service.spec.js.map