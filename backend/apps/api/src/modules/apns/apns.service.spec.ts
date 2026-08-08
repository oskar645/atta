import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as http2 from 'http2';
import * as os from 'os';
import * as path from 'path';
import { EventEmitter } from 'events';

import { env } from '../../config/env';
import { ApnsService } from './apns.service';

const originalPrivateKeyPath = env.APNS_PRIVATE_KEY_PATH;
const originalConnect = http2.connect;

test.afterEach(() => {
  env.APNS_PRIVATE_KEY_PATH = originalPrivateKeyPath;
  setHttp2Connect(originalConnect);
});

test('missing apns.p8 skips push and logs one warning', async () => {
  const service = new ApnsService();
  const warnings: string[] = [];
  let connectCalled = false;
  env.APNS_PRIVATE_KEY_PATH = path.join(
    os.tmpdir(),
    `atta-missing-apns-${Date.now()}.p8`,
  );
  (service as unknown as { logger: { warn: (message: string) => void } }).logger = {
    warn: (message: string) => warnings.push(message),
  };
  setHttp2Connect((() => {
    connectCalled = true;
    throw new Error('connect should not be called without APNs key');
  }) as unknown as typeof http2.connect);

  const first = await service.send({
    token: 'ios-token',
    title: 'ATTA',
    body: 'Test',
  });
  const second = await service.send({
    token: 'ios-token',
    title: 'ATTA',
    body: 'Test',
  });

  assert.equal(first.sent, false);
  assert.equal(first.skipped, true);
  assert.equal(first.reason, 'apns_private_key_missing');
  assert.equal(second.skipped, true);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /private key file is missing/);
  assert.equal(connectCalled, false);
});

test('configured APNs sends push through http2 client', async () => {
  const { privateKey } = crypto.generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
  });
  const keyPath = path.join(os.tmpdir(), `atta-apns-${Date.now()}.p8`);
  fs.writeFileSync(
    keyPath,
    privateKey.export({ type: 'pkcs8', format: 'pem' }),
    'utf8',
  );
  env.APNS_PRIVATE_KEY_PATH = keyPath;

  let requestPath = '';
  let requestBody = '';
  setHttp2Connect((() => ({
    on: () => undefined,
    request: (headers: http2.OutgoingHttpHeaders) => {
      requestPath = `${headers[':path'] ?? ''}`;
      const request = new EventEmitter() as EventEmitter & {
        setEncoding: () => void;
        end: (body: string) => void;
      };
      request.setEncoding = () => undefined;
      request.end = (body: string) => {
        requestBody = body;
        request.emit('response', { ':status': 200 });
        request.emit('end');
      };
      return request;
    },
    close: () => undefined,
  })) as unknown as typeof http2.connect);

  const result = await new ApnsService().send({
    token: 'ios-token',
    title: 'ATTA',
    body: 'Работает',
    payload: { actionType: 'test' },
    badge: 3,
  });

  assert.equal(result.sent, true);
  assert.equal(result.status, 200);
  assert.equal(requestPath, '/3/device/ios-token');
  assert.equal(JSON.parse(requestBody).aps.badge, 3);
  assert.equal(JSON.parse(requestBody).actionType, 'test');
  fs.unlinkSync(keyPath);
});

function setHttp2Connect(connect: typeof http2.connect) {
  (require('http2') as { connect: typeof http2.connect }).connect = connect;
}
