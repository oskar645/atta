import { Injectable } from '@nestjs/common';

import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';

type CursorPayload = {
  viewedAt: string;
  listingId: string;
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
export class ViewedListingsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(authUser: AuthenticatedUser, params?: { limit?: number; cursor?: string }) {
    const limit = pageLimit(params?.limit);
    const cursor = decodeCursor(params?.cursor);
    const cursorDate = cursor ? new Date(cursor.viewedAt) : null;
    const cursorListingId = cursor?.listingId ?? '';
    const items = await this.prisma.viewedListing.findMany({
      where: {
        userId: authUser.userId,
        ...(cursorDate && !Number.isNaN(cursorDate.getTime())
          ? {
              OR: [
                { viewedAt: { lt: cursorDate } },
                { viewedAt: cursorDate, listingId: { lt: cursorListingId } },
              ],
            }
          : {}),
      },
      orderBy: [{ viewedAt: 'desc' }, { listingId: 'desc' }],
      take: limit + 1,
    });
    const pageItems = items.slice(0, limit);
    const hasMore = items.length > limit;
    const last = hasMore ? pageItems[pageItems.length - 1] : null;

    return {
      source: 'timeweb',
      items: pageItems.map((item) => ({
        listing_id: item.listingId,
        viewed_at: item.viewedAt.toISOString(),
      })),
      nextCursor: last
        ? encodeCursor({
            viewedAt: last.viewedAt.toISOString(),
            listingId: last.listingId,
          })
        : null,
      hasMore,
      limit,
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
