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
var RateLimitService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.RateLimitService = void 0;
const common_1 = require("@nestjs/common");
const redis_service_1 = require("../redis/redis.service");
let RateLimitService = RateLimitService_1 = class RateLimitService {
    constructor(redisService) {
        this.redisService = redisService;
        this.logger = new common_1.Logger(RateLimitService_1.name);
        this.buckets = new Map();
        this.lastRedisWarningAt = 0;
    }
    async consumeOrThrow(key, { limit, windowMs, message = 'Слишком много запросов. Попробуйте позже.', }) {
        const redisCount = await this.consumeRedis(key, windowMs);
        if (redisCount != null) {
            if (redisCount > limit) {
                throw new common_1.HttpException(message, common_1.HttpStatus.TOO_MANY_REQUESTS);
            }
            return;
        }
        this.consumeMemoryOrThrow(key, { limit, windowMs, message });
    }
    async countUniqueValues(key, value, windowMs) {
        const ttlSeconds = this.toTtlSeconds(windowMs);
        try {
            await this.redisService.sadd(key, value);
            const ttl = await this.redisService.ttl(key);
            if (ttl < 0) {
                await this.redisService.expire(key, ttlSeconds);
            }
            return this.redisService.scard(key);
        }
        catch (error) {
            this.warnRedisFallback(error);
            return null;
        }
    }
    async debounce(key, windowMs) {
        try {
            const result = await this.redisService.setNxWithTtl(key, '1', this.toTtlSeconds(windowMs));
            return result === 'OK';
        }
        catch (error) {
            this.warnRedisFallback(error);
            return true;
        }
    }
    async consumeRedis(key, windowMs) {
        try {
            const count = await this.redisService.incr(key);
            if (count === 1) {
                await this.redisService.expire(key, this.toTtlSeconds(windowMs));
            }
            return count;
        }
        catch (error) {
            this.warnRedisFallback(error);
            return null;
        }
    }
    consumeMemoryOrThrow(key, { limit, windowMs, message, }) {
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
    toTtlSeconds(windowMs) {
        return Math.max(1, Math.ceil(windowMs / 1000));
    }
    warnRedisFallback(error) {
        const now = Date.now();
        if (now - this.lastRedisWarningAt < 30_000) {
            return;
        }
        this.lastRedisWarningAt = now;
        this.logger.warn(`Redis rate-limit storage unavailable; using local fallback where possible: ${error instanceof Error ? error.message : String(error)}`);
    }
};
exports.RateLimitService = RateLimitService;
exports.RateLimitService = RateLimitService = RateLimitService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [redis_service_1.RedisService])
], RateLimitService);
//# sourceMappingURL=rate-limit.service.js.map