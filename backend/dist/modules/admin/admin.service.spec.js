"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const strict_1 = __importDefault(require("node:assert/strict"));
const client_1 = require("@prisma/client");
const admin_service_1 = require("./admin.service");
function createService(prisma) {
    return new admin_service_1.AdminService(prisma, {}, {}, {});
}
(0, node_test_1.test)('admin promotions list works', async () => {
    const service = createService({
        promotion: {
            updateMany: async () => ({ count: 0 }),
            findMany: async () => [
                {
                    id: 'promo-1',
                    listingId: 'listing-1',
                    userId: 'user-1',
                    type: client_1.PromotionType.SHOWCASE,
                    status: client_1.PromotionStatus.ACTIVE,
                    costBonus: 50,
                    startsAt: new Date('2026-06-18T10:00:00.000Z'),
                    endsAt: new Date('2026-06-19T10:00:00.000Z'),
                    impressionsCount: 12,
                    clicksCount: 3,
                    createdAt: new Date('2026-06-18T09:00:00.000Z'),
                    listing: {
                        title: 'Bike',
                        photos: [{ publicUrl: 'https://cdn.example.com/bike.jpg' }],
                    },
                    user: {
                        displayName: 'Seller',
                        name: 'Seller',
                        phone: '+79990000000',
                    },
                },
            ],
        },
    });
    const response = await service.listPromotions({});
    strict_1.default.equal(response.items.length, 1);
    strict_1.default.equal(response.items[0].type, 'showcase');
});
(0, node_test_1.test)('admin promotion summary works', async () => {
    const counts = [1, 2, 3, 4, 5];
    let countIndex = 0;
    const service = createService({
        promotion: {
            updateMany: async () => ({ count: 0 }),
            count: async () => counts[countIndex++],
            aggregate: async () => ({
                _sum: {
                    costBonus: 120,
                    impressionsCount: 88,
                    clicksCount: 9,
                },
            }),
        },
    });
    const response = await service.getPromotionsSummary();
    strict_1.default.equal(response.activeShowcaseCount, 1);
    strict_1.default.equal(response.totalBonusSpentToday, 120);
    strict_1.default.equal(response.totalShowcaseClicks, 9);
});
(0, node_test_1.test)('admin wallet transactions list works', async () => {
    const service = createService({
        walletTransaction: {
            findMany: async () => [
                {
                    id: 'tx-1',
                    userId: 'user-1',
                    type: client_1.WalletTransactionType.SPEND,
                    amount: 50,
                    reason: client_1.WalletTransactionReason.PROMOTION_SHOWCASE,
                    metadata: { source: 'bonus' },
                    createdAt: new Date('2026-06-18T12:00:00.000Z'),
                    user: {
                        displayName: 'Seller',
                        name: 'Seller',
                        phone: '+79990000000',
                    },
                },
            ],
        },
    });
    const response = await service.listWalletTransactions({});
    strict_1.default.equal(response.items.length, 1);
    strict_1.default.equal(response.items[0].reason, 'promotion_showcase');
});
(0, node_test_1.test)('admin bonus analytics works', async () => {
    const service = createService({
        walletTransaction: {
            findMany: async () => [
                {
                    userId: 'user-1',
                    type: client_1.WalletTransactionType.ACCRUAL,
                    amount: 25,
                    reason: client_1.WalletTransactionReason.WELCOME_BONUS,
                    createdAt: new Date('2026-06-18T12:00:00.000Z'),
                },
                {
                    userId: 'user-1',
                    type: client_1.WalletTransactionType.SPEND,
                    amount: 50,
                    reason: client_1.WalletTransactionReason.PROMOTION_SHOWCASE,
                    createdAt: new Date('2026-06-18T13:00:00.000Z'),
                },
                {
                    userId: 'user-2',
                    type: client_1.WalletTransactionType.REFUND,
                    amount: 10,
                    reason: client_1.WalletTransactionReason.PROMOTION_TURBO,
                    createdAt: new Date('2026-06-18T14:00:00.000Z'),
                },
            ],
        },
        wallet: {
            count: async () => 2,
        },
    });
    const response = await service.getBonusAnalytics({ period: 'day' });
    strict_1.default.equal(response.totalBonusAccrued, 25);
    strict_1.default.equal(response.totalBonusSpent, 50);
    strict_1.default.equal(response.totalBonusRefunded, 10);
    strict_1.default.equal(response.spentByReason.promotion_showcase, 50);
});
//# sourceMappingURL=admin.service.spec.js.map