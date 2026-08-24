import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ChatsGateway } from './chats.gateway';

class FakeSocket {
  handshake = {
    auth: {} as Record<string, string>,
    headers: {} as Record<string, string>,
  };
  data: Record<string, unknown> = {};
  joinedRooms: string[] = [];
  emitted: Array<{ event: string; payload: Record<string, unknown> }> = [];
  disconnected = false;

  constructor(readonly id: string) {}

  join(room: string) {
    this.joinedRooms.push(room);
  }

  emit(event: string, payload: Record<string, unknown>) {
    this.emitted.push({ event, payload });
  }

  disconnect(close: boolean) {
    this.disconnected = close;
  }
}

function createGateway({
  token = 'access-token',
  jwtPayload = { sub: 'user-1', sessionId: 'session-1' },
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
