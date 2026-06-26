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

  async onModuleDestroy() {
    if (this.client) {
      await this.client.quit();
      this.client = null;
    }
  }
}
