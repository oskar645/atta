"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminDashboardSignal = exports.ADMIN_DASHBOARD_SCOPES = void 0;
const common_1 = require("@nestjs/common");
exports.ADMIN_DASHBOARD_SCOPES = [
    'users',
    'presence',
    'visits',
    'usage',
    'listings',
    'wallet',
    'payments',
    'promotions',
    'support',
    'reports',
    'ads',
    'searches',
];
let AdminDashboardSignal = class AdminDashboardSignal {
    constructor() {
        this.listeners = new Set();
        this.pending = new Set();
    }
    subscribe(listener) {
        this.listeners.add(listener);
        return () => this.listeners.delete(listener);
    }
    changed(...scopes) {
        for (const scope of scopes)
            this.pending.add(scope);
        if (this.timer || this.pending.size === 0)
            return;
        this.timer = setTimeout(() => this.flush(), 500);
    }
    flush() {
        if (this.timer)
            clearTimeout(this.timer);
        this.timer = undefined;
        if (this.pending.size === 0)
            return;
        const scopes = [...this.pending];
        this.pending.clear();
        for (const listener of this.listeners) {
            try {
                listener(scopes);
            }
            catch {
                // Dashboard invalidation must never affect the completed business write.
            }
        }
    }
    onModuleDestroy() {
        if (this.timer)
            clearTimeout(this.timer);
        this.timer = undefined;
        this.pending.clear();
        this.listeners.clear();
    }
};
exports.AdminDashboardSignal = AdminDashboardSignal;
exports.AdminDashboardSignal = AdminDashboardSignal = __decorate([
    (0, common_1.Injectable)()
], AdminDashboardSignal);
//# sourceMappingURL=admin-dashboard-signal.js.map