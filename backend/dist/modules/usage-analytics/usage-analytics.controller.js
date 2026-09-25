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
exports.UsageAnalyticsController = exports.ListingOpenDto = exports.GuestActivityDto = void 0;
const common_1 = require("@nestjs/common");
const class_validator_1 = require("class-validator");
const optional_jwt_auth_guard_1 = require("../auth/optional-jwt-auth.guard");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const admin_guard_1 = require("../auth/admin.guard");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const rate_limit_service_1 = require("../rate-limit/rate-limit.service");
const usage_analytics_service_1 = require("./usage-analytics.service");
class GuestActivityDto {
}
exports.GuestActivityDto = GuestActivityDto;
__decorate([
    (0, class_validator_1.IsUUID)('4'),
    __metadata("design:type", String)
], GuestActivityDto.prototype, "guestId", void 0);
class ListingOpenDto {
}
exports.ListingOpenDto = ListingOpenDto;
__decorate([
    (0, class_validator_1.IsUUID)('4'),
    __metadata("design:type", String)
], ListingOpenDto.prototype, "eventId", void 0);
__decorate([
    (0, class_validator_1.IsUUID)(),
    __metadata("design:type", String)
], ListingOpenDto.prototype, "listingId", void 0);
let UsageAnalyticsController = class UsageAnalyticsController {
    constructor(analytics, limits) {
        this.analytics = analytics;
        this.limits = limits;
    }
    limit(request) {
        // IP is used only for abuse throttling, never stored as analytics identity.
        return this.limits.consumeOrThrow(`analytics:${request.ip ?? 'unknown'}`, { limit: 240, windowMs: 60000 });
    }
    async guest(dto, user, request) {
        await this.limit(request);
        return this.analytics.guest(dto.guestId, user?.userId);
    }
    async open(dto, user, request) {
        await this.limit(request);
        return this.analytics.listingOpen(dto.eventId, dto.listingId, user?.userId);
    }
    dashboard() { return this.analytics.dashboard(); }
};
exports.UsageAnalyticsController = UsageAnalyticsController;
__decorate([
    (0, common_1.Post)('analytics/guest-activity'),
    (0, common_1.UseGuards)(optional_jwt_auth_guard_1.OptionalJwtAuthGuard),
    __param(0, (0, common_1.Body)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [GuestActivityDto, Object, Object]),
    __metadata("design:returntype", Promise)
], UsageAnalyticsController.prototype, "guest", null);
__decorate([
    (0, common_1.Post)('analytics/listing-open'),
    (0, common_1.UseGuards)(optional_jwt_auth_guard_1.OptionalJwtAuthGuard),
    __param(0, (0, common_1.Body)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [ListingOpenDto, Object, Object]),
    __metadata("design:returntype", Promise)
], UsageAnalyticsController.prototype, "open", null);
__decorate([
    (0, common_1.Get)('admin/dashboard/usage'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, admin_guard_1.AdminGuard),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], UsageAnalyticsController.prototype, "dashboard", null);
exports.UsageAnalyticsController = UsageAnalyticsController = __decorate([
    (0, common_1.Controller)(),
    __metadata("design:paramtypes", [usage_analytics_service_1.UsageAnalyticsService, rate_limit_service_1.RateLimitService])
], UsageAnalyticsController);
//# sourceMappingURL=usage-analytics.controller.js.map