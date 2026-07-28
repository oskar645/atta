import {
  Body,
  Controller,
  Get,
  Param,
  Post,
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
  getShowcaseByPromotionsRoute() {
    return this.promotionsService.getShowcase();
  }

  @Get('showcase')
  getShowcase() {
    return this.promotionsService.getShowcase();
  }

  @Post('showcase/:promotionId/impression')
  registerImpression(@Param('promotionId') promotionId: string) {
    return this.promotionsService.registerImpression(promotionId);
  }

  @Post('showcase/:promotionId/click')
  registerClick(@Param('promotionId') promotionId: string) {
    return this.promotionsService.registerClick(promotionId);
  }

  @UseGuards(JwtAuthGuard)
  @Post('listings/:id/promotions')
  promoteListing(
    @Req() request: any,
    @Param('id') listingId: string,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: CreatePromotionDto,
  ) {
    this.rateLimitService.consumeOrThrow(
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
  promoteShowcase(
    @Req() request: any,
    @Param('id') listingId: string,
    @CurrentUser() authUser: AuthenticatedUser,
  ) {
    this.rateLimitService.consumeOrThrow(
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
