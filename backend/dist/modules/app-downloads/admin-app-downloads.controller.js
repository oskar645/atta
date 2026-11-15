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
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminAppDownloadsController = void 0;
const common_1 = require("@nestjs/common");
const admin_guard_1 = require("../auth/admin.guard");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const admin_app_downloads_service_1 = require("./admin-app-downloads.service");
let AdminAppDownloadsController = class AdminAppDownloadsController {
    constructor(appDownloads) {
        this.appDownloads = appDownloads;
    }
    getAppDownloads() {
        return this.appDownloads.getSnapshot();
    }
};
exports.AdminAppDownloadsController = AdminAppDownloadsController;
__decorate([
    (0, common_1.Get)(),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AdminAppDownloadsController.prototype, "getAppDownloads", null);
exports.AdminAppDownloadsController = AdminAppDownloadsController = __decorate([
    (0, common_1.Controller)('admin/dashboard/app-downloads'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, admin_guard_1.AdminGuard),
    __metadata("design:paramtypes", [admin_app_downloads_service_1.AdminAppDownloadsService])
], AdminAppDownloadsController);
//# sourceMappingURL=admin-app-downloads.controller.js.map