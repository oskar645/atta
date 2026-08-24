import { Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ViewedListingsService } from './viewed-listings.service';

@Controller('viewed-listings')
@UseGuards(JwtAuthGuard)
export class ViewedListingsController {
  constructor(private readonly viewedListingsService: ViewedListingsService) {}

  @Get()
  list(
    @CurrentUser() authUser: AuthenticatedUser,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.viewedListingsService.list(authUser, {
      limit: limit == null ? undefined : Number(limit),
      cursor,
    });
  }

  @Post(':listingId')
  mark(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('listingId') listingId: string,
  ) {
    return this.viewedListingsService.mark(authUser, listingId);
  }
}
