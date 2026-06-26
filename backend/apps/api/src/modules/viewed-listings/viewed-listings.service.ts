import { Injectable } from '@nestjs/common';

import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class ViewedListingsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(authUser: AuthenticatedUser) {
    const items = await this.prisma.viewedListing.findMany({
      where: {
        userId: authUser.userId,
      },
      orderBy: {
        viewedAt: 'desc',
      },
    });

    return {
      source: 'timeweb',
      items: items.map((item) => ({
        listing_id: item.listingId,
        viewed_at: item.viewedAt.toISOString(),
      })),
    };
  }

  async mark(authUser: AuthenticatedUser, listingId: string) {
    await this.prisma.viewedListing.upsert({
      where: {
        userId_listingId: {
          userId: authUser.userId,
          listingId,
        },
      },
      update: {
        viewedAt: new Date(),
      },
      create: {
        userId: authUser.userId,
        listingId,
      },
    });

    return {
      viewed: true,
      listing_id: listingId,
    };
  }
}
