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
  idempotencyKey?: string | null;
  metadata: Record<string, unknown>;
  createdAt: Date;
};

type ReferralRecord = {
  id: string;
  inviterUserId: string;
  invitedUserId: string;
  referralCode: string;
  walletTransactionId?: string | null;
  createdAt: Date;
};

function createService(initial?: {
  wallet?: Partial<WalletRecord>;
  userCreatedAt?: Date;
  now?: Date;
  transactions?: WalletTransactionRecord[];
  referrals?: ReferralRecord[];
  supportedReasons?: WalletTransactionReason[];
  failWalletTransactionCreate?: boolean;
  failReferralCreate?: boolean;
}) {
  const wallet: WalletRecord = {
    id: 'wallet-1',
    userId: 'user-1',
    bonusBalance: initial?.wallet?.bonusBalance ?? 0,
    lastBonusAccrualAt: initial?.wallet?.lastBonusAccrualAt ?? null,
  };
  const transactions = [...(initial?.transactions ?? [])];
  const referrals = [...(initial?.referrals ?? [])];
  const userCreatedAt =
    initial?.userCreatedAt ?? new Date('2026-07-26T12:00:00.000Z');
  const now = initial?.now ?? new Date('2026-07-27T09:00:00.000Z');
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
    user: {
      findUniqueOrThrow: async () => ({
        id: wallet.userId,
        createdAt: userCreatedAt,
      }),
    },
    walletTransaction: {
      findFirst: async ({
        where,
        select,
      }: {
        where: {
          userId: string;
          reason:
            | WalletTransactionReason
            | { in: WalletTransactionReason[] };
        };
        select?: Record<string, boolean>;
      }) => {
        const reasons =
          typeof where.reason === 'object' && 'in' in where.reason
            ? where.reason.in
            : [where.reason];
        const found = [...transactions]
            .filter(
              (item) =>
                item.userId === where.userId && reasons.includes(item.reason),
            )
            .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())[0] ??
          null;
        if (!found) return null;
        if (!select) return { ...found };
        return Object.fromEntries(
          Object.keys(select).map((key) => [key, found[key as keyof WalletTransactionRecord]]),
        );
      },
      findUnique: async ({
        where,
      }: {
        where: { idempotencyKey: string };
      }) =>
        transactions.find(
          (item) => item.idempotencyKey === where.idempotencyKey,
        ) ?? null,
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
        if (initial?.failWalletTransactionCreate) {
          throw new Error('wallet transaction create failed');
        }
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
    referral: {
      findUnique: async ({
        where,
      }: {
        where: { invitedUserId?: string; walletTransactionId?: string };
      }) =>
        referrals.find(
          (item) =>
            (where.invitedUserId != null &&
              item.invitedUserId === where.invitedUserId) ||
            (where.walletTransactionId != null &&
              item.walletTransactionId === where.walletTransactionId),
        ) ?? null,
      create: async ({
        data,
      }: {
        data: Omit<ReferralRecord, 'id' | 'createdAt'> & {
          createdAt?: Date;
        };
      }) => {
        if (initial?.failReferralCreate) {
          throw new Error('referral create failed');
        }
        if (referrals.some((item) => item.invitedUserId === data.invitedUserId)) {
          throw new Error('duplicate referral invited user');
        }
        const created: ReferralRecord = {
          id: `referral-${referrals.length + 1}`,
          createdAt: data.createdAt ?? new Date(),
          ...data,
        };
        referrals.push(created);
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
      const walletSnapshot = { ...wallet };
      const transactionsSnapshot = [...transactions];
      const referralsSnapshot = [...referrals];
      try {
        return await handler(prisma);
      } catch (error) {
        Object.assign(wallet, walletSnapshot);
        transactions.splice(0, transactions.length, ...transactionsSnapshot);
        referrals.splice(0, referrals.length, ...referralsSnapshot);
        throw error;
      } finally {
        release();
      }
    },
  };

  return {
    service: new WalletService(prisma as never, () => now),
    state: {
      wallet,
      transactions,
      referrals,
    },
  };
}

test('signup bonus 500 is granted once on first wallet bootstrap', async () => {
  const { service } = createService();

  const wallet = await service.ensureWalletAndBonuses('user-1');
  const secondWallet = await service.ensureWalletAndBonuses('user-1');

  assert.equal(wallet.bonusBalance, 500);
  assert.equal(secondWallet.bonusBalance, 500);
});

test('daily bonus is granted only once per day', async () => {
  const { service } = createService();

  await service.ensureWalletAndBonuses('user-1');
  const firstWallet = await service.checkAndAccrueDailyBonus('user-1');
  const secondWallet = await service.checkAndAccrueDailyBonus('user-1');

  assert.equal(firstWallet.bonusBalance, 525);
  assert.equal(secondWallet.bonusBalance, 525);
});

test('daily bonus is skipped on registration calendar day', async () => {
  const { service } = createService({
    userCreatedAt: new Date('2026-07-27T06:00:00.000Z'),
    now: new Date('2026-07-27T20:50:00.000Z'),
  });

  await service.ensureWalletAndBonuses('user-1');
  const response = await service.checkAccrual({
    userId: 'user-1',
    sessionId: 'session-1',
    role: 'user',
  });

  assert.equal(response.awarded, false);
  assert.equal(response.amount, 0);
  assert.equal(response.reason, 'registration_day');
  assert.equal(response.wallet.balance, 500);
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

test('daily bonus does not respect old max balance cap', async () => {
  const { service } = createService({
    wallet: {
      bonusBalance: 990,
    },
    transactions: [
      {
        id: 'tx-1',
        userId: 'user-1',
        walletId: 'wallet-1',
        type: WalletTransactionType.ACCRUAL,
        amount: 500,
        reason: WalletTransactionReason.SIGNUP_BONUS,
        idempotencyKey: 'signup_bonus:user-1',
        metadata: { source: 'signup_bonus' },
        createdAt: new Date('2026-07-26T12:00:00.000Z'),
      },
    ],
  });

  const wallet = await service.checkAndAccrueDailyBonus('user-1');

  assert.equal(wallet.bonusBalance, 1015);
});

test('daily bonus credits balances at 1000, 5000 and 1000000', async () => {
  for (const [balance, expected] of [
    [1000, 1025],
    [5000, 5025],
    [1000000, 1000025],
  ] as const) {
    const { service } = createService({
      wallet: {
        bonusBalance: balance,
      },
      transactions: [
        {
          id: 'tx-1',
          userId: 'user-1',
          walletId: 'wallet-1',
          type: WalletTransactionType.ACCRUAL,
          amount: 500,
          reason: WalletTransactionReason.SIGNUP_BONUS,
          idempotencyKey: 'signup_bonus:user-1',
          metadata: { source: 'signup_bonus' },
          createdAt: new Date('2026-07-26T12:00:00.000Z'),
        },
      ],
    });

    const wallet = await service.checkAndAccrueDailyBonus('user-1');

    assert.equal(wallet.bonusBalance, expected);
  }
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

test('referral inviter bonus credits exactly once with referral reason and idempotency key', async () => {
  const { service, state } = createService({
    wallet: {
      bonusBalance: 300,
    },
  });

  const first = await service.accrueReferralInviterBonusIfNeeded('user-1', {
    invitedUserId: 'new-user-1',
    referralCode: 'REF-CODE-1',
  });
  const second = await service.accrueReferralInviterBonusIfNeeded('user-1', {
    invitedUserId: 'new-user-1',
    referralCode: 'OTHER-REF-CODE',
  });

  assert.equal(first.applied, true);
  assert.equal(second.applied, false);
  assert.equal(first.wallet.bonusBalance, 400);
  assert.equal(second.wallet.bonusBalance, 400);
  assert.equal(
    state.transactions.filter(
      (item) =>
        item.reason === WalletTransactionReason.REFERRAL_INVITER_BONUS &&
        item.idempotencyKey === 'referral_inviter_bonus:new-user-1',
    ).length,
    1,
  );
  assert.equal(
    state.transactions.find(
      (item) => item.idempotencyKey === 'referral_inviter_bonus:new-user-1',
    )?.metadata.description,
    'Реферальный бонус за приглашение нового пользователя',
  );
  assert.equal(state.referrals.length, 1);
  assert.equal(state.referrals[0]?.inviterUserId, 'user-1');
  assert.equal(state.referrals[0]?.invitedUserId, 'new-user-1');
});

test('referral inviter bonus is skipped when invited user already has referral link', async () => {
  const { service, state } = createService({
    wallet: {
      bonusBalance: 300,
    },
    referrals: [
      {
        id: 'referral-1',
        inviterUserId: 'other-user',
        invitedUserId: 'new-user-1',
        referralCode: 'OTHER-REF-CODE',
        walletTransactionId: null,
        createdAt: new Date('2026-07-27T09:00:00.000Z'),
      },
    ],
  });

  const result = await service.accrueReferralInviterBonusIfNeeded('user-1', {
    invitedUserId: 'new-user-1',
    referralCode: 'REF-CODE-1',
  });

  assert.equal(result.applied, false);
  assert.equal(result.wallet.bonusBalance, 300);
  assert.equal(state.transactions.length, 0);
  assert.equal(state.referrals.length, 1);
});

test('referral inviter bonus blocks self-referral', async () => {
  const { service } = createService();

  await assert.rejects(
    service.accrueReferralInviterBonusIfNeeded('user-1', {
      invitedUserId: 'user-1',
      referralCode: 'REF-CODE-1',
    }),
    /Self-referral is not allowed/,
  );
});

test('referral inviter bonus rolls back balance when transaction history creation fails', async () => {
  const { service, state } = createService({
    wallet: {
      bonusBalance: 300,
    },
    failWalletTransactionCreate: true,
  });

  await assert.rejects(
    service.accrueReferralInviterBonusIfNeeded('user-1', {
      invitedUserId: 'new-user-1',
      referralCode: 'REF-CODE-1',
    }),
    /wallet transaction create failed/,
  );

  assert.equal(state.wallet.bonusBalance, 300);
  assert.equal(state.transactions.length, 0);
  assert.equal(state.referrals.length, 0);
});

test('referral inviter bonus rolls back balance and history when referral link creation fails', async () => {
  const { service, state } = createService({
    wallet: {
      bonusBalance: 300,
    },
    failReferralCreate: true,
  });

  await assert.rejects(
    service.accrueReferralInviterBonusIfNeeded('user-1', {
      invitedUserId: 'new-user-1',
      referralCode: 'REF-CODE-1',
    }),
    /referral create failed/,
  );

  assert.equal(state.wallet.bonusBalance, 300);
  assert.equal(state.transactions.length, 0);
  assert.equal(state.referrals.length, 0);
});

test('getWallet returns wallet payload for authorized user without throwing', async () => {
  const { service } = createService();

  const response = await service.getWallet({
    userId: 'user-1',
    sessionId: 'session-1',
    role: 'user',
  });

  assert.equal(response.balance, 500);
  assert.equal(response.dailyBonusAmount, 25);
});

test('checkAccrual returns wallet envelope without throwing', async () => {
  const { service } = createService();

  const response = await service.checkAccrual({
    userId: 'user-1',
    sessionId: 'session-1',
    role: 'user',
  });

  assert.equal(response.awarded, true);
  assert.equal(response.amount, 25);
  assert.equal(response.wallet.balance, 525);
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
      WalletTransactionReason.SIGNUP_BONUS,
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
