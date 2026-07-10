import { test } from 'node:test';
import assert from 'node:assert/strict';

import { hashSync } from 'bcryptjs';
import { HttpException } from '@nestjs/common';
import { UserStatus } from '@prisma/client';

import { buildReferralCode } from '../../common/referral-code';
import { AuthService } from './auth.service';

function createService(
  prisma: Record<string, unknown>,
  overrides?: {
    walletService?: {
      ensureWalletAndBonuses?: (userId: string) => Promise<unknown>;
      ensureWalletAndBonusesSafely?: (userId: string) => Promise<unknown>;
      accrueManualBonusIfNeeded?: (
        userId: string,
        params: {
          amount: number;
          reference: string;
          description: string;
          source?: string;
          metadata?: Record<string, unknown>;
        },
      ) => Promise<unknown>;
    };
  },
) {
  return new AuthService(
    prisma as never,
    {
      signAsync: async (payload: Record<string, unknown>) =>
        `${payload.type ?? 'token'}-token`,
      verifyAsync: async () => ({}),
    } as never,
    {} as never,
    {
      ensureWalletAndBonuses: async () => undefined,
      ensureWalletAndBonusesSafely: async () => undefined,
      accrueManualBonusIfNeeded: async () => undefined,
      ...overrides?.walletService,
    } as never,
  );
}

const baseActiveUser = (overrides?: Partial<Record<string, unknown>>) => ({
  id: 'user-1',
  email: null,
  phone: '79281234567',
  phoneVerified: true,
  displayName: 'ATTA User',
  name: 'ATTA User',
  avatarUrl: null,
  photoUrl: null,
  status: UserStatus.ACTIVE,
  blockedAt: null,
  blockReason: null,
  lastLoginAt: null,
  createdAt: new Date('2026-06-18T10:00:00.000Z'),
  updatedAt: new Date('2026-06-18T10:00:00.000Z'),
  deletedAt: null,
  passwordHash: hashSync('12345678', 10),
  adminProfile: null,
  ...overrides,
});

test('loginPhone works with phone and password without phone verification', async () => {
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
        status: UserStatus.ACTIVE,
        blockedAt: null,
        blockReason: null,
        lastLoginAt: null,
        createdAt: new Date('2026-06-18T10:00:00.000Z'),
        updatedAt: new Date('2026-06-18T10:00:00.000Z'),
        deletedAt: null,
        passwordHash: hashSync('12345678', 10),
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

  assert.equal(response.user.id, 'user-1');
  assert.equal(response.auth.access_token, 'access-token');
  assert.equal(response.auth.refresh_token, 'refresh-token');
});

test('loginPhone does not require verificationCheckId for password login', async () => {
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
        status: UserStatus.ACTIVE,
        blockedAt: null,
        blockReason: null,
        lastLoginAt: null,
        createdAt: new Date('2026-06-18T10:00:00.000Z'),
        updatedAt: new Date('2026-06-18T10:00:00.000Z'),
        deletedAt: null,
        passwordHash: hashSync('secret123', 10),
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

  assert.equal(response.user.id, 'user-1');
});

test('loginPhone returns safe code for wrong password', async () => {
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
        status: UserStatus.ACTIVE,
        blockedAt: null,
        blockReason: null,
        lastLoginAt: null,
        createdAt: new Date('2026-06-18T10:00:00.000Z'),
        updatedAt: new Date('2026-06-18T10:00:00.000Z'),
        deletedAt: null,
        passwordHash: hashSync('secret123', 10),
        adminProfile: null,
      }),
      update: async () => undefined,
    },
    userSession: {
      create: async () => undefined,
    },
  });

  await assert.rejects(
    service.loginPhone({
      phone: '79281234567',
      password: 'wrongpass',
    }),
    (error: unknown) => {
      assert.ok(error instanceof HttpException);
      assert.equal(error.getStatus(), 401);
      assert.deepEqual(error.getResponse(), {
        code: 'INVALID_PHONE_OR_PASSWORD',
        message: 'Неверный номер телефона или пароль',
      });
      return true;
    },
  );
});

test('loginPhone returns safe validation error for empty password', async () => {
  const service = createService({
    user: {
      findUnique: async () => null,
      update: async () => undefined,
    },
    userSession: {
      create: async () => undefined,
    },
  });

  await assert.rejects(
    service.loginPhone({
      phone: '79281234567',
      password: '',
    }),
    (error: unknown) => {
      assert.ok(error instanceof HttpException);
      assert.equal(error.getStatus(), 400);
      assert.deepEqual(error.getResponse(), {
        code: 'PASSWORD_REQUIRED',
        message: 'Введите пароль',
      });
      return true;
    },
  );
});

test('loginPhone succeeds even if wallet bootstrap fails', async () => {
  const service = createService(
    {
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
          status: UserStatus.ACTIVE,
          blockedAt: null,
          blockReason: null,
          lastLoginAt: null,
          createdAt: new Date('2026-06-18T10:00:00.000Z'),
          updatedAt: new Date('2026-06-18T10:00:00.000Z'),
          deletedAt: null,
          passwordHash: hashSync('12345678', 10),
          adminProfile: null,
        }),
        update: async () => undefined,
      },
      userSession: {
        create: async () => undefined,
      },
    },
    {
      walletService: {
        ensureWalletAndBonusesSafely: async () => {
          throw new Error('wallet failed');
        },
      },
    },
  );

  const response = await service.loginPhone({
    phone: '79281234567',
    password: '12345678',
  });

  assert.equal(response.user.id, 'user-1');
  assert.equal(response.auth.access_token, 'access-token');
});

test('getMe does not crash if wallet has issue', async () => {
  const service = createService(
    {
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
          status: UserStatus.ACTIVE,
          blockedAt: null,
          blockReason: null,
          lastLoginAt: null,
          createdAt: new Date('2026-06-18T10:00:00.000Z'),
          updatedAt: new Date('2026-06-18T10:00:00.000Z'),
          deletedAt: null,
          adminProfile: null,
        }),
      },
    },
    {
      walletService: {
        ensureWalletAndBonusesSafely: async () => {
          throw new Error('wallet failed');
        },
      },
    },
  );

  const response = await service.getMe({
    userId: 'user-1',
    sessionId: 'session-1',
    role: 'user',
    email: null,
  });

  assert.equal(response.user.id, 'user-1');
});

test('signupPhone accrues inviter bonus once for valid referral after successful registration', async () => {
  const inviter = baseActiveUser({
    id: 'inviter-1',
    phone: '79281230000',
    displayName: 'Inviter',
    name: 'Inviter',
  });
  const createdUser = baseActiveUser({
    id: 'new-user-1',
    phone: '79281234567',
    displayName: 'New User',
    name: 'New User',
  });
  const bonusCalls: Array<{ userId: string; params: Record<string, unknown> }> =
    [];

  const service = createService(
    {
      phoneVerification: {
        findUnique: async () => ({
          id: 'verification-1',
          phone: '79281234567',
          purpose: 'SIGNUP',
          status: 'CONFIRMED',
        }),
        update: async () => undefined,
        findFirst: async () => null,
      },
      user: {
        findUnique: async ({ where }: { where: { phone?: string; id?: string } }) => {
          if (where.phone) return null;
          if (where.id === inviter.id) return inviter;
          return null;
        },
        create: async () => createdUser,
      },
      userSession: {
        create: async () => undefined,
      },
    },
    {
      walletService: {
        ensureWalletAndBonuses: async () => undefined,
        accrueManualBonusIfNeeded: async (userId, params) => {
          bonusCalls.push({ userId, params: params as Record<string, unknown> });
          return { applied: true };
        },
      },
    },
  );

  await service.signupPhone({
    phone: '+79281234567',
    password: '12345678',
    displayName: 'New User',
    verificationCheckId: 'verification-1',
    referralCode: buildReferralCode(inviter.id),
  });

  assert.equal(bonusCalls.length, 1);
  assert.equal(bonusCalls[0]?.userId, inviter.id);
  assert.equal(bonusCalls[0]?.params.amount, 100);
  assert.equal(
    bonusCalls[0]?.params.description,
    'Бонус за приглашение друга',
  );
  assert.equal(
    bonusCalls[0]?.params.reference,
    'REFERRAL_INVITER_BONUS:new-user-1',
  );
});

test('signupPhone ignores invalid referral code and still completes registration', async () => {
  const createdUser = baseActiveUser({
    id: 'new-user-2',
    phone: '79281234568',
    displayName: 'New User 2',
    name: 'New User 2',
  });
  let bonusCallCount = 0;

  const service = createService(
    {
      phoneVerification: {
        findUnique: async () => ({
          id: 'verification-2',
          phone: '79281234568',
          purpose: 'SIGNUP',
          status: 'CONFIRMED',
        }),
        update: async () => undefined,
        findFirst: async () => null,
      },
      user: {
        findUnique: async () => null,
        create: async () => createdUser,
      },
      userSession: {
        create: async () => undefined,
      },
    },
    {
      walletService: {
        ensureWalletAndBonuses: async () => undefined,
        accrueManualBonusIfNeeded: async () => {
          bonusCallCount += 1;
          return { applied: true };
        },
      },
    },
  );

  const response = await service.signupPhone({
    phone: '+79281234568',
    password: '12345678',
    displayName: 'New User 2',
    verificationCheckId: 'verification-2',
    referralCode: 'broken-referral-code',
  });

  assert.equal(response.user.id, 'new-user-2');
  assert.equal(bonusCallCount, 0);
});

test('signupPhone blocks self-referral bonus by matching inviter user id', async () => {
  const createdUser = baseActiveUser({
    id: 'same-user-1',
    phone: '79281234569',
    displayName: 'Same User',
    name: 'Same User',
  });
  let bonusCallCount = 0;

  const service = createService(
    {
      phoneVerification: {
        findUnique: async () => ({
          id: 'verification-3',
          phone: '79281234569',
          purpose: 'SIGNUP',
          status: 'CONFIRMED',
        }),
        update: async () => undefined,
        findFirst: async () => null,
      },
      user: {
        findUnique: async () => null,
        create: async () => createdUser,
      },
      userSession: {
        create: async () => undefined,
      },
    },
    {
      walletService: {
        ensureWalletAndBonuses: async () => undefined,
        accrueManualBonusIfNeeded: async () => {
          bonusCallCount += 1;
          return { applied: true };
        },
      },
    },
  );

  await service.signupPhone({
    phone: '+79281234569',
    password: '12345678',
    displayName: 'Same User',
    verificationCheckId: 'verification-3',
    referralCode: buildReferralCode('same-user-1'),
  });

  assert.equal(bonusCallCount, 0);
});
