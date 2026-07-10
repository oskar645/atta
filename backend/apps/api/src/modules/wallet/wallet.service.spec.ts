import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  WalletTransactionReason,
  WalletTransactionType,
} from '@prisma/client';

import { WalletService } from './wallet.service';

const DAILY_LOGIN_BONUS_REASON =
  WalletTransactionReason.DAILY_LOGIN_BONUS;

type WalletRecord = {
  id: string;
  userId: string;
  bonusBalance: number;
  lastBonusAccrualAt: Date | null;
};

type WalletTransactionRecord = {
  id: string;
  userId: string;
  walletId: string;
  type: WalletTransactionType;
  amount: number;
  reason: WalletTransactionReason;
  metadata: Record<string, unknown>;
  createdAt: Date;
};

function createService(initial?: {
  wallet?: Partial<WalletRecord>;
  transactions?: WalletTransactionRecord[];
  supportedReasons?: WalletTransactionReason[];
}) {
  const wallet: WalletRecord = {
    id: 'wallet-1',
    userId: 'user-1',
    bonusBalance: initial?.wallet?.bonusBalance ?? 0,
    lastBonusAccrualAt: initial?.wallet?.lastBonusAccrualAt ?? null,
  };
  const transactions = [...(initial?.transactions ?? [])];
  const supportedReasons = new Set<WalletTransactionReason>(
    initial?.supportedReasons ?? Object.values(WalletTransactionReason),
  );
  let transactionSequence = transactions.length;
  let queue = Promise.resolve();

  const prisma: Record<string, unknown> = {
    wallet: {
      upsert: async () => wallet,
      findUnique: async ({ where }: { where: { userId: string } }) =>
        where.userId === wallet.userId ? { ...wallet } : null,
      findUniqueOrThrow: async () => ({ ...wallet }),
      update: async ({ data }: { data: Record<string, unknown> }) => {
        if (typeof data.bonusBalance === 'number') {
          wallet.bonusBalance = data.bonusBalance;
        } else if (
          data.bonusBalance &&
          typeof data.bonusBalance === 'object' &&
          'decrement' in data.bonusBalance
        ) {
          wallet.bonusBalance -= Number(data.bonusBalance.decrement);
        }
        if (
          data.bonusBalance &&
          typeof data.bonusBalance === 'object' &&
          'increment' in data.bonusBalance
        ) {
          wallet.bonusBalance += Number(data.bonusBalance.increment);
        }
        if ('lastBonusAccrualAt' in data) {
          wallet.lastBonusAccrualAt =
            (data.lastBonusAccrualAt as Date | null | undefined) ?? null;
        }
        return { ...wallet };
      },
    },
    walletTransaction: {
      findFirst: async ({
        where,
        select,
      }: {
        where: {
          userId: string;
          reason: WalletTransactionReason;
        };
        select?: Record<string, boolean>;
      }) => {
        const found = [...transactions]
            .filter(
              (item) =>
                item.userId === where.userId && item.reason === where.reason,
            )
            .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())[0] ??
          null;
        if (!found) return null;
        if (!select) return { ...found };
        return Object.fromEntries(
          Object.keys(select).map((key) => [key, found[key as keyof WalletTransactionRecord]]),
        );
      },
      findMany: async ({
        where,
        take,
      }: {
        where: { userId: string; reason?: WalletTransactionReason };
        take?: number;
      }) =>
        [...transactions]
          .filter(
            (item) =>
              item.userId === where.userId &&
              (where.reason == null || item.reason === where.reason),
          )
          .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
          .slice(0, take ?? Number.MAX_SAFE_INTEGER)
          .map((item) => ({ ...item })),
      create: async ({
        data,
      }: {
        data: Omit<WalletTransactionRecord, 'id' | 'createdAt'> & {
          createdAt?: Date;
        };
      }) => {
        transactionSequence += 1;
        const created: WalletTransactionRecord = {
          id: `tx-${transactionSequence}`,
          createdAt: data.createdAt ?? new Date(),
          ...data,
        };
        transactions.push(created);
        return { ...created };
      },
    },
    $queryRaw: async (
      query: TemplateStringsArray,
      ...values: unknown[]
    ) => {
      const sql = query.join(' ');
      if (sql.includes('FROM pg_type t')) {
        const requestedReason = values[0];
        return [
          {
            exists:
              typeof requestedReason === 'string' &&
              supportedReasons.has(
                requestedReason as WalletTransactionReason,
              ),
          },
        ];
      }
      return undefined;
    },
    $transaction: async <T>(
      handler: (tx: any) => Promise<T>,
    ) => {
      let release!: () => void;
      const next = new Promise<void>((resolve) => {
        release = resolve;
      });
      const previous = queue;
      queue = queue.then(() => next);
      await previous;
      try {
        return await handler(prisma);
      } finally {
        release();
      }
    },
  };

  return {
    service: new WalletService(prisma as never),
    state: {
      wallet,
      transactions,
    },
  };
}

test('welcome bonus 200 is granted on first wallet bootstrap', async () => {
  const { service } = createService();

  const wallet = await service.ensureWalletAndBonuses('user-1');

  assert.equal(wallet.bonusBalance, 225);
});

test('daily bonus is granted only once per day', async () => {
  const { service } = createService();

  const firstWallet = await service.ensureWalletAndBonuses('user-1');
  const secondWallet = await service.checkAndAccrueDailyBonus('user-1');

  assert.equal(firstWallet.bonusBalance, 225);
  assert.equal(secondWallet.bonusBalance, 225);
});

test('skipped day does not accrue retroactively', async () => {
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
        type: WalletTransactionType.ACCRUAL,
        amount: 25,
        reason: DAILY_LOGIN_BONUS_REASON,
        metadata: { source: 'bonus' },
        createdAt: yesterday,
      },
    ],
  });

  const wallet = await service.checkAndAccrueDailyBonus('user-1');

  assert.equal(wallet.bonusBalance, 275);
});

test('daily bonus respects max balance cap', async () => {
  const { service } = createService({
    wallet: {
      bonusBalance: 990,
    },
  });

  const wallet = await service.ensureWalletAndBonuses('user-1');

  assert.equal(wallet.bonusBalance, 1000);
});

test('concurrent accrual does not double credit and stores daily_login_bonus reason', async () => {
  const { service, state } = createService({
    wallet: {
      bonusBalance: 100,
    },
    transactions: [
      {
        id: 'tx-1',
        userId: 'user-1',
        walletId: 'wallet-1',
        type: WalletTransactionType.ACCRUAL,
        amount: 100,
        reason: WalletTransactionReason.WELCOME_BONUS,
        metadata: { source: 'bonus' },
        createdAt: new Date(Date.now() - 1000),
      },
    ],
  });

  const [first, second] = await Promise.all([
    service.checkAndAccrueDailyBonus('user-1'),
    service.checkAndAccrueDailyBonus('user-1'),
  ]);

  assert.equal(first.bonusBalance, 125);
  assert.equal(second.bonusBalance, 125);
  assert.equal(
    state.transactions.filter(
      (item) => item.reason === DAILY_LOGIN_BONUS_REASON,
    ).length,
    1,
  );
});

test('manual admin test bonus credits only once and stores russian description', async () => {
  const { service, state } = createService({
    wallet: {
      bonusBalance: 300,
    },
  });

  const first = await service.accrueManualBonusIfNeeded('user-1', {
    amount: 5000,
    reference: 'ADMIN_TEST_BONUS_5000_2026_07',
    description: 'Тестовые бонусы от администрации ATTA',
  });
  const second = await service.accrueManualBonusIfNeeded('user-1', {
    amount: 5000,
    reference: 'ADMIN_TEST_BONUS_5000_2026_07',
    description: 'Тестовые бонусы от администрации ATTA',
  });

  assert.equal(first.applied, true);
  assert.equal(second.applied, false);
  assert.equal(first.wallet.bonusBalance, 5300);
  assert.equal(second.wallet.bonusBalance, 5300);
  assert.equal(
    state.transactions.filter(
      (item) =>
        item.reason === WalletTransactionReason.RECURRING_BONUS &&
        item.metadata.reference === 'ADMIN_TEST_BONUS_5000_2026_07',
    ).length,
    1,
  );
  assert.equal(
    state.transactions.find(
      (item) => item.metadata.reference === 'ADMIN_TEST_BONUS_5000_2026_07',
    )?.metadata.description,
    'Тестовые бонусы от администрации ATTA',
  );
});

test('getWallet returns wallet payload for authorized user without throwing', async () => {
  const { service } = createService();

  const response = await service.getWallet({
    userId: 'user-1',
    sessionId: 'session-1',
    role: 'user',
  });

  assert.equal(response.balance, 225);
  assert.equal(response.dailyBonusAmount, 25);
});

test('checkAccrual returns wallet envelope without throwing', async () => {
  const { service } = createService();

  const response = await service.checkAccrual({
    userId: 'user-1',
    sessionId: 'session-1',
    role: 'user',
  });

  assert.equal(response.wallet.balance, 225);
});

test('resolveSpendReason keeps promotion reason when enum value exists in database', async () => {
  const { service } = createService();

  const reason = await service.resolveSpendReason(
    WalletTransactionReason.PROMOTION_SHOWCASE,
  );

  assert.equal(reason, WalletTransactionReason.PROMOTION_SHOWCASE);
});

test('resolveSpendReason falls back when promotion enum value is missing in database', async () => {
  const { service } = createService({
    supportedReasons: [
      WalletTransactionReason.WELCOME_BONUS,
      WalletTransactionReason.RECURRING_BONUS,
      WalletTransactionReason.DAILY_LOGIN_BONUS,
      WalletTransactionReason.REFUND,
    ],
  });

  const reason = await service.resolveSpendReason(
    WalletTransactionReason.PROMOTION_SHOWCASE,
  );

  assert.equal(reason, WalletTransactionReason.RECURRING_BONUS);
});
