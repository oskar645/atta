"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.RateLimitService = void 0;
const common_1 = require("@nestjs/common");
let RateLimitService = class RateLimitService {
    constructor() {
        this.buckets = new Map();
    }
    consumeOrThrow(key, { limit, windowMs, message = 'Слишком много запросов. Попробуйте позже.', }) {
        const now = Date.now();
        const current = this.buckets.get(key);
        if (!current || current.resetAt <= now) {
            this.buckets.set(key, {
                count: 1,
                resetAt: now + windowMs,
            });
            return;
        }
        if (current.count >= limit) {
            throw new common_1.HttpException(message, common_1.HttpStatus.TOO_MANY_REQUESTS);
        }
        current.count += 1;
        this.buckets.set(key, current);
    }
};
exports.RateLimitService = RateLimitService;
exports.RateLimitService = RateLimitService = __decorate([
    (0, common_1.Injectable)()
], RateLimitService);
//# sourceMappingURL=rate-limit.service.js.map