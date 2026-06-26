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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminReviewsController = exports.ReviewsController = void 0;
const common_1 = require("@nestjs/common");
const admin_guard_1 = require("../auth/admin.guard");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const reviews_service_1 = require("./reviews.service");
let ReviewsController = class ReviewsController {
    constructor(reviewsService) {
        this.reviewsService = reviewsService;
    }
    listSellerReviews(sellerId) {
        return this.reviewsService.listSellerReviews(sellerId);
    }
    createReview(authUser, sellerId, body) {
        return this.reviewsService.createReview(authUser, sellerId, {
            listingId: body.listing_id ?? body.listingId,
            rating: body.rating,
            text: body.text ?? body.comment,
            reviewerName: body.reviewer_name ?? body.reviewerName,
        });
    }
    updateReview(authUser, reviewId, body) {
        return this.reviewsService.updateReview(authUser, reviewId, {
            rating: body.rating,
            text: body.text ?? body.comment,
            replyText: body.reply_text ?? body.replyText,
        });
    }
    deleteReview(authUser, reviewId) {
        return this.reviewsService.deleteReview(authUser, reviewId);
    }
};
exports.ReviewsController = ReviewsController;
__decorate([
    (0, common_1.Get)('users/:id/reviews'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], ReviewsController.prototype, "listSellerReviews", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)('users/:id/reviews'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id')),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, Object]),
    __metadata("design:returntype", void 0)
], ReviewsController.prototype, "createReview", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Patch)('reviews/:id'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id')),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, Object]),
    __metadata("design:returntype", void 0)
], ReviewsController.prototype, "updateReview", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Delete)('reviews/:id'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], ReviewsController.prototype, "deleteReview", null);
exports.ReviewsController = ReviewsController = __decorate([
    (0, common_1.Controller)(),
    __metadata("design:paramtypes", [reviews_service_1.ReviewsService])
], ReviewsController);
let AdminReviewsController = class AdminReviewsController {
    constructor(reviewsService) {
        this.reviewsService = reviewsService;
    }
    deleteReview(authUser, reviewId) {
        return this.reviewsService.deleteReviewAsAdmin(authUser, reviewId);
    }
};
exports.AdminReviewsController = AdminReviewsController;
__decorate([
    (0, common_1.Delete)(':id'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], AdminReviewsController.prototype, "deleteReview", null);
exports.AdminReviewsController = AdminReviewsController = __decorate([
    (0, common_1.Controller)('admin/reviews'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, admin_guard_1.AdminGuard),
    __metadata("design:paramtypes", [reviews_service_1.ReviewsService])
], AdminReviewsController);
//# sourceMappingURL=reviews.controller.js.map