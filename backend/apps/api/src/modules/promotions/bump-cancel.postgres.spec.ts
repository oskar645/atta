import 'reflect-metadata';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import { ListingStatus, PrismaClient, PromotionType } from '@prisma/client';
import { AdminService } from '../admin/admin.service';
import { WalletService } from '../wallet/wallet.service';
import { PromotionsService } from './promotions.service';

// Explicit opt-in to a disposable local database, never DATABASE_URL / .env.
const url = process.env.ATTA_BUMP_TEST_DATABASE_URL;
const DAY = 24 * 60 * 60 * 1000;

test('BUMP admin cancellation / isolated PostgreSQL', { skip: !url }, async (t) => {
  const parsed = new URL(url!);
  assert.equal(parsed.hostname, 'localhost');
  assert.equal(parsed.port, '55439');
  assert.equal(parsed.pathname, '/atta_bump_regression');
  assert.equal(parsed.username, 'atta_test');
  assert.equal(parsed.searchParams.get('host'), '/private/tmp/atta-bump-pg/socket');
  const db = new PrismaClient({ datasources: { db: { url } } });
  const wallet = new WalletService(db as never);
  const promotions = (client = db) => new PromotionsService(client as never, wallet, {} as never);
  const admin = (client = db) => new AdminService(
    client as never, {} as never, {} as never, {} as never,
    {} as never, {} as never, undefined, {} as never,
  );
  const owners: string[] = [];
  async function fixture(days = 3) {
    const userId = randomUUID();
    owners.push(userId);
    await db.user.create({ data: {
      id: userId, phone: `bump-test-${userId}`, name: 'BUMP test', passwordHash: 'unused',
    } });
    await wallet.ensureWalletAndBonuses(userId);
    await db.wallet.update({ where: { userId }, data: { bonusBalance: 10000 } });
    const listing = await db.listing.create({ data: {
      ownerId: userId, title: 'Фара Toyota', description: 'Оригинальная фара',
      category: 'Запчасти', subcategory: 'Оптика', city: 'Грозный',
      price: 1000, status: ListingStatus.APPROVED,
      photos: { create: { storageKey: `test/${userId}`, publicUrl: 'https://example.com/test.jpg' } },
    } });
    const auth = { userId, sessionId: randomUUID(), role: 'user' as const };
    const moderator = { ...auth, role: 'admin' as const };
    const service = promotions();
    async function buy(key = randomUUID(), quantity = days) {
      const response = await service.promoteListing(listing.id, auth, {
        type: 'bump', days: quantity, idempotencyKey: key,
      });
      const campaign = await db.listingRaiseCampaign.findUniqueOrThrow({
        where: { idempotencyKey: `raise_purchase:${userId}:${key}` },
      });
      const promotion = await db.promotion.findFirstOrThrow({ where: { raiseCampaignId: campaign.id } });
      return { response, campaign, promotion, key };
    }
    const purchase = await buy();
    const readCampaign = (id = purchase.campaign.id) => db.listingRaiseCampaign.findUniqueOrThrow({ where: { id } });
    const money = async () => ({
      wallet: await db.wallet.findUniqueOrThrow({ where: { userId } }),
      transactions: await db.walletTransaction.findMany({ where: { userId }, orderBy: { id: 'asc' } }),
    });
    return { ...purchase, buy, readCampaign, money, listing, auth, moderator, service };
  }
  // Pause a real transaction after it has acquired the campaign row lock.
  function pausedClient() {
    let reached!: () => void;
    let release!: () => void;
    const locked = new Promise<void>((done) => { reached = done; });
    const resume = new Promise<void>((done) => { release = done; });
    const client = new Proxy(db, { get(target, property) {
      if (property !== '$transaction') return Reflect.get(target, property);
      return (callback: (tx: unknown) => unknown) => db.$transaction(async (tx) => {
        const wrapped = new Proxy(tx, { get(transaction, key) {
          if (key !== '$queryRaw') return Reflect.get(transaction, key);
          return async (...args: any[]) => {
            const result = await (transaction.$queryRaw as any)(...args);
            if (String(args[0]).includes('listing_raise_campaigns')) {
              reached();
              await resume;
            }
            return result;
          };
        } });
        return callback(wrapped);
      }, { timeout: 10000 });
    } });
    return { client, locked, release };
  }

  try {
    await t.test('active campaign stops; executed raises and wallet remain; repeat cancel is idempotent', async () => {
      const f = await fixture();
      const money = await f.money();
      assert.equal((await f.service.processDueRaiseCampaigns(f.campaign.nextRaiseAt!)).processed, 1);
      const before = await f.readCampaign();
      const history = await db.promotion.findMany({ where: { raiseCampaignId: before.id }, orderBy: { startsAt: 'asc' } });
      assert.equal(history.length, 2);
      assert.equal(before.completedRaises, 2);
      // Cancel the latest scheduled Promotion, not just the initial purchase row.
      const target = history[1];
      const response = await admin().cancelPromotion(target.id, f.moderator);
      assert.equal(response.status, 'cancelled');
      const after = await f.readCampaign();
      assert.equal(after.status, 'CANCELLED');
      assert.equal(after.nextRaiseAt, null);
      assert.equal(after.cancelReason, 'admin_cancelled_promotion');
      assert.equal(after.completedRaises, before.completedRaises);
      assert.deepEqual(after.lastRaiseAt, before.lastRaiseAt);
      assert.deepEqual(await admin().cancelPromotion(target.id, f.moderator), response);
      assert.deepEqual(await f.readCampaign(), after);
      assert.equal((await f.service.processDueRaiseCampaigns(new Date(before.nextRaiseAt!.getTime() + 10 * DAY))).processed, 0);
      const remaining = await db.promotion.findMany({ where: { raiseCampaignId: before.id }, orderBy: { startsAt: 'asc' } });
      assert.deepEqual(remaining[0], history[0]);
      assert.deepEqual(remaining.map(p => [p.id, p.startsAt, p.endsAt, p.costBonus]), history.map(p => [p.id, p.startsAt, p.endsAt, p.costBonus]));
      assert.deepEqual(await f.money(), money);
    });

    await t.test('natural expiration allows remaining scheduled raises and campaign completion', async () => {
      const f = await fixture(2);
      const startsAt = new Date(Date.now() - 3 * DAY);
      await db.promotion.update({ where: { id: f.promotion.id }, data: { startsAt, endsAt: new Date(startsAt.getTime() + DAY) } });
      await db.listingRaiseCampaign.update({ where: { id: f.campaign.id }, data: {
        startedAt: startsAt, lastRaiseAt: startsAt, nextRaiseAt: new Date(startsAt.getTime() + DAY),
      } });
      const money = await f.money();
      await f.service.expirePromotionsByTime();
      assert.equal((await db.promotion.findUniqueOrThrow({ where: { id: f.promotion.id } })).status, 'EXPIRED');
      assert.equal((await f.readCampaign()).status, 'ACTIVE');
      assert.equal((await f.service.processDueRaiseCampaigns()).processed, 1);
      await f.service.expirePromotionsByTime();
      const completed = await f.readCampaign();
      assert.equal(completed.status, 'COMPLETED');
      assert.equal(completed.completedRaises, 2);
      assert.equal(completed.nextRaiseAt, null);
      assert.equal((await f.service.processDueRaiseCampaigns()).processed, 0);
      assert.deepEqual(await f.money(), money);
      const next = await f.buy();
      await admin().cancelPromotion(f.promotion.id, f.moderator);
      assert.deepEqual(await f.readCampaign(), completed);
      assert.equal((await f.readCampaign(next.campaign.id)).status, 'ACTIVE');
      await admin().cancelPromotion(next.promotion.id, f.moderator);
    });

    await t.test('new BUMP after cancellation survives repeat old cancel; replay does not charge again', async () => {
      const f = await fixture();
      await admin().cancelPromotion(f.promotion.id, f.moderator);
      const money = await f.money();
      await f.buy(f.key);
      assert.deepEqual(await f.money(), money);
      assert.equal(await db.listingRaiseCampaign.count({ where: { userId: f.auth.userId } }), 1);
      const next = await f.buy();
      assert.notEqual(next.campaign.id, f.campaign.id);
      assert.equal((await f.money()).wallet.bonusBalance, money.wallet.bonusBalance - next.campaign.totalPrice);
      const afterPurchase = await f.money();
      await admin().cancelPromotion(f.promotion.id, f.moderator);
      assert.equal((await f.readCampaign(next.campaign.id)).status, 'ACTIVE');
      assert.equal((await f.service.processDueRaiseCampaigns(next.campaign.nextRaiseAt!)).processed, 1);
      assert.equal((await f.readCampaign(next.campaign.id)).completedRaises, 2);
      assert.deepEqual(await f.money(), afterPurchase);
      await admin().cancelPromotion(next.promotion.id, f.moderator);
    });

    await t.test('VIP and Showcase cancellation are unchanged; overlapping BUMP purchases are isolated', async () => {
      const f = await fixture();
      const second = await f.buy();
      const special = [];
      for (const type of [PromotionType.VIP, PromotionType.SHOWCASE]) {
        await f.service.promoteListing(f.listing.id, f.auth, { type: type.toLowerCase() });
        special.push(await db.promotion.findFirstOrThrow({ where: { listingId: f.listing.id, type } }));
      }
      const money = await f.money();
      await admin().cancelPromotion(f.promotion.id, f.moderator);
      for (const promotion of special) {
        assert.deepEqual(await db.promotion.findUniqueOrThrow({ where: { id: promotion.id } }), promotion);
        await admin().cancelPromotion(promotion.id, f.moderator);
        await admin().cancelPromotion(promotion.id, f.moderator);
        assert.equal((await db.promotion.findUniqueOrThrow({ where: { id: promotion.id } })).status, 'CANCELLED');
        assert.deepEqual(await f.readCampaign(second.campaign.id), second.campaign);
      }
      assert.deepEqual(await f.money(), money);
      await admin().cancelPromotion(second.promotion.id, f.moderator);
    });

    await t.test('single raise completed campaign keeps its execution history', async () => {
      const f = await fixture(1);
      await admin().cancelPromotion(f.promotion.id, f.moderator);
      assert.deepEqual(await f.readCampaign(), f.campaign);
      assert.equal(f.campaign.status, 'COMPLETED');
    });

    await t.test('legacy standalone BUMP does not cancel another purchase', async () => {
      const f = await fixture();
      const standalone = await db.promotion.create({ data: {
        listingId: f.listing.id, userId: f.auth.userId, type: 'BUMP', costBonus: f.promotion.costBonus,
        startsAt: f.promotion.startsAt, endsAt: f.promotion.endsAt,
      } });
      const money = await f.money();
      const cancelled = await admin().cancelPromotion(standalone.id, f.moderator);
      assert.equal(cancelled.status, 'cancelled');
      assert.deepEqual(await admin().cancelPromotion(standalone.id, f.moderator), cancelled);
      assert.deepEqual(await f.money(), money);
      assert.deepEqual(await f.readCampaign(), f.campaign);
      await admin().cancelPromotion(f.promotion.id, f.moderator);
    });

    await t.test('cancel rolls back the campaign if Promotion update fails', async () => {
      const f = await fixture();
      const broken = new Proxy(db, { get(target, property) {
        if (property !== '$transaction') return Reflect.get(target, property);
        return (callback: (tx: unknown) => unknown) => db.$transaction(async (tx) => callback(new Proxy(tx, { get(transaction, key) {
          if (key !== 'promotion') return Reflect.get(transaction, key);
          return { findUnique: transaction.promotion.findUnique.bind(transaction.promotion), update: async () => { throw new Error('test failure'); } };
        } })));
      } });
      await assert.rejects(admin(broken).cancelPromotion(f.promotion.id, f.moderator), /test failure/);
      assert.deepEqual(await f.readCampaign(), f.campaign);
      assert.deepEqual(await db.promotion.findUniqueOrThrow({ where: { id: f.promotion.id } }), f.promotion);
      await admin().cancelPromotion(f.promotion.id, f.moderator);
    });

    await t.test('cancel takes lock first: worker skips it and never raises after commit', async () => {
      const f = await fixture();
      const gate = pausedClient();
      const cancellation = admin(gate.client).cancelPromotion(f.promotion.id, f.moderator);
      try {
        await gate.locked;
        assert.equal((await f.service.processDueRaiseCampaigns(f.campaign.nextRaiseAt!)).processed, 0);
      } finally { gate.release(); }
      await cancellation;
      assert.equal((await f.service.processDueRaiseCampaigns(f.campaign.nextRaiseAt!)).processed, 0);
      assert.equal((await f.readCampaign()).completedRaises, 1);
    });

    await t.test('worker takes lock first: cancel waits, preserves that raise, then stops future raises', async () => {
      const f = await fixture();
      const money = await f.money();
      const gate = pausedClient();
      const raising = promotions(gate.client).processDueRaiseCampaigns(f.campaign.nextRaiseAt!);
      let cancellation: Promise<unknown> | undefined;
      try {
        await gate.locked;
        cancellation = admin().cancelPromotion(f.promotion.id, f.moderator);
        const deadline = Date.now() + 3000;
        let blocked = false;
        while (Date.now() < deadline) {
          const rows = await db.$queryRaw<Array<{ blocked: boolean }>>`
            SELECT EXISTS (
              SELECT 1 FROM pg_stat_activity
              WHERE datname = current_database() AND wait_event_type = 'Lock'
                AND query LIKE '%listing_raise_campaigns%'
            ) AS blocked
          `;
          if (rows[0].blocked) { blocked = true; break; }
          await new Promise(done => setTimeout(done, 10));
        }
        assert.equal(blocked, true, 'cancel must wait for the worker row lock');
      } finally { gate.release(); }
      assert.equal((await raising).processed, 1);
      await cancellation;
      const campaign = await f.readCampaign();
      assert.equal(campaign.status, 'CANCELLED');
      assert.equal(campaign.completedRaises, 2);
      assert.deepEqual(campaign.lastRaiseAt, f.campaign.nextRaiseAt);
      assert.equal((await f.service.processDueRaiseCampaigns(new Date(f.campaign.nextRaiseAt!.getTime() + DAY))).processed, 0);
      assert.equal(await db.promotion.count({ where: { raiseCampaignId: campaign.id } }), 2);
      assert.deepEqual(await f.money(), money);
    });

    await t.test('migration backfills only mutually unique slots and never cancels historical campaigns', async () => {
      const migration = readFileSync(resolve(__dirname, '../../../../../prisma/migrations/20260922120000_link_bump_promotions_to_raise_campaigns/migration.sql'), 'utf8');
      // Temporary tables shadow public tables; each psql session drops them on exit.
      const setup = `
        CREATE TEMP TABLE listing_raise_campaigns (
          id uuid PRIMARY KEY, listing_id uuid, user_id uuid, price_per_raise int,
          completed_raises int, started_at timestamp(3), created_at timestamp(3),
          status text DEFAULT 'ACTIVE', next_raise_at timestamp(3), cancel_reason text, updated_at timestamp(3)
        );
        CREATE TEMP TABLE promotions (
          id uuid PRIMARY KEY, listing_id uuid, user_id uuid, cost_bonus int,
          starts_at timestamp(3), created_at timestamp(3), type text, status text DEFAULT 'EXPIRED'
        );
        INSERT INTO listing_raise_campaigns (id, listing_id, user_id, price_per_raise, completed_raises, started_at, created_at) VALUES
          ('00000000-0000-0000-0000-000000000001', '${randomUUID()}', '${randomUUID()}', 100, 2, '2026-09-01 10:00', '2026-09-01 09:59');
        INSERT INTO promotions (id, listing_id, user_id, cost_bonus, starts_at, created_at, type)
          SELECT '00000000-0000-0000-0000-000000000002', listing_id, user_id, 100, started_at, created_at, 'BUMP' FROM listing_raise_campaigns;
        INSERT INTO promotions (id, listing_id, user_id, cost_bonus, starts_at, created_at, type)
          SELECT '00000000-0000-0000-0000-000000000003', listing_id, user_id, 100, started_at + interval '24 hours', created_at + interval '24 hours', 'BUMP' FROM listing_raise_campaigns;
        INSERT INTO promotions (id, listing_id, user_id, cost_bonus, starts_at, created_at, type)
          SELECT '00000000-0000-0000-0000-000000000004', listing_id, user_id, 100, started_at, created_at, 'VIP' FROM listing_raise_campaigns;
      `;
      const run = (input: string) => spawnSync('psql', ['-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1', '-d', url!], { input, encoding: 'utf8' });
      const result = run(setup + migration + `SELECT type, raise_campaign_id IS NOT NULL FROM promotions ORDER BY id;`);
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.stdout.trim(), 'BUMP|t\nBUMP|t\nVIP|f');
      const repaired = run(setup + `
        UPDATE promotions SET status = 'CANCELLED' WHERE id = '00000000-0000-0000-0000-000000000002';
        UPDATE listing_raise_campaigns SET next_raise_at = started_at + interval '48 hours';
      ` + migration + `SELECT status, next_raise_at IS NULL, completed_raises, cancel_reason FROM listing_raise_campaigns;`);
      assert.equal(repaired.status, 0, repaired.stderr);
      assert.equal(repaired.stdout.trim(), 'ACTIVE|f|2|');
      const completed = run(setup + `
        UPDATE promotions SET status = 'CANCELLED';
        UPDATE listing_raise_campaigns SET status = 'COMPLETED';
      ` + migration + `SELECT status FROM listing_raise_campaigns;`);
      assert.equal(completed.status, 0, completed.stderr);
      assert.equal(completed.stdout.trim(), 'COMPLETED');
      const ambiguous = run(setup + `
        INSERT INTO listing_raise_campaigns (id, listing_id, user_id, price_per_raise, completed_raises, started_at, created_at) SELECT '00000000-0000-0000-0000-000000000005', listing_id, user_id, price_per_raise, completed_raises, started_at, created_at FROM listing_raise_campaigns;
      ` + migration);
      assert.equal(ambiguous.status, 0, ambiguous.stderr);
      const check = (changes: string, expected: string) => {
        const result = run(setup + changes + migration + `
          SELECT type, raise_campaign_id IS NOT NULL FROM promotions ORDER BY id;
          SELECT status, completed_raises FROM listing_raise_campaigns ORDER BY id;
        `);
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.stdout.trim(), expected);
      };
      check(`UPDATE promotions SET cost_bonus = 999 WHERE type = 'BUMP';`,
        'BUMP|f\nBUMP|f\nVIP|f\nACTIVE|2');
      const duplicateCampaign = `INSERT INTO listing_raise_campaigns
        SELECT '00000000-0000-0000-0000-000000000005', listing_id, user_id,
          price_per_raise, completed_raises, started_at, created_at, status,
          next_raise_at, cancel_reason, updated_at FROM listing_raise_campaigns;`;
      check(duplicateCampaign, 'BUMP|f\nBUMP|f\nVIP|f\nACTIVE|2\nACTIVE|2');
      // Slot 0 is contested (including a cancelled row); slot 1 still links.
      const duplicatePromotion = `INSERT INTO promotions
        SELECT '00000000-0000-0000-0000-000000000006', listing_id, user_id,
          cost_bonus, starts_at, created_at, type, 'CANCELLED' FROM promotions
        WHERE id = '00000000-0000-0000-0000-000000000002';`;
      check(duplicatePromotion, 'BUMP|f\nBUMP|t\nVIP|f\nBUMP|f\nACTIVE|2');
      // Count slot contention before excluding promotions with multiple candidates.
      check(duplicateCampaign + `UPDATE listing_raise_campaigns SET completed_raises = 1
        WHERE id = '00000000-0000-0000-0000-000000000005';` + duplicatePromotion,
        'BUMP|f\nBUMP|t\nVIP|f\nBUMP|f\nACTIVE|2\nACTIVE|1');
      for (const status of ['ACTIVE', 'COMPLETED', 'CANCELLED', 'FAILED']) {
        check(`UPDATE listing_raise_campaigns SET status = '${status}';
          UPDATE promotions SET status = 'CANCELLED';`,
          `BUMP|t\nBUMP|t\nVIP|f\n${status}|2`);
      }
      check(`UPDATE promotions SET status = 'ACTIVE';`, 'BUMP|t\nBUMP|t\nVIP|f\nACTIVE|2');
      for (const type of ['VIP', 'SHOWCASE', 'TURBO']) {
        check(`UPDATE promotions SET type = '${type}';`,
          `${type}|f\n${type}|f\n${type}|f\nACTIVE|2`);
      }
      // An injected failure after UPDATE must leave no partially linked rows.
      const failed = run(setup + migration.replace('COMMIT;\n\n-- Historical',
        `SELECT 1 / 0;\nCOMMIT;\n\n-- Historical`).replace('SELECT 1 / 0;',
        `\\set ON_ERROR_STOP off\nSELECT 1 / 0;`) +
        `SELECT count(*) FROM promotions WHERE raise_campaign_id IS NOT NULL;`);
      assert.equal(failed.status, 0, failed.stderr);
      assert.match(failed.stderr, /division by zero/);
      assert.equal(failed.stdout.trim(), '0');
    });
  } finally {
    await db.user.deleteMany({ where: { id: { in: owners } } });
    await db.$disconnect();
  }
});
