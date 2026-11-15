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
exports.ContactLinkService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const crypto_1 = require("crypto");
const phone_1 = require("../../common/phone");
const phone_verification_service_1 = require("../phone-verification/phone-verification.service");
const prisma_service_1 = require("../prisma/prisma.service");
const RECENT_AUTH_MS = 15 * 60_000;
let ContactLinkService = class ContactLinkService {
    constructor(prisma, phoneVerification) {
        this.prisma = prisma;
        this.phoneVerification = phoneVerification;
    }
    async startPhone(authUser, rawPhone, source) {
        await this.assertRecentAuthentication(authUser);
        const phone = (0, phone_1.normalizeRussianPhone)(rawPhone);
        (0, phone_1.validateRussianPhoneOrThrow)(phone);
        await this.assertPhoneAvailable(phone, authUser.userId);
        return this.phoneVerification.startCallVerification(phone, 'change_phone', source, {
            id: (0, crypto_1.randomUUID)(),
            metadata: {
                contactLink: {
                    version: 1,
                    userId: authUser.userId,
                    sessionId: authUser.sessionId,
                    state: 'pending',
                },
            },
        });
    }
    async completePhone(authUser, rawPhone, verificationId) {
        await this.assertRecentAuthentication(authUser);
        const phone = (0, phone_1.normalizeRussianPhone)(rawPhone);
        (0, phone_1.validateRussianPhoneOrThrow)(phone);
        await this.assertPhoneAvailable(phone, authUser.userId);
        const result = await this.phoneVerification.checkCallVerification(phone, verificationId, 'change_phone');
        if (result.status !== 'confirmed')
            return result;
        return this.prisma.$transaction(async (tx) => {
            await tx.$queryRaw `
        SELECT id FROM phone_verifications
        WHERE phone = ${phone} AND provider_check_id = ${verificationId}
        FOR UPDATE
      `;
            const verification = await tx.phoneVerification.findFirst({
                where: {
                    phone,
                    checkId: verificationId,
                    purpose: client_1.PhoneVerificationPurpose.CHANGE_PHONE,
                    status: 'CONFIRMED',
                },
            });
            const metadata = verification?.metadata;
            const link = metadata?.contactLink;
            if (!verification ||
                verification.expiresAt.getTime() <= Date.now() ||
                link?.version !== 1 ||
                link?.userId !== authUser.userId ||
                link?.sessionId !== authUser.sessionId ||
                link?.state !== 'pending') {
                throw new common_1.BadRequestException('PHONE_LINK_VERIFICATION_INVALID');
            }
            await this.assertPhoneAvailable(phone, authUser.userId, tx);
            const user = await tx.user.update({
                where: { id: authUser.userId },
                data: { phone, phoneVerified: true },
            });
            await tx.phoneVerification.update({
                where: { id: verification.id },
                data: {
                    createdUserId: authUser.userId,
                    metadata: {
                        ...metadata,
                        contactLink: {
                            ...link,
                            state: 'consumed',
                            consumedAt: new Date().toISOString(),
                        },
                    },
                },
            });
            return {
                status: 'confirmed',
                phone: user.phone,
                phoneVerified: user.phoneVerified,
            };
        });
    }
    async assertRecentAuthentication(authUser) {
        const session = await this.prisma.userSession.findFirst({
            where: {
                id: authUser.sessionId,
                userId: authUser.userId,
                revokedAt: null,
                createdAt: { gte: new Date(Date.now() - RECENT_AUTH_MS) },
            },
            select: { id: true },
        });
        if (!session) {
            throw new common_1.UnauthorizedException({
                code: 'RECENT_AUTH_REQUIRED',
                message: 'Для изменения способов входа войдите в аккаунт заново.',
            });
        }
    }
    async assertPhoneAvailable(phone, userId, tx) {
        const prisma = tx ?? this.prisma;
        const occupied = await prisma.user.findFirst({
            where: {
                phone,
                id: { not: userId },
                deletedAt: null,
                status: { not: client_1.UserStatus.DELETED },
            },
            select: { id: true },
        });
        if (occupied)
            throw new common_1.ConflictException('Этот номер уже используется');
    }
};
exports.ContactLinkService = ContactLinkService;
exports.ContactLinkService = ContactLinkService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        phone_verification_service_1.PhoneVerificationService])
], ContactLinkService);
//# sourceMappingURL=contact-link.service.js.map