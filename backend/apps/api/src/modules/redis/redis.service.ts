import { Injectable, OnModuleDestroy } from '@nestjs/common';
import Redis from 'ioredis';

import { env } from '../../config/env';

@Injectable()
export class RedisService implements OnModuleDestroy {
  private client: Redis | null = null;

  private getClient() {
    if (!this.client) {
      this.client = new Redis(env.REDIS_URL, {
        lazyConnect: true,
        maxRetriesPerRequest: 1,
      });
    }

    return this.client;
  }

  async ping() {
    const client = this.getClient();
    return client.ping();
  }

  async setWithTtl(key: string, value: string, ttlSeconds: number) {
    const client = this.getClient();
    await client.set(key, value, 'EX', ttlSeconds);

    return {
      ok: true,
      message: 'Redis TTL write completed',
      redisUrl: env.REDIS_URL,
    };
  }

  async del(key: string) {
    const client = this.getClient();
    await client.del(key);

    return {
      ok: true,
      message: 'Redis delete completed',
    };
  }

  async get(key: string) {
    const client = this.getClient();
    return client.get(key);
  }

  async incr(key: string) {
    const client = this.getClient();
    return client.incr(key);
  }

  async expire(key: string, ttlSeconds: number) {
    const client = this.getClient();
    return client.expire(key, ttlSeconds);
  }

  async ttl(key: string) {
    const client = this.getClient();
    return client.ttl(key);
  }

  async sadd(key: string, value: string) {
    const client = this.getClient();
    return client.sadd(key, value);
  }

  async scard(key: string) {
    const client = this.getClient();
    return client.scard(key);
  }

  async setNxWithTtl(key: string, value: string, ttlSeconds: number) {
    const client = this.getClient();
    return client.set(key, value, 'EX', ttlSeconds, 'NX');
  }

  async onModuleDestroy() {
    if (this.client) {
      await this.client.quit();
      this.client = null;
    }
  }
}
