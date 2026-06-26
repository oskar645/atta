"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.RedisService = void 0;
const common_1 = require("@nestjs/common");
const ioredis_1 = __importDefault(require("ioredis"));
const env_1 = require("../../config/env");
let RedisService = class RedisService {
    constructor() {
        this.client = null;
    }
    getClient() {
        if (!this.client) {
            this.client = new ioredis_1.default(env_1.env.REDIS_URL, {
                lazyConnect: true,
                maxRetriesPerRequest: 1,
            });
        }
        return this.client;
    }
    async ping() {
        const client = this.getClient();
        return client.ping();
    }
    async setWithTtl(key, value, ttlSeconds) {
        const client = this.getClient();
        await client.set(key, value, 'EX', ttlSeconds);
        return {
            ok: true,
            message: 'Redis TTL write completed',
            redisUrl: env_1.env.REDIS_URL,
        };
    }
    async del(key) {
        const client = this.getClient();
        await client.del(key);
        return {
            ok: true,
            message: 'Redis delete completed',
        };
    }
    async get(key) {
        const client = this.getClient();
        return client.get(key);
    }
    async onModuleDestroy() {
        if (this.client) {
            await this.client.quit();
            this.client = null;
        }
    }
};
exports.RedisService = RedisService;
exports.RedisService = RedisService = __decorate([
    (0, common_1.Injectable)()
], RedisService);
//# sourceMappingURL=redis.service.js.map