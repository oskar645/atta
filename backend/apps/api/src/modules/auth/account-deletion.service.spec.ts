import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JwtService } from '@nestjs/jwt';
import { env } from '../../config/env';
import { serializeUser } from '../../common/serializers';
import { buildReferralCode } from '../../common/referral-code';
import { AccountDeletionService } from './account-deletion.service';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { ChatsGateway } from '../chats/chats.gateway';
import { ChatsService } from '../chats/chats.service';
import { ReviewsService } from '../reviews/reviews.service';

const A = '11111111-1111-4111-8111-111111111111';
const B = '22222222-2222-4222-8222-222222222222';
const future = () => new Date(Date.now() + 60_000);
const user = (id: string) => ({ id, phone: id === A ? '79281234567' : '79281234568',
  email: `${id}@example.test`, displayName: 'Private name', name: 'Private name',
  avatarUrl: `/media/object?category=avatars&key=avatars/${id}/image.jpg`, photoUrl: null,
  phoneVerified: true, passwordHash: 'old-hash', status: 'ACTIVE', deletedAt: null,
  blockedAt: null, blockReason: null, lastLoginAt: new Date(), adminProfile: null,
  createdAt: new Date(), updatedAt: new Date(), lastNotificationsSeenAt: new Date() });

// Stateful transaction double checks resulting A/B data and rollback, not just call signatures.
// This does not simulate PostgreSQL isolation or prove production runtime behavior.
function fixture() {
  let rows: Record<string, any[]> = Object.fromEntries([
    'user', 'userSession', 'userDevice', 'restoreCredential', 'userPresence', 'favorite',
    'savedSearch', 'viewedListing', 'appDailyVisit', 'listingView', 'userFollow', 'chatPeerBlock',
    'userNotification', 'chat', 'chatMessage', 'review', 'supportTicket', 'supportMessage',
    'listing', 'listingPhoto', 'promotion', 'listingRaiseCampaign', 'userConsent',
    'phoneVerification', 'report', 'wallet', 'walletTransaction', 'payment', 'referral',
    'auditLog', 'listingModerationRevision', 'accountDeletionCleanup', 'blockedIdentity',
  ].map(name => [name, []]));
  rows.user = [user(A), user(B)];
  for (const userId of [A, B]) {
    for (const name of ['favorite', 'savedSearch', 'viewedListing', 'appDailyVisit', 'userPresence', 'userNotification']) rows[name].push({ id: `${name}-${userId}`, userId });
    for (const device of [1, 2]) {
      rows.userSession.push({ id: `${userId}-${device}`, userId, revokedAt: null, refreshTokenHash: 'secret', ip: '192.0.2.1', userAgent: 'agent', deviceName: 'phone', deviceId: 'device', expiresAt: future() });
      rows.userDevice.push({ id: `push-${userId}-${device}`, userId, deviceToken: 'token', isActive: true });
      rows.restoreCredential.push({ id: `restore-${userId}-${device}`, userId, publicKey: 'key' });
    }
    rows.listingView.push({ viewerUserId: userId, viewerDeviceId: `device-${userId}`, ip: '192.0.2.1' });
    rows.review.push({ reviewerId: userId, sellerId: userId === A ? B : A, reviewerName: 'Name', comment: 'History', deletedAt: null });
    rows.supportTicket.push({ userId, name: 'Private name', subject: 'History' });
    rows.supportMessage.push({ senderUserId: userId, text: 'Evidence' });
    rows.promotion.push({ userId, status: 'ACTIVE', costBonus: 50 });
    rows.listingRaiseCampaign.push({ userId, status: 'ACTIVE', nextRaiseAt: future(), totalPrice: 100 });
    rows.userConsent.push({ userId, consentType: 'MARKETING_MESSAGES', withdrawnAt: null });
    rows.userConsent.push({ userId, consentType: 'TERMS_ACCEPTANCE', withdrawnAt: null });
    for (const name of ['wallet', 'walletTransaction', 'payment', 'auditLog', 'listingModerationRevision']) rows[name].push({ id: `${name}-${userId}`, userId, balance: 100, metadata: { evidence: true } });
  }
  rows.referral = [{ inviterUserId: B, invitedUserId: A, rewardStatus: 'REWARDED', rewardAmount: 200 }];
  rows.phoneVerification = [{ id: 'original-signup', phone: '79281234567', purpose: 'SIGNUP', status: 'CONFIRMED', createdUserId: A, requestedByIp: '192.0.2.1', requestedByDeviceId: 'device', expiresAt: future() }];
  rows.userFollow = [{ followerId: A, sellerId: B }, { followerId: B, sellerId: A }, { followerId: B, sellerId: 'third' }];
  rows.chatPeerBlock = [{ blockerUserId: A, blockedUserId: B }, { blockerUserId: B, blockedUserId: 'third' }];
  rows.chat = [{ id: 'chat', buyerId: A, sellerId: B, deletedByBuyerAt: null, deletedBySellerAt: null, unreadForBuyer: 3, unreadForSeller: 7, lastMessage: 'Peer history' }];
  rows.chatMessage = [{ senderId: A, text: 'A history', imageKey: 'a.jpg' }, { senderId: B, text: 'B history', imageKey: 'b.jpg' }];
  for (const status of ['APPROVED', 'PENDING', 'REJECTED', 'ARCHIVED', 'SOLD', 'DELETED']) {
    rows.listing.push({ id: status, ownerId: A, status, ownerName: 'Owner', ownerEmail: 'owner@test', phone: '79281234567', address: 'Home', latitude: 1, longitude: 1, locationJson: { street: 'Home' }, deletedAt: status === 'DELETED' ? new Date(0) : null, publishedAt: new Date() });
    rows.listingPhoto.push({ listingId: status, storageKey: status + '.jpg' });
  }
  rows.listing.push({ id: 'B-listing', ownerId: B, status: 'APPROVED', deletedAt: null });
  rows.report.push({ listingOwnerId: A, comment: 'Evidence' });
  let failTable = '', externalFailure = false, committed = false;
  const externalCalls: string[] = [];
  function matches(row: any, where: any): boolean {
    if (!where) return true;
    return Object.entries(where).every(([key, value]: [string, any]) => {
      if (key === 'OR') return value.some((part: any) => matches(row, part));
      if (key === 'AND') return value.every((part: any) => matches(row, part));
      if (key === 'user') return matches(rows.user.find(u => u.id === row.userId), value);
      if (value && typeof value === 'object' && !(value instanceof Date)) {
        if ('not' in value) return row[key] !== value.not;
        if ('lte' in value) return row[key] <= value.lte;
        if ('gt' in value) return row[key] > value.gt;
        if ('in' in value) return value.in.includes(row[key]);
      }
      return row[key] === value;
    });
  }
  const prisma: any = {};
  for (const table of Object.keys(rows)) {
    const find = (args: any = {}) => rows[table].filter(row => matches(row, args.where));
    const check = () => { if (failTable === table) throw new Error('injected DB failure'); };
    prisma[table] = {
      findMany: async (args: any) => structuredClone(find(args)),
      findUnique: async (args: any) => structuredClone(find(args)[0] ?? null),
      findFirst: async (args: any) => { const row = find(args)[0]; return row ? structuredClone({ ...row, ...(table === 'userSession' ? { user: rows.user.find(u => u.id === row.userId) } : {}) }) : null; },
      create: async ({ data }: any) => { check(); const row = table === 'user' ? { ...user(data.id), ...data } : { ...data }; rows[table].push(row); return structuredClone(row); },
      createMany: async ({ data }: any) => { check(); rows[table].push(...structuredClone(data)); return { count: data.length }; },
      update: async ({ where, data }: any) => { check(); const row = find({ where })[0]; if (!row) throw new Error('missing'); Object.assign(row, data); return structuredClone(row); },
      updateMany: async ({ where, data }: any) => { check(); const selected = find({ where }); selected.forEach(row => Object.assign(row, data)); return { count: selected.length }; },
      deleteMany: async ({ where }: any) => { check(); const selected = find({ where }); rows[table] = rows[table].filter(row => !selected.includes(row)); return { count: selected.length }; },
    };
  }
  prisma.$transaction = async (fn: any) => { const before = structuredClone(rows); try { const result = await fn(prisma); committed = true; return result; } catch (error) { rows = before; throw error; } };
  const deletion = new AccountDeletionService(prisma, { deleteAccountAvatar: async (_: string, url: string) => {
    assert.equal(committed, true); externalCalls.push(url); if (externalFailure) throw new Error('S3 unavailable');
  } } as never, { del: async () => {} } as never);
  const jwt = new JwtService();
  const auth = new AuthService(prisma, jwt, {} as never, {
    ensureWalletAndBonuses: async (id: string) => { rows.wallet.push({ id: `new-${id}`, userId: id, balance: 0 }); },
    ensureWalletAndBonusesSafely: async () => {},
    accrueReferralInviterBonusIfNeeded: async () => { throw new Error('repeat referral must not pay'); },
  } as never, { getActiveBlock: async () => null } as never, deletion);
  return { prisma, deletion, auth, jwt, state: () => rows, externalCalls,
    fail: (table: string) => { failTable = table; }, failExternal: (value: boolean) => { externalFailure = value; } };
}

test('deletion invalidates both devices, purges private identifiers and leaves B isolated', async () => {
  const f = fixture(), otherUser = structuredClone(f.state().user[1]);
  const b = structuredClone(Object.fromEntries(Object.entries(f.state()).map(([k, rows]) => [k, rows.filter(r => r.userId === B)])));
  await f.deletion.deleteUser(A); const state = f.state();
  assert.equal(state.user[0].status, 'DELETED'); assert.equal(state.user[0].phone, null); assert.equal(state.user[0].passwordHash, '');
  for (const row of state.userSession.filter(s => s.userId === A)) { assert.ok(row.revokedAt); assert.equal(row.refreshTokenHash, ''); assert.equal(row.ip, null); assert.equal(row.userAgent, null); }
  for (const table of ['userDevice', 'restoreCredential', 'favorite', 'savedSearch', 'viewedListing', 'appDailyVisit', 'userNotification', 'userPresence']) assert.equal(state[table].filter(r => r.userId === A).length, 0, table);
  assert.equal(state.listingView[0].viewerUserId, null); assert.equal(state.listingView[0].viewerDeviceId, null); assert.equal(state.listingView[0].ip, null);
  for (const [table, rows] of Object.entries(b)) assert.deepEqual(state[table].filter(r => r.userId === B), rows, table);
  assert.deepEqual(state.user[1], otherUser);
});

test('old access and refresh tokens fail on both devices while B remains authenticated', async () => {
  const f = fixture(), guard = new JwtAuthGuard(f.jwt, f.prisma, {} as never);
  const token = async (id: string, device: number, type: string) => f.jwt.signAsync({ sub: id, sessionId: `${id}-${device}`, type }, { secret: type === 'access' ? env.JWT_ACCESS_SECRET : env.JWT_REFRESH_SECRET });
  const access = async (raw: string) => guard.canActivate({ switchToHttp: () => ({ getRequest: () => ({ headers: { authorization: `Bearer ${raw}` }, method: 'GET' }) }) } as never);
  for (const device of [1, 2]) assert.equal(await access(await token(A, device, 'access')), true);
  await f.deletion.deleteUser(A);
  for (const device of [1, 2]) {
    await assert.rejects(access(await token(A, device, 'access')), /session is not active/i);
    await assert.rejects(f.auth.refresh({ refreshToken: await token(A, device, 'refresh') }), /session is not active/i);
  }
  assert.equal(await access(await token(B, 1, 'access')), true);
});

test('every listing state leaves publication; paid promotions stop without damaging financial/audit history', async () => {
  const f = fixture(), tables = ['wallet', 'walletTransaction', 'payment', 'referral', 'auditLog', 'listingModerationRevision', 'listingPhoto'];
  const history = structuredClone(Object.fromEntries(tables.map(name => [name, f.state()[name]])));
  await f.deletion.deleteUser(A);
  for (const listing of f.state().listing.filter(row => row.ownerId === A)) {
    assert.equal(listing.status, 'DELETED'); assert.ok(listing.deletedAt); assert.equal(listing.phone, ''); assert.equal(listing.ownerEmail, null);
    assert.equal(listing.ownerName, 'Удалённый пользователь'); assert.equal(listing.latitude, null); assert.deepEqual(listing.locationJson, {});
  }
  assert.equal(f.state().listing.find(l => l.ownerId === B).status, 'APPROVED');
  assert.equal(f.state().promotion[0].status, 'CANCELLED'); assert.equal(f.state().listingRaiseCampaign[0].status, 'CANCELLED');
  for (const name of tables) assert.deepEqual(f.state()[name], history[name], name);
});

test('B keeps chat, messages, attachments, unread and reviews; A identity/private edges are removed', async () => {
  const f = fixture(), messages = structuredClone(f.state().chatMessage);
  await f.deletion.deleteUser(A); assert.deepEqual(f.state().chatMessage, messages);
  const chat = f.state().chat[0]; assert.ok(chat.deletedByBuyerAt); assert.equal(chat.deletedBySellerAt, null);
  assert.equal(chat.unreadForBuyer, 0); assert.equal(chat.unreadForSeller, 7); assert.equal(chat.lastMessage, 'Peer history');
  assert.equal(f.state().review[0].reviewerName, 'Удалённый пользователь'); assert.ok(f.state().review[0].deletedAt); assert.equal(f.state().review[1].deletedAt, null);
  assert.equal(f.state().supportTicket[0].name, 'Удалённый пользователь'); assert.equal(f.state().supportMessage[0].text, 'Evidence'); assert.equal(f.state().supportMessage[0].senderUserId, null);
  assert.deepEqual(f.state().userFollow, [{ followerId: B, sellerId: 'third' }]);
});

test('legacy deleted identity is masked in profile, chat and review serializers', () => {
  const legacy = { ...user(A), status: 'DELETED' }, profile = serializeUser(legacy as never, { includePrivate: true });
  const chats = new ChatsService({} as never, {} as never, {} as never, {} as never);
  const preview = (chats as any).participantPreview(legacy, { isOnline: true, lastSeen: 'private' });
  const reviews = new ReviewsService({} as never, {} as never);
  const review = (reviews as any).serializeReview({ id: 'review', sellerId: B, reviewerId: A, reviewerName: 'Leaked name', reviewer: legacy, seller: user(B), createdAt: new Date(), updatedAt: null, replyAt: null });
  assert.equal((profile as any).phone, null); assert.equal((profile as any).normalizedPhone, null); assert.equal((profile as any).email, null);
  assert.equal(profile.display_name, 'Удалённый пользователь'); assert.equal(profile.avatar_url, null);
  assert.equal(preview.displayName, 'Удалённый пользователь'); assert.equal(preview.avatarUrl, ''); assert.equal(preview.isOnline, false);
  assert.equal(review.reviewer_name, 'Удалённый пользователь'); assert.equal(review.author_preview.avatar_url, null);
});

test('late DB failure rolls back everything and never touches external resources', async () => {
  const f = fixture(), before = structuredClone(f.state()); f.fail('report');
  await assert.rejects(f.deletion.deleteUser(A), /injected DB failure/); assert.deepEqual(f.state(), before); assert.deepEqual(f.externalCalls, []);
});

test('external failure keeps account deleted; durable cleanup retry is idempotent', async () => {
  const f = fixture(); f.failExternal(true); assert.equal((await f.deletion.deleteUser(A)).deleted, true);
  assert.equal(f.state().user[0].status, 'DELETED'); assert.equal(f.state().accountDeletionCleanup.length, 1);
  const deletionTime = f.state().user[0].deletedAt; f.failExternal(false);
  await f.deletion.deleteUser(A); await f.deletion.cleanupUser(A);
  assert.deepEqual(f.state().user[0].deletedAt, deletionTime); assert.equal(f.state().accountDeletionCleanup.length, 0); assert.equal(f.externalCalls.length, 2);
});

test('worker refuses cleanup of an active account', async () => {
  const f = fixture(); f.state().accountDeletionCleanup.push({ userId: A, avatarUrls: ['url'], retryAt: new Date() });
  await f.deletion.retryCleanup(); assert.equal(f.state().user[0].status, 'ACTIVE'); assert.equal(f.externalCalls.length, 0); assert.equal(f.state().accountDeletionCleanup.length, 1);
});

test('same phone registration gets new UUID/session/wallet and cannot repeat referral reward', async () => {
  const f = fixture(); await f.deletion.deleteUser(A);
  f.state().phoneVerification.push({ id: 'new-verification', phone: '79281234567', purpose: 'SIGNUP', status: 'CONFIRMED', checkId: 'new-check', createdUserId: null, expiresAt: future() });
  const result = await f.auth.signupPhone({ phone: '79281234567', displayName: 'New user', password: 'secret123', acceptedLegal: true, acceptedPersonalData: true, verificationCheckId: 'new-check', referralCode: buildReferralCode(B) });
  assert.notEqual(result.user.id, A); assert.equal(f.state().user.find(u => u.id === A).status, 'DELETED');
  const session = f.state().userSession.find(s => s.userId === result.user.id); assert.ok(session); assert.notEqual(session.id, `${A}-1`);
  assert.equal(f.state().wallet.find(w => w.userId === result.user.id).balance, 0); assert.equal(f.state().wallet.find(w => w.userId === A).balance, 100);
  assert.equal(f.state().phoneVerification[0].phone, '79281234567'); assert.equal(f.state().referral.length, 1);
});

test('self-deletion protects admins; authorized admin path records the actor', async () => {
  const f = fixture(); f.state().user[0].adminProfile = { isAdmin: true }; const before = structuredClone(f.state());
  await assert.rejects(f.deletion.deleteUser(A), /admin-аккаунта/); assert.deepEqual(f.state(), before);
  await f.deletion.deleteUser(A, { actorUserId: B, reason: 'Удалено администратором' }); assert.equal(f.state().listing[0].moderatedBy, B);
});

test('deletion disconnects all A sockets and stale events cannot touch chats or presence', async () => {
  const f = fixture(), disconnected: string[] = []; let handlerCalls = 0;
  const gateway = new ChatsGateway({ touchHeartbeat: async () => { handlerCalls++; } } as never, { getChat: async () => { handlerCalls++; } } as never, f.jwt, f.prisma, f.deletion);
  gateway.server = { in: (room: string) => ({ disconnectSockets: () => disconnected.push(room) }), emit: () => {} } as never;
  gateway.onModuleInit(); await f.deletion.deleteUser(A); assert.deepEqual(disconnected, [`user:${A}`]);
  const token = await f.jwt.signAsync({ sub: A, sessionId: `${A}-2`, type: 'access' }, { secret: env.JWT_ACCESS_SECRET });
  const client = { handshake: { auth: { token }, headers: {} }, data: { userId: A }, disconnect: () => disconnected.push('stale') };
  await assert.rejects(gateway.handlePing(client as never), /session is not active/i);
  await assert.rejects(gateway.handleJoin({ chatId: 'chat' }, client as never), /session is not active/i); assert.equal(handlerCalls, 0); gateway.onModuleDestroy();
});

test('self and admin entry points use the shared lifecycle; protected admin checks remain', async () => {
  const { AdminService } = await import('../admin/admin.service');
  const f = fixture();
  await f.auth.deleteAccount({ userId: A, sessionId: `${A}-1`, role: 'user' });
  assert.equal(f.state().user[0].status, 'DELETED');
  const next = fixture();
  const admin = new AdminService(next.prisma, {} as never, {} as never, {} as never,
    {} as never, {} as never, undefined, next.deletion);
  const selfResult = await admin.deleteUser(B, { userId: B, sessionId: `${B}-1`, role: 'admin' });
  assert.equal(selfResult.deleted, false);
  assert.equal(next.state().user[1].status, 'ACTIVE');
  const result = await admin.deleteUser(A, { userId: B, sessionId: `${B}-1`, role: 'admin' });
  assert.equal(result.deleted, true); assert.equal(next.state().user[0].status, 'DELETED');
});

test('seller public API returns anonymized tombstone without private identity', async () => {
  const { UsersService } = await import('../users/users.service');
  const f = fixture(); await f.deletion.deleteUser(A);
  const users = new UsersService(f.prisma, {} as never, {} as never);
  const result = await users.getSellerPublicProfile(A);
  assert.equal(result.user.display_name, 'Удалённый пользователь');
  assert.equal(result.user.avatar_url, null); assert.equal(result.user.normalizedPhone, null);
});

test('admin optional saved-search alerts injection retains its concrete DI token', async () => {
  const { AdminService } = await import('../admin/admin.service');
  const { SavedSearchAlertsService } = await import('../saved-searches/saved-search-alerts.service');
  const explicit = Reflect.getMetadata('self:paramtypes', AdminService) as Array<{ index: number; param: unknown }>;
  assert.equal(explicit.find(p => p.index === 6)?.param, SavedSearchAlertsService);
});
