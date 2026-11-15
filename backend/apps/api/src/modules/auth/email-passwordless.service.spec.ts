import 'reflect-metadata';

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { EmailChallengePurpose } from '@prisma/client';
import { HttpException } from '@nestjs/common';

import { EmailPasswordlessService } from './email-passwordless.service';

type Challenge = {
  id: string;
  userId: string | null;
  purpose: EmailChallengePurpose;
  targetEmail: string;
  codeHash: string;
  attempts: number;
  maxAttempts: number;
  expiresAt: Date;
  resendAvailableAt: Date;
  consumedAt: Date | null;
  metadata: unknown;
};

function fixture() {
  let challenge: Challenge | null = null;
  let delivered: { to: string; code: string } | null = null;
  let sendCount = 0;
  let authCalls = 0;
  const limits: string[] = [];

  const emailChallenge = {
    findFirst: async ({ where }: any) => {
      if (!challenge) return null;
      if (where?.id && where.id !== challenge.id) return null;
      if (where?.purpose && where.purpose !== challenge.purpose) return null;
      if (where?.targetEmail && where.targetEmail !== challenge.targetEmail) {
        return null;
      }
      if (where?.consumedAt === null && challenge.consumedAt !== null) return null;
      return challenge;
    },
    updateMany: async ({ data }: any) => {
      if (challenge) challenge = { ...challenge, ...data };
      return { count: challenge ? 1 : 0 };
    },
    create: async ({ data }: any) => {
      challenge = {
        ...data,
        userId: data.userId ?? null,
        attempts: 0,
        maxAttempts: 5,
        consumedAt: null,
      };
      return challenge;
    },
    update: async ({ data }: any) => {
      assert.ok(challenge);
      const attempts = data.attempts?.increment
        ? challenge.attempts + data.attempts.increment
        : challenge.attempts;
      challenge = { ...challenge, ...data, attempts };
      return challenge;
    },
  };
  const prisma: any = {
    emailChallenge,
    user: {
      findFirst: async () => null,
    },
    $queryRaw: async () => [],
    $transaction: async (handler: (tx: any) => Promise<unknown>) =>
      handler(prisma),
  };
  const rateLimit = {
    consumeOrThrow: async (key: string) => {
      limits.push(key);
    },
  };
  const email = {
    ensureAvailable: () => undefined,
    sendLoginCode: async (value: { to: string; code: string }) => {
      sendCount += 1;
      delivered = value;
    },
  };
  const authResponse = {
    user: { id: 'email-user', email: 'member@example.com' },
    auth: { access_token: 'access', refresh_token: 'refresh' },
  };
  const auth = {
    authenticateEmailPasswordless: async () => {
      authCalls += 1;
      return authResponse;
    },
  };
  const service = new EmailPasswordlessService(
    prisma,
    rateLimit as never,
    email as never,
    auth as never,
  );
  return {
    service,
    limits,
    authResponse,
    get challenge() {
      return challenge;
    },
    get delivered() {
      return delivered;
    },
    get authCalls() {
      return authCalls;
    },
    get sendCount() {
      return sendCount;
    },
    expireChallenge() {
      assert.ok(challenge);
      challenge.expiresAt = new Date(Date.now() - 1);
    },
  };
}

test('email auth normalizes address and sends exactly six digits', async () => {
  const f = fixture();
  const result = await f.service.start('  Member@Example.COM ', {
    ip: '127.0.0.1',
    deviceId: 'device-1',
  });

  assert.equal(f.delivered?.to, 'member@example.com');
  assert.match(f.delivered?.code ?? '', /^\d{6}$/);
  assert.equal(f.challenge?.targetEmail, 'member@example.com');
  assert.equal(result.status, 'ok');
  assert.equal(result.expiresIn, 600);
  assert.equal(result.resendAfter, 60);
  assert.equal(f.limits.length, 3);
});

test('wrong email code is rejected and consumes an attempt', async () => {
  const f = fixture();
  const started = await f.service.start('member@example.com');

  await assert.rejects(
    () => f.service.check(started.challengeId, '000000'),
    (error: unknown) => {
      assert.ok(error instanceof HttpException);
      assert.equal((error.getResponse() as any).code, 'EMAIL_CODE_INVALID');
      return true;
    },
  );
  assert.equal(f.challenge?.attempts, 1);
  assert.equal(f.authCalls, 0);
});

test('resend cooldown reuses one challenge without sending a second email', async () => {
  const f = fixture();
  const first = await f.service.start('member@example.com');
  const second = await f.service.start('member@example.com');

  assert.equal(second.challengeId, first.challengeId);
  assert.equal(f.sendCount, 1);
  assert.ok(second.resendAfter > 0);
});

test('expired code and a challenge with five failed attempts stay unusable', async () => {
  const expired = fixture();
  const expiredStart = await expired.service.start('member@example.com');
  const correctExpiredCode = expired.delivered!.code;
  expired.expireChallenge();
  await assert.rejects(
    () => expired.service.check(expiredStart.challengeId, correctExpiredCode),
    HttpException,
  );

  const exhausted = fixture();
  const exhaustedStart = await exhausted.service.start('member@example.com');
  const correctCode = exhausted.delivered!.code;
  const wrongCode = correctCode === '000000' ? '000001' : '000000';
  for (let attempt = 0; attempt < 5; attempt += 1) {
    await assert.rejects(
      () => exhausted.service.check(exhaustedStart.challengeId, wrongCode),
      HttpException,
    );
  }
  assert.equal(exhausted.challenge?.attempts, 5);
  await assert.rejects(
    () => exhausted.service.check(exhaustedStart.challengeId, correctCode),
    HttpException,
  );
  assert.equal(exhausted.authCalls, 0);
});

test('verified code requires a name, then registration is one-time and replay-safe', async () => {
  const f = fixture();
  const started = await f.service.start('member@example.com');
  const checked = await f.service.check(
    started.challengeId,
    f.delivered!.code,
  ) as any;

  assert.equal(checked.status, 'registration_required');
  assert.match(checked.registrationToken, /^[^.]+\.[A-Za-z0-9_-]{43}$/);

  const completed = await f.service.complete({
    registrationToken: checked.registrationToken,
    displayName: 'ATTA User',
    acceptedLegal: true,
    acceptedPersonalData: true,
  });
  assert.deepEqual(completed, f.authResponse);
  assert.equal(f.challenge?.consumedAt instanceof Date, true);
  assert.equal(f.authCalls, 1);

  const replay = await f.service.complete({
    registrationToken: checked.registrationToken,
    displayName: 'ATTA User',
    acceptedLegal: true,
    acceptedPersonalData: true,
  });
  assert.deepEqual(replay, f.authResponse);
  assert.equal(f.authCalls, 1);
});
