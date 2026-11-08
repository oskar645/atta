import assert from 'node:assert/strict';
import test from 'node:test';

import { buildAndroidFcmMessage } from './fcm.service';

test('capable Android client receives data-only payload for native navigation', () => {
  const payload = buildAndroidFcmMessage({
    token: '  android-token  ',
    title: 'ATTA',
    body: 'Новое сообщение',
    notification: { id: 'notification-A', payload: { chatId: 'chat-A' } },
    recipientId: 'recipient-A',
    actionType: 'chat_message',
    supportsDataOnly: true,
  });

  assert.equal(payload.message.token, 'android-token');
  assert.equal(payload.message.android.priority, 'HIGH');
  assert.equal('notification' in payload.message, false);
  assert.equal('notification' in payload.message.android, false);
  assert.equal(payload.message.data.title, 'ATTA');
  assert.equal(payload.message.data.body, 'Новое сообщение');
  assert.equal(payload.message.data.recipientId, 'recipient-A');
  assert.deepEqual(JSON.parse(payload.message.data.notification), {
    id: 'notification-A',
    payload: { chatId: 'chat-A' },
  });
});

test('unknown Android client keeps legacy notification payload', () => {
  const payload = buildAndroidFcmMessage({
    token: 'legacy-token',
    title: 'ATTA',
    body: 'Новое сообщение',
    notification: { id: 'notification-B' },
    recipientId: 'recipient-B',
    actionType: 'chat_message',
  });

  assert.deepEqual(payload.message.notification, {
    title: 'ATTA',
    body: 'Новое сообщение',
  });
  assert.deepEqual(payload.message.android.notification, {
    channel_id: 'atta_messages',
    sound: 'default',
  });
});
