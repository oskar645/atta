import { test } from 'node:test';
import assert from 'node:assert/strict';
import { HttpException } from '@nestjs/common';

import { RateLimitService } from './rate-limit.service';

class FakeRedisRateLimitStore {
  counters = new Map<string, number>();
  ttls = new Map<string, number>();
  sets = new Map<string, Set<string>>();
  nx = new Set<string>();

  async incr(key: string) {
    const next = (this.counters.get(key) ?? 0) + 1;
    this.counters.set(key, next);
    return next;
  }

  async expire(key: string, ttlSeconds: number) {
    this.ttls.set(key, ttlSeconds);
    return 1;
  }

  async ttl(key: string) {
    return this.ttls.has(key) ? this.ttls.get(key) ?? -1 : -1;
  }

  async sadd(key: string, value: string) {
    const values = this.sets.get(key) ?? new Set<string>();
    const sizeBefore = values.size;
    values.add(value);
    this.sets.set(key, values);
    return values.size === sizeBefore ? 0 : 1;
  }

  async scard(key: string) {
    return this.sets.get(key)?.size ?? 0;
  }

  async setNxWithTtl(key: string) {
    if (this.nx.has(key)) {
      return null;
    }
    this.nx.add(key);
    return 'OK';
  }
}

test('Redis rate limit counters survive a new service instance', async () => {
  const redis = new FakeRedisRateLimitStore();
  const firstService = new RateLimitService(redis as never);
  const secondService = new RateLimitService(redis as never);

  await firstService.consumeOrThrow('auth:login:203.0.113.1', {
    limit: 2,
    windowMs: 60_000,
  });
  await secondService.consumeOrThrow('auth:login:203.0.113.1', {
    limit: 2,
    windowMs: 60_000,
  });

  await assert.rejects(
    () =>
      secondService.consumeOrThrow('auth:login:203.0.113.1', {
        limit: 2,
        windowMs: 60_000,
      }),
    (error: unknown) => {
      assert.ok(error instanceof HttpException);
      assert.equal(error.getStatus(), 429);
      return true;
    },
  );
});

test('Redis outage falls back to local counters without crashing', async () => {
  const redis = {
    incr: async () => {
      throw new Error('redis unavailable');
    },
  };
  const service = new RateLimitService(redis as never);

  await service.consumeOrThrow('reports:user-1', {
    limit: 1,
    windowMs: 60_000,
  });

  await assert.rejects(
    () =>
      service.consumeOrThrow('reports:user-1', {
        limit: 1,
        windowMs: 60_000,
      }),
    (error: unknown) => {
      assert.ok(error instanceof HttpException);
      assert.equal(error.getStatus(), 429);
      return true;
    },
  );
});

