import { Injectable } from '@nestjs/common';

import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';

@Injectable()
export class PresenceService {
  private readonly ttlSeconds = 120;

  constructor(
    private readonly redisService: RedisService,
    private readonly prisma: PrismaService,
  ) {}

  private presenceKey(userId: string) {
    return `presence:user:${userId}`;
  }

  private isFresh(lastSeen: Date) {
    return lastSeen.getTime() >= Date.now() - this.ttlSeconds * 1000;
  }

  private async formatPresence(userId: string) {
    const record = await this.prisma.userPresence.findUnique({
      where: {
        userId,
      },
    });

    if (!record) {
      return {
        userId,
        isOnline: false,
        ttlSeconds: this.ttlSeconds,
        lastSeen: null,
      };
    }

    return {
      userId,
      isOnline: record.isOnline && this.isFresh(record.lastSeen),
      ttlSeconds: this.ttlSeconds,
      lastSeen: record.lastSeen.toISOString(),
    };
  }

  async setPresence(userId: string, isOnline: boolean) {
    const key = this.presenceKey(userId);
    const now = new Date();

    if (isOnline) {
      await this.redisService.setWithTtl(key, 'online', this.ttlSeconds);
      await this.prisma.userPresence.upsert({
        where: {
          userId,
        },
        update: {
          isOnline: true,
          lastSeen: now,
          socketId: null,
        },
        create: {
          userId,
          isOnline: true,
          lastSeen: now,
        },
      });
    } else {
      await this.redisService.del(key);
      await this.prisma.userPresence.upsert({
        where: {
          userId,
        },
        update: {
          isOnline: false,
          lastSeen: now,
        },
        create: {
          userId,
          isOnline: false,
          lastSeen: now,
        },
      });
    }

    return this.formatPresence(userId);
  }

  async touchSocket(userId: string, socketId: string) {
    const now = new Date();
    await this.redisService.setWithTtl(this.presenceKey(userId), socketId, this.ttlSeconds);
    await this.prisma.userPresence.upsert({
      where: {
        userId,
      },
      update: {
        isOnline: true,
        lastSeen: now,
        socketId,
      },
      create: {
        userId,
        isOnline: true,
        lastSeen: now,
        socketId,
      },
    });

    return this.formatPresence(userId);
  }

  async touchHeartbeat(userId: string) {
    const current = await this.prisma.userPresence.findUnique({
      where: {
        userId,
      },
    });

    return this.touchSocket(userId, current?.socketId ?? 'heartbeat');
  }

  async disconnectSocket(userId: string, socketId: string) {
    const current = await this.prisma.userPresence.findUnique({
      where: {
        userId,
      },
    });

    if (!current) {
      await this.redisService.del(this.presenceKey(userId));
      return {
        userId,
        isOnline: false,
        ttlSeconds: this.ttlSeconds,
        lastSeen: null,
      };
    }

    if (current.socketId && current.socketId != socketId) {
      return this.formatPresence(userId);
    }

    const now = new Date();
    await this.redisService.del(this.presenceKey(userId));
    await this.prisma.userPresence.update({
      where: {
        userId,
      },
      data: {
        isOnline: false,
        lastSeen: now,
        socketId: null,
      },
    });

    return this.formatPresence(userId);
  }

  async getPresence(userId: string) {
    return this.formatPresence(userId);
  }

  async getPresenceMap(userIds: string[]) {
    const uniqueIds = [...new Set(userIds.map((id) => id.trim()).filter(Boolean))];
    if (uniqueIds.length === 0) {
      return new Map<string, { isOnline: boolean; lastSeen: string | null }>();
    }

    const rows = await this.prisma.userPresence.findMany({
      where: {
        userId: {
          in: uniqueIds,
        },
      },
    });

    const map = new Map<string, { isOnline: boolean; lastSeen: string | null }>();
    for (const id of uniqueIds) {
      map.set(id, {
        isOnline: false,
        lastSeen: null,
      });
    }

    for (const row of rows) {
      map.set(row.userId, {
        isOnline: row.isOnline && this.isFresh(row.lastSeen),
        lastSeen: row.lastSeen.toISOString(),
      });
    }

    return map;
  }
}
