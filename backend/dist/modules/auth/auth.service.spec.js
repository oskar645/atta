"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const strict_1 = __importDefault(require("node:assert/strict"));
const bcryptjs_1 = require("bcryptjs");
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const auth_service_1 = require("./auth.service");
function createService(prisma, overrides) {
    return new auth_service_1.AuthService(prisma, {
        signAsync: async (payload) => `${payload.type ?? 'token'}-token`,
        verifyAsync: async () => ({}),
    }, {}, {
        ensureWalletAndBonuses: async () => undefined,
        ensureWalletAndBonusesSafely: async () => undefined,
        ...overrides?.walletService,
    });
}
(0, node_test_1.test)('loginPhone works with phone and password without phone verification', async () => {
    const service = createService({
        user: {
            findUnique: async () => ({
                id: 'user-1',
                email: null,
                phone: '79281234567',
                phoneVerified: true,
                displayName: 'ATTA User',
                name: 'ATTA User',
                avatarUrl: null,
                photoUrl: null,
                status: client_1.UserStatus.ACTIVE,
                blockedAt: null,
                blockReason: null,
                lastLoginAt: null,
                createdAt: new Date('2026-06-18T10:00:00.000Z'),
                updatedAt: new Date('2026-06-18T10:00:00.000Z'),
                deletedAt: null,
                passwordHash: (0, bcryptjs_1.hashSync)('12345678', 10),
                adminProfile: null,
            }),
            update: async () => undefined,
        },
        userSession: {
            create: async () => undefined,
        },
    });
    const response = await service.loginPhone({
        phone: '79281234567',
        password: '12345678',
    });
    strict_1.default.equal(response.user.id, 'user-1');
    strict_1.default.equal(response.auth.access_token, 'access-token');
    strict_1.default.equal(response.auth.refresh_token, 'refresh-token');
});
(0, node_test_1.test)('loginPhone does not require verificationCheckId for password login', async () => {
    const service = createService({
        user: {
            findUnique: async () => ({
                id: 'user-1',
                email: null,
                phone: '79281234567',
                phoneVerified: true,
                displayName: 'ATTA User',
                name: 'ATTA User',
                avatarUrl: null,
                photoUrl: null,
                status: client_1.UserStatus.ACTIVE,
                blockedAt: null,
                blockReason: null,
                lastLoginAt: null,
                createdAt: new Date('2026-06-18T10:00:00.000Z'),
                updatedAt: new Date('2026-06-18T10:00:00.000Z'),
                deletedAt: null,
                passwordHash: (0, bcryptjs_1.hashSync)('secret123', 10),
                adminProfile: null,
            }),
            update: async () => undefined,
        },
        userSession: {
            create: async () => undefined,
        },
    });
    const response = await service.loginPhone({
        phone: '79281234567',
        password: 'secret123',
    });
    strict_1.default.equal(response.user.id, 'user-1');
});
(0, node_test_1.test)('loginPhone returns safe code for wrong password', async () => {
    const service = createService({
        user: {
            findUnique: async () => ({
                id: 'user-1',
                email: null,
                phone: '79281234567',
                phoneVerified: true,
                displayName: 'ATTA User',
                name: 'ATTA User',
                avatarUrl: null,
                photoUrl: null,
                status: client_1.UserStatus.ACTIVE,
                blockedAt: null,
                blockReason: null,
                lastLoginAt: null,
                createdAt: new Date('2026-06-18T10:00:00.000Z'),
                updatedAt: new Date('2026-06-18T10:00:00.000Z'),
                deletedAt: null,
                passwordHash: (0, bcryptjs_1.hashSync)('secret123', 10),
                adminProfile: null,
            }),
            update: async () => undefined,
        },
        userSession: {
            create: async () => undefined,
        },
    });
    await strict_1.default.rejects(service.loginPhone({
        phone: '79281234567',
        password: 'wrongpass',
    }), (error) => {
        strict_1.default.ok(error instanceof common_1.HttpException);
        strict_1.default.equal(error.getStatus(), 401);
        strict_1.default.deepEqual(error.getResponse(), {
            code: 'INVALID_PHONE_OR_PASSWORD',
            message: 'Неверный номер телефона или пароль',
        });
        return true;
    });
});
(0, node_test_1.test)('loginPhone returns safe validation error for empty password', async () => {
    const service = createService({
        user: {
            findUnique: async () => null,
            update: async () => undefined,
        },
        userSession: {
            create: async () => undefined,
        },
    });
    await strict_1.default.rejects(service.loginPhone({
        phone: '79281234567',
        password: '',
    }), (error) => {
        strict_1.default.ok(error instanceof common_1.HttpException);
        strict_1.default.equal(error.getStatus(), 400);
        strict_1.default.deepEqual(error.getResponse(), {
            code: 'PASSWORD_REQUIRED',
            message: 'Введите пароль',
        });
        return true;
    });
});
(0, node_test_1.test)('loginPhone succeeds even if wallet bootstrap fails', async () => {
    const service = createService({
        user: {
            findUnique: async () => ({
                id: 'user-1',
                email: null,
                phone: '79281234567',
                phoneVerified: true,
                displayName: 'ATTA User',
                name: 'ATTA User',
                avatarUrl: null,
                photoUrl: null,
                status: client_1.UserStatus.ACTIVE,
                blockedAt: null,
                blockReason: null,
                lastLoginAt: null,
                createdAt: new Date('2026-06-18T10:00:00.000Z'),
                updatedAt: new Date('2026-06-18T10:00:00.000Z'),
                deletedAt: null,
                passwordHash: (0, bcryptjs_1.hashSync)('12345678', 10),
                adminProfile: null,
            }),
            update: async () => undefined,
        },
        userSession: {
            create: async () => undefined,
        },
    }, {
        walletService: {
            ensureWalletAndBonusesSafely: async () => {
                throw new Error('wallet failed');
            },
        },
    });
    const response = await service.loginPhone({
        phone: '79281234567',
        password: '12345678',
    });
    strict_1.default.equal(response.user.id, 'user-1');
    strict_1.default.equal(response.auth.access_token, 'access-token');
});
(0, node_test_1.test)('getMe does not crash if wallet has issue', async () => {
    const service = createService({
        user: {
            findUnique: async () => ({
                id: 'user-1',
                email: null,
                phone: '79281234567',
                phoneVerified: true,
                displayName: 'ATTA User',
                name: 'ATTA User',
                avatarUrl: null,
                photoUrl: null,
                status: client_1.UserStatus.ACTIVE,
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
        walletService: {
            ensureWalletAndBonusesSafely: async () => {
                throw new Error('wallet failed');
            },
        },
    });
    const response = await service.getMe({
        userId: 'user-1',
        sessionId: 'session-1',
        role: 'user',
        email: null,
    });
    strict_1.default.equal(response.user.id, 'user-1');
});
//# sourceMappingURL=auth.service.spec.js.map