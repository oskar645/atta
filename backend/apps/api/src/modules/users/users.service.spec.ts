import { test } from 'node:test';
import assert from 'node:assert/strict';

import { BadRequestException } from '@nestjs/common';
import {
  PhoneVerificationPurpose,
  PhoneVerificationStatus,
  UserStatus,
} from '@prisma/client';

import { UsersService } from './users.service';

test('getMe does not crash if wallet has issue', async () => {
  const service = new UsersService(
    {
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
    } as never,
    {} as never,
    {
      ensureWalletAndBonusesSafely: async () => {
        throw new Error('wallet failed');
      },
    } as never,
  );

  const response = await service.getMe({
    userId: 'user-1',
    sessionId: 'session-1',
    role: 'user',
    email: 'user@example.com',
  });

  assert.equal(response.user.id, 'user-1');
  assert.equal(response.isAdmin, false);
});

test('updateMe rejects changed phone without confirmed verification', async () => {
  let updateCalled = false;
  const service = new UsersService(
    {
      user: {
        findUnique: async () => ({ phone: '79281234567' }),
        findFirst: async () => null,
        update: async () => {
          updateCalled = true;
          throw new Error('should not update');
        },
      },
      phoneVerification: {
        findFirst: async () => null,
      },
    } as never,
    {} as never,
    {} as never,
  );

  await assert.rejects(
    () =>
      service.updateMe(
        { userId: 'user-1', role: 'user' } as never,
        { phone: '+7 928 111-22-33' },
      ),
    (error) =>
      error instanceof BadRequestException &&
      error.message === 'PHONE_VERIFICATION_REQUIRED',
  );
  assert.equal(updateCalled, false);
});

test('updateMe allows changed phone with confirmed verification', async () => {
  let updateArgs: Record<string, any> | undefined;
  const service = new UsersService(
    {
      user: {
        findUnique: async () => ({ phone: '79281234567' }),
        findFirst: async () => null,
        update: async (args: Record<string, any>) => {
          updateArgs = args;
          return {
            id: 'user-1',
            email: 'user@example.com',
            phone: args.data.phone,
            phoneVerified: args.data.phoneVerified,
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
          };
        },
      },
      phoneVerification: {
        findFirst: async (args: Record<string, any>) => ({
          id: 'verification-1',
          phone: args.where.phone,
          purpose: PhoneVerificationPurpose.CHANGE_PHONE,
          checkId: args.where.checkId,
          status: PhoneVerificationStatus.CONFIRMED,
          expiresAt: new Date(Date.now() + 60_000),
        }),
      },
    } as never,
    {} as never,
    {} as never,
  );

  const response = await service.updateMe(
    { userId: 'user-1', role: 'user' } as never,
    {
      phone: '+7 928 111-22-33',
      verificationCheckId: 'verification-1',
    },
  );

  assert.equal(updateArgs?.data.phone, '79281112233');
  assert.equal(updateArgs?.data.phoneVerified, true);
  assert.ok('phone' in response.user);
  assert.equal(response.user.phone, '79281112233');
});

test('updateMe rejects changed phone owned by another active account', async () => {
  let verificationCalled = false;
  const service = new UsersService(
    {
      user: {
        findUnique: async () => ({ phone: '79281234567' }),
        findFirst: async () => ({ id: 'user-2' }),
        update: async () => {
          throw new Error('should not update');
        },
      },
      phoneVerification: {
        findFirst: async () => {
          verificationCalled = true;
          return null;
        },
      },
    } as never,
    {} as never,
    {} as never,
  );

  await assert.rejects(
    () =>
      service.updateMe(
        { userId: 'user-1', role: 'user' } as never,
        {
          phone: '+7 928 111-22-33',
          verificationCheckId: 'verification-1',
        },
      ),
    (error) =>
      error instanceof BadRequestException &&
      error.message === 'PHONE_ALREADY_REGISTERED',
  );
  assert.equal(verificationCalled, false);
});

test('avatar upload uses selected storage provider flow', async () => {
  const storageCalls: Array<Record<string, unknown>> = [];
  const service = new UsersService(
    {
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
    } as never,
    {
      deleteAvatarUrl: async () => undefined,
      saveUploadedFile: async (payload: Record<string, unknown>) => {
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
    } as never,
    {
      ensureWalletAndBonusesSafely: async () => undefined,
    } as never,
  );

  const response = await service.uploadAvatar(
    { userId: 'user-1', role: 'user' } as never,
    {
      buffer: Buffer.from('avatar'),
      mimetype: 'image/jpeg',
      originalname: 'avatar.jpg',
    } as never,
  );

  assert.equal(storageCalls.length, 1);
  assert.equal(storageCalls[0].category, 'avatars');
  assert.deepEqual(storageCalls[0].context, { userId: 'user-1' });
  assert.match(response.avatar_url, /avatars\/user-1\/new\.jpg/);
});
