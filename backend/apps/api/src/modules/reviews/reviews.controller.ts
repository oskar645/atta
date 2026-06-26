import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';

import { AdminGuard } from '../auth/admin.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ReviewsService } from './reviews.service';

@Controller()
export class ReviewsController {
  constructor(private readonly reviewsService: ReviewsService) {}

  @Get('users/:id/reviews')
  listSellerReviews(@Param('id') sellerId: string) {
    return this.reviewsService.listSellerReviews(sellerId);
  }

  @UseGuards(JwtAuthGuard)
  @Post('users/:id/reviews')
  createReview(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id') sellerId: string,
    @Body()
    body: {
      listing_id?: string;
      listingId?: string;
      rating?: number;
      text?: string;
      comment?: string;
      reviewer_name?: string;
      reviewerName?: string;
    },
  ) {
    return this.reviewsService.createReview(authUser, sellerId, {
      listingId: body.listing_id ?? body.listingId,
      rating: body.rating,
      text: body.text ?? body.comment,
      reviewerName: body.reviewer_name ?? body.reviewerName,
    });
  }

  @UseGuards(JwtAuthGuard)
  @Patch('reviews/:id')
  updateReview(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id') reviewId: string,
    @Body()
    body: {
      rating?: number;
      text?: string;
      comment?: string;
      reply_text?: string;
      replyText?: string;
    },
  ) {
    return this.reviewsService.updateReview(authUser, reviewId, {
      rating: body.rating,
      text: body.text ?? body.comment,
      replyText: body.reply_text ?? body.replyText,
    });
  }

  @UseGuards(JwtAuthGuard)
  @Delete('reviews/:id')
  deleteReview(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id') reviewId: string,
  ) {
    return this.reviewsService.deleteReview(authUser, reviewId);
  }
}

@Controller('admin/reviews')
@UseGuards(JwtAuthGuard, AdminGuard)
export class AdminReviewsController {
  constructor(private readonly reviewsService: ReviewsService) {}

  @Delete(':id')
  deleteReview(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id') reviewId: string,
  ) {
    return this.reviewsService.deleteReviewAsAdmin(authUser, reviewId);
  }
}
