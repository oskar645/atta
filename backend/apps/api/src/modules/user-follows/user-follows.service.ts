import { Injectable } from '@nestjs/common';

import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UserFollowsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(authUser: AuthenticatedUser) {
    const items = await this.prisma.userFollow.findMany({
      where: {
        followerId: authUser.userId,
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    return {
      source: 'timeweb',
      items: items.map((item) => ({
        follower_id: item.followerId,
        seller_id: item.sellerId,
        created_at: item.createdAt.toISOString(),
      })),
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
