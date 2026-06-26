import { Controller, Get } from '@nestjs/common';

import { PrismaService } from './modules/prisma/prisma.service';
import { RedisService } from './modules/redis/redis.service';
import { StorageService } from './modules/storage/storage.service';

@Controller()
export class AppController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redisService: RedisService,
    private readonly storageService: StorageService,
  ) {}

  @Get('health')
  getHealth() {
    return { status: 'ok' };
  }

  @Get('health/dependencies')
  async getDependenciesHealth() {
    const [database, redis, storage] = await Promise.all([
      this.checkDatabaseHealth(),
      this.checkRedisHealth(),
      this.storageService.getHealthStatus(),
    ]);

    return {
      api: 'ok',
      database,
      redis,
      storage: storage.status,
      storage_message: storage.message ?? null,
    };
  }

  private async checkDatabaseHealth() {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
      return 'ok';
    } catch {
      return 'error';
    }
  }

  private async checkRedisHealth() {
    try {
      const result = await this.redisService.ping();
      return result === 'PONG' ? 'ok' : 'error';
    } catch {
      return 'error';
    }
  }
}
