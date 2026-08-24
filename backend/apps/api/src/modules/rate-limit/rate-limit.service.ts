import { HttpException, HttpStatus, Injectable, Logger } from '@nestjs/common';

import { RedisService } from '../redis/redis.service';

type Bucket = {
  count: number;
  resetAt: number;
};

@Injectable()
export class RateLimitService {
  private readonly logger = new Logger(RateLimitService.name);
  private readonly buckets = new Map<string, Bucket>();
  private lastRedisWarningAt = 0;

  constructor(private readonly redisService: RedisService) {}

  async consumeOrThrow(
    key: string,
    {
      limit,
      windowMs,
      message = 'Слишком много запросов. Попробуйте позже.',
    }: {
      limit: number;
      windowMs: number;
      message?: string;
    },
  ) {
    const redisCount = await this.consumeRedis(key, windowMs);
    if (redisCount != null) {
      if (redisCount > limit) {
        throw new HttpException(message, HttpStatus.TOO_MANY_REQUESTS);
      }
      return;
    }

    this.consumeMemoryOrThrow(key, { limit, windowMs, message });
  }

  async countUniqueValues(
    key: string,
    value: string,
    windowMs: number,
  ): Promise<number | null> {
    const ttlSeconds = this.toTtlSeconds(windowMs);
    try {
      await this.redisService.sadd(key, value);
      const ttl = await this.redisService.ttl(key);
      if (ttl < 0) {
        await this.redisService.expire(key, ttlSeconds);
      }
      return this.redisService.scard(key);
    } catch (error) {
      this.warnRedisFallback(error);
      return null;
    }
  }

  async debounce(key: string, windowMs: number): Promise<boolean> {
    try {
      const result = await this.redisService.setNxWithTtl(
        key,
        '1',
        this.toTtlSeconds(windowMs),
      );
      return result === 'OK';
    } catch (error) {
      this.warnRedisFallback(error);
      return true;
    }
  }

  private async consumeRedis(
    key: string,
    windowMs: number,
  ): Promise<number | null> {
    try {
      const count = await this.redisService.incr(key);
      if (count === 1) {
        await this.redisService.expire(key, this.toTtlSeconds(windowMs));
      }
      return count;
    } catch (error) {
      this.warnRedisFallback(error);
      return null;
    }
  }

  private consumeMemoryOrThrow(
    key: string,
    {
      limit,
      windowMs,
      message,
    }: {
      limit: number;
      windowMs: number;
      message: string;
    },
  ) {
    const now = Date.now();
    const current = this.buckets.get(key);
    if (!current || current.resetAt <= now) {
      this.buckets.set(key, {
        count: 1,
        resetAt: now + windowMs,
      });
      return;
    }

    if (current.count >= limit) {
      throw new HttpException(message, HttpStatus.TOO_MANY_REQUESTS);
    }

    current.count += 1;
    this.buckets.set(key, current);
  }

  private toTtlSeconds(windowMs: number) {
    return Math.max(1, Math.ceil(windowMs / 1000));
  }

  private warnRedisFallback(error: unknown) {
    const now = Date.now();
    if (now - this.lastRedisWarningAt < 30_000) {
      return;
    }
    this.lastRedisWarningAt = now;
    this.logger.warn(
      `Redis rate-limit storage unavailable; using local fallback where possible: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
  }
}
