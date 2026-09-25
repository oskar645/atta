import 'reflect-metadata';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PATH_METADATA, METHOD_METADATA } from '@nestjs/common/constants';
import { Module, RequestMethod, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { UsageAnalyticsService } from './usage-analytics.service';
import { AnalyticsSignal } from './analytics-signal';
import { ChatsGateway } from '../chats/chats.gateway';
import { UsageAnalyticsController } from './usage-analytics.controller';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { OptionalJwtAuthGuard } from '../auth/optional-jwt-auth.guard';
import { PrismaService } from '../prisma/prisma.service';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { UserBlocksService } from '../user-blocks/user-blocks.service';

const testGuests = new Set<string>();
const testAnalytics = {
  guest: async (guestId: string, userId?: string) => {
    if (userId) return { recorded: false };
    const recorded = !testGuests.has(guestId);
    testGuests.add(guestId);
    return { recorded };
  },
};

@Module({
  controllers: [UsageAnalyticsController],
  providers: [
    { provide: UsageAnalyticsService, useValue: testAnalytics },
    {
      provide: RateLimitService,
      useValue: { consumeOrThrow: async () => undefined },
    },
    {
      provide: JwtService,
      useValue: {
        verifyAsync: async () => ({
          type: 'access', sub: 'registered', sessionId: 'session',
        }),
      },
    },
    {
      provide: PrismaService,
      useValue: {
        userSession: {
          findFirst: async () => ({
            id: 'session',
            expiresAt: new Date(Date.now() + 60_000),
            user: {
              id: 'registered', email: null, phone: null, status: 'ACTIVE',
              deletedAt: null, adminProfile: null,
            },
          }),
        },
      },
    },
    { provide: JwtAuthGuard, useValue: { canActivate: () => true } },
    { provide: AdminGuard, useValue: { canActivate: () => true } },
    { provide: UserBlocksService, useValue: {} },
    OptionalJwtAuthGuard,
  ],
})
class UsageAnalyticsHttpTestModule {}

test('anonymous guest activity uses POST and keeps dedupe and authenticated classification intact', async () => {
  testGuests.clear();
  const guestId = '7f965d60-4fa6-4bfc-9258-c1208bce89d6';
  const app = await NestFactory.create(UsageAnalyticsHttpTestModule, {
    abortOnError: false,
    logger: false,
  });
  app.useGlobalPipes(new ValidationPipe({
    whitelist: true,
    transform: true,
    forbidNonWhitelisted: true,
  }));
  await app.listen(0, '127.0.0.1');
  try {
    const url = `${await app.getUrl()}/analytics/guest-activity`;
    const post = (authorization?: string) => fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...(authorization ? { authorization } : {}) },
      body: JSON.stringify({ guestId }),
    });
    const first = await post();
    assert.equal(first.status, 201);
    assert.deepEqual(await first.json(), { recorded: true });
    const duplicate = await post();
    assert.equal(duplicate.status, 201);
    assert.deepEqual(await duplicate.json(), { recorded: false });
    const authenticated = await post('Bearer registered');
    assert.equal(authenticated.status, 201);
    assert.deepEqual(await authenticated.json(), { recorded: false });
    assert.equal(testGuests.size, 1);
  } finally {
    await app.close();
  }

  assert.equal(
    Reflect.getMetadata(PATH_METADATA, UsageAnalyticsController.prototype.guest),
    'analytics/guest-activity',
  );
  assert.equal(
    Reflect.getMetadata(METHOD_METADATA, UsageAnalyticsController.prototype.guest),
    RequestMethod.POST,
  );
});

test('nginx sends analytics endpoints to Nest instead of the Flutter static fallback', () => {
  for (const file of ['atta-domain.production', 'atta-domain.nginx']) {
    const config = readFileSync(
      resolve(__dirname, '../../../../../..', 'deploy', file),
      'utf8',
    );
    const apiLocation = config.split('\n').find(line => line.includes('location ~ ^/(?:'));
    assert.match(apiLocation ?? '', /(?:\||^)analytics(?:\||\))/);
  }
});

test('guest service accepts a duplicate and never writes authenticated activity', async () => {
  const results = [1, 0];
  let writes = 0;
  const service = new UsageAnalyticsService({
    $executeRaw: async () => {
      writes++;
      return results.shift();
    },
  } as never, new AnalyticsSignal());
  const guestId = '7f965d60-4fa6-4bfc-9258-c1208bce89d6';

  assert.deepEqual(await service.guest(guestId), { recorded: true });
  assert.deepEqual(await service.guest(guestId), { recorded: false });
  assert.deepEqual(await service.guest(guestId, 'registered'), { recorded: false });
  assert.equal(writes, 2);
});

test('dashboard HTTP endpoint requires both session and admin guards', () => {
  assert.deepEqual(Reflect.getMetadata('__guards__', UsageAnalyticsController.prototype.dashboard), [JwtAuthGuard, AdminGuard]);
});

test('analytics subscription rejects normal users and missing sessions; revocation removes subscribed admins', async () => {
  let admin = false;
  let active = true;
  const signal = new AnalyticsSignal();
  const gateway = new ChatsGateway({} as never, {} as never,
    { verifyAsync: async () => ({ type: 'access', sub: 'user', sessionId: 'session' }) } as never,
    { userSession: { findFirst: async () => active ? ({ userId: 'user', expiresAt: new Date(Date.now() + 60000) }) : null },
      user: { findUnique: async () => ({ phone: null, adminProfile: { isAdmin: admin } }) } } as never,
    { onDeleted: () => () => {} } as never, signal);
  const rooms = new Set<string>();
  const received: string[] = [];
  const client = {
    handshake: { auth: { token: 'valid' }, headers: {} }, rooms,
    join: async (room: string) => { rooms.add(room); },
    leave: async (room: string) => { rooms.delete(room); },
    emit: (event: string) => received.push(event),
  };
  gateway.server = { sockets: { sockets: new Map([['one', client]]) } } as never;
  await assert.rejects(gateway.subscribeAnalytics(client as never), /Admin access/);
  assert.equal(rooms.size, 0);
  admin = true;
  await gateway.subscribeAnalytics(client as never);
  await (gateway as any).notifyAnalyticsAdmins();
  assert.deepEqual(received, ['analytics_updated']);
  active = false;
  await (gateway as any).notifyAnalyticsAdmins();
  assert.equal(rooms.size, 0);
  assert.equal(received.length, 1);
  await assert.rejects(gateway.subscribeAnalytics(client as never));
});

test('analytics observer failure cannot break successful business writes', () => {
  const signal = new AnalyticsSignal();
  let called = 0;
  signal.subscribe(() => { throw Error('disconnected socket'); });
  const unsubscribe = signal.subscribe(() => called++);
  signal.changed();
  unsubscribe();
  signal.changed();
  assert.equal(called, 1);
});


test('dashboard coalesces queries and refetches database after invalidation', async () => {
  const signal = new AnalyticsSignal();
  const service = new UsageAnalyticsService({} as never, signal);
  let queries = 0;
  service.aggregate = async () => ({ timezone: 'Europe/Moscow', asOf: 'test', periods: { today: { guests: ++queries } } }) as never;
  await Promise.all([service.dashboard(), service.dashboard()]);
  assert.equal(queries, 1);
  await service.dashboard();
  assert.equal(queries, 1);
  signal.changed();
  await service.dashboard();
  assert.equal(queries, 2);
});
