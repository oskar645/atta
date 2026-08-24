import { test } from 'node:test';
import assert from 'node:assert/strict';

import { TRUSTED_PROXY_HOPS, configureTrustProxy } from './trust-proxy';

const proxyaddr = require('proxy-addr') as {
  compile: (value: string) => (addr: string, index: number) => boolean;
  (request: {
    socket: { remoteAddress?: string };
    headers: Record<string, string | undefined>;
  }, trust: (addr: string, index: number) => boolean): string;
};

function expressIpFor(params: {
  remoteAddress: string;
  forwardedFor?: string;
}) {
  const trust = proxyaddr.compile(TRUSTED_PROXY_HOPS);
  return proxyaddr(
    {
      socket: {
        remoteAddress: params.remoteAddress,
      },
      headers: {
        'x-forwarded-for': params.forwardedFor,
      },
    },
    trust,
  );
}

test('trust proxy is limited to loopback Nginx hop', () => {
  const settings = new Map<string, unknown>();

  configureTrustProxy({
    set: (setting, value) => {
      settings.set(setting, value);
    },
  });

  assert.equal(settings.get('trust proxy'), 'loopback');
});

test('request.ip resolves to client IP behind local Nginx', () => {
  assert.equal(
    expressIpFor({
      remoteAddress: '127.0.0.1',
      forwardedFor: '198.51.100.10',
    }),
    '198.51.100.10',
  );
  assert.equal(
    expressIpFor({
      remoteAddress: '::1',
      forwardedFor: '198.51.100.11',
    }),
    '198.51.100.11',
  );
});

test('spoofed external X-Forwarded-For before the Nginx hop is ignored', () => {
  assert.equal(
    expressIpFor({
      remoteAddress: '127.0.0.1',
      forwardedFor: '203.0.113.200, 198.51.100.10',
    }),
    '198.51.100.10',
  );
});

test('direct external requests cannot spoof request.ip with X-Forwarded-For', () => {
  assert.equal(
    expressIpFor({
      remoteAddress: '203.0.113.55',
      forwardedFor: '198.51.100.10',
    }),
    '203.0.113.55',
  );
});
