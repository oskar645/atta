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
exports.AccountRecoveryService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const crypto_1 = require("crypto");
const phone_1 = require("../../common/phone");
const email_service_1 = require("../email/email.service");
const phone_verification_service_1 = require("../phone-verification/phone-verification.service");
const prisma_service_1 = require("../prisma/prisma.service");
const rate_limit_service_1 = require("../rate-limit/rate-limit.service");
const auth_service_1 = require("./auth.service");
const CODE_TTL_MS = 10 * 60_000;
const RESEND_MS = 60_000;
const GRANT_TTL_MS = 15 * 60_000;
const NEUTRAL_MESSAGE = 'Если этот email был подтверждён в ATTA, мы отправили код.';
let AccountRecoveryService = class AccountRecoveryService {
    constructor(prisma, rateLimit, email, phoneVerification, auth) {
        this.prisma = prisma;
        this.rateLimit = rateLimit;
        this.email = email;
        this.phoneVerification = phoneVerification;
        this.auth = auth;
    }
    async startRecoveryEmail(userId, rawEmail, source = {}) {
        this.email.ensureAvailable();
        const email = this.normalizeEmail(rawEmail);
        await this.limitStart('settings', email, userId, source);
        const duplicate = await this.prisma.user.findFirst({
            where: { email: { equals: email, mode: 'insensitive' }, id: { not: userId } },
            select: { id: true },
        });
        if (duplicate)
            throw new common_1.ConflictException('Этот email уже используется');
        const challenge = await this.createChallenge(userId, client_1.EmailChallengePurpose.RECOVERY_EMAIL, email, source);
        // A client can lose the HTTP response after SMTP has accepted the email.
        // During the cooldown, acknowledge the already-created challenge instead
        // of creating/sending another one. This also lets older clients recover by
        // pressing the button again after a transport timeout.
        if (challenge.code)
            await this.email.sendVerificationCode({ to: email, code: challenge.code });
        return this.challengeResponse(challenge.id, email, 'Код отправлен', challenge.resendAfter);
    }
    async verifyRecoveryEmail(userId, challengeId, code) {
        const challenge = await this.consumeCode(challengeId, code, client_1.EmailChallengePurpose.RECOVERY_EMAIL, userId);
        const previous = await this.prisma.$transaction(async (tx) => {
            const user = await tx.user.findUniqueOrThrow({ where: { id: userId }, select: { email: true, emailVerifiedAt: true } });
            const duplicate = await tx.user.findFirst({ where: { email: { equals: challenge.targetEmail, mode: 'insensitive' }, id: { not: userId } }, select: { id: true } });
            if (duplicate)
                throw new common_1.ConflictException('Этот email уже используется');
            await tx.user.update({ where: { id: userId }, data: { email: challenge.targetEmail, emailVerifiedAt: new Date() } });
            const consumed = await tx.emailChallenge.updateMany({ where: { id: challenge.id, consumedAt: null }, data: { consumedAt: new Date() } });
            if (consumed.count !== 1)
                throw this.invalidCode();
            return user.emailVerifiedAt ? user.email : null;
        });
        if (previous && previous.toLowerCase() !== challenge.targetEmail) {
            this.email.sendRecoveryEmailChanged({ to: previous }).catch(() => undefined);
        }
        return { verified: true, email: this.maskEmail(challenge.targetEmail), emailVerifiedAt: new Date().toISOString() };
    }
    async startAccountRecovery(rawEmail, source = {}) {
        this.email.ensureAvailable();
        const email = this.normalizeEmail(rawEmail);
        await this.limitStart('account', email, undefined, source);
        const user = await this.prisma.user.findFirst({
            where: { email: { equals: email, mode: 'insensitive' }, emailVerifiedAt: { not: null }, deletedAt: null, status: client_1.UserStatus.ACTIVE },
            select: { id: true },
        });
        const publicChallengeId = (0, crypto_1.randomUUID)();
        if (!user)
            return { status: 'ok', message: NEUTRAL_MESSAGE, challengeId: publicChallengeId, expiresIn: 600, resendAfter: 60 };
        const challenge = await this.createChallenge(user.id, client_1.EmailChallengePurpose.ACCOUNT_RECOVERY, email, source, publicChallengeId);
        // Keep the public response indistinguishable even during a transient SMTP
        // delivery failure. Missing SMTP configuration was rejected above for all
        // addresses before the account lookup.
        await this.email.sendVerificationCode({ to: email, code: challenge.code }).catch(() => undefined);
        return { status: 'ok', message: NEUTRAL_MESSAGE, challengeId: challenge.id, expiresIn: 600, resendAfter: 60 };
    }
    async verifyAccountRecoveryEmail(challengeId, code, source = {}) {
        await this.rateLimit.consumeOrThrow(`recovery:verify:${this.digest(source.ip ?? 'unknown')}`, { limit: 20, windowMs: 60_000 });
        const challenge = await this.consumeCode(challengeId, code, client_1.EmailChallengePurpose.ACCOUNT_RECOVERY);
        if (!challenge.userId)
            throw this.invalidCode();
        const token = (0, crypto_1.randomBytes)(32).toString('base64url');
        await this.prisma.$transaction(async (tx) => {
            const consumed = await tx.emailChallenge.updateMany({ where: { id: challenge.id, consumedAt: null }, data: { consumedAt: new Date() } });
            if (consumed.count !== 1)
                throw this.invalidCode();
            await tx.accountRecoveryGrant.create({ data: { userId: challenge.userId, tokenHash: this.digest(token), expiresAt: new Date(Date.now() + GRANT_TTL_MS) } });
        });
        return { recoveryToken: token, expiresIn: 900 };
    }
    async startPhone(token, rawPhone, source = {}) {
        const grant = await this.validGrant(token);
        const phone = (0, phone_1.normalizeRussianPhone)(rawPhone);
        (0, phone_1.validateRussianPhoneOrThrow)(phone);
        await this.assertPhoneAvailable(phone, grant.userId);
        const result = await this.phoneVerification.startCallVerification(phone, 'change_phone', source, {
            id: (0, crypto_1.randomUUID)(), metadata: { accountRecovery: { grantId: grant.id } },
        });
        return { ...result, phone };
    }
    async completePhone(token, rawPhone, checkId) {
        const grant = await this.validGrant(token);
        const phone = (0, phone_1.normalizeRussianPhone)(rawPhone);
        (0, phone_1.validateRussianPhoneOrThrow)(phone);
        await this.assertPhoneAvailable(phone, grant.userId);
        const verification = await this.phoneVerification.checkCallVerification(phone, checkId, 'change_phone');
        if (verification.status !== 'confirmed')
            return verification;
        const response = await this.auth.completeAccountRecovery(grant.id, this.digest(token), phone);
        const user = await this.prisma.user.findUnique({ where: { id: grant.userId }, select: { email: true, emailVerifiedAt: true } });
        if (user?.email && user.emailVerifiedAt)
            this.email.sendRecoveryCompleted({ to: user.email }).catch(() => undefined);
        return response;
    }
    async createChallenge(userId, purpose, email, source, id = (0, crypto_1.randomUUID)()) {
        const latest = await this.prisma.emailChallenge.findFirst({ where: { userId, purpose, targetEmail: email }, orderBy: { createdAt: 'desc' } });
        if (latest && latest.resendAvailableAt.getTime() > Date.now()) {
            const retryAfter = Math.ceil((latest.resendAvailableAt.getTime() - Date.now()) / 1000);
            if (purpose === client_1.EmailChallengePurpose.RECOVERY_EMAIL)
                return { id: latest.id, resendAfter: retryAfter };
            throw new common_1.BadRequestException({ code: 'EMAIL_COOLDOWN', retryAfter: Math.ceil((latest.resendAvailableAt.getTime() - Date.now()) / 1000), message: 'Код уже отправлен' });
        }
        const code = (0, crypto_1.randomInt)(0, 1_000_000).toString().padStart(6, '0');
        await this.prisma.emailChallenge.create({ data: { id, userId, purpose, targetEmail: email, codeHash: this.digest(`${id}:${code}`), expiresAt: new Date(Date.now() + CODE_TTL_MS), resendAvailableAt: new Date(Date.now() + RESEND_MS), requestedByIp: source.ip, requestedByDevice: source.deviceId, metadata: {} } });
        return { id, code, resendAfter: RESEND_MS / 1000 };
    }
    async consumeCode(id, code, purpose, userId) {
        const challenge = await this.prisma.emailChallenge.findFirst({ where: { id, purpose, ...(userId ? { userId } : {}) } });
        if (!challenge || challenge.consumedAt || challenge.expiresAt.getTime() <= Date.now() || challenge.attempts >= challenge.maxAttempts)
            throw this.invalidCode();
        const actual = Buffer.from(this.digest(`${id}:${code}`));
        const expected = Buffer.from(challenge.codeHash);
        const correct = actual.length === expected.length && (0, crypto_1.timingSafeEqual)(actual, expected);
        if (!correct) {
            await this.prisma.emailChallenge.update({ where: { id }, data: { attempts: { increment: 1 } } });
            throw this.invalidCode();
        }
        return challenge;
    }
    async validGrant(token) {
        const grant = await this.prisma.accountRecoveryGrant.findUnique({ where: { tokenHash: this.digest(token) } });
        if (!grant || grant.consumedAt || grant.expiresAt.getTime() <= Date.now())
            throw new common_1.BadRequestException('Сессия восстановления недействительна или истекла');
        return grant;
    }
    async assertPhoneAvailable(phone, userId) {
        const occupied = await this.prisma.user.findFirst({ where: { phone, id: { not: userId }, deletedAt: null }, select: { id: true } });
        if (occupied)
            throw new common_1.ConflictException('Этот номер уже используется');
    }
    async limitStart(scope, email, userId, source = {}) {
        await Promise.all([
            this.rateLimit.consumeOrThrow(`email:${scope}:ip:${this.digest(source.ip ?? 'unknown')}`, { limit: 8, windowMs: 60 * 60_000 }),
            this.rateLimit.consumeOrThrow(`email:${scope}:address:${this.digest(email)}`, { limit: 5, windowMs: 60 * 60_000 }),
            ...(userId ? [this.rateLimit.consumeOrThrow(`email:${scope}:user:${userId}`, { limit: 5, windowMs: 60 * 60_000 })] : []),
        ]);
    }
    normalizeEmail(value) { return value.trim().toLowerCase(); }
    digest(value) { return (0, crypto_1.createHash)('sha256').update(value).digest('hex'); }
    maskEmail(value) { const [local, domain] = value.split('@'); return `${local[0]}***@${domain}`; }
    invalidCode() { return new common_1.BadRequestException('Неверный или истёкший код'); }
    challengeResponse(id, email, message, resendAfter = 60) { return { challengeId: id, maskedEmail: this.maskEmail(email), expiresIn: 600, resendAfter, message }; }
};
exports.AccountRecoveryService = AccountRecoveryService;
exports.AccountRecoveryService = AccountRecoveryService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        rate_limit_service_1.RateLimitService,
        email_service_1.EmailService,
        phone_verification_service_1.PhoneVerificationService,
        auth_service_1.AuthService])
], AccountRecoveryService);
//# sourceMappingURL=account-recovery.service.js.map