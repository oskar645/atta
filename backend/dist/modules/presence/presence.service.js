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
exports.PresenceService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../prisma/prisma.service");
const redis_service_1 = require("../redis/redis.service");
let PresenceService = class PresenceService {
    constructor(redisService, prisma) {
        this.redisService = redisService;
        this.prisma = prisma;
        this.ttlSeconds = 120;
    }
    presenceKey(userId) {
        return `presence:user:${userId}`;
    }
    isFresh(lastSeen) {
        return lastSeen.getTime() >= Date.now() - this.ttlSeconds * 1000;
    }
    async formatPresence(userId) {
        const record = await this.prisma.userPresence.findUnique({
            where: {
                userId,
            },
        });
        if (!record) {
            return {
                userId,
                isOnline: false,
                ttlSeconds: this.ttlSeconds,
                lastSeen: null,
            };
        }
        return {
            userId,
            isOnline: record.isOnline && this.isFresh(record.lastSeen),
            ttlSeconds: this.ttlSeconds,
            lastSeen: record.lastSeen.toISOString(),
        };
    }
    async setPresence(userId, isOnline) {
        const key = this.presenceKey(userId);
        const now = new Date();
        if (isOnline) {
            await this.redisService.setWithTtl(key, 'online', this.ttlSeconds);
            await this.prisma.userPresence.upsert({
                where: {
                    userId,
                },
                update: {
                    isOnline: true,
                    lastSeen: now,
                    socketId: null,
                },
                create: {
                    userId,
                    isOnline: true,
                    lastSeen: now,
                },
            });
        }
        else {
            await this.redisService.del(key);
            await this.prisma.userPresence.upsert({
                where: {
                    userId,
                },
                update: {
                    isOnline: false,
                    lastSeen: now,
                },
                create: {
                    userId,
                    isOnline: false,
                    lastSeen: now,
                },
            });
        }
        return this.formatPresence(userId);
    }
    async touchSocket(userId, socketId) {
        const now = new Date();
        await this.redisService.setWithTtl(this.presenceKey(userId), socketId, this.ttlSeconds);
        await this.prisma.userPresence.upsert({
            where: {
                userId,
            },
            update: {
                isOnline: true,
                lastSeen: now,
                socketId,
            },
            create: {
                userId,
                isOnline: true,
                lastSeen: now,
                socketId,
            },
        });
        return this.formatPresence(userId);
    }
    async touchHeartbeat(userId) {
        const current = await this.prisma.userPresence.findUnique({
            where: {
                userId,
            },
        });
        return this.touchSocket(userId, current?.socketId ?? 'heartbeat');
    }
    async disconnectSocket(userId, socketId) {
        const current = await this.prisma.userPresence.findUnique({
            where: {
                userId,
            },
        });
        if (!current) {
            await this.redisService.del(this.presenceKey(userId));
            return {
                userId,
                isOnline: false,
                ttlSeconds: this.ttlSeconds,
                lastSeen: null,
            };
        }
        if (current.socketId && current.socketId != socketId) {
            return this.formatPresence(userId);
        }
        const now = new Date();
        await this.redisService.del(this.presenceKey(userId));
        await this.prisma.userPresence.update({
            where: {
                userId,
            },
            data: {
                isOnline: false,
                lastSeen: now,
                socketId: null,
            },
        });
        return this.formatPresence(userId);
    }
    async getPresence(userId) {
        return this.formatPresence(userId);
    }
    async getPresenceMap(userIds) {
        const uniqueIds = [...new Set(userIds.map((id) => id.trim()).filter(Boolean))];
        if (uniqueIds.length === 0) {
            return new Map();
        }
        const rows = await this.prisma.userPresence.findMany({
            where: {
                userId: {
                    in: uniqueIds,
                },
            },
        });
        const map = new Map();
        for (const id of uniqueIds) {
            map.set(id, {
                isOnline: false,
                lastSeen: null,
            });
        }
        for (const row of rows) {
            map.set(row.userId, {
                isOnline: row.isOnline && this.isFresh(row.lastSeen),
                lastSeen: row.lastSeen.toISOString(),
            });
        }
        return map;
    }
};
exports.PresenceService = PresenceService;
exports.PresenceService = PresenceService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [redis_service_1.RedisService,
        prisma_service_1.PrismaService])
], PresenceService);
//# sourceMappingURL=presence.service.js.map