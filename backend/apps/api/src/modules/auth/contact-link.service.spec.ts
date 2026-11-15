import 'reflect-metadata';

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { BadRequestException, ConflictException } from '@nestjs/common';

import { ContactLinkService } from './contact-link.service';

const authUser = {
  userId: 'user-1',
  sessionId: 'session-1',
  role: 'user' as const,
  email: 'member@example.com',
};

function fixture(options?: { occupied?: boolean; linkedSession?: string }) {
  let updatedUserId: string | undefined;
  let verificationMetadata: any = {
    contactLink: {
      version: 1,
      userId: 'user-1',
      sessionId: options?.linkedSession ?? 'session-1',
      state: 'pending',
    },
  };
  const verification = {
    id: 'verification-row-1',
    phone: '79281112233',
    checkId: 'provider-check-1',
    status: 'CONFIRMED',
    expiresAt: new Date(Date.now() + 60_000),
    metadata: verificationMetadata,
  };
  const prisma: any = {
    userSession: { findFirst: async () => ({ id: 'session-1' }) },
    user: {
      findFirst: async () => (options?.occupied ? { id: 'user-2' } : null),
      update: async ({ where, data }: any) => {
        updatedUserId = where.id;
        return { id: where.id, ...data };
      },
    },
    phoneVerification: {
      findFirst: async () => ({ ...verification, metadata: verificationMetadata }),
      update: async ({ data }: any) => {
        verificationMetadata = data.metadata;
        return verification;
      },
    },
    $queryRaw: async () => [],
    $transaction: async (handler: (tx: any) => Promise<unknown>) =>
      handler(prisma),
  };
  let startOptions: any;
  const phoneVerification = {
    startCallVerification: async (...args: any[]) => {
      startOptions = args[3];
      return { checkId: 'provider-check-1', callToPhone: '78005553535' };
    },
    checkCallVerification: async () => ({ status: 'confirmed' }),
  };
  return {
    service: new ContactLinkService(prisma, phoneVerification as never),
    get startOptions() {
      return startOptions;
    },
    get updatedUserId() {
      return updatedUserId;
    },
    get verificationMetadata() {
      return verificationMetadata;
    },
  };
}

test('phone link challenge is bound to current user and session', async () => {
  const f = fixture();
  await f.service.startPhone(authUser, '+7 928 111-22-33', {});

  assert.equal(f.startOptions.metadata.contactLink.userId, 'user-1');
  assert.equal(f.startOptions.metadata.contactLink.sessionId, 'session-1');
  assert.equal(f.startOptions.metadata.contactLink.state, 'pending');
});

test('confirmed phone links to the same User.id and becomes one-time', async () => {
  const f = fixture();
  const result = await f.service.completePhone(
    authUser,
    '+7 928 111-22-33',
    'provider-check-1',
  );

  assert.equal(result.status, 'confirmed');
  assert.equal(f.updatedUserId, 'user-1');
  assert.equal(f.verificationMetadata.contactLink.state, 'consumed');

  await assert.rejects(
    () =>
      f.service.completePhone(
        authUser,
        '+7 928 111-22-33',
        'provider-check-1',
      ),
    (error: unknown) =>
      error instanceof BadRequestException &&
      error.message === 'PHONE_LINK_VERIFICATION_INVALID',
  );
});

test('phone link rejects another session and an occupied phone', async () => {
  const wrongSession = fixture({ linkedSession: 'session-2' });
  await assert.rejects(
    () =>
      wrongSession.service.completePhone(
        authUser,
        '+7 928 111-22-33',
        'provider-check-1',
      ),
    BadRequestException,
  );

  const occupied = fixture({ occupied: true });
  await assert.rejects(
    () =>
      occupied.service.startPhone(authUser, '+7 928 111-22-33', {}),
    ConflictException,
  );
});
