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
