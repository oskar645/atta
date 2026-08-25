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
const admin_registration_stats_dto_1 = require("./dto/admin-registration-stats.dto");
const list_admin_listings_dto_1 = require("./dto/list-admin-listings.dto");
const list_admin_points_purchases_dto_1 = require("./dto/list-admin-points-purchases.dto");
const list_admin_promotions_dto_1 = require("./dto/list-admin-promotions.dto");
const list_admin_blocks_dto_1 = require("./dto/list-admin-blocks.dto");
const list_admin_wallet_transactions_dto_1 = require("./dto/list-admin-wallet-transactions.dto");
const list_admin_users_dto_1 = require("./dto/list-admin-users.dto");
const moderate_listing_dto_1 = require("./dto/moderate-listing.dto");
const archive_listing_dto_1 = require("../listings/dto/archive-listing.dto");
const block_user_dto_1 = require("./dto/block-user.dto");
const send_admin_support_message_dto_1 = require("./dto/send-admin-support-message.dto");
const support_service_1 = require("../support/support.service");
let AdminController = class AdminController {
    constructor(adminService, supportService) {
        this.adminService = adminService;
        this.supportService = supportService;
    }
    getDashboardStats() {
        return this.adminService.getDashboardStats();
    }
    listUsers(query) {
        return this.adminService.listUsers(query);
    }
    getUserRegistrationStats(query) {
        return this.adminService.getUserRegistrationStats(query);
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
    sendSupportMessageToUser(userId, dto) {
        return this.supportService.openTicketForAdminContact({
            userId,
            text: dto.message,
            idempotencyKey: dto.idempotencyKey,
            subject: 'Сообщение от администрации',
        });
    }
    getUserReferrals(userId, query) {
        return this.adminService.getUserReferrals(userId, query);
    }
    blockUser(id, authUser, dto) {
        return this.adminService.blockUser(id, authUser, dto);
    }
    listBlocks(query) {
        return this.adminService.listBlocks(query);
    }
    unblockUserBlock(id, authUser, dto) {
        return this.adminService.unblockUserBlock(id, authUser, dto);
    }
    updateUserBlock(id, authUser, dto) {
        return this.adminService.updateUserBlock(id, authUser, dto);
    }
    deleteUser(id, authUser) {
        return this.adminService.deleteUser(id, authUser);
    }
    getModerationQueue(query) {
        return this.adminService.getModerationQueue(query);
    }
    getListingsAlias(query) {
        return this.adminService.listListings(query);
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
    listWallets(query) {
        return this.adminService.listWallets(query);
    }
    listWalletTransactions(query) {
        return this.adminService.listWalletTransactions(query);
    }
    getBonusAnalytics(query) {
        return this.adminService.getBonusAnalytics(query);
    }
    getPointsPurchasesSummary(query) {
        return this.adminService.getPointsPurchasesSummary(query);
    }
    listPointsPurchases(query) {
        return this.adminService.listPointsPurchases(query);
    }
    getReferralsSummary(query) {
        return this.adminService.getReferralSummary(query);
    }
    listReferrals(query) {
        return this.adminService.listReferrals(query);
    }
    getReferralById(id) {
        return this.adminService.getReferralById(id);
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
        return this.supportService.listTickets();
    }
    getSupportTicketsPlaceholder() {
        return this.supportService.listTickets();
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
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [list_admin_users_dto_1.ListAdminUsersDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "listUsers", null);
__decorate([
    (0, common_1.Get)('users/registration-stats'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [admin_registration_stats_dto_1.AdminRegistrationStatsDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "getUserRegistrationStats", null);
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
    (0, common_1.Post)('users/:userId/support-message'),
    __param(0, (0, common_1.Param)('userId', new common_1.ParseUUIDPipe())),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, send_admin_support_message_dto_1.SendAdminSupportMessageDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "sendSupportMessageToUser", null);
__decorate([
    (0, common_1.Get)('users/:userId/referrals'),
    __param(0, (0, common_1.Param)('userId')),
    __param(1, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, list_admin_bonus_analytics_dto_1.ListAdminBonusAnalyticsDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "getUserReferrals", null);
__decorate([
    (0, common_1.Post)('users/:id/block'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, block_user_dto_1.BlockUserDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "blockUser", null);
__decorate([
    (0, common_1.Get)('blocks'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [list_admin_blocks_dto_1.ListAdminBlocksDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "listBlocks", null);
__decorate([
    (0, common_1.Post)('blocks/:id/unblock'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, block_user_dto_1.UnblockUserDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "unblockUserBlock", null);
__decorate([
    (0, common_1.Patch)('blocks/:id'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, block_user_dto_1.UpdateUserBlockDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "updateUserBlock", null);
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
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [list_admin_users_dto_1.ListAdminUsersDto]),
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
    (0, common_1.Get)('payments/points-purchases/summary'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [list_admin_points_purchases_dto_1.ListAdminPointsPurchasesDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "getPointsPurchasesSummary", null);
__decorate([
    (0, common_1.Get)('payments/points-purchases'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [list_admin_points_purchases_dto_1.ListAdminPointsPurchasesDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "listPointsPurchases", null);
__decorate([
    (0, common_1.Get)('referrals/summary'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [list_admin_bonus_analytics_dto_1.ListAdminBonusAnalyticsDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "getReferralsSummary", null);
__decorate([
    (0, common_1.Get)('referrals'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [list_admin_bonus_analytics_dto_1.ListAdminBonusAnalyticsDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "listReferrals", null);
__decorate([
    (0, common_1.Get)('referrals/:id'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "getReferralById", null);
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
    __metadata("design:paramtypes", [admin_service_1.AdminService,
        support_service_1.SupportService])
], AdminController);
//# sourceMappingURL=admin.controller.js.map