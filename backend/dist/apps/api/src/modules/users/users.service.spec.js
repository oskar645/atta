"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const strict_1 = __importDefault(require("node:assert/strict"));
const users_service_1 = require("./users.service");
(0, node_test_1.test)('getMe does not crash if wallet has issue', async () => {
    const service = new users_service_1.UsersService({
        user: {
            findUnique: async () => ({
                id: 'user-1',
                email: 'user@example.com',
                phone: null,
                phoneVerified: false,
                displayName: 'ATTA User',
                name: 'ATTA User',
                avatarUrl: null,
                photoUrl: null,
                status: 'ACTIVE',
                blockedAt: null,
                blockReason: null,
                lastLoginAt: null,
                createdAt: new Date('2026-06-18T10:00:00.000Z'),
                updatedAt: new Date('2026-06-18T10:00:00.000Z'),
                deletedAt: null,
                adminProfile: null,
            }),
        },
    }, {}, {
        ensureWalletAndBonusesSafely: async () => {
            throw new Error('wallet failed');
        },
    });
    const response = await service.getMe({
        userId: 'user-1',
        sessionId: 'session-1',
        role: 'user',
        email: 'user@example.com',
    });
    strict_1.default.equal(response.user.id, 'user-1');
    strict_1.default.equal(response.isAdmin, false);
});
(0, node_test_1.test)('avatar upload uses selected storage provider flow', async () => {
    const storageCalls = [];
    const service = new users_service_1.UsersService({
        user: {
            findUnique: async () => ({
                id: 'user-1',
                email: 'user@example.com',
                phone: null,
                phoneVerified: false,
                displayName: 'ATTA User',
                name: 'ATTA User',
                avatarUrl: 'https://atta.local/uploads/avatars/old.jpg',
                photoUrl: 'https://atta.local/uploads/avatars/old.jpg',
                status: 'ACTIVE',
                blockedAt: null,
                blockReason: null,
                lastLoginAt: null,
                createdAt: new Date('2026-06-18T10:00:00.000Z'),
                updatedAt: new Date('2026-06-18T10:00:00.000Z'),
                deletedAt: null,
                adminProfile: null,
            }),
            update: async () => ({
                id: 'user-1',
                email: 'user@example.com',
                phone: null,
                phoneVerified: false,
                displayName: 'ATTA User',
                name: 'ATTA User',
                avatarUrl: 'https://s3.twcstorage.ru/atta-media-prod/avatars/user-1/new.jpg',
                photoUrl: 'https://s3.twcstorage.ru/atta-media-prod/avatars/user-1/new.jpg',
                status: 'ACTIVE',
                blockedAt: null,
                blockReason: null,
                lastLoginAt: null,
                createdAt: new Date('2026-06-18T10:00:00.000Z'),
                updatedAt: new Date('2026-06-18T10:00:00.000Z'),
                deletedAt: null,
                adminProfile: null,
            }),
        },
    }, {
        deleteAvatarUrl: async () => undefined,
        saveUploadedFile: async (payload) => {
            storageCalls.push(payload);
            return {
                bucket: 'atta-media-prod',
                key: 'avatars/user-1/new.jpg',
                mimeType: 'image/jpeg',
                provider: 's3',
                sizeBytes: 12,
                url: 'https://s3.twcstorage.ru/atta-media-prod/avatars/user-1/new.jpg',
            };
        },
    }, {
        ensureWalletAndBonusesSafely: async () => undefined,
    });
    const response = await service.uploadAvatar({ userId: 'user-1', role: 'user' }, {
        buffer: Buffer.from('avatar'),
        mimetype: 'image/jpeg',
        originalname: 'avatar.jpg',
    });
    strict_1.default.equal(storageCalls.length, 1);
    strict_1.default.equal(storageCalls[0].category, 'avatars');
    strict_1.default.deepEqual(storageCalls[0].context, { userId: 'user-1' });
    strict_1.default.match(response.avatar_url, /avatars\/user-1\/new\.jpg/);
});
//# sourceMappingURL=users.service.spec.js.map