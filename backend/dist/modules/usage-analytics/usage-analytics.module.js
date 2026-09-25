"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.UsageAnalyticsModule = void 0;
const common_1 = require("@nestjs/common");
const auth_module_1 = require("../auth/auth.module");
const prisma_module_1 = require("../prisma/prisma.module");
const user_blocks_module_1 = require("../user-blocks/user-blocks.module");
const analytics_signal_1 = require("./analytics-signal");
const usage_analytics_service_1 = require("./usage-analytics.service");
const usage_analytics_controller_1 = require("./usage-analytics.controller");
let UsageAnalyticsModule = class UsageAnalyticsModule {
};
exports.UsageAnalyticsModule = UsageAnalyticsModule;
exports.UsageAnalyticsModule = UsageAnalyticsModule = __decorate([
    (0, common_1.Global)(),
    (0, common_1.Module)({
        imports: [auth_module_1.AuthModule, prisma_module_1.PrismaModule, user_blocks_module_1.UserBlocksModule],
        providers: [analytics_signal_1.AnalyticsSignal, usage_analytics_service_1.UsageAnalyticsService],
        controllers: [usage_analytics_controller_1.UsageAnalyticsController],
        exports: [analytics_signal_1.AnalyticsSignal],
    })
], UsageAnalyticsModule);
//# sourceMappingURL=usage-analytics.module.js.map