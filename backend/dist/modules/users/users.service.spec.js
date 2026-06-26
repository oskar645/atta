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
//# sourceMappingURL=users.service.spec.js.map