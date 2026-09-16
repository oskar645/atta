import type { AccountDeletionService } from '../auth/account-deletion.service';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'crypto';
import { PrismaClient, ListingStatus, NotificationScope, NotificationType } from '@prisma/client';
import { SavedSearchAlertsService } from './saved-search-alerts.service';
import { NotificationsService } from '../notifications/notifications.service';
import { AuthService } from '../auth/auth.service';

// Explicit opt-in; never falls back to the application's DATABASE_URL.
const url = process.env.ATTA_UNREAD_TEST_DATABASE_URL;
test('isolated PostgreSQL: matching, concurrent deduplication, canonical badge and token sessions', { skip: !url }, async () => {
  const target = new URL(url!);
  assert.equal(target.hostname, '127.0.0.1');
  assert.equal(target.port, '55439');
  const prisma = new PrismaClient({ datasources: { db: { url } } });
  const a = randomUUID(), b = randomUUID();
  const globalIds: string[] = [];
  const pushes: any[] = [], events: any[] = [];
  const notifications = new NotificationsService({ send: async (payload: any) => {
    pushes.push(payload); return { sent: true, status: 200 };
  } } as never, prisma as never, { emitNotificationNew: (item: any) => events.push(item) } as never);
  const alerts = new SavedSearchAlertsService(prisma as never, notifications);
  const auth = new AuthService(prisma as never, {} as never, {} as never, {} as never, {} as never,
    {
      deleteUser: async () => {
        throw new Error('Unexpected account deletion in this test');
      },
    } satisfies Pick<AccountDeletionService, 'deleteUser'> as unknown as AccountDeletionService,
  );
  try {
    await prisma.user.createMany({ data: [a, b].map(id => ({ id, passwordHash: 'synthetic-not-a-credential' })) });
    const sessionA = await prisma.userSession.create({ data: { userId: a, refreshTokenHash: 'synthetic-a',
      createdAt: new Date('2026-01-01'), expiresAt: new Date('2099-01-01') } });
    const sessionB = await prisma.userSession.create({ data: { userId: b, refreshTokenHash: 'synthetic-b',
      createdAt: new Date('2026-02-01'), expiresAt: new Date('2099-01-01') } });
    const userA = { userId: a, sessionId: sessionA.id, role: 'user' } as const;
    const userB = { userId: b, sessionId: sessionB.id, role: 'user' } as const;
    const token = `synthetic-token-${randomUUID()}`;
    await notifications.registerDevice(userA as never, { token, platform: 'ios' });
    await prisma.chat.create({ data: { buyerId: a, sellerId: b, unreadForBuyer: 2 } });
    await notifications.createSystemNotification({ userId: a, title: 'Support', body: 'Reply', type: NotificationType.SUPPORT });
    await prisma.userNotification.create({ data: { userId: a, scope: NotificationScope.PERSONAL, type: NotificationType.CHAT_MESSAGE } });
    assert.equal(await notifications.canonicalBadgeCount(a), 3, 'chat record is not double-counted');
    assert.equal(pushes.at(-1).badge, 3);
    await notifications.markAllRead(userA as never);
    assert.equal(await notifications.canonicalBadgeCount(a), 2);
    await prisma.chat.updateMany({ where: { buyerId: a }, data: { unreadForBuyer: 0 } });
    const global = await prisma.userNotification.create({ data: { scope: NotificationScope.GLOBAL } });
    globalIds.push(global.id);
    assert.equal(await notifications.canonicalBadgeCount(a), 1);
    await notifications.markAllSeen(userA as never);
    assert.equal(await notifications.canonicalBadgeCount(a), 0);
    assert.equal(await notifications.canonicalBadgeCount(b), 1, 'global seen is per-user');

    const search = await prisma.savedSearch.create({ data: { userId: a, queryKey: randomUUID(), search: 'Toyota Corolla', category: 'Авто',
      location: 'Москва', radiusKm: 10, autoBrand: 'Toyota', autoMileageTo: 50000, createdAt: new Date('2026-01-01') } });
    async function makeListing(status: ListingStatus, title = 'Toyota Corolla', city = 'Москва') {
      return prisma.listing.create({ data: { ownerId: b, title, description: 'Автомобиль', category: 'Авто', city,
        status, publishedAt: new Date(), car: { brand: 'Toyota', mileageKm: 10000 },
        photos: { create: { storageKey: randomUUID(), publicUrl: 'https://example.invalid/photo.jpg' } } } });
    }
    const approved = await makeListing(ListingStatus.APPROVED);
    await Promise.all([alerts.notifyApprovedListing(approved.id), alerts.notifyApprovedListing(approved.id)]);
    assert.equal(await prisma.savedSearchAlert.count({ where: { savedSearchId: search.id } }), 1);
    const matches = await prisma.userNotification.findMany({ where: { userId: a, type: NotificationType.SAVED_SEARCH } });
    assert.equal(matches.length, 1);
    assert.equal(events.filter(n => n.type === 'saved_search').length, 1);
    assert.equal((matches[0].payload as any).listingId, approved.id);
    assert.equal(pushes.at(-1).badge, 1);
    for (const status of [ListingStatus.PENDING, ListingStatus.REJECTED, ListingStatus.ARCHIVED]) {
      await alerts.notifyApprovedListing((await makeListing(status)).id);
    }
    await alerts.notifyApprovedListing((await makeListing(ListingStatus.APPROVED, 'Ford Focus')).id);
    await alerts.notifyApprovedListing((await makeListing(ListingStatus.APPROVED, 'Toyota Corolla', 'Казань')).id);
    assert.equal(await prisma.savedSearchAlert.count({ where: { savedSearchId: search.id } }), 1);
    await prisma.savedSearch.delete({ where: { id: search.id } });
    await alerts.notifyApprovedListing((await makeListing(ListingStatus.APPROVED)).id);
    assert.equal(await prisma.userNotification.count({ where: { userId: a, type: NotificationType.SAVED_SEARCH } }), 1);

    await auth.logout(userA as never);
    assert.equal((await prisma.userDevice.findUniqueOrThrow({ where: { deviceToken: token } })).isActive, false);
    const before = pushes.length;
    await notifications.createSystemNotification({ userId: a, title: 'A logged out', body: '' });
    assert.equal(pushes.length, before);
    await notifications.registerDevice(userB as never, { token, platform: 'ios' });
    await assert.rejects(() => notifications.registerDevice(userA as never, { token, platform: 'ios' }), /not active/);
    await notifications.unregisterDevice(userA as never, token);
    const device = await prisma.userDevice.findUniqueOrThrow({ where: { deviceToken: token } });
    assert.equal(device.userId, b); assert.equal(device.sessionId, sessionB.id); assert.equal(device.isActive, true);
    await notifications.createSystemNotification({ userId: b, title: 'B only', body: '' });
    assert.equal(pushes.at(-1).payload.recipientId, b);
    assert.equal(pushes.at(-1).badge, 2);
  } finally {
    await prisma.userNotification.deleteMany({ where: { id: { in: globalIds } } });
    await prisma.user.deleteMany({ where: { id: { in: [a, b] } } });
    await prisma.$disconnect();
  }
});
