import 'reflect-metadata';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'crypto';
import { PrismaClient } from '@prisma/client';
import { JwtService } from '@nestjs/jwt';
import { hash } from 'bcryptjs';

import { AccountRecoveryService } from './account-recovery.service';
import { AuthService } from './auth.service';
import { RestoreCredentialsService } from './restore-credentials.service';
import { WalletService } from '../wallet/wallet.service';
import { UserBlocksService } from '../user-blocks/user-blocks.service';

// Explicit opt-in. Never falls back to DATABASE_URL or any project database.
const url = process.env.ATTA_RECOVERY_TEST_DATABASE_URL;
test('account recovery uses absolute timestamps in every PostgreSQL timezone', { skip: !url }, async (t) => {
  const parsed = new URL(url!);
  assert.equal(parsed.hostname, 'localhost');
  assert.equal(parsed.pathname, '/atta_recovery_regression');
  assert.match(parsed.searchParams.get('host') ?? '', /^\/private\/tmp\/atta-recovery-pg\.[A-Za-z0-9]+\/socket$/);
  assert.equal(parsed.username, 'atta_test');

  parsed.searchParams.set('connection_limit', '1');
  const db = new PrismaClient({ datasources: { db: { url: parsed.toString() } } });
  const rate = { consumeOrThrow: async () => {} };
  const sentCodes = new Map<string, string>();
  const email = {
    ensureAvailable: () => {},
    sendVerificationCode: async ({ to, code }: { to: string; code: string }) => { sentCodes.set(to, code); },
    sendRecoveryEmailChanged: async () => {},
    sendRecoveryCompleted: async () => {},
  };
  const phone = {
    startCallVerification: async (_phone: string, _purpose: string, _source: unknown, options: { id: string }) => ({
      status: 'pending', challenge: options.id, checkId: options.id, callToPhone: '79990000000', expiresAt: new Date(Date.now() + 60_000).toISOString(),
    }),
    checkCallVerification: async () => ({ status: 'confirmed' }),
  };
  const auth = new AuthService(db as never, new JwtService(), {} as never,
    new WalletService(db as never), new UserBlocksService(db as never), {} as never);
  const recovery = new AccountRecoveryService(db as never, rate as never, email as never, phone as never, auth);
  const restore = new RestoreCredentialsService(db as never, {} as never,
    new UserBlocksService(db as never), auth);
  let phoneCounter = Math.floor(Math.random() * 100_000_000);
  const nextPhone = () => `79${String(++phoneCounter).padStart(9, '0')}`;

  async function createUser(emailAddress: string, phoneNumber: string) {
    return db.user.create({ data: { id: randomUUID(), email: emailAddress, phone: phoneNumber,
      displayName: 'Recovery test', name: 'Recovery test', passwordHash: await hash(randomUUID(), 4) } });
  }

  try {
    for (const [index, timezone] of ['UTC', 'Europe/Moscow', 'America/New_York'].entries()) {
      await t.test(timezone, async () => {
        await db.$executeRawUnsafe(`SET TIME ZONE '${timezone}'`);
        const shown = await db.$queryRawUnsafe<Array<{ TimeZone: string }>>('SHOW TIME ZONE');
        assert.equal(shown[0].TimeZone, timezone);
        const suffix = `${Date.now()}-${index}`;
        const recoveryEmail = `recovery-${suffix}@example.test`;
        const user = await createUser(`legacy-${suffix}@example.test`, nextPhone());
        const other = await createUser(`other-${suffix}@example.test`, nextPhone());

        const emailChallenge = await recovery.startRecoveryEmail(user.id, recoveryEmail);
        await recovery.verifyRecoveryEmail(user.id, emailChallenge.challengeId, sentCodes.get(recoveryEmail)!);
        const verified = await db.user.findUniqueOrThrow({ where: { id: user.id } });
        assert.equal(verified.email, recoveryEmail);
        assert.ok(verified.emailVerifiedAt);

        const started = await recovery.startAccountRecovery(recoveryEmail);
        const grantResponse = await recovery.verifyAccountRecoveryEmail(started.challengeId, sentCodes.get(recoveryEmail)!);
        const grant = await db.accountRecoveryGrant.findUniqueOrThrow({ where: { tokenHash: (recovery as any).digest(grantResponse.recoveryToken) } });

        const oldRefresh = await (auth as any).buildAuthTokens({ id: user.id, email: recoveryEmail }, randomUUID(), null);
        await db.userSession.create({ data: { id: oldRefresh.session_id, userId: user.id,
          refreshTokenHash: await hash(oldRefresh.refresh_token, 4), expiresAt: new Date(Date.now() + 60_000) } });
        await db.restoreCredential.createMany({ data: [1, 2].map(n => ({ userId: user.id,
          credentialId: `credential-${suffix}-${n}`, publicKey: Buffer.from(`key-${n}`) })) });
        await db.restoreCredential.create({ data: { userId: other.id,
          credentialId: `credential-other-${suffix}`, publicKey: Buffer.from('other-key') } });

        const newPhone = nextPhone();
        const call = await recovery.startPhone(grantResponse.recoveryToken, newPhone);
        const result = await recovery.completePhone(grantResponse.recoveryToken, newPhone, call.checkId!);
        assert.ok('user' in result && 'auth' in result);
        assert.equal(result.user.id, user.id);
        assert.equal(await db.user.count({ where: { id: user.id } }), 1);
        assert.equal((await db.accountRecoveryGrant.findUniqueOrThrow({ where: { id: grant.id } })).consumedAt instanceof Date, true);
        assert.equal(await db.userSession.count({ where: { userId: user.id, revokedAt: null } }), 1);
        assert.equal(await db.restoreCredential.count({ where: { userId: user.id, revokedAt: null } }), 0);
        assert.equal(await db.restoreCredential.count({ where: { userId: other.id, revokedAt: null } }), 1);
        await assert.rejects(auth.refresh({ refreshToken: oldRefresh.refresh_token }), /session is not active/i);
        (restore as any).consumeChallenge = async () => ({ purpose: 'authentication', challenge: 'old-challenge', createdAt: new Date().toISOString() });
        const sessionsBeforePasskeyAttempt = await db.userSession.count({ where: { userId: user.id } });
        await assert.rejects(restore.verifyAuthentication({ id: `credential-${suffix}-1`, response: {
          clientDataJSON: Buffer.from(JSON.stringify({ challenge: 'old-challenge' })).toString('base64url'),
        } }), /not active/i);
        assert.equal(await db.userSession.count({ where: { userId: user.id } }), sessionsBeforePasskeyAttempt);
        assert.ok(result.auth.refresh_token);

        const expiredToken = `expired-${suffix}`;
        const expiredGrant = await db.accountRecoveryGrant.create({ data: { userId: user.id,
          tokenHash: (recovery as any).digest(expiredToken), expiresAt: new Date(Date.now() - 1000) } });
        await assert.rejects(auth.completeAccountRecovery(expiredGrant.id, (recovery as any).digest(expiredToken), newPhone), /истекла/i);
      });
    }
  } finally {
    await db.$disconnect();
  }
});
