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
exports.AdminController = void 0;
const common_1 = require("@nestjs/common");
const admin_guard_1 = require("../auth/admin.guard");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const admin_service_1 = require("./admin.service");
const list_admin_bonus_analytics_dto_1 = require("./dto/list-admin-bonus-analytics.dto");
const list_admin_listings_dto_1 = require("./dto/list-admin-listings.dto");
const list_admin_promotions_dto_1 = require("./dto/list-admin-promotions.dto");
const list_admin_wallet_transactions_dto_1 = require("./dto/list-admin-wallet-transactions.dto");
const moderate_listing_dto_1 = require("./dto/moderate-listing.dto");
const archive_listing_dto_1 = require("../listings/dto/archive-listing.dto");
let AdminController = class AdminController {
    constructor(adminService) {
        this.adminService = adminService;
    }
    getDashboardStats() {
        return this.adminService.getDashboardStats();
    }
    listUsers() {
        return this.adminService.listUsers();
    }
    listOnlineUsers() {
        return this.adminService.listOnlineUsers();
    }
    listTodayVisits() {
        return this.adminService.listTodayVisits();
    }
    getUserById(id) {
        return this.adminService.getUserById(id);
    }
    deleteUser(id, authUser) {
        return this.adminService.deleteUser(id, authUser);
    }
    getModerationQueue(query) {
        return this.adminService.getModerationQueue(query.status ?? 'pending');
    }
    getListingsAlias(query) {
        return this.adminService.listListings(query.status);
    }
    listPromotions(query) {
        return this.adminService.listPromotions(query);
    }
    getPromotionsSummary() {
        return this.adminService.getPromotionsSummary();
    }
    cancelPromotion(id, authUser) {
        return this.adminService.cancelPromotion(id, authUser);
    }
    listWallets() {
        return this.adminService.listWallets();
    }
    listWalletTransactions(query) {
        return this.adminService.listWalletTransactions(query);
    }
    getBonusAnalytics(query) {
        return this.adminService.getBonusAnalytics(query);
    }
    approveListing(id, authUser) {
        return this.adminService.approveListing(id, authUser);
    }
    rejectListing(id, authUser, dto) {
        return this.adminService.rejectListing(id, authUser, {
            reason: dto.reason,
            moderationNote: dto.moderation_note,
        });
    }
    archiveListing(id, authUser, dto) {
        return this.adminService.archiveListing(id, authUser, dto);
    }
    deleteListing(id, authUser, dto) {
        return this.adminService.deleteListing(id, authUser, {
            reason: dto.reason,
            moderationNote: dto.moderation_note,
        });
    }
    deleteReview(id, authUser) {
        return this.adminService.deleteReview(id, authUser);
    }
    getReportsPlaceholder() {
        return this.adminService.getReportsPlaceholder();
    }
    getSupportAlias() {
        return this.adminService.getSupportTicketsPlaceholder();
    }
    getSupportTicketsPlaceholder() {
        return this.adminService.getSupportTicketsPlaceholder();
    }
};
exports.AdminController = AdminController;
__decorate([
    (0, common_1.Get)('dashboard/stats'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "getDashboardStats", null);
__decorate([
    (0, common_1.Get)('users'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "listUsers", null);
__decorate([
    (0, common_1.Get)('online-users'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "listOnlineUsers", null);
__decorate([
    (0, common_1.Get)('today-visits'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "listTodayVisits", null);
__decorate([
    (0, common_1.Get)('users/:id'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "getUserById", null);
__decorate([
    (0, common_1.Delete)('users/:id'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "deleteUser", null);
__decorate([
    (0, common_1.Get)('listings/moderation'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [list_admin_listings_dto_1.ListAdminListingsDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "getModerationQueue", null);
__decorate([
    (0, common_1.Get)('listings'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [list_admin_listings_dto_1.ListAdminListingsDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "getListingsAlias", null);
__decorate([
    (0, common_1.Get)('promotions'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [list_admin_promotions_dto_1.ListAdminPromotionsDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "listPromotions", null);
__decorate([
    (0, common_1.Get)('promotions/summary'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "getPromotionsSummary", null);
__decorate([
    (0, common_1.Patch)('promotions/:id/cancel'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "cancelPromotion", null);
__decorate([
    (0, common_1.Get)('wallets'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "listWallets", null);
__decorate([
    (0, common_1.Get)('wallet-transactions'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [list_admin_wallet_transactions_dto_1.ListAdminWalletTransactionsDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "listWalletTransactions", null);
__decorate([
    (0, common_1.Get)('analytics/bonuses'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [list_admin_bonus_analytics_dto_1.ListAdminBonusAnalyticsDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "getBonusAnalytics", null);
__decorate([
    (0, common_1.Patch)('listings/:id/approve'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "approveListing", null);
__decorate([
    (0, common_1.Patch)('listings/:id/reject'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, moderate_listing_dto_1.ModerateListingDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "rejectListing", null);
__decorate([
    (0, common_1.Patch)('listings/:id/archive'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, archive_listing_dto_1.ArchiveListingDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "archiveListing", null);
__decorate([
    (0, common_1.Delete)('listings/:id'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, moderate_listing_dto_1.ModerateListingDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "deleteListing", null);
__decorate([
    (0, common_1.Delete)('reviews/:id'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "deleteReview", null);
__decorate([
    (0, common_1.Get)('reports'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "getReportsPlaceholder", null);
__decorate([
    (0, common_1.Get)('support'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "getSupportAlias", null);
__decorate([
    (0, common_1.Get)('support/tickets'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "getSupportTicketsPlaceholder", null);
exports.AdminController = AdminController = __decorate([
    (0, common_1.Controller)('admin'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, admin_guard_1.AdminGuard),
    __metadata("design:paramtypes", [admin_service_1.AdminService])
], AdminController);
//# sourceMappingURL=admin.controller.js.map