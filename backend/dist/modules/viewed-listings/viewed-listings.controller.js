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
exports.ViewedListingsController = void 0;
const common_1 = require("@nestjs/common");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const viewed_listings_service_1 = require("./viewed-listings.service");
let ViewedListingsController = class ViewedListingsController {
    constructor(viewedListingsService) {
        this.viewedListingsService = viewedListingsService;
    }
    list(authUser, limit, cursor) {
        return this.viewedListingsService.list(authUser, {
            limit: limit == null ? undefined : Number(limit),
            cursor,
        });
    }
    mark(authUser, listingId) {
        return this.viewedListingsService.mark(authUser, listingId);
    }
};
exports.ViewedListingsController = ViewedListingsController;
__decorate([
    (0, common_1.Get)(),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Query)('limit')),
    __param(2, (0, common_1.Query)('cursor')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, String]),
    __metadata("design:returntype", void 0)
], ViewedListingsController.prototype, "list", null);
__decorate([
    (0, common_1.Post)(':listingId'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('listingId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], ViewedListingsController.prototype, "mark", null);
exports.ViewedListingsController = ViewedListingsController = __decorate([
    (0, common_1.Controller)('viewed-listings'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [viewed_listings_service_1.ViewedListingsService])
], ViewedListingsController);
//# sourceMappingURL=viewed-listings.controller.js.map