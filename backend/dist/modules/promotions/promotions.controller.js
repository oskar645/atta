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
exports.PromotionsController = void 0;
const common_1 = require("@nestjs/common");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const create_promotion_dto_1 = require("./dto/create-promotion.dto");
const promotions_service_1 = require("./promotions.service");
let PromotionsController = class PromotionsController {
    constructor(promotionsService) {
        this.promotionsService = promotionsService;
    }
    getPlans() {
        return this.promotionsService.getPlans();
    }
    getShowcaseByPromotionsRoute() {
        return this.promotionsService.getShowcase();
    }
    getShowcase() {
        return this.promotionsService.getShowcase();
    }
    registerImpression(promotionId) {
        return this.promotionsService.registerImpression(promotionId);
    }
    registerClick(promotionId) {
        return this.promotionsService.registerClick(promotionId);
    }
    promoteListing(listingId, authUser, dto) {
        return this.promotionsService.promoteListing(listingId, authUser, dto.type);
    }
    promoteShowcase(listingId, authUser) {
        return this.promotionsService.promoteListing(listingId, authUser, 'showcase');
    }
    getListingPromotions(listingId, authUser) {
        return this.promotionsService.getListingPromotions(listingId, authUser);
    }
};
exports.PromotionsController = PromotionsController;
__decorate([
    (0, common_1.Get)('promotions/plans'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], PromotionsController.prototype, "getPlans", null);
__decorate([
    (0, common_1.Get)('promotions/showcase'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], PromotionsController.prototype, "getShowcaseByPromotionsRoute", null);
__decorate([
    (0, common_1.Get)('showcase'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], PromotionsController.prototype, "getShowcase", null);
__decorate([
    (0, common_1.Post)('showcase/:promotionId/impression'),
    __param(0, (0, common_1.Param)('promotionId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], PromotionsController.prototype, "registerImpression", null);
__decorate([
    (0, common_1.Post)('showcase/:promotionId/click'),
    __param(0, (0, common_1.Param)('promotionId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], PromotionsController.prototype, "registerClick", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)('listings/:id/promotions'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, create_promotion_dto_1.CreatePromotionDto]),
    __metadata("design:returntype", void 0)
], PromotionsController.prototype, "promoteListing", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)('listings/:id/promote/showcase'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], PromotionsController.prototype, "promoteShowcase", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Get)('listings/:id/promotions'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], PromotionsController.prototype, "getListingPromotions", null);
exports.PromotionsController = PromotionsController = __decorate([
    (0, common_1.Controller)(),
    __metadata("design:paramtypes", [promotions_service_1.PromotionsService])
], PromotionsController);
//# sourceMappingURL=promotions.controller.js.map