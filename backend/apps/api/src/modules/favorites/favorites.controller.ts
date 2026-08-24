import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { FavoriteListingDto } from './dto/favorite-listing.dto';
import { FavoritesService } from './favorites.service';

@UseGuards(JwtAuthGuard)
@Controller('favorites')
export class FavoritesController {
  constructor(private readonly favoritesService: FavoritesService) {}

  @Get()
  list(
    @CurrentUser() authUser: AuthenticatedUser,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.favoritesService.list(authUser, {
      limit: limit == null ? undefined : Number(limit),
      cursor,
    });
  }

  @Post()
  add(
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: FavoriteListingDto,
  ) {
    return this.favoritesService.add(authUser, dto.listing_id);
  }

  @Post(':listingId')
  addByPath(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('listingId') listingId: string,
  ) {
    return this.favoritesService.add(authUser, listingId);
  }

  @Delete(':listingId')
  remove(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('listingId') listingId: string,
  ) {
    return this.favoritesService.remove(authUser, listingId);
  }
}
