"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminDashboardRealtimeModule = void 0;
const common_1 = require("@nestjs/common");
const admin_dashboard_signal_1 = require("./admin-dashboard-signal");
const support_realtime_signal_1 = require("./support-realtime-signal");
let AdminDashboardRealtimeModule = class AdminDashboardRealtimeModule {
};
exports.AdminDashboardRealtimeModule = AdminDashboardRealtimeModule;
exports.AdminDashboardRealtimeModule = AdminDashboardRealtimeModule = __decorate([
    (0, common_1.Global)(),
    (0, common_1.Module)({
        providers: [admin_dashboard_signal_1.AdminDashboardSignal, support_realtime_signal_1.SupportRealtimeSignal],
        exports: [admin_dashboard_signal_1.AdminDashboardSignal, support_realtime_signal_1.SupportRealtimeSignal],
    })
], AdminDashboardRealtimeModule);
//# sourceMappingURL=admin-dashboard-realtime.module.js.map