import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ChatsGateway } from './chats.gateway';

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
