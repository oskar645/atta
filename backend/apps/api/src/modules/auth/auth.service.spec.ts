import { test } from 'node:test';
import assert from 'node:assert/strict';

import { compareSync, hashSync } from 'bcryptjs';
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
      accrueReferralInviterBonusIfNeeded?: (
        userId: string,
        params: {
          invitedUserId: string;
          referralCode: string;
        },
        tx?: unknown,
      ) => Promise<unknown>;
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
    userBlocksService?: {
      getActiveBlock?: (userId: string) => Promise<unknown>;
      assertNotBlocked?: (userId: string) => Promise<void>;
    };
    jwtService?: {
      signAsync?: (payload: Record<string, unknown>) => Promise<string>;
      verifyAsync?: (token: string, options?: unknown) => Promise<Record<string, unknown>>;
    };
  },
) {
  const prismaWithTransaction: Record<string, unknown> = {
    ...prisma,
    blockedIdentity: {
      updateMany: async () => ({ count: 0 }),
      findFirst: async () => null,
      ...((prisma.blockedIdentity as Record<string, unknown> | undefined) ?? {}),
    },
    $transaction:
      prisma.$transaction ??
      (async <T>(handler: (tx: Record<string, unknown>) => Promise<T>) =>
        handler(prismaWithTransaction)),
  };
  return new AuthService(
    prismaWithTransaction as never,
    {
      signAsync: async (payload: Record<string, unknown>) =>
        `${payload.type ?? 'token'}-token`,
      verifyAsync: async () => ({}),
      ...overrides?.jwtService,
    } as never,
    {} as never,
    {
      ensureWalletAndBonuses: async () => undefined,
      ensureWalletAndBonusesSafely: async () => undefined,
      accrueReferralInviterBonusIfNeeded: async () => undefined,
      accrueManualBonusIfNeeded: async () => undefined,
      ...overrides?.walletService,
    } as never,
    {
      getActiveBlock: async () => null,
      assertNotBlocked: async () => undefined,
      serializeBlock: () => null,
      ...overrides?.userBlocksService,
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

for (const days of [1, 7, 30]) {
  test(`loginPhone allows expired ${days}-day block after active block reconciliation`, async () => {
    let checkedUserId = '';
    const service = createService(
      {
        user: {
          findUnique: async () =>
            baseActiveUser({
              status: UserStatus.BLOCKED,
              blockedAt: new Date(Date.now() - days * 86400000),
              blockReason: 'Temporary block',
            }),
          update: async () => undefined,
        },
        userSession: {
          create: async () => undefined,
        },
      },
      {
        userBlocksService: {
          getActiveBlock: async (userId) => {
            checkedUserId = userId;
            return null;
          },
        },
      },
    );

    const response = await service.loginPhone({
      phone: '79281234567',
      password: '12345678',
    });

    assert.equal(checkedUserId, 'user-1');
    assert.equal(response.user.id, 'user-1');
  });
}

test('loginPhone rejects permanent active block', async () => {
  const service = createService(
    {
      user: {
        findUnique: async () => baseActiveUser({ blockedAt: new Date() }),
        update: async () => undefined,
      },
      userSession: {
        create: async () => undefined,
      },
    },
    {
      userBlocksService: {
        getActiveBlock: async () => ({
          id: 'block-1',
          userId: 'user-1',
          adminId: 'admin-1',
          type: 'PERMANENT',
          status: 'ACTIVE',
          reason: 'Permanent block',
          startsAt: new Date(),
          endsAt: null,
          createdAt: new Date(),
          updatedAt: new Date(),
        }),
      },
    },
  );

  await assert.rejects(
    service.loginPhone({
      phone: '79281234567',
      password: '12345678',
    }),
    (error: unknown) => {
      assert.ok(error instanceof HttpException);
      assert.equal(error.getStatus(), 401);
      assert.deepEqual(error.getResponse(), {
        code: 'ACCOUNT_BLOCKED',
        message: 'Аккаунт заблокирован',
      });
      return true;
    },
  );
});

test('signupPhone allows expired temporary BlockedIdentity and lifts it idempotently', async () => {
  let updateManyCalls = 0;
  const createdUser = baseActiveUser({
    id: 'new-user-expired-identity',
    phone: '79281234571',
  });

  const service = createService({
    blockedIdentity: {
      updateMany: async () => {
        updateManyCalls += 1;
        return { count: updateManyCalls === 1 ? 1 : 0 };
      },
      findFirst: async () => null,
    },
    phoneVerification: {
      update: async () => undefined,
      findFirst: async ({ where }: { where: Record<string, unknown> }) =>
        'createdUserId' in where
          ? null
          : {
              id: 'verification-expired-identity',
              phone: '79281234571',
              purpose: 'SIGNUP',
              status: 'CONFIRMED',
              expiresAt: new Date(Date.now() + 60_000),
            },
    },
    user: {
      findUnique: async ({ where }: { where: { phone?: string; id?: string } }) => {
        if (where.phone) return null;
        if (where.id === createdUser.id) return createdUser;
        return null;
      },
      create: async () => createdUser,
    },
    userSession: {
      create: async () => undefined,
    },
  });

  const first = await service.signupPhone({
    phone: '+79281234571',
    password: '12345678',
    displayName: 'Expired Identity',
    verificationCheckId: 'verification-expired-identity',
  });

  const second = await service.signupPhone({
    phone: '+79281234571',
    password: '12345678',
    displayName: 'Expired Identity',
    verificationCheckId: 'verification-expired-identity',
  });

  assert.equal(first.user.id, 'new-user-expired-identity');
  assert.equal(second.user.id, 'new-user-expired-identity');
  assert.equal(updateManyCalls, 2);
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

test('revokeOtherSessions revokes only current user sessions except current session', async () => {
  let updateWhere: unknown;
  const service = createService({
    userSession: {
      updateMany: async ({ where }: { where: unknown }) => {
        updateWhere = where;
        return { count: 2 };
      },
    },
  });

  const response = await service.revokeOtherSessions({
    userId: 'user-1',
    sessionId: 'session-current',
    role: 'user',
    email: null,
  });

  assert.deepEqual(updateWhere, {
    userId: 'user-1',
    id: {
      not: 'session-current',
    },
    revokedAt: null,
  });
  assert.deepEqual(response, { revoked: 2 });
});

test('revokeAllSessions revokes only current user sessions', async () => {
  let updateWhere: unknown;
  const service = createService({
    userSession: {
      updateMany: async ({ where }: { where: unknown }) => {
        updateWhere = where;
        return { count: 3 };
      },
    },
  });

  const response = await service.revokeAllSessions({
    userId: 'user-1',
    sessionId: 'session-current',
    role: 'user',
    email: null,
  });

  assert.deepEqual(updateWhere, {
    userId: 'user-1',
    revokedAt: null,
  });
  assert.deepEqual(response, { revoked: 3 });
});

test('refresh rotation keeps active session and stores new refresh token hash', async () => {
  const user = baseActiveUser();
  let updatedHash = '';
  let updatedExpiry: Date | null = null;
  const service = createService(
    {
      user: {
        findUnique: async () => user,
      },
      userSession: {
        findUnique: async () => ({
          id: 'session-1',
          userId: 'user-1',
          refreshTokenHash: hashSync('old-refresh-token', 10),
          revokedAt: null,
          expiresAt: new Date(Date.now() + 60_000),
          user,
        }),
        update: async ({ data }: { data: { refreshTokenHash: string; expiresAt: Date } }) => {
          updatedHash = data.refreshTokenHash;
          updatedExpiry = data.expiresAt;
        },
      },
    },
    {
      jwtService: {
        verifyAsync: async () => ({
          sub: 'user-1',
          sessionId: 'session-1',
          type: 'refresh',
          role: 'user',
          email: null,
        }),
        signAsync: async (payload) => `new-${payload.type}-token`,
      },
    },
  );

  const response = await service.refresh({
    refreshToken: 'old-refresh-token',
  });

  assert.equal(response.auth.access_token, 'new-access-token');
  assert.equal(response.auth.refresh_token, 'new-refresh-token');
  assert.equal(compareSync('new-refresh-token', updatedHash), true);
  assert.ok((updatedExpiry as unknown) instanceof Date);
});

test('refresh mismatch rejects without blindly revoking the session', async () => {
  const user = baseActiveUser();
  let revokeCalls = 0;
  const service = createService(
    {
      userSession: {
        findUnique: async () => ({
          id: 'session-1',
          userId: 'user-1',
          refreshTokenHash: hashSync('current-refresh-token', 10),
          revokedAt: null,
          expiresAt: new Date(Date.now() + 60_000),
          user,
        }),
        updateMany: async () => {
          revokeCalls += 1;
          return { count: 1 };
        },
      },
    },
    {
      jwtService: {
        verifyAsync: async () => ({
          sub: 'user-1',
          sessionId: 'session-1',
          type: 'refresh',
          role: 'user',
          email: null,
        }),
      },
    },
  );

  await assert.rejects(
    service.refresh({
      refreshToken: 'old-refresh-token',
    }),
    (error: unknown) => {
      assert.ok(error instanceof HttpException);
      assert.equal(error.getStatus(), 401);
      return true;
    },
  );
  assert.equal(revokeCalls, 0);
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
        update: async () => undefined,
        findFirst: async ({ where }: { where: Record<string, unknown> }) =>
          'createdUserId' in where
            ? null
            : {
                id: 'verification-1',
                phone: '79281234567',
                purpose: 'SIGNUP',
                status: 'CONFIRMED',
                expiresAt: new Date(Date.now() + 60_000),
              },
      },
      user: {
        findUnique: async ({ where }: { where: { phone?: string; id?: string } }) => {
          if (where.phone) return null;
          if (where.id === createdUser.id) return createdUser;
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
        accrueReferralInviterBonusIfNeeded: async (userId, params) => {
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
  assert.equal(
    bonusCalls[0]?.params.invitedUserId,
    'new-user-1',
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
        update: async () => undefined,
        findFirst: async ({ where }: { where: Record<string, unknown> }) =>
          'createdUserId' in where
            ? null
            : {
                id: 'verification-2',
                phone: '79281234568',
                purpose: 'SIGNUP',
                status: 'CONFIRMED',
                expiresAt: new Date(Date.now() + 60_000),
              },
      },
      user: {
        findUnique: async ({ where }: { where: { phone?: string; id?: string } }) => {
          if (where.phone) return null;
          if (where.id === createdUser.id) return createdUser;
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
        accrueReferralInviterBonusIfNeeded: async () => {
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

test('signupPhone ignores referral code when inviter does not exist', async () => {
  const createdUser = baseActiveUser({
    id: 'new-user-4',
    phone: '79281234570',
    displayName: 'New User 4',
    name: 'New User 4',
  });
  let bonusCallCount = 0;

  const service = createService(
    {
      phoneVerification: {
        update: async () => undefined,
        findFirst: async ({ where }: { where: Record<string, unknown> }) =>
          'createdUserId' in where
            ? null
            : {
                id: 'verification-4',
                phone: '79281234570',
                purpose: 'SIGNUP',
                status: 'CONFIRMED',
                expiresAt: new Date(Date.now() + 60_000),
              },
      },
      user: {
        findUnique: async ({ where }: { where: { phone?: string; id?: string } }) => {
          if (where.phone) return null;
          if (where.id === createdUser.id) return createdUser;
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
        accrueReferralInviterBonusIfNeeded: async () => {
          bonusCallCount += 1;
          return { applied: true };
        },
      },
    },
  );

  const response = await service.signupPhone({
    phone: '+79281234570',
    password: '12345678',
    displayName: 'New User 4',
    verificationCheckId: 'verification-4',
    referralCode: buildReferralCode('missing-inviter'),
  });

  assert.equal(response.user.id, 'new-user-4');
  assert.equal(bonusCallCount, 0);
});

test('signupPhone blocks existing phone before referral bonus', async () => {
  let bonusCallCount = 0;

  const service = createService(
    {
      phoneVerification: {
        findFirst: async () => ({
          id: 'verification-existing',
          phone: '79281234567',
          purpose: 'SIGNUP',
          status: 'CONFIRMED',
          expiresAt: new Date(Date.now() + 60_000),
        }),
      },
      user: {
        findUnique: async ({ where }: { where: { phone?: string } }) =>
          where.phone ? baseActiveUser() : null,
      },
    },
    {
      walletService: {
        accrueReferralInviterBonusIfNeeded: async () => {
          bonusCallCount += 1;
          return { applied: true };
        },
      },
    },
  );

  await assert.rejects(
    service.signupPhone({
      phone: '+79281234567',
      password: '12345678',
      displayName: 'Existing User',
      verificationCheckId: 'verification-existing',
      referralCode: buildReferralCode('inviter-1'),
    }),
    /Phone is already registered/,
  );
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
        update: async () => undefined,
        findFirst: async ({ where }: { where: Record<string, unknown> }) =>
          'createdUserId' in where
            ? null
            : {
                id: 'verification-3',
                phone: '79281234569',
                purpose: 'SIGNUP',
                status: 'CONFIRMED',
                expiresAt: new Date(Date.now() + 60_000),
              },
      },
      user: {
        findUnique: async ({ where }: { where: { phone?: string; id?: string } }) => {
          if (where.phone) return null;
          if (where.id === createdUser.id) return createdUser;
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
        accrueReferralInviterBonusIfNeeded: async () => {
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
