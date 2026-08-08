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
exports.UserBlocksService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const serializers_1 = require("../../common/serializers");
const prisma_service_1 = require("../prisma/prisma.service");
let UserBlocksService = class UserBlocksService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    serializeBlock(block) {
        if (!block)
            return null;
        return {
            id: block.id,
            user_id: block.userId,
            listing_id: block.listingId ?? null,
            admin_id: block.adminId,
            type: block.type.toLowerCase(),
            status: block.status.toLowerCase(),
            reason: block.reason,
            internal_note: block.internalNote ?? null,
            starts_at: block.startsAt.toISOString(),
            ends_at: (0, serializers_1.toIsoString)(block.endsAt),
            lifted_at: (0, serializers_1.toIsoString)(block.liftedAt),
            lifted_by_admin_id: block.liftedByAdminId ?? null,
            lift_reason: block.liftReason ?? null,
            permanent: block.type === 'PERMANENT',
            created_at: block.createdAt.toISOString(),
            updated_at: block.updatedAt.toISOString(),
        };
    }
    async getActiveBlock(userId) {
        const now = new Date();
        await this.prisma.userBlock.updateMany({
            where: {
                userId,
                status: client_1.UserBlockStatus.ACTIVE,
                endsAt: {
                    not: null,
                    lte: now,
                },
            },
            data: {
                status: client_1.UserBlockStatus.EXPIRED,
            },
        });
        await this.prisma.blockedIdentity.updateMany({
            where: {
                liftedAt: null,
                permanent: false,
                bannedUntil: {
                    not: null,
                    lte: now,
                },
            },
            data: {
                liftedAt: now,
            },
        });
        const block = await this.prisma.userBlock.findFirst({
            where: {
                userId,
                status: client_1.UserBlockStatus.ACTIVE,
                OR: [{ endsAt: null }, { endsAt: { gt: now } }],
            },
            orderBy: {
                startsAt: 'desc',
            },
        });
        if (!block) {
            await this.prisma.user.updateMany({
                where: {
                    id: userId,
                    status: client_1.UserStatus.BLOCKED,
                },
                data: {
                    status: client_1.UserStatus.ACTIVE,
                    blockedAt: null,
                    blockReason: null,
                },
            });
        }
        return block;
    }
    async assertNotBlocked(userId) {
        const block = await this.getActiveBlock(userId);
        if (!block)
            return;
        throw new common_1.ForbiddenException({
            code: 'ACCOUNT_BLOCKED',
            message: 'Аккаунт заблокирован',
            blockId: block.id,
            reason: block.reason,
            endsAt: (0, serializers_1.toIsoString)(block.endsAt),
            permanent: block.type === 'PERMANENT',
        });
    }
};
exports.UserBlocksService = UserBlocksService;
exports.UserBlocksService = UserBlocksService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], UserBlocksService);
//# sourceMappingURL=user-blocks.service.js.map