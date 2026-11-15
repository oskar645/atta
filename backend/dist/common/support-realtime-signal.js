"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.SupportRealtimeSignal = void 0;
const common_1 = require("@nestjs/common");
let SupportRealtimeSignal = class SupportRealtimeSignal {
    constructor() {
        this.listeners = new Set();
    }
    subscribe(listener) {
        this.listeners.add(listener);
        return () => this.listeners.delete(listener);
    }
    changed(event) {
        for (const listener of this.listeners) {
            try {
                listener(event);
            }
            catch {
                // Realtime invalidation must never affect a committed support write.
            }
        }
    }
    onModuleDestroy() {
        this.listeners.clear();
    }
};
exports.SupportRealtimeSignal = SupportRealtimeSignal;
exports.SupportRealtimeSignal = SupportRealtimeSignal = __decorate([
    (0, common_1.Injectable)()
], SupportRealtimeSignal);
//# sourceMappingURL=support-realtime-signal.js.map