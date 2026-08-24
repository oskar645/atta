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
exports.FeedAdsController = void 0;
const common_1 = require("@nestjs/common");
const admin_guard_1 = require("../auth/admin.guard");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const feed_ads_service_1 = require("./feed-ads.service");
let FeedAdsController = class FeedAdsController {
    constructor(feedAdsService) {
        this.feedAdsService = feedAdsService;
    }
    list(placement) {
        return this.feedAdsService.listAll(placement);
    }
    active(placement, afterId) {
        return this.feedAdsService.getActive(placement, afterId);
    }
    impression(request, id) {
        return this.feedAdsService.recordImpression(id, this.counterSource(request));
    }
    click(request, id) {
        return this.feedAdsService.recordClick(id, this.counterSource(request));
    }
    counterSource(request) {
        const forwarded = `${request?.headers?.['x-forwarded-for'] ?? ''}`.trim();
        return {
            ip: `${request?.ip ?? ''}`.trim() ||
                forwarded.split(',')[0]?.trim() ||
                'unknown',
            userAgent: `${request?.headers?.['user-agent'] ?? ''}`.trim(),
        };
    }
    adminList(placement) {
        return this.feedAdsService.listAll(placement);
    }
    create(authUser, body) {
        return this.feedAdsService.create(authUser, body);
    }
    update(id, body) {
        return this.feedAdsService.update(id, body);
    }
    activate(id) {
        return this.feedAdsService.activate(id);
    }
    deactivate(id) {
        return this.feedAdsService.deactivate(id);
    }
    remove(id) {
        return this.feedAdsService.remove(id);
    }
};
exports.FeedAdsController = FeedAdsController;
__decorate([
    (0, common_1.Get)('feed-ads'),
    __param(0, (0, common_1.Query)('placement')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], FeedAdsController.prototype, "list", null);
__decorate([
    (0, common_1.Get)('feed-ads/active'),
    __param(0, (0, common_1.Query)('placement')),
    __param(1, (0, common_1.Query)('after_id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", void 0)
], FeedAdsController.prototype, "active", null);
__decorate([
    (0, common_1.Post)('feed-ads/:id/impression'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], FeedAdsController.prototype, "impression", null);
__decorate([
    (0, common_1.Post)('feed-ads/:id/click'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], FeedAdsController.prototype, "click", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, admin_guard_1.AdminGuard),
    (0, common_1.Get)('admin/feed-ads'),
    __param(0, (0, common_1.Query)('placement')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], FeedAdsController.prototype, "adminList", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, admin_guard_1.AdminGuard),
    (0, common_1.Post)('admin/feed-ads'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", void 0)
], FeedAdsController.prototype, "create", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, admin_guard_1.AdminGuard),
    (0, common_1.Patch)('admin/feed-ads/:id'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], FeedAdsController.prototype, "update", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, admin_guard_1.AdminGuard),
    (0, common_1.Post)('admin/feed-ads/:id/activate'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], FeedAdsController.prototype, "activate", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, admin_guard_1.AdminGuard),
    (0, common_1.Post)('admin/feed-ads/:id/deactivate'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], FeedAdsController.prototype, "deactivate", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, admin_guard_1.AdminGuard),
    (0, common_1.Delete)('admin/feed-ads/:id'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], FeedAdsController.prototype, "remove", null);
exports.FeedAdsController = FeedAdsController = __decorate([
    (0, common_1.Controller)(),
    __metadata("design:paramtypes", [feed_ads_service_1.FeedAdsService])
], FeedAdsController);
//# sourceMappingURL=feed-ads.controller.js.map