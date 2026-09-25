import 'reflect-metadata';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'crypto';
import { BadRequestException, HttpException, ValidationPipe } from '@nestjs/common';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { PasswordlessService } from './passwordless.service';
import { PasswordlessController } from './passwordless.controller';
import { PasswordlessCheckDto, PasswordlessCompleteDto } from './dto/passwordless.dto';

function limits() {
  const counts = new Map<string, number>();
  return new RateLimitService({
    incr: async (key: string) => { const n = (counts.get(key) ?? 0) + 1; counts.set(key, n); return n; },
    expire: async () => 1,
  } as never);
}

test('start normalizes phone, stores only a hash, never reads accounts and uses the same response shape', async () => {
  const calls: any[] = [];
  const prisma = { user: { findUnique: () => assert.fail('start must not query users') },
    blockedIdentity: { findFirst: () => assert.fail('start must not query identities') } };
  const phone = { startCallVerification: async (...args: any[]) => {
    calls.push(args);
    return { callToPhone: '+79990000000', checkId: 'PRIVATE-PROVIDER-ID', expiresAt: new Date(Date.now() + 300_000).toISOString() };
  } };
  const service = new PasswordlessService(prisma as never, phone as never, limits(), {} as never);
  const a = await service.start('8 (999) 123-45-67');
  const b = await service.start('+7 999 123 45 68');
  assert.deepEqual(Object.keys(a), Object.keys(b));
  assert.equal(calls[0][0], '79991234567');
  assert.equal(calls[0][1], 'login');
  assert.equal(a.challenge.length, 80);
  assert.notEqual(a.challenge, b.challenge);
  assert.ok(!JSON.stringify(calls).includes(a.challenge));
  assert.ok(!JSON.stringify(a).includes('PRIVATE-PROVIDER-ID'));
  await assert.rejects(service.start('+7 999 123 45 67'), (e: any) => e.getStatus() === 429);
});

test('malformed challenge is rejected before database or provider access', async () => {
  const service = new PasswordlessService({} as never, {} as never, limits(), {} as never);
  for (const value of ['', 'provider-id', randomUUID(), `${randomUUID()}.short`]) {
    await assert.rejects(service.check(value), (e: any) => e.getStatus() === 400);
  }
});

test('check and complete rate limits bound repeated valid-shaped but invalid credentials', async () => {
  let transactions = 0;
  const service = new PasswordlessService({ $transaction: async () => {
    transactions++;
    throw new BadRequestException('invalid');
  } } as never, {} as never, limits(), {} as never);
  const token = `${randomUUID()}.${'a'.repeat(43)}`;
  for (let i = 0; i < 20; i++) await assert.rejects(service.check(token), (e: any) => e.getStatus() === 400);
  await assert.rejects(service.check(token), (e: any) => e.getStatus() === 429);
  for (let i = 0; i < 6; i++) await assert.rejects(service.complete({ registrationToken: token } as never), (e: any) => e.getStatus() === 400);
  await assert.rejects(service.complete({ registrationToken: token } as never), (e: any) => e.getStatus() === 429);
  assert.equal(transactions, 26);
});

test('complete DTO rejects another phone, missing consents, blank name, stale legal version and bad platform', async () => {
  const pipe = new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true });
  const valid = { registrationToken: `${randomUUID()}.${'a'.repeat(43)}`, displayName: 'Name',
    acceptedLegal: true, acceptedPersonalData: true, platform: 'IOS', legalDocumentVersion: '2026-09-12' };
  for (const patch of [{ phone: '79990000000' }, { referralCode: 'changed' }, { referralId: 'changed' }, { acceptedLegal: false }, { acceptedPersonalData: undefined },
    { displayName: '' }, { legalDocumentVersion: 'old' }, { platform: 'unknown' }]) {
    await assert.rejects(pipe.transform({ ...valid, ...patch }, { type: 'body', metatype: PasswordlessCompleteDto }));
  }
  await pipe.transform(valid, { type: 'body', metatype: PasswordlessCompleteDto });
  await assert.rejects(pipe.transform({ challenge: valid.registrationToken, phone: '79990000000' },
    { type: 'body', metatype: PasswordlessCheckDto }));
});

test('controller applies IP/device limits, does not trust forwarded header, and returns Retry-After on 429', async () => {
  const keys: string[] = [];
  const headers = new Map<string, string>();
  const controller = new PasswordlessController({ start: async () => { throw new HttpException('slow down', 429); } } as never,
    { consumeOrThrow: async (key: string) => { keys.push(key); } } as never);
  await assert.rejects(controller.start({ ip: '127.0.0.1', headers: { 'x-device-id': 'device', 'x-forwarded-for': 'untrusted' } },
    { setHeader: (key: string, value: string) => headers.set(key, value) }, { phone: '79991234567' }));
  assert.equal(keys.length, 2);
  assert.equal(headers.get('Retry-After'), '60');
  assert.equal(headers.get('Cache-Control'), 'no-store');
});

test('controller does not bind one challenge to one IP across start/check/complete', async () => {
  const calls: string[] = [];
  const controller = new PasswordlessController({
    start: async (_phone: string, source: any) => {
      calls.push(`start:${source.ip}`);
      return { status: 'pending', challenge: 'challenge', callToPhone: '79990000000', expiresAt: new Date().toISOString(), ttlSeconds: 300 };
    },
    check: async (challenge: string) => {
      calls.push(`check:${challenge}`);
      return { status: 'registration_required', registrationToken: 'token', expiresAt: new Date().toISOString(), ttlSeconds: 180 };
    },
    complete: async (dto: any) => {
      calls.push(`complete:${dto.registrationToken}`);
      return { auth: { session_id: 'session-1' } };
    },
  } as never, { consumeOrThrow: async () => {} } as never);
  const response = { setHeader: () => {} };
  await controller.start({ ip: '192.0.2.10', headers: { 'x-device-id': 'device' } }, response, { phone: '79991234567' });
  await controller.check({ ip: '198.51.100.20', headers: { 'x-device-id': 'device' } }, response, { challenge: 'challenge' });
  await controller.complete({ ip: '203.0.113.30', headers: { 'x-device-id': 'device' } }, response, { registrationToken: 'token' } as never);
  assert.deepEqual(calls, ['start:192.0.2.10', 'check:challenge', 'complete:token']);
});


test('controller publishes pending cooldown as Retry-After without changing challenge', async () => {
  const headers = new Map<string, string>();
  const controller = new PasswordlessController({ check: async (challenge: string) => {
    assert.equal(challenge, 'same-challenge');
    return { status: 'pending', retryAfterSeconds: 3 };
  } } as never, { consumeOrThrow: async () => {} } as never);
  const result = await controller.check({ ip: '203.0.113.42' },
    { setHeader: (key: string, value: string) => headers.set(key, value) }, { challenge: 'same-challenge' });
  assert.ok('status' in result);
  assert.equal(result.status, 'pending');
  assert.equal(headers.get('Retry-After'), '3');
  assert.equal(headers.get('Cache-Control'), 'no-store');
});
