import 'reflect-metadata';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'crypto';
import { ListingStatus, PrismaClient } from '@prisma/client';
import { isListingReadyForPublication } from '../../common/listing-publication';
import { ListingsService } from '../listings/listings.service';
import { AdminService } from './admin.service';

// Opt in only against a disposable local database, never the application's URL.
const url = process.env.ATTA_MODERATION_TEST_DATABASE_URL;
test('admin moderation / isolated PostgreSQL', { skip: !url }, async (t) => {
  const parsed = new URL(url!);
  assert.equal(parsed.hostname, 'localhost');
  assert.equal(parsed.pathname, '/atta_moderation_regression');
  assert.equal(parsed.username, 'atta_test');
  assert.equal(parsed.searchParams.get('host'), '/private/tmp/atta-moderation-pg/socket');
  const db = new PrismaClient({ datasources: { db: { url } } });
  const ownerId = randomUUID();
  const service = new AdminService(
    db as never, { countToday: async () => 0 } as never,
    { createSystemNotification: async () => undefined } as never,
    {} as never, {} as never, {} as never, undefined, {} as never,
  );
  const listings = new ListingsService(db as never, {} as never, {} as never);
  const auth = { userId: ownerId, sessionId: randomUUID(), role: 'admin' as const };
  const createdAt = new Date('2026-09-01T10:00:00Z');
  async function create(patch: Record<string, unknown> = {}, photo = true) {
    const id = randomUUID();
    return db.listing.create({ data: {
      id, ownerId, title: 'Фара Toyota', description: 'Оригинальная фара',
      category: 'Запчасти', subcategory: 'Оптика', city: 'Грозный', price: BigInt(1000),
      status: ListingStatus.PENDING, createdAt,
      ...(photo ? { photos: { create: { storageKey: `regression/${id}`, publicUrl: 'https://example.com/photo.jpg' } } } : {}),
      ...patch,
    }, include: { photos: true } });
  }
  async function expectQueue(ids: string[]) {
    const dashboard = await service.getDashboardStats();
    const queue = await service.getModerationQueue();
    assert.equal(dashboard.stats.pendingModeration, ids.length);
    assert.equal(queue.total, ids.length);
    assert.equal(queue.pendingModeration, ids.length);
    assert.equal(queue.pending_moderation, ids.length);
    assert.deepEqual(queue.items.map(item => item.id).sort(), [...ids].sort());
    return queue;
  }
  try {
    await db.user.create({ data: { id: ownerId, phone: `test-${ownerId}`, name: 'Regression', passwordHash: 'unused-test-hash' } });
    await t.test('ready pending is counted and returned; technical drafts are excluded', async () => {
      const ready = await create();
      const cases = [
        { title: 'Черновик объявления' }, { title: ' \tЧерновик объявления\n' },
        { title: ' \t\n' }, { description: '\u00a0\u2003\ufeff' }, { city: '\n\t' },
        { category: 'Все' }, { category: 'Unknown' }, { subcategory: '' },
        { subcategory: 'Телефоны' }, { price: BigInt(0) }, { price: BigInt(-1) },
      ];
      for (const patch of cases) {
        const draft = await create(patch);
        assert.equal(isListingReadyForPublication(draft), false);
      }
      await create({}, false);
      await expectQueue([ready.id]);
      // Legacy surrounding whitespace must match the existing approval validator.
      const padded = await create({ category: ' Запчасти\n', subcategory: '\tОптика ', title: ' Фара ' });
      assert.equal(isListingReadyForPublication(padded), true);
      const unrestricted = await create({ category: 'Услуги', subcategory: '' });
      await expectQueue([ready.id, padded.id, unrestricted.id]);
    });
    await db.listing.deleteMany({ where: { ownerId } });
    await t.test('deleted, archived and non-pending records are excluded', async () => {
      await create({ deletedAt: new Date() });
      await create({ archivedAt: new Date() });
      for (const status of [ListingStatus.APPROVED, ListingStatus.REJECTED, ListingStatus.SOLD, ListingStatus.ARCHIVED]) {
        await create({ status });
      }
      await expectQueue([]);
    });
    await db.listing.deleteMany({ where: { ownerId } });
    await t.test('filtering precedes pagination; all pages have a stable total', async () => {
      for (let i = 0; i < 5; i++) await create({ subcategory: '', createdAt: new Date('2026-09-02') });
      const ready = await Promise.all([create(), create(), create({ createdAt: new Date('2026-08-31T09:00:00Z') })]);
      let cursor: string | undefined;
      const seen: string[] = [];
      do {
        const page = await service.getModerationQueue({ limit: 1, cursor });
        assert.equal(page.items.length, 1);
        assert.equal(page.total, 3);
        assert.equal(page.pendingModeration, 3);
        seen.push(page.items[0].id);
        cursor = page.nextCursor ?? undefined;
        assert.equal(page.hasMore, !!cursor);
      } while (cursor && seen.length < 5);
      assert.deepEqual(seen.sort(), ready.map(item => item.id).sort());
      assert.equal((await service.getDashboardStats()).stats.pendingModeration, 3);
      assert.equal((await service.listListings()).total, 3);
    });
    await db.listing.deleteMany({ where: { ownerId } });
    await t.test('approve, owner edit, repeat moderation, reject remove items immediately', async () => {
      const ready = await create();
      await expectQueue([ready.id]);
      const approved = await service.approveListing(ready.id, auth);
      assert.equal(approved.listing.status, 'approved');
      await expectQueue([]);
      const edited = await listings.update(ready.id, { ...auth, role: 'user' }, { title: 'Новая фара Toyota' });
      assert.equal(edited.listing.status, 'pending');
      const queue = await expectQueue([ready.id]);
      assert.equal(queue.items[0].title, 'Новая фара Toyota');
      assert.equal(queue.items[0].photo_urls.length, 1);
      await service.approveListing(ready.id, auth);
      await expectQueue([]);
      await listings.update(ready.id, { ...auth, role: 'user' }, { description: 'Уточнённое описание' });
      await expectQueue([ready.id]);
      const rejected = await service.rejectListing(ready.id, auth, { reason: 'Неверное описание', moderationNote: 'Уточните состояние' });
      assert.equal(rejected.listing.status, 'rejected');
      const saved = await db.listing.findUniqueOrThrow({ where: { id: ready.id } });
      assert.equal(saved.rejectionReason, 'Неверное описание');
      assert.equal(saved.moderationNote, 'Уточните состояние');
      await expectQueue([]);
    });
  } finally {
    await db.user.deleteMany({ where: { id: ownerId } });
    await db.$disconnect();
  }
});
