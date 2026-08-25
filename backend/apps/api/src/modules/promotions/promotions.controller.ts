import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { CreatePromotionDto } from './dto/create-promotion.dto';
import { PromotionsService } from './promotions.service';

@Controller()
export class PromotionsController {
  constructor(
    private readonly promotionsService: PromotionsService,
    private readonly rateLimitService: RateLimitService,
  ) {}

  @Get('promotions/plans')
  getPlans() {
    return this.promotionsService.getPlans();
  }

  @Get('promotions/showcase')
  getShowcaseByPromotionsRoute(
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
    @Query('category') category?: string,
    @Query('search') search?: string,
  ) {
    return this.promotionsService.getShowcase({
      limit: limit == null ? undefined : Number(limit),
      cursor,
      category,
      search,
    });
  }

  @Get('showcase')
  getShowcase(
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
    @Query('category') category?: string,
    @Query('search') search?: string,
  ) {
    return this.promotionsService.getShowcase({
      limit: limit == null ? undefined : Number(limit),
      cursor,
      category,
      search,
    });
  }

  @Post('showcase/:promotionId/impression')
  registerImpression(@Req() request: any, @Param('promotionId') promotionId: string) {
    return this.promotionsService.registerImpression(
      promotionId,
      this.counterSource(request),
    );
  }

  @Post('showcase/:promotionId/click')
  registerClick(@Req() request: any, @Param('promotionId') promotionId: string) {
    return this.promotionsService.registerClick(
      promotionId,
      this.counterSource(request),
    );
  }

  private counterSource(request: any) {
    const forwarded = `${request?.headers?.['x-forwarded-for'] ?? ''}`.trim();
    return {
      ip:
        `${request?.ip ?? ''}`.trim() ||
        forwarded.split(',')[0]?.trim() ||
        'unknown',
      userAgent: `${request?.headers?.['user-agent'] ?? ''}`.trim(),
    };
  }

  @UseGuards(JwtAuthGuard)
  @Post('listings/:id/promotions')
  async promoteListing(
    @Req() request: any,
    @Param('id') listingId: string,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: CreatePromotionDto,
  ) {
    await this.rateLimitService.consumeOrThrow(
      `promotion:purchase:${authUser.userId}:${request?.ip?.toString() ?? listingId}`,
      {
        limit: 20,
        windowMs: 60 * 60 * 1000,
      },
    );
    return this.promotionsService.promoteListing(listingId, authUser, {
      type: dto.type,
      days: dto.days,
      idempotencyKey: dto.idempotencyKey,
    });
  }

  @UseGuards(JwtAuthGuard)
  @Post('listings/:id/promote/showcase')
  async promoteShowcase(
    @Req() request: any,
    @Param('id') listingId: string,
    @CurrentUser() authUser: AuthenticatedUser,
  ) {
    await this.rateLimitService.consumeOrThrow(
      `promotion:purchase:${authUser.userId}:${request?.ip?.toString() ?? listingId}`,
      {
        limit: 20,
        windowMs: 60 * 60 * 1000,
      },
    );
    return this.promotionsService.promoteListing(
      listingId,
      authUser,
      {
        type: 'showcase',
      },
    );
  }

  @UseGuards(JwtAuthGuard)
  @Get('listings/:id/promotions')
  getListingPromotions(
    @Param('id') listingId: string,
    @CurrentUser() authUser: AuthenticatedUser,
  ) {
    return this.promotionsService.getListingPromotions(listingId, authUser);
  }
}
