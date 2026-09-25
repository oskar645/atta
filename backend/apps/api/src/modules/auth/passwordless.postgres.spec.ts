import 'reflect-metadata';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'crypto';
import { PrismaClient } from '@prisma/client';
import { HttpException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { compare, hash } from 'bcryptjs';

import { buildReferralCode } from '../../common/referral-code';
import { WALLET_DAILY_BONUS_AMOUNT, WALLET_WELCOME_BONUS, WALLET_REFERRAL_INVITER_BONUS } from '../wallet/wallet.constants';
import { AuthService } from './auth.service';
import { PasswordlessService } from './passwordless.service';
import { PhoneVerificationService } from '../phone-verification/phone-verification.service';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { WalletService } from '../wallet/wallet.service';
import { UserBlocksService } from '../user-blocks/user-blocks.service';

// Explicit opt-in. This suite never uses DATABASE_URL or the project's database.
const url = process.env.ATTA_PASSWORDLESS_TEST_DATABASE_URL;
test('passwordless / isolated PostgreSQL', { skip: !url }, async (t) => {
  const parsed = new URL(url!);
  assert.equal(parsed.hostname, 'localhost');
  assert.equal(parsed.pathname, '/atta_passwordless_regression');
  assert.match(parsed.searchParams.get('host') ?? '', /^\/private\/tmp\/atta-passwordless-pg\.[A-Za-z0-9]+\/socket$/);
  assert.equal(parsed.username, 'atta_test');
  const db = new PrismaClient({ datasources: { db: { url } } });
  let phoneCounter = Math.floor(Math.random() * 1_000_000);
  const nextPhone = () => `7999${String(++phoneCounter).padStart(7, '0')}`;
  const rate = { consumeOrThrow: async () => {}, countUniqueValues: async () => 1 } as unknown as RateLimitService;
  const wallet = new WalletService(db as never);
  const blocks = new UserBlocksService(db as never);
  const auth = new AuthService(db as never, new JwtService(), {} as never, wallet, blocks, {} as never);
  const provider = new PhoneVerificationService(db as never, rate);
  let providerCode = 401;
  let providerUnavailable = false;
  let providerCalls = 0;
  let concurrentPolls = 0;
  let maxConcurrentPolls = 0;
  // Exercise the real SMS.ru adapter/state code without calling a paid provider.
  (provider as any).useFakeProvider = () => false;
  (provider as any).assertProviderConfigured = () => {};
  (provider as any).callSmsRu = async (path: string) => {
    if (path.endsWith('/add')) return { status: 'OK', status_code: 100, check_id: randomUUID(), call_phone: '79990000000' };
    providerCalls++;
    concurrentPolls++;
    maxConcurrentPolls = Math.max(maxConcurrentPolls, concurrentPolls);
    await new Promise(resolve => setTimeout(resolve, 15));
    concurrentPolls--;
    if (providerUnavailable) throw new HttpException('provider offline', 503);
    return { status: 'OK', status_code: 100, check_status: providerCode };
  };
  const service = new PasswordlessService(db as never, provider, rate, auth);
  const completeDto = (registrationToken: string) => ({ registrationToken, displayName: 'Synthetic signup',
    acceptedLegal: true, acceptedPersonalData: true, acceptedMarketing: true, platform: 'IOS', legalDocumentVersion: '2026-09-12' });
  const start = (phone = nextPhone()) => service.start(phone);
  async function releaseCooldown(id: string) {
    const row = await db.phoneVerification.findUniqueOrThrow({ where: { id } });
    const metadata = row.metadata as any;
    await db.phoneVerification.update({ where: { id }, data: { metadata: {
      ...metadata, passwordless: { ...metadata.passwordless, nextProviderPollAt: Date.now() - 1 },
    } } });
  }
  async function registration(phone = nextPhone()) {
    const started = await start(phone);
    const checked = await service.check(started.challenge);
    assert.ok('registrationToken' in checked);
    return { phone, started, checked };
  }
  async function createUser(phone = nextPhone(), patch: any = {}) {
    return db.user.create({ data: { id: randomUUID(), phone, displayName: 'Existing', name: 'Existing', passwordHash: await hash('existing-password', 10), ...patch } });
  }
  async function counts(userId: string) {
    return { sessions: await db.userSession.count({ where: { userId } }),
      wallets: await db.wallet.count({ where: { userId } }),
      bonuses: await db.walletTransaction.count({ where: { userId, reason: 'SIGNUP_BONUS' } }),
      consents: await db.userConsent.count({ where: { userId } }) };
  }
  try {
    await t.test('start has identical pre-confirmation behavior for existing, absent and blocked numbers', async () => {
      const existing = await createUser();
      const blocked = await createUser(undefined, { status: 'BLOCKED' });
      const responses = await Promise.all([existing.phone!, blocked.phone!, nextPhone()].map(phone => start(phone)));
      for (const response of responses) {
        assert.deepEqual(Object.keys(response), Object.keys(responses[0]));
        assert.equal(response.status, 'pending');
        assert.equal(response.callToPhone, responses[0].callToPhone);
        assert.equal(response.challenge.length, 80);
        const row = await db.phoneVerification.findUniqueOrThrow({ where: { id: response.challenge.slice(0, 36) } });
        assert.equal(row.purpose, 'LOGIN');
        assert.ok(!JSON.stringify(row.metadata).includes(response.challenge));
      }
    });

    await t.test('confirmed existing user keeps id/password and gets standard session without signup bonus', async () => {
      const user = await createUser();
      const started = await start(user.phone!);
      const result = await service.check(started.challenge);
      assert.ok('auth' in result);
      assert.equal(result.auth.user_id, user.id);
      assert.equal(result.user.id, user.id);
      assert.equal((await db.user.findUniqueOrThrow({ where: { id: user.id } })).passwordHash, user.passwordHash);
      const session = await db.userSession.findUniqueOrThrow({ where: { id: result.auth.session_id } });
      assert.ok(await compare(result.auth.refresh_token, session.refreshTokenHash));
      assert.deepEqual(await counts(user.id), { sessions: 1, wallets: 0, bonuses: 0, consents: 0 });
      const replay = await service.check(started.challenge);
      assert.ok('auth' in replay);
      assert.equal(replay.auth.session_id, result.auth.session_id);
      assert.equal(replay.auth.refresh_token, result.auth.refresh_token);
      assert.equal(await db.userSession.count({ where: { userId: user.id } }), 1);
    });

    await t.test('new user receives one-time registration token, consents, random password hash, wallet and session', async () => {
      const { phone, started, checked } = await registration();
      assert.equal(await db.user.count({ where: { phone } }), 0);
      assert.ok(!JSON.stringify(await db.phoneVerification.findUnique({ where: { id: started.challenge.slice(0, 36) } })).includes(started.challenge));
      await assert.rejects(service.complete(completeDto(started.challenge)));
      await assert.rejects(service.check(checked.registrationToken));
      const retryCheck = await service.check(started.challenge);
      assert.deepEqual(retryCheck, checked);
      const result = await service.complete(completeDto(checked.registrationToken));
      const user = await db.user.findUniqueOrThrow({ where: { phone } });
      assert.equal(result.auth.user_id, user.id);
      assert.match(user.passwordHash, /^\$2[aby]\$10\$/);
      assert.equal(await compare(phone, user.passwordHash), false);
      assert.deepEqual(await counts(user.id), { sessions: 1, wallets: 1, bonuses: 1, consents: 3 });
      const consents = await db.userConsent.findMany({ where: { userId: user.id } });
      assert.ok(consents.every(c => c.acceptedAt && c.documentVersion === '2026-09-12' && c.platform === 'IOS'));
      const other = await registration();
      const otherResult = await service.complete(completeDto(other.checked.registrationToken));
      assert.notEqual((await db.user.findUniqueOrThrow({ where: { id: otherResult.auth.user_id } })).passwordHash, user.passwordHash);
    });

    await t.test('concurrent complete/replay and lost responses never duplicate user/session/wallet/bonus', async () => {
      const { phone, checked } = await registration();
      const dto = completeDto(checked.registrationToken);
      const results = await Promise.allSettled([service.complete(dto), service.complete(dto)]);
      assert.equal(results.filter(r => r.status === 'fulfilled').length, 2);
      const completed = results.find((r): r is PromiseFulfilledResult<any> => r.status === 'fulfilled')!.value;
      const replay = await service.complete(dto); // client lost the successful response
      assert.equal(replay.auth.session_id, completed.auth.session_id);
      assert.equal(replay.auth.refresh_token, completed.auth.refresh_token);
      const user = await db.user.findUniqueOrThrow({ where: { phone } });
      assert.deepEqual(await counts(user.id), { sessions: 1, wallets: 1, bonuses: 1, consents: 3 });
      // Starting again safely logs into the same account.
      await db.phoneVerification.updateMany({ where: { phone }, data: { createdAt: new Date(Date.now() - 120_000) } });
      const fresh = await start(phone);
      const login = await service.check(fresh.challenge);
      assert.ok('auth' in login);
      assert.equal(login.auth.user_id, user.id);
      assert.deepEqual(await counts(user.id), { sessions: 2, wallets: 1, bonuses: 1, consents: 3 });
    });

    await t.test('network loss retries keep the same challenge, user, bonus and session until challenge expiry', async () => {
      const phone = nextPhone();
      const firstIp = await service.start(phone, { ip: '192.0.2.1', deviceId: 'device-a', userAgent: 'wifi' });
      const registrationResult = await service.check(firstIp.challenge);
      assert.ok('registrationToken' in registrationResult);
      const retryAfterNetworkLoss = await service.check(firstIp.challenge);
      assert.deepEqual(retryAfterNetworkLoss, registrationResult);
      const completed = await service.complete(completeDto(registrationResult.registrationToken));
      const user = await db.user.findUniqueOrThrow({ where: { phone } });
      assert.equal(completed.auth.user_id, user.id);
      assert.deepEqual(await counts(user.id), { sessions: 1, wallets: 1, bonuses: 1, consents: 3 });

      const retryComplete = await service.complete(completeDto(registrationResult.registrationToken));
      assert.equal(retryComplete.auth.session_id, completed.auth.session_id);
      assert.equal(retryComplete.auth.refresh_token, completed.auth.refresh_token);
      const retryCheck = await service.check(firstIp.challenge);
      assert.ok('auth' in retryCheck);
      assert.equal(retryCheck.auth.session_id, completed.auth.session_id);
      assert.deepEqual(await counts(user.id), { sessions: 1, wallets: 1, bonuses: 1, consents: 3 });

      const id = firstIp.challenge.slice(0, 36);
      await db.phoneVerification.update({ where: { id }, data: { expiresAt: new Date(Date.now() - 1) } });
      await assert.rejects(service.check(firstIp.challenge));
      await assert.rejects(service.complete(completeDto(registrationResult.registrationToken)));
    });

    await t.test('two independent registration tokens for one phone create one account and one signup bonus', async () => {
      const phone = nextPhone();
      const a = await registration(phone), b = await registration(phone);
      const results = await Promise.all([service.complete(completeDto(a.checked.registrationToken)), service.complete(completeDto(b.checked.registrationToken))]);
      assert.equal(results[0].auth.user_id, results[1].auth.user_id);
      assert.equal(await db.user.count({ where: { phone } }), 1);
      assert.deepEqual(await counts(results[0].auth.user_id), { sessions: 2, wallets: 1, bonuses: 1, consents: 3 });
    });

    await t.test('expired pending and confirmed challenges are rejected; legacy confirmed verification checks TTL', async () => {
      for (const status of ['PENDING', 'CONFIRMED'] as const) {
        const started = await start();
        await db.phoneVerification.update({ where: { id: started.challenge.slice(0, 36) }, data: { status, expiresAt: new Date(Date.now() - 1) } });
        await assert.rejects(service.check(started.challenge));
      }
      const legacyPhone = nextPhone();
      const legacy = await provider.startCallVerification(legacyPhone, 'login');
      await db.phoneVerification.updateMany({ where: { checkId: legacy.checkId }, data: { status: 'CONFIRMED', expiresAt: new Date(Date.now() - 1) } });
      assert.equal((await provider.checkCallVerification(legacyPhone, legacy.checkId, 'login')).status, 'expired');
    });

    await t.test('invalid secret, missing marker, provider ID and registration token cannot authorize another phone', async () => {
      const a = await registration(), b = await registration();
      await assert.rejects(service.check(a.started.challenge.slice(0, 37) + 'x'.repeat(43)));
      await assert.rejects(service.complete(completeDto(b.checked.registrationToken.slice(0, 37) + a.checked.registrationToken.slice(37))));
      const row = await db.phoneVerification.findUniqueOrThrow({ where: { id: a.started.challenge.slice(0, 36) } });
      await assert.rejects(service.check(row.checkId!));
      await assert.rejects(provider.checkCallVerification(a.phone, row.checkId!, 'login'));
      await db.phoneVerification.update({ where: { id: row.id }, data: { metadata: {} } });
      await assert.rejects(service.complete(completeDto(a.checked.registrationToken)));
      assert.equal(await db.user.count({ where: { phone: { in: [a.phone, b.phone] } } }), 0);
    });

    await t.test('registration token TTL is checked independently of confirmed verification TTL', async () => {
      const { started, checked } = await registration();
      const id = started.challenge.slice(0, 36);
      const row = await db.phoneVerification.findUniqueOrThrow({ where: { id } });
      const metadata = row.metadata as any;
      metadata.passwordless.registrationExpiresAt = new Date(Date.now() - 1).toISOString();
      await db.phoneVerification.update({ where: { id }, data: { metadata } });
      await assert.rejects(service.complete(completeDto(checked.registrationToken)));
    });

    await t.test('referral is bound at start and concurrent complete/replay awards each bonus once', async () => {
      const inviter = await createUser();
      const phone = nextPhone();
      const referralCode = buildReferralCode(inviter.id);
      const opened = await auth.recordReferralAppOpen({ referralCode });
      assert.ok(opened.referralId);
      const started = await service.start(phone, undefined, { referralCode, referralId: opened.referralId });
      const checked = await service.check(started.challenge);
      assert.ok('registrationToken' in checked);
      const dto = { ...completeDto(checked.registrationToken), referralCode: buildReferralCode(randomUUID()) };
      const results = await Promise.all([service.complete(dto), service.complete(dto)]);
      const userId = results[0].auth.user_id;
      assert.equal(results[1].auth.user_id, userId);
      await service.complete(dto);
      const referral = await db.referral.findUniqueOrThrow({ where: { invitedUserId: userId } });
      assert.equal(referral.inviterUserId, inviter.id);
      assert.equal(referral.id, opened.referralId);
      const rewards = await db.walletTransaction.findMany({ where: { userId: inviter.id, reason: 'REFERRAL_INVITER_BONUS' } });
      assert.equal(rewards.length, 1);
      assert.equal(rewards[0].amount, WALLET_REFERRAL_INVITER_BONUS);
      const bonuses = await db.walletTransaction.findMany({ where: { userId, reason: 'SIGNUP_BONUS' } });
      assert.equal(bonuses.length, 1);
      assert.equal(bonuses[0].amount, WALLET_WELCOME_BONUS);
      await wallet.checkAndAccrueDailyBonus(userId);
      assert.equal(await db.walletTransaction.count({ where: { userId, reason: 'DAILY_LOGIN_BONUS' } }), 0);
      const login = await service.check((await service.start(phone, undefined, { referralCode: buildReferralCode(inviter.id) })).challenge);
      assert.ok('auth' in login);
      assert.equal(login.auth.user_id, userId);
      assert.equal((await counts(userId)).bonuses, 1);
      assert.equal(await db.referral.count({ where: { invitedUserId: userId } }), 1);
    });

    await t.test('invalid and same-phone self referral preserve legacy no-reward policy', async () => {
      for (const self of [false, true]) {
        const phone = nextPhone();
        const inviter = self ? await createUser(undefined, { phone: '+' + phone }) : null;
        const started = await service.start(phone, undefined, { referralCode: inviter ? buildReferralCode(inviter.id) : 'invalid' });
        const checked = await service.check(started.challenge);
        assert.ok('registrationToken' in checked);
        const result = await service.complete(completeDto(checked.registrationToken));
        assert.equal(await db.referral.count({ where: { invitedUserId: result.auth.user_id } }), 0);
        assert.equal((await counts(result.auth.user_id)).bonuses, 1);
      }
    });

    await t.test('previous passwordless registration for a released phone prevents another inviter bonus', async () => {
      const inviter = await createUser();
      const { phone, checked } = await registration();
      const original = await service.complete(completeDto(checked.registrationToken));
      await db.user.update({ where: { id: original.auth.user_id },
        data: { phone: null, status: 'DELETED', deletedAt: new Date() } });
      const started = await service.start(phone, undefined, { referralCode: buildReferralCode(inviter.id) });
      const next = await service.check(started.challenge);
      assert.ok('registrationToken' in next);
      const result = await service.complete(completeDto(next.registrationToken));
      assert.equal(await db.referral.count({ where: { invitedUserId: result.auth.user_id } }), 0);
      assert.equal(await db.walletTransaction.count({ where: { userId: inviter.id, reason: 'REFERRAL_INVITER_BONUS' } }), 0);
    });

    await t.test('temporary expiry allows passwordless and legacy password login; active/permanent deny', async () => {
      for (const mode of ['expired', 'active', 'permanent', 'legacy']) {
        const user = await createUser(undefined, { status: 'BLOCKED' });
        await db.userBlock.create({ data: { userId: user.id, adminId: user.id,
          type: mode === 'permanent' ? 'PERMANENT' : 'TEMPORARY', reason: 'test',
          endsAt: new Date(Date.now() + (mode === 'active' ? 60000 : -60000)) } });
        if (mode === 'legacy') {
          await auth.loginPhone({ phone: user.phone!, password: 'existing-password' });
          await auth.findActiveUserByIdOrThrow(user.id);
        } else {
          const challenge = (await start(user.phone!)).challenge;
          if (mode === 'expired') {
            const result = await service.check(challenge);
            assert.ok('auth' in result);
            assert.equal(result.auth.user_id, user.id);
          } else {
            await assert.rejects(service.check(challenge));
          }
        }
      }
    });

    await t.test('daily bonus survives logout/passwordless login and awards only once on next calendar day', async () => {
      const user = await createUser(undefined, { createdAt: new Date('2026-01-01T12:00:00Z') });
      let now = new Date('2026-09-20T12:00:00Z');
      const dailyWallet = new WalletService(db as never, () => now);
      await dailyWallet.ensureWalletAndBonuses(user.id);
      await dailyWallet.checkAndAccrueDailyBonus(user.id);
      const login = await service.check((await start(user.phone!)).challenge);
      assert.ok('auth' in login);
      await auth.logout({ userId: user.id, sessionId: login.auth.session_id } as never);
      await service.check((await start(user.phone!)).challenge);
      await dailyWallet.checkAndAccrueDailyBonus(user.id);
      assert.equal(await db.walletTransaction.count({ where: { userId: user.id, reason: 'DAILY_LOGIN_BONUS' } }), 1);
      now = new Date('2026-09-22T12:00:00Z');
      await Promise.all([dailyWallet.checkAndAccrueDailyBonus(user.id), dailyWallet.checkAndAccrueDailyBonus(user.id)]);
      assert.equal(await db.walletTransaction.count({ where: { userId: user.id, reason: 'DAILY_LOGIN_BONUS' } }), 2);
      assert.equal((await counts(user.id)).bonuses, 1);
      assert.equal((await db.wallet.findUniqueOrThrow({ where: { userId: user.id } })).bonusBalance,
        WALLET_WELCOME_BONUS + 2 * WALLET_DAILY_BONUS_AMOUNT);
    });

    await t.test('all non-ACTIVE account statuses, deletedAt and active UserBlock cannot bypass access checks', async () => {
      for (const patch of [{ status: 'BLOCKED' }, { status: 'DELETED' }, { deletedAt: new Date() }]) {
        const user = await createUser(undefined, patch);
        const started = await start(user.phone!);
        await assert.rejects(service.check(started.challenge));
        assert.equal(await db.userSession.count({ where: { userId: user.id } }), 0);
      }
      const user = await createUser();
      await db.userBlock.create({ data: { userId: user.id, adminId: user.id, type: 'PERMANENT', reason: 'test' } });
      const started = await start(user.phone!);
      await assert.rejects(service.check(started.challenge));
      assert.equal(await db.userSession.count({ where: { userId: user.id } }), 0);
    });

    await t.test('BlockedIdentity prevents login and registration even when added after CallCheck confirmation', async () => {
      const admin = await createUser();
      const block = await db.userBlock.create({ data: { userId: admin.id, adminId: admin.id, type: 'PERMANENT', reason: 'test' } });
      const { phone, checked } = await registration();
      await db.blockedIdentity.create({ data: { normalizedPhone: phone, userBlockId: block.id, reason: 'test', permanent: true } });
      await assert.rejects(service.complete(completeDto(checked.registrationToken)));
      assert.equal(await db.user.count({ where: { phone } }), 0);
      const existing = await createUser();
      await db.blockedIdentity.create({ data: { normalizedPhone: existing.phone!, userBlockId: block.id, reason: 'test', permanent: false, bannedUntil: new Date(Date.now() + 60_000) } });
      await assert.rejects(service.check((await start(existing.phone!)).challenge));
      assert.equal(await db.userSession.count({ where: { userId: existing.id } }), 0);
    });

    await t.test('complete rereads a concurrently created blocked/deleted account without overwriting it', async () => {
      for (const patch of [{ status: 'BLOCKED' }, { status: 'DELETED' }, { deletedAt: new Date() }]) {
        const { phone, checked } = await registration();
        const winner = await createUser(phone, patch);
        await assert.rejects(service.complete(completeDto(checked.registrationToken)));
        assert.deepEqual(await db.user.findUniqueOrThrow({ where: { phone } }), winner);
        assert.deepEqual(await counts(winner.id), { sessions: 0, wallets: 0, bonuses: 0, consents: 0 });
      }
    });

    await t.test('pending/confirmed provider updates preserve metadata and concurrent polling is serialized', async () => {
      providerCode = 400;
      const started = await start();
      maxConcurrentPolls = 0;
      const results = await Promise.all([service.check(started.challenge), service.check(started.challenge)]);
      assert.ok(results.every(r => 'status' in r && r.status === 'pending'));
      assert.equal(maxConcurrentPolls, 1);
      const id = started.challenge.slice(0, 36);
      const row = await db.phoneVerification.findUniqueOrThrow({ where: { id } });
      assert.ok((row.metadata as any).passwordless.challengeHash);
      assert.equal(row.attempts, 1);
      assert.ok((row.metadata as any).passwordless.nextProviderPollAt > Date.now());
      await releaseCooldown(id);
      providerCode = 401;
      const before = providerCalls;
      const confirmed = await Promise.allSettled([service.check(started.challenge), service.check(started.challenge)]);
      assert.equal(confirmed.filter(r => r.status === 'fulfilled').length, 2);
      assert.equal(providerCalls - before, 1);
      assert.equal((await db.phoneVerification.findUniqueOrThrow({ where: { id } })).status, 'CONFIRMED');
    });

    await t.test('12 eligible pending polls survive the old limit, cooldown survives another API instance, then confirm', async () => {
      providerCode = 400;
      const started = await service.start(nextPhone(), { ip: '192.0.2.1', deviceId: 'desktop' });
      const id = started.challenge.slice(0, 36);
      const otherProcess = new PasswordlessService(db as never, provider, rate, auth);
      const before = providerCalls;
      for (let i = 1; i <= 12; i++) {
        await releaseCooldown(id);
        const pending = await service.check(started.challenge);
        assert.ok('status' in pending && pending.status === 'pending');
        assert.ok('retryAfterSeconds' in pending && pending.retryAfterSeconds === 5);
        const immediate = await otherProcess.check(started.challenge);
        assert.ok('status' in immediate && immediate.status === 'pending');
        assert.equal(providerCalls - before, i);
        const row = await db.phoneVerification.findUniqueOrThrow({ where: { id } });
        assert.equal(row.status, 'PENDING');
        assert.equal(row.attempts, i);
      }
      // A call from the registered SIM is represented only by SMS.ru's status.
      // No tel launch, client lifecycle, caller IP or device is sent to check.
      providerCode = 401;
      await releaseCooldown(id); // browser reconnects after the cooldown
      const confirmed = await otherProcess.check(started.challenge);
      assert.ok('registrationToken' in confirmed);
      assert.deepEqual(await service.check(started.challenge), confirmed);
      assert.equal(providerCalls - before, 13);
    });

    await t.test('provider outages and malformed statuses retain pending and commit cooldown', async () => {
      for (const unavailable of [true, false]) {
        providerUnavailable = unavailable;
        providerCode = 999;
        const started = await start();
        const before = providerCalls;
        const pending = await service.check(started.challenge);
        assert.ok('status' in pending && pending.status === 'pending');
        await service.check(started.challenge);
        assert.equal(providerCalls - before, 1);
        assert.equal((await db.phoneVerification.findUniqueOrThrow({ where: { id: started.challenge.slice(0, 36) } })).status, 'PENDING');
      }
      providerUnavailable = false;
      providerCode = 401;
    });

    await t.test('local TTL and provider terminal expiry stop polling; legacy five-attempt limit stays', async () => {
      providerCode = 400;
      const expired = await start();
      const id = expired.challenge.slice(0, 36);
      await service.check(expired.challenge);
      await db.phoneVerification.update({ where: { id }, data: { expiresAt: new Date(Date.now() - 1) } });
      const before = providerCalls;
      await assert.rejects(service.check(expired.challenge));
      assert.equal(providerCalls, before);
      providerCode = 402; // documented terminal failure: expired or invalid check_id
      const terminal = await start();
      const result = await service.check(terminal.challenge);
      assert.ok('status' in result && result.status === 'expired');
      assert.equal((await db.phoneVerification.findUniqueOrThrow({ where: { id: terminal.challenge.slice(0, 36) } })).status, 'EXPIRED');
      await assert.rejects(service.check(terminal.challenge));
      providerCode = 400;
      const phone = nextPhone();
      const legacy = await provider.startCallVerification(phone, 'signup');
      for (let i = 0; i < 5; i++) assert.equal((await provider.checkCallVerification(phone, legacy.checkId, 'signup')).status, 'pending');
      assert.equal((await provider.checkCallVerification(phone, legacy.checkId, 'signup')).status, 'failed');
      providerCode = 401;
    });

    await t.test('late session failure rolls back user, consents, wallet/bonus and token; retry then succeeds', async () => {
      const { phone, checked } = await registration();
      const failingDb = new Proxy(db, { get(target, key) {
        if (key !== '$transaction') return Reflect.get(target, key);
        return (fn: any, options: any) => target.$transaction(tx => fn(new Proxy(tx, { get(value, field) {
          if (field === 'userSession') return { create: async () => { throw new Error('injected session failure'); } };
          return Reflect.get(value, field);
        } })), options);
      } });
      const failing = new PasswordlessService(failingDb as never, provider, rate, auth);
      const before = { wallets: await db.wallet.count(), bonuses: await db.walletTransaction.count(), consents: await db.userConsent.count() };
      await assert.rejects(failing.complete(completeDto(checked.registrationToken)), /injected session failure/);
      assert.equal(await db.user.count({ where: { phone } }), 0);
      assert.deepEqual({ wallets: await db.wallet.count(), bonuses: await db.walletTransaction.count(), consents: await db.userConsent.count() }, before);
      const result = await service.complete(completeDto(checked.registrationToken));
      assert.deepEqual(await counts(result.auth.user_id), { sessions: 1, wallets: 1, bonuses: 1, consents: 3 });
    });

    await t.test('actual User.phone unique conflict retries in a fresh transaction and preserves winning account', async () => {
      const { phone, checked } = await registration();
      let winner: Awaited<ReturnType<typeof createUser>> | undefined;
      const racingDb = new Proxy(db, { get(target, key) {
        if (key !== '$transaction') return Reflect.get(target, key);
        return (fn: any, options: any) => target.$transaction(tx => fn(new Proxy(tx, { get(value, field) {
          if (field === 'user') return new Proxy(value.user, { get(delegate, method) {
            if (method !== 'create') return Reflect.get(delegate, method);
            return async (args: any) => { winner = await createUser(phone); return delegate.create(args); };
          } });
          return Reflect.get(value, field);
        } })), options);
      } });
      const racing = new PasswordlessService(racingDb as never, provider, rate, auth);
      const result = await racing.complete(completeDto(checked.registrationToken));
      assert.equal(result.auth.user_id, winner!.id);
      const user = await db.user.findUniqueOrThrow({ where: { phone } });
      assert.equal(user.displayName, 'Existing');
      assert.equal(user.passwordHash, winner!.passwordHash);
      assert.deepEqual(await counts(user.id), { sessions: 1, wallets: 0, bonuses: 0, consents: 0 });
    });

    await t.test('legacy phone/start/check, signup/login/reset, refresh and session revoke remain functional', async () => {
      const phone = nextPhone();
      const started = await provider.startCallVerification(phone, 'signup');
      assert.equal((await provider.checkCallVerification(phone, started.checkId, 'signup')).status, 'confirmed');
      const signup = await auth.signupPhone({ phone, password: 'legacy-password', displayName: 'Legacy',
        acceptedLegal: true, acceptedPersonalData: true, verificationCheckId: started.checkId });
      const logged = await auth.loginPhone({ phone, password: 'legacy-password' });
      assert.equal(logged.auth.user_id, signup.auth.user_id);
      const reset = await provider.startCallVerification(phone, 'reset_password');
      await provider.checkCallVerification(phone, reset.checkId, 'reset_password');
      assert.equal((await auth.resetPasswordPhone({ phone, verificationCheckId: reset.checkId, newPassword: 'changed-password' })).status, 'ok');
      await assert.rejects(auth.loginPhone({ phone, password: 'legacy-password' }));
      assert.equal((await auth.loginPhone({ phone, password: 'changed-password' })).auth.user_id, signup.auth.user_id);
      const refreshed = await auth.refresh({ refreshToken: logged.auth.refresh_token });
      assert.equal(refreshed.auth.session_id, logged.auth.session_id);
      await auth.logout({ userId: logged.auth.user_id, sessionId: logged.auth.session_id } as never);
      await assert.rejects(auth.refresh({ refreshToken: refreshed.auth.refresh_token }));
      assert.equal((await provider.checkRegistration(phone)).exists, true);
    });
  } finally { await db.$disconnect(); }
});
