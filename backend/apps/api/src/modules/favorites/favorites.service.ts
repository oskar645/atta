import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import { serializeFavorite } from '../../common/serializers';
import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class FavoritesService {
  constructor(private readonly prisma: PrismaService) {}

  async list(authUser: AuthenticatedUser) {
    const favorites = await this.prisma.favorite.findMany({
      where: {
        userId: authUser.userId,
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    return {
      items: favorites.map((favorite) => serializeFavorite(favorite)),
      favorite_ids: favorites.map((favorite) => favorite.listingId),
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
