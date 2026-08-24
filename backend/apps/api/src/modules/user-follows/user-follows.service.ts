import { Injectable } from '@nestjs/common';

import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';

type CursorPayload = {
  createdAt: string;
  sellerId: string;
};

const pageLimit = (value?: number) =>
  Math.max(1, Math.min(Number.isFinite(value ?? NaN) ? value! : 50, 100));

const encodeCursor = (payload: CursorPayload) =>
  Buffer.from(JSON.stringify(payload)).toString('base64url');

const decodeCursor = (cursor?: string): CursorPayload | null => {
  const raw = cursor?.trim();
  if (!raw) return null;
  try {
    const decoded = JSON.parse(Buffer.from(raw, 'base64url').toString('utf8'));
    return decoded && typeof decoded === 'object' ? decoded : null;
  } catch {
    return null;
  }
};

@Injectable()
export class UserFollowsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(authUser: AuthenticatedUser, params?: { limit?: number; cursor?: string }) {
    const limit = pageLimit(params?.limit);
    const cursor = decodeCursor(params?.cursor);
    const cursorDate = cursor ? new Date(cursor.createdAt) : null;
    const cursorSellerId = cursor?.sellerId ?? '';
    const items = await this.prisma.userFollow.findMany({
      where: {
        followerId: authUser.userId,
        ...(cursorDate && !Number.isNaN(cursorDate.getTime())
          ? {
              OR: [
                { createdAt: { lt: cursorDate } },
                { createdAt: cursorDate, sellerId: { lt: cursorSellerId } },
              ],
            }
          : {}),
      },
      orderBy: [{ createdAt: 'desc' }, { sellerId: 'desc' }],
      take: limit + 1,
    });
    const pageItems = items.slice(0, limit);
    const hasMore = items.length > limit;
    const last = hasMore ? pageItems[pageItems.length - 1] : null;

    return {
      source: 'timeweb',
      items: pageItems.map((item) => ({
        follower_id: item.followerId,
        seller_id: item.sellerId,
        created_at: item.createdAt.toISOString(),
      })),
      nextCursor: last
        ? encodeCursor({
            createdAt: last.createdAt.toISOString(),
            sellerId: last.sellerId,
          })
        : null,
      hasMore,
      limit,
    };
  }

  async follow(authUser: AuthenticatedUser, sellerId: string) {
    await this.prisma.userFollow.upsert({
      where: {
        followerId_sellerId: {
          followerId: authUser.userId,
          sellerId,
        },
      },
      update: {},
      create: {
        followerId: authUser.userId,
        sellerId,
      },
    });

    return {
      followed: true,
      seller_id: sellerId,
    };
  }

  async unfollow(authUser: AuthenticatedUser, sellerId: string) {
    await this.prisma.userFollow.deleteMany({
      where: {
        followerId: authUser.userId,
        sellerId,
      },
    });

    return {
      followed: false,
      seller_id: sellerId,
    };
  }

  async countFollowers(sellerId: string) {
    const count = await this.prisma.userFollow.count({
      where: {
        sellerId,
      },
    });

    return {
      source: 'timeweb',
      seller_id: sellerId,
      followers_count: count,
    };
  }
}
