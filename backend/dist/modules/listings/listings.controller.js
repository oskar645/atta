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
exports.ListingsController = void 0;
const common_1 = require("@nestjs/common");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const optional_jwt_auth_guard_1 = require("../auth/optional-jwt-auth.guard");
const rate_limit_service_1 = require("../rate-limit/rate-limit.service");
const create_listing_dto_1 = require("./dto/create-listing.dto");
const archive_listing_dto_1 = require("./dto/archive-listing.dto");
const update_listing_dto_1 = require("./dto/update-listing.dto");
const listings_service_1 = require("./listings.service");
let ListingsController = class ListingsController {
    constructor(listingsService, rateLimitService) {
        this.listingsService = listingsService;
        this.rateLimitService = rateLimitService;
    }
    async create(request, authUser, dto) {
        await this.rateLimitService.consumeOrThrow(`listing:create:${authUser.userId}:${request?.ip?.toString() ?? 'unknown'}`, {
            limit: 20,
            windowMs: 60 * 60 * 1000,
        });
        return this.listingsService.create(authUser, dto);
    }
    findAll(search, category, city, minPrice, maxPrice, limit, cursor, ownerId, status) {
        return this.listingsService.findAll({
            search,
            category,
            city,
            ownerId,
            status,
            limit: limit == null ? undefined : Number(limit),
            cursor,
            minPrice: minPrice == null ? undefined : Number(minPrice),
            maxPrice: maxPrice == null ? undefined : Number(maxPrice),
        });
    }
    findVip(limit, cursor, category) {
        return this.listingsService.findVipListings({
            limit: limit == null ? undefined : Number(limit),
            cursor,
            category,
        });
    }
    findMy(authUser, status, limit, cursor) {
        return this.listingsService.findMy(authUser, {
            status,
            limit: limit == null ? undefined : Number(limit),
            cursor,
        });
    }
    findOne(id, authUser) {
        return this.listingsService.findOne(id, authUser);
    }
    update(id, authUser, dto) {
        return this.listingsService.update(id, authUser, dto);
    }
    archive(id, authUser, dto) {
        return this.listingsService.archive(id, authUser, dto);
    }
    incrementView(id, authUser) {
        return this.listingsService.incrementView(id, authUser);
    }
    incrementViewAlias(id, authUser) {
        return this.listingsService.incrementView(id, authUser);
    }
    remove(id, authUser) {
        return this.listingsService.remove(id, authUser);
    }
};
exports.ListingsController = ListingsController;
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)(),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object, create_listing_dto_1.CreateListingDto]),
    __metadata("design:returntype", Promise)
], ListingsController.prototype, "create", null);
__decorate([
    (0, common_1.Get)(),
    __param(0, (0, common_1.Query)('search')),
    __param(1, (0, common_1.Query)('category')),
    __param(2, (0, common_1.Query)('city')),
    __param(3, (0, common_1.Query)('minPrice')),
    __param(4, (0, common_1.Query)('maxPrice')),
    __param(5, (0, common_1.Query)('limit')),
    __param(6, (0, common_1.Query)('cursor')),
    __param(7, (0, common_1.Query)('ownerId')),
    __param(8, (0, common_1.Query)('status')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String, String, String, String, String, String, String]),
    __metadata("design:returntype", void 0)
], ListingsController.prototype, "findAll", null);
__decorate([
    (0, common_1.Get)('vip'),
    __param(0, (0, common_1.Query)('limit')),
    __param(1, (0, common_1.Query)('cursor')),
    __param(2, (0, common_1.Query)('category')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String]),
    __metadata("design:returntype", void 0)
], ListingsController.prototype, "findVip", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Get)('my'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Query)('status')),
    __param(2, (0, common_1.Query)('limit')),
    __param(3, (0, common_1.Query)('cursor')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, String, String]),
    __metadata("design:returntype", void 0)
], ListingsController.prototype, "findMy", null);
__decorate([
    (0, common_1.UseGuards)(optional_jwt_auth_guard_1.OptionalJwtAuthGuard),
    (0, common_1.Get)(':id'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], ListingsController.prototype, "findOne", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Patch)(':id'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, update_listing_dto_1.UpdateListingDto]),
    __metadata("design:returntype", void 0)
], ListingsController.prototype, "update", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)(':id/archive'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, archive_listing_dto_1.ArchiveListingDto]),
    __metadata("design:returntype", void 0)
], ListingsController.prototype, "archive", null);
__decorate([
    (0, common_1.Post)(':id/views'),
    (0, common_1.UseGuards)(optional_jwt_auth_guard_1.OptionalJwtAuthGuard),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], ListingsController.prototype, "incrementView", null);
__decorate([
    (0, common_1.Post)(':id/view'),
    (0, common_1.UseGuards)(optional_jwt_auth_guard_1.OptionalJwtAuthGuard),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], ListingsController.prototype, "incrementViewAlias", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Delete)(':id'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], ListingsController.prototype, "remove", null);
exports.ListingsController = ListingsController = __decorate([
    (0, common_1.Controller)('listings'),
    __metadata("design:paramtypes", [listings_service_1.ListingsService,
        rate_limit_service_1.RateLimitService])
], ListingsController);
//# sourceMappingURL=listings.controller.js.map