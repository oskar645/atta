import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CreatePromotionDto } from './dto/create-promotion.dto';
import { PromotionsService } from './promotions.service';

@Controller()
export class PromotionsController {
  constructor(private readonly promotionsService: PromotionsService) {}

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
    @Param('id') listingId: string,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: CreatePromotionDto,
  ) {
    return this.promotionsService.promoteListing(listingId, authUser, dto.type);
  }

  @UseGuards(JwtAuthGuard)
  @Post('listings/:id/promote/showcase')
  promoteShowcase(
    @Param('id') listingId: string,
    @CurrentUser() authUser: AuthenticatedUser,
  ) {
    return this.promotionsService.promoteListing(
      listingId,
      authUser,
      'showcase',
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
