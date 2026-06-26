"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const strict_1 = __importDefault(require("node:assert/strict"));
const client_1 = require("@prisma/client");
const wallet_service_1 = require("./wallet.service");
const DAILY_LOGIN_BONUS_REASON = client_1.WalletTransactionReason.DAILY_LOGIN_BONUS;
function createService(initial) {
    const wallet = {
        id: 'wallet-1',
        userId: 'user-1',
        bonusBalance: initial?.wallet?.bonusBalance ?? 0,
        lastBonusAccrualAt: initial?.wallet?.lastBonusAccrualAt ?? null,
    };
    const transactions = [...(initial?.transactions ?? [])];
    let transactionSequence = transactions.length;
    let queue = Promise.resolve();
    const prisma = {
        wallet: {
            upsert: async () => wallet,
            findUnique: async ({ where }) => where.userId === wallet.userId ? { ...wallet } : null,
            findUniqueOrThrow: async () => ({ ...wallet }),
            update: async ({ data }) => {
                if (typeof data.bonusBalance === 'number') {
                    wallet.bonusBalance = data.bonusBalance;
                }
                else if (data.bonusBalance &&
                    typeof data.bonusBalance === 'object' &&
                    'decrement' in data.bonusBalance) {
                    wallet.bonusBalance -= Number(data.bonusBalance.decrement);
                }
                if (data.bonusBalance &&
                    typeof data.bonusBalance === 'object' &&
                    'increment' in data.bonusBalance) {
                    wallet.bonusBalance += Number(data.bonusBalance.increment);
                }
                if ('lastBonusAccrualAt' in data) {
                    wallet.lastBonusAccrualAt =
                        data.lastBonusAccrualAt ?? null;
                }
                return { ...wallet };
            },
        },
        walletTransaction: {
            findFirst: async ({ where, select, }) => {
                const found = [...transactions]
                    .filter((item) => item.userId === where.userId && item.reason === where.reason)
                    .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())[0] ??
                    null;
                if (!found)
                    return null;
                if (!select)
                    return { ...found };
                return Object.fromEntries(Object.keys(select).map((key) => [key, found[key]]));
            },
            findMany: async ({ where, take, }) => [...transactions]
                .filter((item) => item.userId === where.userId)
                .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
                .slice(0, take ?? Number.MAX_SAFE_INTEGER)
                .map((item) => ({ ...item })),
            create: async ({ data, }) => {
                transactionSequence += 1;
                const created = {
                    id: `tx-${transactionSequence}`,
                    createdAt: data.createdAt ?? new Date(),
                    ...data,
                };
                transactions.push(created);
                return { ...created };
            },
        },
        $queryRaw: async () => undefined,
        $transaction: async (handler) => {
            let release;
            const next = new Promise((resolve) => {
                release = resolve;
            });
            const previous = queue;
            queue = queue.then(() => next);
            await previous;
            try {
                return await handler(prisma);
            }
            finally {
                release();
            }
        },
    };
    return {
        service: new wallet_service_1.WalletService(prisma),
        state: {
            wallet,
            transactions,
        },
    };
}
(0, node_test_1.test)('welcome bonus 100 is granted on first wallet bootstrap', async () => {
    const { service } = createService();
    const wallet = await service.ensureWalletAndBonuses('user-1');
    strict_1.default.equal(wallet.bonusBalance, 125);
});
(0, node_test_1.test)('daily bonus is granted only once per day', async () => {
    const { service } = createService();
    const firstWallet = await service.ensureWalletAndBonuses('user-1');
    const secondWallet = await service.checkAndAccrueDailyBonus('user-1');
    strict_1.default.equal(firstWallet.bonusBalance, 125);
    strict_1.default.equal(secondWallet.bonusBalance, 125);
});
(0, node_test_1.test)('skipped day does not accrue retroactively', async () => {
    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const { service } = createService({
        wallet: {
            bonusBalance: 250,
            lastBonusAccrualAt: yesterday,
        },
        transactions: [
            {
                id: 'tx-1',
                userId: 'user-1',
                walletId: 'wallet-1',
                type: client_1.WalletTransactionType.ACCRUAL,
                amount: 25,
                reason: DAILY_LOGIN_BONUS_REASON,
                metadata: { source: 'bonus' },
                createdAt: yesterday,
            },
        ],
    });
    const wallet = await service.checkAndAccrueDailyBonus('user-1');
    strict_1.default.equal(wallet.bonusBalance, 275);
});
(0, node_test_1.test)('daily bonus respects max balance cap', async () => {
    const { service } = createService({
        wallet: {
            bonusBalance: 990,
        },
    });
    const wallet = await service.ensureWalletAndBonuses('user-1');
    strict_1.default.equal(wallet.bonusBalance, 1000);
});
(0, node_test_1.test)('concurrent accrual does not double credit and stores daily_login_bonus reason', async () => {
    const { service, state } = createService({
        wallet: {
            bonusBalance: 100,
        },
        transactions: [
            {
                id: 'tx-1',
                userId: 'user-1',
                walletId: 'wallet-1',
                type: client_1.WalletTransactionType.ACCRUAL,
                amount: 100,
                reason: client_1.WalletTransactionReason.WELCOME_BONUS,
                metadata: { source: 'bonus' },
                createdAt: new Date(Date.now() - 1000),
            },
        ],
    });
    const [first, second] = await Promise.all([
        service.checkAndAccrueDailyBonus('user-1'),
        service.checkAndAccrueDailyBonus('user-1'),
    ]);
    strict_1.default.equal(first.bonusBalance, 125);
    strict_1.default.equal(second.bonusBalance, 125);
    strict_1.default.equal(state.transactions.filter((item) => item.reason === DAILY_LOGIN_BONUS_REASON).length, 1);
});
(0, node_test_1.test)('getWallet returns wallet payload for authorized user without throwing', async () => {
    const { service } = createService();
    const response = await service.getWallet({
        userId: 'user-1',
        sessionId: 'session-1',
        role: 'user',
    });
    strict_1.default.equal(response.balance, 125);
    strict_1.default.equal(response.dailyBonusAmount, 25);
});
(0, node_test_1.test)('checkAccrual returns wallet envelope without throwing', async () => {
    const { service } = createService();
    const response = await service.checkAccrual({
        userId: 'user-1',
        sessionId: 'session-1',
        role: 'user',
    });
    strict_1.default.equal(response.wallet.balance, 125);
});
//# sourceMappingURL=wallet.service.spec.js.map