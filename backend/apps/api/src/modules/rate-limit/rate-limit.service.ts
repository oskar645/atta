import { HttpException, HttpStatus, Injectable } from '@nestjs/common';

type Bucket = {
  count: number;
  resetAt: number;
};

@Injectable()
export class RateLimitService {
  private readonly buckets = new Map<string, Bucket>();

  consumeOrThrow(
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
}
