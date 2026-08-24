import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import { serializeFavorite } from '../../common/serializers';
import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';

type CursorPayload = {
  createdAt: string;
  id: string;
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
export class FavoritesService {
  constructor(private readonly prisma: PrismaService) {}

  async list(authUser: AuthenticatedUser, params?: { limit?: number; cursor?: string }) {
    const limit = pageLimit(params?.limit);
    const cursor = decodeCursor(params?.cursor);
    const cursorDate = cursor ? new Date(cursor.createdAt) : null;
    const cursorId = cursor?.id ?? '';
    const favorites = await this.prisma.favorite.findMany({
      where: {
        userId: authUser.userId,
        ...(cursorDate && !Number.isNaN(cursorDate.getTime())
          ? {
              OR: [
                { createdAt: { lt: cursorDate } },
                { createdAt: cursorDate, id: { lt: cursorId } },
              ],
            }
          : {}),
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const pageItems = favorites.slice(0, limit);
    const hasMore = favorites.length > limit;
    const last = hasMore ? pageItems[pageItems.length - 1] : null;

    return {
      items: pageItems.map((favorite) => serializeFavorite(favorite)),
      favorite_ids: pageItems.map((favorite) => favorite.listingId),
      nextCursor: last
        ? encodeCursor({
            createdAt: last.createdAt.toISOString(),
            id: last.id,
          })
        : null,
      hasMore,
      limit,
    };
  }

  async add(authUser: AuthenticatedUser, listingId: string) {
    const listing = await this.prisma.listing.findUnique({
      where: {
        id: listingId,
      },
      select: {
        id: true,
      },
    });

    if (!listing) {
      throw new NotFoundException('Listing not found');
    }

    const existingFavorite = await this.prisma.favorite.findFirst({
      where: {
        userId: authUser.userId,
        listingId,
      },
    });

    if (existingFavorite) {
      throw new ConflictException('Listing is already favorite');
    }

    const favorite = await this.prisma.favorite.create({
      data: {
        userId: authUser.userId,
        listingId,
      },
    });

    return {
      item: serializeFavorite(favorite),
    };
  }

  async remove(authUser: AuthenticatedUser, listingId: string) {
    const favorite = await this.prisma.favorite.findFirst({
      where: {
        userId: authUser.userId,
        listingId,
      },
    });

    if (!favorite) {
      throw new NotFoundException('Favorite not found');
    }

    await this.prisma.favorite.delete({
      where: {
        id: favorite.id,
      },
    });

    return {
      deleted: true,
      listing_id: listingId,
    };
  }
}
