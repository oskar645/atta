import type { AccountDeletionService } from '../auth/account-deletion.service';
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { AdminDashboardSignal } from '../../common/admin-dashboard-signal';
import { SupportRealtimeSignal } from '../../common/support-realtime-signal';
import { ChatsGateway } from './chats.gateway';

class FakeSocket {
  handshake = {
    auth: {} as Record<string, string>,
    headers: {} as Record<string, string>,
  };
  data: Record<string, unknown> = {};
  joinedRooms: string[] = [];
  rooms = new Set<string>();
  emitted: Array<{ event: string; payload: Record<string, unknown> }> = [];
  disconnected = false;

  constructor(readonly id: string) {}

  join(room: string) {
    this.joinedRooms.push(room);
    this.rooms.add(room);
  }

  leave(room: string) {
    this.rooms.delete(room);
  }

  emit(event: string, payload: Record<string, unknown>) {
    this.emitted.push({ event, payload });
  }

  disconnect(close: boolean) {
    this.disconnected = close;
  }
}

test('admin dashboard realtime is emitted only to reauthorized admins', async () => {
  const signal = new AdminDashboardSignal();
  const gateway = new ChatsGateway(
    {} as never,
    {} as never,
    {
      async verifyAsync(token: string) {
        const userId = token === 'admin-token' ? 'admin-1' : 'user-1';
        return { sub: userId, sessionId: `session-${userId}`, type: 'access' };
      },
    } as never,
    {
      userSession: {
        async findFirst({ where }: { where: { userId: string } }) {
          return {
            userId: where.userId,
            expiresAt: new Date(Date.now() + 60_000),
          };
        },
      },
      user: {
        async findUnique({ where }: { where: { id: string } }) {
          return {
            phone: null,
            adminProfile: where.id === 'admin-1' ? { isAdmin: true } : null,
          };
        },
      },
    } as never,
    { onDeleted: () => () => false } as never,
    undefined,
    signal,
  );
  const admin = new FakeSocket('admin-socket');
  admin.handshake.auth['token'] = 'admin-token';
  admin.join('admin:analytics');
  const regular = new FakeSocket('user-socket');
  regular.handshake.auth['token'] = 'user-token';
  regular.join('admin:analytics');
  gateway.server = {
    sockets: { sockets: new Map([[admin.id, admin], [regular.id, regular]]) },
    in() { return { disconnectSockets() {} }; },
    emit() {},
  } as never;

  gateway.onModuleInit();
  signal.changed('users', 'listings');
  signal.flush();
  await new Promise((resolve) => setImmediate(resolve));

  assert.deepEqual(
    admin.emitted.find((item) => item.event === 'admin.dashboard.changed')?.payload,
    { scopes: ['users', 'listings'] },
  );
  assert.equal(
    regular.emitted.some((item) => item.event === 'admin.dashboard.changed'),
    false,
  );
  assert.equal(regular.rooms.has('admin:analytics'), false);
  gateway.onModuleDestroy();
  signal.onModuleDestroy();
});

test('support realtime removes an admin whose rights were revoked after joining', async () => {
  const supportSignal = new SupportRealtimeSignal();
  let isAdmin = true;
  const gateway = new ChatsGateway(
    {} as never,
    {} as never,
    { verifyAsync: async () => ({ sub: 'admin-1', sessionId: 'session-1', type: 'access' }) } as never,
    {
      userSession: { findFirst: async () => ({ userId: 'admin-1', expiresAt: new Date(Date.now() + 60_000) }) },
      user: { findUnique: async () => ({ phone: null, adminProfile: isAdmin ? { isAdmin: true } : null }) },
    } as never,
    { onDeleted: () => () => false } as never,
    undefined,
    undefined,
    supportSignal,
  );
  const socket = new FakeSocket('admin-socket');
  socket.handshake.auth['token'] = 'admin-token';
  socket.join('admin:analytics');
  gateway.server = {
    sockets: { sockets: new Map([[socket.id, socket]]) },
    in() { return { disconnectSockets() {} }; },
    emit() {},
  } as never;
  gateway.onModuleInit();

  isAdmin = false;
  supportSignal.changed({
    ticketId: 'ticket-1',
    userId: null,
    messageId: 'message-1',
    action: 'created',
  });
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(socket.emitted.some((item) => item.event === 'support.changed'), false);
  assert.equal(socket.rooms.has('admin:analytics'), false);
  gateway.onModuleDestroy();
  supportSignal.onModuleDestroy();
});

function createGateway({
  token = 'access-token',
  jwtPayload = { sub: 'user-1', sessionId: 'session-1', type: 'access' },
  session = {
    userId: 'user-1',
    expiresAt: new Date(Date.now() + 60_000),
  },
  presenceError,
}: {
  token?: string;
  jwtPayload?: Record<string, string>;
  session?: { userId: string; expiresAt: Date } | null;
  presenceError?: Error;
} = {}) {
  const logs: Array<{ level: string; message: string }> = [];
  const gateway = new ChatsGateway(
    {
      async touchSocket(userId: string) {
        if (presenceError) throw presenceError;
        return {
          userId,
          isOnline: true,
          lastSeen: new Date().toISOString(),
          changed: true,
        };
      },
    } as never,
    {} as never,
    {
      async verifyAsync(receivedToken: string) {
        assert.equal(receivedToken, token);
        return jwtPayload;
      },
    } as never,
    {
      userSession: {
        async findFirst() {
          return session;
        },
      },
    } as never,
    { onDeleted: () => () => false } satisfies Pick<AccountDeletionService, 'onDeleted'> as unknown as AccountDeletionService,
  );

  gateway.server = {
    emit() {},
    to() {
      return {
        emit() {},
      };
    },
  } as never;
  (gateway as unknown as { logger: { log: Function; warn: Function } }).logger =
    {
      log(message: string) {
        logs.push({ level: 'log', message });
      },
      warn(message: string) {
        logs.push({ level: 'warn', message });
      },
    };

  const client = new FakeSocket('socket-1');
  client.handshake.auth['token'] = token;
  return { gateway, client, logs };
}

test('handleConnection rejects missing auth with stage log and disconnects', async () => {
  const { gateway, client, logs } = createGateway();
  client.handshake.auth = {};

  await gateway.handleConnection(client as never);

  assert.equal(client.disconnected, true);
  assert.equal(client.joinedRooms.length, 0);
  assert.ok(
    logs.some(
      (entry) =>
        entry.level === 'warn' &&
        entry.message.includes('stage=auth') &&
        entry.message.includes('Access token is missing'),
    ),
  );
});

test('handleConnection rejects inactive session with stage=session', async () => {
  const { gateway, client, logs } = createGateway({ session: null });

  await gateway.handleConnection(client as never);

  assert.equal(client.disconnected, true);
  assert.ok(
    logs.some(
      (entry) =>
        entry.level === 'warn' &&
        entry.message.includes('stage=session') &&
        entry.message.includes('Session is not active'),
    ),
  );
});

test('handleConnection keeps authorized socket when presence touch fails', async () => {
  const { gateway, client, logs } = createGateway({
    presenceError: new Error('Redis unavailable'),
  });

  await gateway.handleConnection(client as never);

  assert.equal(client.disconnected, false);
  assert.deepEqual(client.joinedRooms, ['user:user-1']);
  assert.equal(client.data.userId, 'user-1');
  assert.equal(client.data.sessionId, 'session-1');
  assert.ok(
    logs.some(
      (entry) =>
        entry.level === 'warn' &&
        entry.message.includes('stage=presence') &&
        entry.message.includes('Redis unavailable') &&
        entry.message.includes('user=user-1') &&
        entry.message.includes('session=session-1'),
    ),
  );
});

test('handleConnection successful path remains connected', async () => {
  const { gateway, client, logs } = createGateway();

  await gateway.handleConnection(client as never);

  assert.equal(client.disconnected, false);
  assert.deepEqual(client.joinedRooms, ['user:user-1']);
  assert.ok(
    logs.some(
      (entry) =>
        entry.level === 'log' &&
        entry.message.includes('Socket connected: socket-1 user=user-1'),
    ),
  );
});

test('emitOutgoingMessage keeps personalized chat payload out of shared room event', () => {
  const emissions: Array<{
    room: string;
    event: string;
    payload: Record<string, unknown>;
  }> = [];

  const gateway = new ChatsGateway(
    {} as never,
    {} as never,
    {} as never,
    {} as never,
    { onDeleted: () => () => false } satisfies Pick<AccountDeletionService, 'onDeleted'> as unknown as AccountDeletionService,
  );

  gateway.server = {
    to(room: string) {
      return {
        emit(event: string, payload: Record<string, unknown>) {
          emissions.push({ room, event, payload });
        },
      };
    },
    emit() {},
  } as never;

  gateway.emitOutgoingMessage(
    {
      id: 'chat-1',
      unreadCount: 0,
    },
    {
      id: 'chat-1',
      unreadCount: 1,
    },
    {
      id: 'message-1',
      chatId: 'chat-1',
      senderId: 'seller-1',
    },
    'buyer-1',
  );

  const roomMessage = emissions.find(
    (item) => item.room == 'chat:chat-1' && item.event == 'message.new',
  );
  assert.ok(roomMessage);
  assert.deepEqual(roomMessage.payload, {
    message: {
      id: 'message-1',
      chatId: 'chat-1',
      senderId: 'seller-1',
    },
  });
});

test('emitOutgoingMessage sends personalized unread counts per user', () => {
  const emissions: Array<{
    room: string;
    event: string;
    payload: Record<string, unknown>;
  }> = [];

  const gateway = new ChatsGateway(
    {} as never,
    {} as never,
    {} as never,
    {} as never,
    { onDeleted: () => () => false } satisfies Pick<AccountDeletionService, 'onDeleted'> as unknown as AccountDeletionService,
  );

  gateway.server = {
    to(room: string) {
      return {
        emit(event: string, payload: Record<string, unknown>) {
          emissions.push({ room, event, payload });
        },
      };
    },
    emit() {},
  } as never;

  gateway.emitOutgoingMessage(
    {
      id: 'chat-1',
      unreadCount: 0,
    },
    {
      id: 'chat-1',
      unreadCount: 1,
    },
    {
      id: 'message-1',
      chatId: 'chat-1',
      senderId: 'seller-1',
    },
    'buyer-1',
  );

  const senderChatUpdated = emissions.find(
    (item) => item.room == 'user:seller-1' && item.event == 'chat.updated',
  );
  const recipientChatUpdated = emissions.find(
    (item) => item.room == 'user:buyer-1' && item.event == 'chat.updated',
  );

  assert.equal(
    (senderChatUpdated?.payload['chat'] as Record<string, unknown>)
      ?.['unreadCount'],
    0,
  );
  assert.equal(
    (recipientChatUpdated?.payload['chat'] as Record<string, unknown>)
      ?.['unreadCount'],
    1,
  );
});

test('emitOutgoingMessage forwards absolute unread total to recipient', () => {
  const emissions: Array<{
    room: string;
    event: string;
    payload: Record<string, unknown>;
  }> = [];

  const gateway = new ChatsGateway(
    {} as never,
    {} as never,
    {} as never,
    {} as never,
    { onDeleted: () => () => false } satisfies Pick<AccountDeletionService, 'onDeleted'> as unknown as AccountDeletionService,
  );

  gateway.server = {
    to(room: string) {
      return {
        emit(event: string, payload: Record<string, unknown>) {
          emissions.push({ room, event, payload });
        },
      };
    },
    emit() {},
  } as never;

  gateway.emitOutgoingMessage(
    {
      id: 'chat-1',
      unreadCount: 0,
    },
    {
      id: 'chat-1',
      unreadCount: 2,
    },
    {
      id: 'message-1',
      chatId: 'chat-1',
      senderId: 'seller-1',
    },
    'buyer-1',
    undefined,
    7,
  );

  const recipientMessage = emissions.find(
    (item) => item.room == 'user:buyer-1' && item.event == 'message.new',
  );
  const unreadChanged = emissions.find(
    (item) => item.room == 'user:buyer-1' && item.event == 'unread.changed',
  );

  assert.equal(recipientMessage?.payload['unreadTotal'], 7);
  assert.equal(unreadChanged?.payload['unreadTotal'], 7);
  const recipientChatUpdated = emissions.find(
    (item) => item.room == 'user:buyer-1' && item.event == 'chat.updated',
  );
  assert.equal(recipientChatUpdated?.payload['unreadTotal'], 7);
});

test('emitNotificationNew sends global notification to all sockets', () => {
  const emissions: Array<{
    room: string;
    event: string;
    payload: Record<string, unknown>;
  }> = [];
  const broadcasts: Array<{
    event: string;
    payload: Record<string, unknown>;
  }> = [];

  const gateway = new ChatsGateway(
    {} as never,
    {} as never,
    {} as never,
    {} as never,
    { onDeleted: () => () => false } satisfies Pick<AccountDeletionService, 'onDeleted'> as unknown as AccountDeletionService,
  );

  gateway.server = {
    to(room: string) {
      return {
        emit(event: string, payload: Record<string, unknown>) {
          emissions.push({ room, event, payload });
        },
      };
    },
    emit(event: string, payload: Record<string, unknown>) {
      broadcasts.push({ event, payload });
    },
  } as never;

  gateway.emitNotificationNew({
    id: 'global-1',
    scope: 'global',
    type: 'generic',
  });

  assert.equal(emissions.length, 0);
  assert.deepEqual(broadcasts, [
    {
      event: 'notification.new',
      payload: {
        notification: {
          id: 'global-1',
          scope: 'global',
          type: 'generic',
        },
      },
    },
  ]);
});

test('emitPresenceChanged skips unchanged heartbeat updates', () => {
  const emissions: Array<{
    room: string;
    event: string;
    payload: Record<string, unknown>;
  }> = [];
  const broadcasts: Array<{
    event: string;
    payload: Record<string, unknown>;
  }> = [];

  const gateway = new ChatsGateway(
    {} as never,
    {} as never,
    {} as never,
    {} as never,
    { onDeleted: () => () => false } satisfies Pick<AccountDeletionService, 'onDeleted'> as unknown as AccountDeletionService,
  );

  gateway.server = {
    to(room: string) {
      return {
        emit(event: string, payload: Record<string, unknown>) {
          emissions.push({ room, event, payload });
        },
      };
    },
    emit(event: string, payload: Record<string, unknown>) {
      broadcasts.push({ event, payload });
    },
  } as never;

  gateway.emitPresenceChanged({
    userId: 'user-1',
    isOnline: true,
    changed: false,
  });

  assert.equal(emissions.length, 0);
  assert.equal(broadcasts.length, 0);
});

test('emitPresenceChanged can force unchanged presence broadcasts', () => {
  const broadcasts: Array<{
    event: string;
    payload: Record<string, unknown>;
  }> = [];

  const gateway = new ChatsGateway(
    {} as never,
    {} as never,
    {} as never,
    {} as never,
    { onDeleted: () => () => false } satisfies Pick<AccountDeletionService, 'onDeleted'> as unknown as AccountDeletionService,
  );

  gateway.server = {
    to() {
      return {
        emit() {},
      };
    },
    emit(event: string, payload: Record<string, unknown>) {
      broadcasts.push({ event, payload });
    },
  } as never;

  gateway.emitPresenceChanged(
    {
      userId: 'user-1',
      isOnline: true,
      changed: false,
    },
    { force: true },
  );

  assert.deepEqual(broadcasts, [
    {
      event: 'presence.changed',
      payload: {
        userId: 'user-1',
        isOnline: true,
      },
    },
    {
      event: 'user.presence.changed',
      payload: {
        userId: 'user-1',
        isOnline: true,
      },
    },
  ]);
});

test('emitPresenceChanged sends one presence.changed broadcast per change', () => {
  const emissions: Array<{
    room: string;
    event: string;
    payload: Record<string, unknown>;
  }> = [];
  const broadcasts: Array<{
    event: string;
    payload: Record<string, unknown>;
  }> = [];

  const gateway = new ChatsGateway(
    {} as never,
    {} as never,
    {} as never,
    {} as never,
    { onDeleted: () => () => false } satisfies Pick<AccountDeletionService, 'onDeleted'> as unknown as AccountDeletionService,
  );

  gateway.server = {
    to(room: string) {
      return {
        emit(event: string, payload: Record<string, unknown>) {
          emissions.push({ room, event, payload });
        },
      };
    },
    emit(event: string, payload: Record<string, unknown>) {
      broadcasts.push({ event, payload });
    },
  } as never;

  gateway.emitPresenceChanged({
    userId: 'user-1',
    isOnline: true,
    changed: true,
  });

  assert.equal(emissions.length, 0);
  assert.deepEqual(broadcasts, [
    {
      event: 'presence.changed',
      payload: {
        userId: 'user-1',
        isOnline: true,
      },
    },
    {
      event: 'user.presence.changed',
      payload: {
        userId: 'user-1',
        isOnline: true,
      },
    },
  ]);
});
