"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AnalyticsSignal = void 0;
const common_1 = require("@nestjs/common");
// Invalidation only: never a counter or a source of truth.
let AnalyticsSignal = class AnalyticsSignal {
    constructor() {
        this.listeners = new Set();
    }
    subscribe(listener) {
        this.listeners.add(listener);
        return () => { this.listeners.delete(listener); };
    }
    changed() {
        for (const listener of this.listeners) {
            try {
                listener();
            }
            catch { /* Analytics must not fail chat writes. */ }
        }
    }
};
exports.AnalyticsSignal = AnalyticsSignal;
exports.AnalyticsSignal = AnalyticsSignal = __decorate([
    (0, common_1.Injectable)()
], AnalyticsSignal);
//# sourceMappingURL=analytics-signal.js.map