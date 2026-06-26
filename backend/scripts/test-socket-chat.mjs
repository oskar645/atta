#!/usr/bin/env node

import { io } from 'socket.io-client';

const baseUrl = process.env.SOCKET_BASE_URL || process.env.BACKEND_URL || 'http://5.42.125.179';
const tokenA = process.env.ACCESS_TOKEN_A || process.argv[2] || '';
const tokenB = process.env.ACCESS_TOKEN_B || process.argv[3] || '';
const chatId = process.env.CHAT_ID || process.argv[4] || '';
const messageText = process.env.MESSAGE_TEXT || 'ATTA socket live test';
const timeoutMs = Number(process.env.SOCKET_TEST_TIMEOUT_MS || '20000');

if (!tokenA || !tokenB || !chatId) {
  console.error(
    'Usage: ACCESS_TOKEN_A=... ACCESS_TOKEN_B=... CHAT_ID=... node scripts/test-socket-chat.mjs',
  );
  process.exit(1);
}

const expected = {
  messageNewOnB: false,
  deliveredOnA: false,
  readOnA: false,
};

let sentMessageId = '';
let done = false;

function log(message, extra) {
  if (extra === undefined) {
    console.log(`[socket-test] ${message}`);
    return;
  }
  console.log(`[socket-test] ${message}`, extra);
}

function createClient(name, token) {
  const socket = io(baseUrl, {
    transports: ['websocket'],
    auth: {
      token,
    },
    reconnection: false,
    timeout: timeoutMs,
  });

  socket.on('connect', () => {
    log(`${name} connected: true`);
    socket.emit('chat.join', { chatId });
  });

  socket.on('disconnect', (reason) => {
    log(`${name} disconnected: ${reason}`);
  });

  socket.on('connect_error', (error) => {
    log(`${name} connect_error: ${error.message}`);
  });

  socket.on('error', (payload) => {
    log(`${name} socket error`, payload);
  });

  return socket;
}

const clientA = createClient('A', tokenA);
const clientB = createClient('B', tokenB);

function cleanup(code) {
  if (done) return;
  done = true;
  clientA.disconnect();
  clientB.disconnect();
  clearTimeout(timeoutHandle);
  process.exit(code);
}

function maybeFinish() {
  if (
    expected.messageNewOnB &&
    expected.deliveredOnA &&
    expected.readOnA
  ) {
    log('Socket chat flow verified successfully.');
    cleanup(0);
  }
}

clientA.on('message.sent', (payload) => {
  const message = payload?.message ?? {};
  sentMessageId = String(message.id || '');
  log('A received message.sent', {
    chatId: payload?.chat?.id,
    messageId: sentMessageId,
    status: message.status,
  });
});

clientA.on('message.delivered', (payload) => {
  const message = payload?.message ?? {};
  if (String(message.id || '') != sentMessageId) return;
  expected.deliveredOnA = true;
  log('A received message.delivered', {
    messageId: sentMessageId,
    status: message.status,
  });
  maybeFinish();
});

clientA.on('message.read', (payload) => {
  const message = payload?.message ?? {};
  if (String(message.id || '') != sentMessageId) return;
  expected.readOnA = true;
  log('A received message.read', {
    messageId: sentMessageId,
    status: message.status,
  });
  maybeFinish();
});

clientB.on('message.new', (payload) => {
  const message = payload?.message ?? {};
  if (String(message.id || '') != sentMessageId) return;
  expected.messageNewOnB = true;
  log('B received message.new', {
    messageId: sentMessageId,
    status: message.status,
  });
  clientB.emit('message.delivered', { messageId: sentMessageId });
  setTimeout(() => {
    clientB.emit('message.read', { messageId: sentMessageId });
  }, 250);
  maybeFinish();
});

let connectedCount = 0;
function onReady() {
  connectedCount += 1;
  if (connectedCount < 2) return;
  setTimeout(() => {
    log('A sending test message');
    clientA.emit('message.send', {
      chatId,
      text: messageText,
    });
  }, 400);
}

clientA.on('connect', onReady);
clientB.on('connect', onReady);

const timeoutHandle = setTimeout(() => {
  log('Timed out waiting for socket events', expected);
  cleanup(2);
}, timeoutMs);
