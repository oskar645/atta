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
exports.AdminReportsController = exports.ReportsController = void 0;
const common_1 = require("@nestjs/common");
const admin_guard_1 = require("../auth/admin.guard");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const chats_gateway_1 = require("../chats/chats.gateway");
const rate_limit_service_1 = require("../rate-limit/rate-limit.service");
const create_report_dto_1 = require("./dto/create-report.dto");
const moderate_report_dto_1 = require("./dto/moderate-report.dto");
const list_admin_reports_dto_1 = require("./dto/list-admin-reports.dto");
const reports_service_1 = require("./reports.service");
let ReportsController = class ReportsController {
    constructor(reportsService, chatsGateway, rateLimitService) {
        this.reportsService = reportsService;
        this.chatsGateway = chatsGateway;
        this.rateLimitService = rateLimitService;
    }
    create(request, authUser, body) {
        this.rateLimitService.consumeOrThrow(`reports:${authUser.userId}:${request?.ip?.toString() ?? 'unknown'}`, {
            limit: 10,
            windowMs: 60 * 1000,
        });
        return this.reportsService.create(authUser, body).then((result) => {
            const notifications = result['admin_notifications'];
            if (Array.isArray(notifications)) {
                for (const item of notifications) {
                    if (!item || typeof item !== 'object') {
                        continue;
                    }
                    const notification = item;
                    const userId = `${notification['user_id'] ?? ''}`.trim();
                    if (userId.length === 0) {
                        continue;
                    }
                    this.chatsGateway.emitNotificationNew(notification, userId);
                }
            }
            return result;
        });
    }
};
exports.ReportsController = ReportsController;
__decorate([
    (0, common_1.Post)(),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object, create_report_dto_1.CreateReportDto]),
    __metadata("design:returntype", void 0)
], ReportsController.prototype, "create", null);
exports.ReportsController = ReportsController = __decorate([
    (0, common_1.Controller)('reports'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [reports_service_1.ReportsService,
        chats_gateway_1.ChatsGateway,
        rate_limit_service_1.RateLimitService])
], ReportsController);
let AdminReportsController = class AdminReportsController {
    constructor(reportsService) {
        this.reportsService = reportsService;
    }
    list(query) {
        return this.reportsService.listForAdmin(query);
    }
    resolve(reportId, authUser, body) {
        return this.reportsService.resolve(reportId, authUser, body.comment);
    }
    reject(reportId, authUser, body) {
        return this.reportsService.reject(reportId, authUser, body.comment);
    }
    reopen(reportId, authUser) {
        return this.reportsService.reopen(reportId, authUser);
    }
    hide(reportId, authUser) {
        return this.reportsService.hide(reportId, authUser);
    }
};
exports.AdminReportsController = AdminReportsController;
__decorate([
    (0, common_1.Get)(),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [list_admin_reports_dto_1.ListAdminReportsDto]),
    __metadata("design:returntype", void 0)
], AdminReportsController.prototype, "list", null);
__decorate([
    (0, common_1.Patch)(':id/resolve'),
    __param(0, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, moderate_report_dto_1.ModerateReportDto]),
    __metadata("design:returntype", void 0)
], AdminReportsController.prototype, "resolve", null);
__decorate([
    (0, common_1.Patch)(':id/reject'),
    __param(0, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, moderate_report_dto_1.ModerateReportDto]),
    __metadata("design:returntype", void 0)
], AdminReportsController.prototype, "reject", null);
__decorate([
    (0, common_1.Patch)(':id/reopen'),
    __param(0, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], AdminReportsController.prototype, "reopen", null);
__decorate([
    (0, common_1.Delete)(':id'),
    __param(0, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], AdminReportsController.prototype, "hide", null);
exports.AdminReportsController = AdminReportsController = __decorate([
    (0, common_1.Controller)('admin/reports'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, admin_guard_1.AdminGuard),
    __metadata("design:paramtypes", [reports_service_1.ReportsService])
], AdminReportsController);
//# sourceMappingURL=reports.controller.js.map