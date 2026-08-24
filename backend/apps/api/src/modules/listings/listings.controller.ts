import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { OptionalJwtAuthGuard } from '../auth/optional-jwt-auth.guard';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { CreateListingDto } from './dto/create-listing.dto';
import { ArchiveListingDto } from './dto/archive-listing.dto';
import { UpdateListingDto } from './dto/update-listing.dto';
import { ListingsService } from './listings.service';

@Controller('listings')
export class ListingsController {
  constructor(
    private readonly listingsService: ListingsService,
    private readonly rateLimitService: RateLimitService,
  ) {}

  @UseGuards(JwtAuthGuard)
  @Post()
  async create(
    @Req() request: any,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: CreateListingDto,
  ) {
    await this.rateLimitService.consumeOrThrow(
      `listing:create:${authUser.userId}:${request?.ip?.toString() ?? 'unknown'}`,
      {
        limit: 20,
        windowMs: 60 * 60 * 1000,
      },
    );
    return this.listingsService.create(authUser, dto);
  }

  @Get()
  findAll(
    @Query('search') search?: string,
    @Query('category') category?: string,
    @Query('city') city?: string,
    @Query('minPrice') minPrice?: string,
    @Query('maxPrice') maxPrice?: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
    @Query('ownerId') ownerId?: string,
    @Query('status') status?: string,
  ) {
    return this.listingsService.findAll({
      search,
      category,
      city,
      ownerId,
      status,
      limit: limit == null ? undefined : Number(limit),
      cursor,
      minPrice: minPrice == null ? undefined : Number(minPrice),
      maxPrice: maxPrice == null ? undefined : Number(maxPrice),
    });
  }

  @Get('vip')
  findVip(
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
    @Query('category') category?: string,
  ) {
    return this.listingsService.findVipListings({
      limit: limit == null ? undefined : Number(limit),
      cursor,
      category,
    });
  }

  @UseGuards(JwtAuthGuard)
  @Get('my')
  findMy(
    @CurrentUser() authUser: AuthenticatedUser,
    @Query('status') status?: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.listingsService.findMy(authUser, {
      status,
      limit: limit == null ? undefined : Number(limit),
      cursor,
    });
  }

  @UseGuards(OptionalJwtAuthGuard)
  @Get(':id')
  findOne(
    @Param('id') id: string,
    @CurrentUser() authUser?: AuthenticatedUser,
  ) {
    return this.listingsService.findOne(id, authUser);
  }

  @UseGuards(JwtAuthGuard)
  @Patch(':id')
  update(
    @Param('id') id: string,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: UpdateListingDto,
  ) {
    return this.listingsService.update(id, authUser, dto);
  }

  @UseGuards(JwtAuthGuard)
  @Post(':id/archive')
  archive(
    @Param('id') id: string,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: ArchiveListingDto,
  ) {
    return this.listingsService.archive(id, authUser, dto);
  }

  @Post(':id/views')
  @UseGuards(OptionalJwtAuthGuard)
  incrementView(
    @Param('id') id: string,
    @CurrentUser() authUser?: AuthenticatedUser,
  ) {
    return this.listingsService.incrementView(id, authUser);
  }

  @Post(':id/view')
  @UseGuards(OptionalJwtAuthGuard)
  incrementViewAlias(
    @Param('id') id: string,
    @CurrentUser() authUser?: AuthenticatedUser,
  ) {
    return this.listingsService.incrementView(id, authUser);
  }

  @UseGuards(JwtAuthGuard)
  @Delete(':id')
  remove(
    @Param('id') id: string,
    @CurrentUser() authUser: AuthenticatedUser,
  ) {
    return this.listingsService.remove(id, authUser);
  }
}
