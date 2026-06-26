import { test } from 'node:test';
import assert from 'node:assert/strict';

import { hashSync } from 'bcryptjs';
import { HttpException } from '@nestjs/common';
import { UserStatus } from '@prisma/client';

import { AuthService } from './auth.service';

function createService(
  prisma: Record<string, unknown>,
  overrides?: {
    walletService?: {
      ensureWalletAndBonuses?: (userId: string) => Promise<unknown>;
      ensureWalletAndBonusesSafely?: (userId: string) => Promise<unknown>;
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
      ...overrides?.walletService,
    } as never,
  );
}

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
