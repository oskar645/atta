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
exports.JwtAuthGuard = void 0;
const common_1 = require("@nestjs/common");
const jwt_1 = require("@nestjs/jwt");
const client_1 = require("@prisma/client");
const env_1 = require("../../config/env");
const phone_1 = require("../../common/phone");
const env_2 = require("../../config/env");
const prisma_service_1 = require("../prisma/prisma.service");
const user_blocks_service_1 = require("../user-blocks/user-blocks.service");
let JwtAuthGuard = class JwtAuthGuard {
    constructor(jwtService, prisma, userBlocksService) {
        this.jwtService = jwtService;
        this.prisma = prisma;
        this.userBlocksService = userBlocksService;
    }
    async canActivate(context) {
        const request = context.switchToHttp().getRequest();
        const authorizationHeader = request.headers?.authorization;
        const rawHeader = Array.isArray(authorizationHeader)
            ? authorizationHeader[0]
            : authorizationHeader;
        if (!rawHeader?.startsWith('Bearer ')) {
            throw new common_1.UnauthorizedException('Authorization header is missing');
        }
        const token = rawHeader.slice('Bearer '.length).trim();
        if (!token) {
            throw new common_1.UnauthorizedException('Access token is missing');
        }
        let payload;
        try {
            payload = await this.jwtService.verifyAsync(token, {
                secret: env_2.env.JWT_ACCESS_SECRET,
            });
        }
        catch {
            throw new common_1.UnauthorizedException('Access token is invalid or expired');
        }
        if (payload.type !== 'access') {
            throw new common_1.UnauthorizedException('Access token type is invalid');
        }
        const session = await this.prisma.userSession.findFirst({
            where: {
                id: payload.sessionId,
                userId: payload.sub,
                revokedAt: null,
            },
            select: {
                id: true,
                expiresAt: true,
                user: {
                    select: {
                        id: true,
                        email: true,
                        phone: true,
                        status: true,
                        deletedAt: true,
                        adminProfile: {
                            select: {
                                isAdmin: true,
                            },
                        },
                    },
                },
            },
        });
        if (!session) {
            throw new common_1.UnauthorizedException('Session is not active');
        }
        if (session.expiresAt.getTime() <= Date.now()) {
            throw new common_1.UnauthorizedException('Session has expired');
        }
        if (session.user.status === client_1.UserStatus.DELETED || session.user.deletedAt) {
            throw new common_1.UnauthorizedException('User account is deleted');
        }
        const authUser = {
            userId: session.user.id,
            sessionId: session.id,
            email: session.user.email,
            role: this.resolveRole(session.user.adminProfile?.isAdmin === true, session.user.phone),
        };
        request.authUser = authUser;
        if (authUser.role !== 'admin' && this.shouldBlockWriteRequest(request)) {
            const block = await this.userBlocksService.getActiveBlock(authUser.userId);
            if (block) {
                throw new common_1.ForbiddenException({
                    code: 'ACCOUNT_BLOCKED',
                    message: 'Аккаунт заблокирован',
                    blockId: block.id,
                    reason: block.reason,
                    endsAt: block.endsAt?.toISOString() ?? null,
                    permanent: block.type === 'PERMANENT',
                });
            }
        }
        return true;
    }
    shouldBlockWriteRequest(request) {
        const method = (request.method ?? 'GET').toUpperCase();
        if (method === 'GET' || method === 'HEAD' || method === 'OPTIONS') {
            return false;
        }
        const path = (request.path ?? request.url ?? '').split('?')[0] ?? '';
        if (path === '/auth/logout')
            return false;
        if (path.startsWith('/support'))
            return false;
        return true;
    }
    resolveRole(isAdminFromDb, phone) {
        if (isAdminFromDb) {
            return 'admin';
        }
        const normalizedPhone = (0, phone_1.normalizeRussianPhone)(phone ?? '');
        if (!normalizedPhone) {
            return 'user';
        }
        return new Set((0, env_1.parseAdminPhoneNumbers)()).has(normalizedPhone)
            ? 'admin'
            : 'user';
    }
};
exports.JwtAuthGuard = JwtAuthGuard;
exports.JwtAuthGuard = JwtAuthGuard = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [jwt_1.JwtService,
        prisma_service_1.PrismaService,
        user_blocks_service_1.UserBlocksService])
], JwtAuthGuard);
//# sourceMappingURL=jwt-auth.guard.js.map