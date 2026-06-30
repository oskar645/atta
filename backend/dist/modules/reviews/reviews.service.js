"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.ReviewsService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const serializers_1 = require("../../common/serializers");
const notifications_service_1 = require("../notifications/notifications.service");
const prisma_service_1 = require("../prisma/prisma.service");
let ReviewsService = class ReviewsService {
    constructor(prisma, notificationsService) {
        this.prisma = prisma;
        this.notificationsService = notificationsService;
    }
    duplicateReviewError() {
        return new common_1.ConflictException({
            code: 'REVIEW_ALREADY_EXISTS',
            message: 'Можно оставить только один отзыв',
        });
    }
    serializeReview(review) {
        const authorName = review.reviewerName?.trim() ||
            review.reviewer?.displayName?.trim() ||
            review.reviewer?.name?.trim() ||
            'Пользователь';
        const sellerName = review.seller?.displayName?.trim() ||
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
                avatar_url: (0, serializers_1.normalizeStoredMediaUrl)(review.reviewer?.avatarUrl ?? review.reviewer?.photoUrl ?? null, {
                    category: 'avatars',
                }),
            },
            seller_preview: {
                id: review.seller?.id ?? review.sellerId,
                display_name: sellerName,
                avatar_url: (0, serializers_1.normalizeStoredMediaUrl)(review.seller?.avatarUrl ?? review.seller?.photoUrl ?? null, {
                    category: 'avatars',
                }),
            },
        };
    }
    async listSellerReviews(sellerId) {
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
    async createReview(authUser, sellerId, params) {
        if (authUser.userId === sellerId) {
            throw new common_1.BadRequestException('Нельзя оставить отзыв самому себе');
        }
        const rating = Number(params.rating ?? 0);
        if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
            throw new common_1.BadRequestException('Rating must be between 1 and 5');
        }
        const text = params.text?.trim() ?? '';
        if (!text) {
            throw new common_1.BadRequestException('Текст отзыва не должен быть пустым');
        }
        const seller = await this.prisma.user.findUnique({
            where: { id: sellerId },
            select: { id: true, displayName: true, name: true },
        });
        if (!seller) {
            throw new common_1.NotFoundException('Seller not found');
        }
        const listingId = params.listingId?.trim() || null;
        if (listingId) {
            const listing = await this.prisma.listing.findUnique({
                where: { id: listingId },
                select: { id: true, ownerId: true, deletedAt: true },
            });
            if (!listing || listing.deletedAt) {
                throw new common_1.NotFoundException('Listing not found');
            }
            if (listing.ownerId !== sellerId) {
                throw new common_1.BadRequestException('Listing does not belong to this seller');
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
        }
        catch (error) {
            if (error instanceof client_1.Prisma.PrismaClientKnownRequestError &&
                error.code === 'P2002') {
                throw this.duplicateReviewError();
            }
            throw error;
        }
        await this.notificationsService.createSystemNotification({
            userId: sellerId,
            title: 'Новый отзыв',
            body: `${review.reviewerName?.trim() ||
                reviewer?.displayName?.trim() ||
                reviewer?.name?.trim() ||
                'Пользователь'} оставил новый отзыв.`,
            type: client_1.NotificationType.GENERIC,
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
    async updateReview(authUser, reviewId, params) {
        const review = await this.prisma.review.findUnique({
            where: { id: reviewId },
            include: {
                reviewer: true,
                seller: true,
            },
        });
        if (!review || review.deletedAt) {
            throw new common_1.NotFoundException('Review not found');
        }
        const isAdmin = authUser.role === 'admin';
        const isAuthor = authUser.userId === review.reviewerId;
        const isSeller = authUser.userId === review.sellerId;
        const patch = {};
        if (params.rating != null || params.text != null) {
            if (!isAuthor && !isAdmin) {
                throw new common_1.ForbiddenException('Only author can edit review');
            }
            if (params.rating != null) {
                const rating = Number(params.rating);
                if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
                    throw new common_1.BadRequestException('Rating must be between 1 and 5');
                }
                patch.rating = rating;
            }
            if (params.text != null) {
                const text = params.text.trim();
                if (!text) {
                    throw new common_1.BadRequestException('Текст отзыва не должен быть пустым');
                }
                patch.comment = text;
            }
        }
        if (params.replyText != null) {
            if (!isSeller && !isAdmin) {
                throw new common_1.ForbiddenException('Only seller can reply to review');
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
    async deleteReview(authUser, reviewId) {
        const review = await this.prisma.review.findUnique({
            where: { id: reviewId },
            include: {
                reviewer: true,
                seller: true,
            },
        });
        if (!review || review.deletedAt) {
            throw new common_1.NotFoundException('Review not found');
        }
        const isAllowed = authUser.role === 'admin' ||
            authUser.userId === review.reviewerId ||
            authUser.userId === review.sellerId;
        if (!isAllowed) {
            throw new common_1.ForbiddenException('No access to delete review');
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
    async deleteReviewAsAdmin(authUser, reviewId) {
        if (authUser.role !== 'admin') {
            throw new common_1.ForbiddenException('Admin access is required');
        }
        return this.deleteReview(authUser, reviewId);
    }
};
exports.ReviewsService = ReviewsService;
exports.ReviewsService = ReviewsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        notifications_service_1.NotificationsService])
], ReviewsService);
//# sourceMappingURL=reviews.service.js.map