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
exports.AppController = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("./modules/prisma/prisma.service");
const redis_service_1 = require("./modules/redis/redis.service");
const storage_service_1 = require("./modules/storage/storage.service");
let AppController = class AppController {
    constructor(prisma, redisService, storageService) {
        this.prisma = prisma;
        this.redisService = redisService;
        this.storageService = storageService;
    }
    getHealth() {
        return { status: 'ok' };
    }
    async getDependenciesHealth() {
        const [database, redis, storage] = await Promise.all([
            this.checkDatabaseHealth(),
            this.checkRedisHealth(),
            this.storageService.getHealthStatus(),
        ]);
        return {
            api: 'ok',
            database,
            redis,
            storage: storage.status,
            storage_message: storage.message ?? null,
        };
    }
    async checkDatabaseHealth() {
        try {
            await this.prisma.$queryRaw `SELECT 1`;
            return 'ok';
        }
        catch {
            return 'error';
        }
    }
    async checkRedisHealth() {
        try {
            const result = await this.redisService.ping();
            return result === 'PONG' ? 'ok' : 'error';
        }
        catch {
            return 'error';
        }
    }
};
exports.AppController = AppController;
__decorate([
    (0, common_1.Get)('health'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AppController.prototype, "getHealth", null);
__decorate([
    (0, common_1.Get)('health/dependencies'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], AppController.prototype, "getDependenciesHealth", null);
exports.AppController = AppController = __decorate([
    (0, common_1.Controller)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        redis_service_1.RedisService,
        storage_service_1.StorageService])
], AppController);
//# sourceMappingURL=app.controller.js.map