import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { NotificationType, Prisma } from '@prisma/client';

import { normalizeStoredMediaUrl } from '../../common/serializers';
import { AuthenticatedUser } from '../auth/auth.types';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class ReviewsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notificationsService: NotificationsService,
  ) {}

  private duplicateReviewError() {
    return new ConflictException({
      code: 'REVIEW_ALREADY_EXISTS',
      message: 'Можно оставить только один отзыв',
    });
  }

  private serializeReview(review: {
    id: string;
    sellerId: string;
    reviewerId: string;
    reviewerName: string | null;
    listingId: string | null;
    rating: number;
    comment: string;
    replyText: string | null;
    replyAt: Date | null;
    createdAt: Date;
    updatedAt: Date | null;
    reviewer?: {
      id: string;
      displayName: string;
      name: string;
      avatarUrl: string | null;
      photoUrl: string | null;
    };
    seller?: {
      id: string;
      displayName: string;
      name: string;
      avatarUrl: string | null;
      photoUrl: string | null;
    };
  }) {
    const authorName =
        review.reviewerName?.trim() ||
        review.reviewer?.displayName?.trim() ||
        review.reviewer?.name?.trim() ||
        'Пользователь';
    const sellerName =
        review.seller?.displayName?.trim() ||
        review.seller?.name?.trim() ||
        'Пользователь';

    return {
      id: review.id,
      seller_id: review.sellerId,
      reviewer_id: review.reviewerId,
      author_id: review.reviewerId,
      reviewer_name: authorName,
      listing_id: review.listingId,
      rating: review.rating,
      comment: review.comment,
      text: review.comment,
      reply_text: review.replyText,
      reply_at: review.replyAt?.toISOString() ?? null,
      created_at: review.createdAt.toISOString(),
      updated_at: review.updatedAt?.toISOString() ?? null,
      author_preview: {
        id: review.reviewer?.id ?? review.reviewerId,
        display_name: authorName,
        avatar_url: normalizeStoredMediaUrl(
          review.reviewer?.avatarUrl ?? review.reviewer?.photoUrl ?? null,
          {
            category: 'avatars',
          },
        ),
      },
      seller_preview: {
        id: review.seller?.id ?? review.sellerId,
        display_name: sellerName,
        avatar_url: normalizeStoredMediaUrl(
          review.seller?.avatarUrl ?? review.seller?.photoUrl ?? null,
          {
            category: 'avatars',
          },
        ),
      },
    };
  }

  async listSellerReviews(sellerId: string) {
    const items = await this.prisma.review.findMany({
      where: {
        sellerId,
        deletedAt: null,
      },
      include: {
        reviewer: true,
        seller: true,
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    return {
      source: 'timeweb',
      items: items.map((item) => this.serializeReview(item)),
    };
  }

  async createReview(
    authUser: AuthenticatedUser,
    sellerId: string,
    params: {
      listingId?: string;
      rating?: number;
      text?: string;
      reviewerName?: string;
    },
  ) {
    if (authUser.userId === sellerId) {
      throw new BadRequestException('Нельзя оставить отзыв самому себе');
    }

    const rating = Number(params.rating ?? 0);
    if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
      throw new BadRequestException('Rating must be between 1 and 5');
    }

    const text = params.text?.trim() ?? '';
    if (!text) {
      throw new BadRequestException('Текст отзыва не должен быть пустым');
    }

    const seller = await this.prisma.user.findUnique({
      where: { id: sellerId },
      select: { id: true, displayName: true, name: true },
    });
    if (!seller) {
      throw new NotFoundException('Seller not found');
    }

    const listingId = params.listingId?.trim() || null;
    if (listingId) {
      const listing = await this.prisma.listing.findUnique({
        where: { id: listingId },
        select: { id: true, ownerId: true, deletedAt: true },
      });
      if (!listing || listing.deletedAt) {
        throw new NotFoundException('Listing not found');
      }
      if (listing.ownerId !== sellerId) {
        throw new BadRequestException('Listing does not belong to this seller');
      }
    }

    const existing = await this.prisma.review.findFirst({
      where: {
        sellerId,
        reviewerId: authUser.userId,
        deletedAt: null,
      },
      select: { id: true },
    });
    if (existing) {
      throw this.duplicateReviewError();
    }

    const reviewer = await this.prisma.user.findUnique({
      where: { id: authUser.userId },
      select: {
        id: true,
        displayName: true,
        name: true,
        avatarUrl: true,
        photoUrl: true,
      },
    });

    let review;
    try {
      review = await this.prisma.review.create({
        data: {
          sellerId,
          reviewerId: authUser.userId,
          reviewerName: params.reviewerName?.trim() || null,
          listingId,
          rating,
          comment: text,
        },
        include: {
          reviewer: true,
          seller: true,
        },
      });
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        throw this.duplicateReviewError();
      }
      throw error;
    }

    await this.notificationsService.createSystemNotification({
      userId: sellerId,
      title: 'Новый отзыв',
      body: `${
        review.reviewerName?.trim() ||
        reviewer?.displayName?.trim() ||
        reviewer?.name?.trim() ||
        'Пользователь'
      } оставил новый отзыв.`,
      type: NotificationType.GENERIC,
      payload: {
        reviewId: review.id,
        sellerId,
        authorId: authUser.userId,
      },
    });

    return {
      source: 'timeweb',
      item: this.serializeReview(review),
    };
  }

  async updateReview(
    authUser: AuthenticatedUser,
    reviewId: string,
    params: {
      rating?: number;
      text?: string;
      replyText?: string;
    },
  ) {
    const review = await this.prisma.review.findUnique({
      where: { id: reviewId },
      include: {
        reviewer: true,
        seller: true,
      },
    });

    if (!review || review.deletedAt) {
      throw new NotFoundException('Review not found');
    }

    const isAdmin = authUser.role === 'admin';
    const isAuthor = authUser.userId === review.reviewerId;
    const isSeller = authUser.userId === review.sellerId;

    const patch: Record<string, unknown> = {};

    if (params.rating != null || params.text != null) {
      if (!isAuthor && !isAdmin) {
        throw new ForbiddenException('Only author can edit review');
      }
      if (params.rating != null) {
        const rating = Number(params.rating);
        if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
          throw new BadRequestException('Rating must be between 1 and 5');
        }
        patch.rating = rating;
      }
      if (params.text != null) {
        const text = params.text.trim();
        if (!text) {
          throw new BadRequestException('Текст отзыва не должен быть пустым');
        }
        patch.comment = text;
      }
    }

    if (params.replyText != null) {
      if (!isSeller && !isAdmin) {
        throw new ForbiddenException('Only seller can reply to review');
      }
      const replyText = params.replyText.trim();
      patch.replyText = replyText || null;
      patch.replyAt = replyText.length === 0 ? null : new Date();
    }

    if (Object.keys(patch).length == 0) {
      return {
        source: 'timeweb',
        item: this.serializeReview(review),
      };
    }

    const updated = await this.prisma.review.update({
      where: { id: reviewId },
      data: {
        ...patch,
        updatedAt: new Date(),
      },
      include: {
        reviewer: true,
        seller: true,
      },
    });

    return {
      source: 'timeweb',
      item: this.serializeReview(updated),
    };
  }

  async deleteReview(authUser: AuthenticatedUser, reviewId: string) {
    const review = await this.prisma.review.findUnique({
      where: { id: reviewId },
      include: {
        reviewer: true,
        seller: true,
      },
    });

    if (!review || review.deletedAt) {
      throw new NotFoundException('Review not found');
    }

    const isAllowed =
        authUser.role === 'admin' ||
        authUser.userId === review.reviewerId ||
        authUser.userId === review.sellerId;
    if (!isAllowed) {
      throw new ForbiddenException('No access to delete review');
    }

    const deleted = await this.prisma.review.update({
      where: { id: reviewId },
      data: {
        deletedAt: new Date(),
        updatedAt: new Date(),
      },
      include: {
        reviewer: true,
        seller: true,
      },
    });

    return {
      source: 'timeweb',
      deleted: true,
      item: this.serializeReview(deleted),
    };
  }

  async deleteReviewAsAdmin(
    authUser: AuthenticatedUser,
    reviewId: string,
  ) {
    if (authUser.role !== 'admin') {
      throw new ForbiddenException('Admin access is required');
    }

    return this.deleteReview(authUser, reviewId);
  }
}
