import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ChatsController, MessagesController } from './chats.controller';

test('mark-as-read returns and emits the identical absolute unread total', async () => {
  const emissions: Array<Record<string, unknown>> = [];
  let badgeUserId = '';
  const result = {
    chat: { id: 'chat-1', unreadCount: 0 },
    unreadTotal: 4,
    messageIds: ['message-1'],
    readAt: new Date().toISOString(),
    senderIds: ['seller-1'],
  };
  const controller = new ChatsController(
    { markChatRead: async () => result } as never,
    {
      emitChatRead: () => undefined,
      emitUnreadChanged: (_userId: string, _chat: unknown, unreadTotal: number) => {
        emissions.push({ unreadTotal });
      },
    } as never,
    {} as never,
    { sendBadgeUpdate: async (userId: string) => { badgeUserId = userId; } } as never,
  );

  const response = await controller.markChatRead(
    { userId: 'buyer-1', role: 'user' } as never,
    'chat-1',
  );

  assert.equal(response.unreadTotal, 4);
  assert.deepEqual(emissions, [{ unreadTotal: 4 }]);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(badgeUserId, 'buyer-1');
});

test('idempotent delivered ACK publishes its socket event only for the winning update', async () => {
  let calls = 0;
  let events = 0;
  const controller = new MessagesController(
    { markMessageDelivered: async () => ({ message: { id: 'message-1' }, published: calls++ === 0 }) } as never,
    { emitDelivered: () => { events += 1; } } as never,
  );
  const auth = { userId: 'buyer-1', role: 'user' } as never;

  await controller.markDelivered(auth, 'message-1');
  await controller.markDelivered(auth, 'message-1');

  assert.equal(events, 1);
});
