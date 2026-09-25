import 'reflect-metadata';
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { AccountRecoveryService } from './account-recovery.service';

test('recovery-email start reuses the cooldown challenge and sends only once', async () => {
  const challenges: any[] = [];
  const prisma = {
    user: { findFirst: async () => null },
    emailChallenge: {
      findFirst: async () => challenges.at(-1) ?? null,
      create: async ({ data }: any) => {
        challenges.push({ ...data, createdAt: new Date() });
        return data;
      },
    },
  };
  let sends = 0;
  let releaseSend!: () => void;
  const sending = new Promise<void>((resolve) => { releaseSend = resolve; });
  const email = {
    ensureAvailable: () => {},
    sendVerificationCode: async () => { sends++; await sending; },
  };
  const rate = { consumeOrThrow: async () => {} };
  const service = new AccountRecoveryService(
    prisma as never,
    rate as never,
    email as never,
    {} as never,
    {} as never,
  );

  const first = service.startRecoveryEmail('user-1', 'Member@Example.com');
  while (sends === 0) await new Promise((resolve) => setImmediate(resolve));

  // Models a retry after the client lost/timed out waiting for the first HTTP
  // response while the original SMTP operation is still completing.
  const recovered = await service.startRecoveryEmail('user-1', 'member@example.com');
  assert.equal(recovered.challengeId, challenges[0].id);
  assert.equal(recovered.resendAfter, 60);
  assert.equal(challenges.length, 1);
  assert.equal(sends, 1);

  releaseSend();
  const completed = await first;
  assert.equal(completed.challengeId, recovered.challengeId);
});

test('recovery-email verify stores email and emailVerifiedAt on the authenticated user', async () => {
  const expiresAt = new Date(Date.now() + 60_000);
  const challenge = {
    id: 'challenge-1', userId: 'user-1', purpose: 'RECOVERY_EMAIL',
    targetEmail: 'member@example.com', codeHash: '', expiresAt,
    consumedAt: null, attempts: 0, maxAttempts: 5,
  };
  const updates: any[] = [];
  const prisma = {
    emailChallenge: { findFirst: async () => challenge },
    $transaction: async (callback: (tx: any) => unknown) => callback({
      user: {
        findUniqueOrThrow: async () => ({ email: 'old@example.com', emailVerifiedAt: null }),
        findFirst: async () => null,
        update: async (args: any) => { updates.push(args); },
      },
      emailChallenge: { updateMany: async () => ({ count: 1 }) },
    }),
  };
  const service = new AccountRecoveryService(
    prisma as never, {} as never,
    { sendRecoveryEmailChanged: async () => {} } as never,
    {} as never, {} as never,
  );
  (service as any).digest = () => '';

  await service.verifyRecoveryEmail('user-1', challenge.id, '123456');

  assert.equal(updates.length, 1);
  assert.equal(updates[0].where.id, 'user-1');
  assert.equal(updates[0].data.email, 'member@example.com');
  assert.ok(updates[0].data.emailVerifiedAt instanceof Date);
});
