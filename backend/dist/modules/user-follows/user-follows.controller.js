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
exports.UserFollowsController = void 0;
const common_1 = require("@nestjs/common");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const user_follows_service_1 = require("./user-follows.service");
let UserFollowsController = class UserFollowsController {
    constructor(userFollowsService) {
        this.userFollowsService = userFollowsService;
    }
    list(authUser, limit, cursor) {
        return this.userFollowsService.list(authUser, {
            limit: limit == null ? undefined : Number(limit),
            cursor,
        });
    }
    countFollowers(sellerId) {
        return this.userFollowsService.countFollowers(sellerId);
    }
    follow(authUser, sellerId) {
        return this.userFollowsService.follow(authUser, sellerId);
    }
    unfollow(authUser, sellerId) {
        return this.userFollowsService.unfollow(authUser, sellerId);
    }
};
exports.UserFollowsController = UserFollowsController;
__decorate([
    (0, common_1.Get)(),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Query)('limit')),
    __param(2, (0, common_1.Query)('cursor')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, String]),
    __metadata("design:returntype", void 0)
], UserFollowsController.prototype, "list", null);
__decorate([
    (0, common_1.Get)('seller/:sellerId/count'),
    __param(0, (0, common_1.Param)('sellerId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], UserFollowsController.prototype, "countFollowers", null);
__decorate([
    (0, common_1.Post)(':sellerId'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('sellerId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], UserFollowsController.prototype, "follow", null);
__decorate([
    (0, common_1.Delete)(':sellerId'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('sellerId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], UserFollowsController.prototype, "unfollow", null);
exports.UserFollowsController = UserFollowsController = __decorate([
    (0, common_1.Controller)('user-follows'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [user_follows_service_1.UserFollowsService])
], UserFollowsController);
//# sourceMappingURL=user-follows.controller.js.map