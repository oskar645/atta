import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'crypto';
import { PrismaClient } from '@prisma/client';
import { AccountDeletionService } from './account-deletion.service';

// Opt-in only. Never falls back to DATABASE_URL / .env / project database.
const url = process.env.ATTA_DELETE_TEST_DATABASE_URL;
test('isolated PostgreSQL: actual rollback, cascades, two-device revoke, concurrency and media retry', { skip: !url }, async () => {
  const parsed = new URL(url!);
  assert.equal(parsed.hostname, 'localhost');
  assert.equal(parsed.pathname, '/atta_deletion_regression');
  assert.equal(parsed.searchParams.get('host'), '/private/tmp/atta-delete-pg-20260915/socket');
  assert.equal(parsed.port, '56439');
  const db = new PrismaClient({ datasources: { db: { url } } });
  const a = randomUUID(), b = randomUUID(), listingId = randomUUID();
  let externalFailure = true;
  let mediaCalls = 0;
  const storage = { deleteAccountAvatar: async () => {
    assert.equal((await db.user.findUniqueOrThrow({ where: { id: a } })).status, 'DELETED');
    mediaCalls++;
    if (externalFailure) throw new Error('mock S3 failure');
  } };
  const redis = { del: async () => {} };
  try {
    await db.user.createMany({ data: [
      { id: a, displayName: 'Synthetic A', name: 'Synthetic A', passwordHash: 'test', avatarUrl: '/mock-avatar' },
      { id: b, displayName: 'Synthetic B', name: 'Synthetic B', passwordHash: 'test' },
    ] });
    const bBefore = await db.user.findUniqueOrThrow({ where: { id: b } });
    const notice = await db.userNotification.create({ data: { userId: b, scope: 'PERSONAL', type: 'GENERIC',
      title: 'Новый отзыв', body: 'Synthetic A оставил новый отзыв.', payload: { actionType: 'review_new', authorId: a } } });
    await db.listing.create({ data: { id: listingId, ownerId: a, title: 'Synthetic listing', category: 'Test', status: 'APPROVED', phone: 'private', ownerName: 'A' } });
    const search = await db.savedSearch.create({ data: { userId: a, queryKey: 'test' } });
    await db.savedSearchAlert.create({ data: { savedSearchId: search.id, listingId } });
    await db.favorite.create({ data: { userId: a, listingId } });
    const sessions = await Promise.all([1, 2].map(() => db.userSession.create({ data: { userId: a, refreshTokenHash: 'test', expiresAt: new Date(Date.now() + 60_000) } })));
    await db.userDevice.createMany({ data: sessions.map((s, i) => ({ userId: a, sessionId: s.id, platform: 'IOS', deviceToken: `test-${a}-${i}` })) });
    await db.restoreCredential.create({ data: { userId: a, credentialId: `test-${a}`, publicKey: Buffer.from('test') } });
    const chat = await db.chat.create({ data: { buyerId: a, sellerId: b, listingId, unreadForSeller: 4 } });
    const message = await db.chatMessage.create({ data: { chatId: chat.id, senderId: b, text: 'Keep peer history', imageKey: 'keep-peer-attachment' } });
    const wallet = await db.wallet.create({ data: { userId: a, bonusBalance: 100 } });
    const transaction = await db.walletTransaction.create({ data: { userId: a, walletId: wallet.id, type: 'ACCRUAL', amount: 100, reason: 'POINTS_PURCHASE' } });
    const payment = await db.payment.create({ data: { userId: a, idempotencyKey: `test-${a}`, amountRub: 100, pointsAmount: 100 } });
    await db.report.create({ data: { listingId, listingOwnerId: a, reporterId: b, reason: 'Keep evidence' } });
    const failingDb = new Proxy(db, { get(target, key) {
      if (key !== '$transaction') return Reflect.get(target, key);
      return (fn: any, options: any) => target.$transaction(tx => fn(new Proxy(tx, { get(value, field) {
        if (field === 'report') return { updateMany: async () => { throw new Error('late failure'); } };
        return Reflect.get(value, field);
      } })), options);
    } });
    const failed = new AccountDeletionService(failingDb as never, storage as never, redis as never);
    await assert.rejects(failed.deleteUser(a), /late failure/);
    assert.equal((await db.user.findUniqueOrThrow({ where: { id: a } })).status, 'ACTIVE');
    assert.equal(await db.userDevice.count({ where: { userId: a } }), 2);
    assert.equal(await db.savedSearchAlert.count({ where: { savedSearchId: search.id } }), 1);
    assert.equal(await db.accountDeletionCleanup.count({ where: { userId: a } }), 0);
    assert.equal(mediaCalls, 0);

    const service = new AccountDeletionService(db as never, storage as never, redis as never);
    const results = await Promise.all([service.deleteUser(a), service.deleteUser(a)]);
    assert.ok(results.every(result => result.deleted));
    assert.equal((await db.user.findUniqueOrThrow({ where: { id: a } })).status, 'DELETED');
    assert.equal(await db.userSession.count({ where: { userId: a, revokedAt: null } }), 0);
    assert.equal(await db.userDevice.count({ where: { userId: a } }), 0);
    assert.equal(await db.restoreCredential.count({ where: { userId: a } }), 0);
    assert.equal(await db.savedSearch.count({ where: { userId: a } }), 0);
    assert.equal(await db.savedSearchAlert.count({ where: { savedSearchId: search.id } }), 0);
    assert.equal((await db.listing.findUniqueOrThrow({ where: { id: listingId } })).status, 'DELETED');
    assert.deepEqual(await db.user.findUniqueOrThrow({ where: { id: b } }), bBefore);
    assert.equal((await db.userNotification.findUniqueOrThrow({ where: { id: notice.id } })).body, 'Удалённый пользователь оставил новый отзыв.');
    assert.deepEqual(await db.chatMessage.findUniqueOrThrow({ where: { id: message.id } }), message);
    const keptChat = await db.chat.findUniqueOrThrow({ where: { id: chat.id } });
    assert.equal(keptChat.deletedBySellerAt, null); assert.equal(keptChat.unreadForSeller, 4);
    assert.deepEqual(await db.wallet.findUniqueOrThrow({ where: { id: wallet.id } }), wallet);
    assert.deepEqual(await db.walletTransaction.findUniqueOrThrow({ where: { id: transaction.id } }), transaction);
    assert.deepEqual(await db.payment.findUniqueOrThrow({ where: { id: payment.id } }), payment);
    assert.equal(await db.accountDeletionCleanup.count({ where: { userId: a } }), 1);
    externalFailure = false;
    await service.cleanupUser(a); await service.cleanupUser(a);
    assert.equal(await db.accountDeletionCleanup.count({ where: { userId: a } }), 0);
  } finally { await db.$disconnect(); }
});
