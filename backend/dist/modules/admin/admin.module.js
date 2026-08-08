"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminModule = void 0;
const common_1 = require("@nestjs/common");
const auth_module_1 = require("../auth/auth.module");
const app_visits_module_1 = require("../app-visits/app-visits.module");
const notifications_module_1 = require("../notifications/notifications.module");
const reviews_module_1 = require("../reviews/reviews.module");
const storage_module_1 = require("../storage/storage.module");
const user_blocks_module_1 = require("../user-blocks/user-blocks.module");
const support_module_1 = require("../support/support.module");
const admin_controller_1 = require("./admin.controller");
const admin_service_1 = require("./admin.service");
let AdminModule = class AdminModule {
};
exports.AdminModule = AdminModule;
exports.AdminModule = AdminModule = __decorate([
    (0, common_1.Module)({
        imports: [
            app_visits_module_1.AppVisitsModule,
            auth_module_1.AuthModule,
            notifications_module_1.NotificationsModule,
            reviews_module_1.ReviewsModule,
            storage_module_1.StorageModule,
            support_module_1.SupportModule,
            user_blocks_module_1.UserBlocksModule,
        ],
        controllers: [admin_controller_1.AdminController],
        providers: [admin_service_1.AdminService],
        exports: [admin_service_1.AdminService],
    })
], AdminModule);
//# sourceMappingURL=admin.module.js.map