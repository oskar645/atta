import 'reflect-metadata';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'crypto';
import { PrismaClient } from '@prisma/client';
import { AnalyticsSignal } from './analytics-signal';
import { UsageAnalyticsService } from './usage-analytics.service';

const url = process.env.ATTA_USAGE_TEST_DATABASE_URL;
test('usage analytics / disposable PostgreSQL', { skip: !url }, async t => {
  const parsed = new URL(url!);
  assert.equal(parsed.hostname, 'localhost');
  assert.equal(parsed.pathname, '/atta_usage_regression');
  assert.equal(parsed.searchParams.get('host'), '/private/tmp/atta-usage-pg/socket');
  const db = new PrismaClient({ datasources: { db: { url } } });
  const signal = new AnalyticsSignal();
  const service = new UsageAnalyticsService(db as never, signal);
  let invalidations = 0;
  signal.subscribe(() => invalidations++);
  const now = new Date('2026-10-01T09:00:00Z');
  const today = new Date('2026-09-30T21:00:00Z'); // Moscow October 1, midnight
  const yesterday = new Date('2026-09-30T20:59:59.999Z');
  const guest = randomUUID();
  const other = randomUUID();
  const listing = randomUUID();
  async function snapshot() { return (await service.aggregate(now)).periods as Record<string, Record<string, number>>; }
  try {
    await db.$executeRaw`TRUNCATE analytics_guest_days, analytics_listing_opens, chat_messages`;
    await t.test('guest uniqueness, simultaneous retries, next day, registered and IP-independent identity', async () => {
      await Promise.all(Array.from({ length: 20 }, () => service.guest(guest, undefined, today)));
      assert.equal(invalidations, 1);
      assert.equal((await snapshot()).today.guests, 1);
      await service.guest(guest, undefined, yesterday);
      await service.guest(other, undefined, today);
      await service.guest(randomUUID(), randomUUID(), today);
      const counts = await snapshot();
      assert.equal(counts.today.guests, 2);
      assert.equal(counts.today.totalOpens, 0);
      assert.equal(counts.yesterday.guests, 1);
      assert.equal(counts.week.guests, 2); // distinct people, not sum of daily counts
      assert.equal(counts.month.guests, 2);
      assert.equal(counts.all.guests, 2);
      // Service identity has no IP parameter: VPN cannot affect uniqueness.
    });
    await t.test('opening dedupe, immutable classification after login, real reopen and calendar bounds', async () => {
      const event = randomUUID();
      const startSignals = invalidations;
      await Promise.all(Array.from({ length: 20 }, () => service.listingOpen(event, listing, undefined, today)));
      await service.listingOpen(event, listing, randomUUID(), today);
      assert.equal(invalidations - startSignals, 1);
      await service.listingOpen(randomUUID(), listing, randomUUID(), today);
      await service.listingOpen(randomUUID(), listing, undefined, yesterday);
      await service.listingOpen(randomUUID(), listing, undefined, new Date('2026-09-24T21:00:00Z'));
      await service.listingOpen(randomUUID(), listing, undefined, new Date('2026-09-24T20:59:59.999Z'));
      const counts = await snapshot();
      assert.equal(counts.today.guestOpens, 1);
      assert.equal(counts.today.registeredOpens, 1);
      assert.equal(counts.today.totalOpens, 2);
      assert.equal(counts.yesterday.totalOpens, 1);
      assert.equal(counts.week.totalOpens, 4);
      assert.equal(counts.month.totalOpens, 2);
      assert.equal(counts.all.totalOpens, 5);
    });
    await t.test('existing messages: ten in one chat, second chat, socket invalidation replay', async () => {
      // Minimal fixture table has the production analytics columns. No auth/business fixtures needed.
      const chat = randomUUID();
      for (let i = 0; i < 10; i++) await db.$executeRaw`
        INSERT INTO chat_messages (id, chat_id, created_at) VALUES (${randomUUID()}::uuid, ${chat}::uuid, (${today}::timestamptz AT TIME ZONE 'UTC'))`;
      let counts = await snapshot();
      assert.equal(counts.today.messages, 10);
      assert.equal(counts.today.activeChats, 1);
      await db.$executeRaw`INSERT INTO chat_messages (id, chat_id, created_at) VALUES (${randomUUID()}::uuid, ${randomUUID()}::uuid, (${yesterday}::timestamptz AT TIME ZONE 'UTC'))`;
      for (let i = 0; i < 10; i++) signal.changed(); // delivery/socket replay cannot alter DB metrics
      counts = await snapshot();
      assert.equal(counts.today.messages, 10);
      assert.equal(counts.month.activeChats, 1);
      assert.equal(counts.all.messages, 11);
      assert.equal(counts.all.activeChats, 2);
      assert.equal(counts.yesterday.messages, 1);
      assert.equal(counts.yesterday.activeChats, 1);
    });
    await t.test('support rows and delivery/read/delete metadata never inflate marketplace messages', async () => {
      const before = await snapshot();
      await db.$executeRaw`CREATE TABLE IF NOT EXISTS support_messages (id uuid PRIMARY KEY)`;
      await db.$executeRaw`INSERT INTO support_messages (id) VALUES (${randomUUID()}::uuid)`;
      await db.$executeRaw`ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS delivered_at timestamp, ADD COLUMN IF NOT EXISTS read_at timestamp, ADD COLUMN IF NOT EXISTS deleted_at timestamp`;
      await db.$executeRaw`UPDATE chat_messages SET delivered_at = CURRENT_TIMESTAMP, read_at = CURRENT_TIMESTAMP, deleted_at = CURRENT_TIMESTAMP`;
      assert.deepEqual(await snapshot(), before);
    });
    await t.test('year boundary uses Moscow calendar and not UTC dates', async () => {
      await service.listingOpen(randomUUID(), listing, undefined, new Date('2026-12-31T21:00:00Z'));
      const counts = (await service.aggregate(new Date('2027-01-01T01:00:00Z'))).periods as Record<string, Record<string, number>>;
      assert.equal(counts.today.totalOpens, 1);
      assert.equal(counts.month.totalOpens, 1);
      assert.equal(counts.all.totalOpens, 6);
    });
  } finally { await db.$disconnect(); }
});
