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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.EmailPasswordlessService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const crypto_1 = require("crypto");
const admin_dashboard_signal_1 = require("../../common/admin-dashboard-signal");
const env_1 = require("../../config/env");
const email_service_1 = require("../email/email.service");
const prisma_service_1 = require("../prisma/prisma.service");
const rate_limit_service_1 = require("../rate-limit/rate-limit.service");
const auth_service_1 = require("./auth.service");
const legal_document_version_1 = require("./legal-document-version");
const CODE_TTL_MS = 10 * 60_000;
const RESEND_MS = 60_000;
const REGISTRATION_TTL_MS = 5 * 60_000;
const PURPOSE = client_1.EmailChallengePurpose.EMAIL_AUTH;
const NEUTRAL_MESSAGE = 'Если адрес доступен для входа, мы отправили код.';
let EmailPasswordlessService = class EmailPasswordlessService {
    constructor(prisma, rateLimit, emailService, auth, adminDashboardSignal) {
        this.prisma = prisma;
        this.rateLimit = rateLimit;
        this.emailService = emailService;
        this.auth = auth;
        this.adminDashboardSignal = adminDashboardSignal;
    }
    async start(rawEmail, source = {}) {
        this.emailService.ensureAvailable();
        const email = this.normalizeEmail(rawEmail);
        await this.limitStart(email, source);
        const latest = await this.prisma.emailChallenge.findFirst({
            where: { purpose: PURPOSE, targetEmail: email, consumedAt: null },
            orderBy: { createdAt: 'desc' },
        });
        if (latest && latest.resendAvailableAt.getTime() > Date.now()) {
            return this.startResponse(latest.id, email, Math.ceil((latest.resendAvailableAt.getTime() - Date.now()) / 1000));
        }
        const user = await this.prisma.user.findFirst({
            where: {
                email: { equals: email, mode: 'insensitive' },
                emailVerifiedAt: { not: null },
                deletedAt: null,
                status: client_1.UserStatus.ACTIVE,
            },
            select: { id: true },
        });
        const id = (0, crypto_1.randomUUID)();
        const code = (0, crypto_1.randomInt)(0, 1_000_000).toString().padStart(6, '0');
        const now = Date.now();
        await this.prisma.$transaction(async (tx) => {
            await tx.emailChallenge.updateMany({
                where: { purpose: PURPOSE, targetEmail: email, consumedAt: null },
                data: { consumedAt: new Date() },
            });
            await tx.emailChallenge.create({
                data: {
                    id,
                    userId: user?.id,
                    purpose: PURPOSE,
                    targetEmail: email,
                    codeHash: this.codeDigest(id, code),
                    expiresAt: new Date(now + CODE_TTL_MS),
                    resendAvailableAt: new Date(now + RESEND_MS),
                    requestedByIp: source.ip,
                    requestedByDevice: source.deviceId || null,
                    metadata: {
                        emailPasswordless: {
                            version: 1,
                            state: 'pending',
                        },
                    },
                },
            });
        });
        await this.emailService.sendLoginCode({ to: email, code });
        return this.startResponse(id, email, 60);
    }
    async check(id, code, source = {}) {
        this.assertUuid(id);
        await Promise.all([
            this.rateLimit.consumeOrThrow(`email-auth:check:${id}`, {
                limit: 10,
                windowMs: 10 * 60_000,
            }),
            this.rateLimit.consumeOrThrow(`email-auth:check-ip:${this.digest(source.ip ?? 'unknown')}`, { limit: 30, windowMs: 10 * 60_000 }),
        ]);
        const result = await this.prisma.$transaction(async (tx) => {
            const challenge = await this.lockChallenge(tx, id);
            const capability = this.capability(challenge.metadata);
            if (capability.state === 'consumed') {
                if (!capability.authResponse)
                    throw this.invalidCode();
                return capability.authResponse;
            }
            this.assertLive(challenge);
            const codeCorrect = await this.isCodeCorrect(tx, challenge, code);
            if (!codeCorrect)
                return { emailCodeInvalid: true };
            if (capability.state === 'registration') {
                return this.registrationResponse(challenge, capability);
            }
            const user = await tx.user.findFirst({
                where: {
                    email: { equals: challenge.targetEmail, mode: 'insensitive' },
                    emailVerifiedAt: { not: null },
                    deletedAt: null,
                    status: client_1.UserStatus.ACTIVE,
                },
                include: { adminProfile: true },
            });
            if (user) {
                const response = await this.auth.authenticateEmailPasswordless(challenge.targetEmail, tx);
                if (!response)
                    throw this.invalidCode();
                await tx.emailChallenge.update({
                    where: { id },
                    data: {
                        consumedAt: new Date(),
                        metadata: {
                            emailPasswordless: {
                                ...capability,
                                state: 'consumed',
                                authResponse: response,
                            },
                        },
                    },
                });
                return response;
            }
            const registrationExpiresAt = new Date(Math.min(challenge.expiresAt.getTime(), Date.now() + REGISTRATION_TTL_MS));
            const next = {
                ...capability,
                state: 'registration',
                registrationExpiresAt: registrationExpiresAt.toISOString(),
            };
            await tx.emailChallenge.update({
                where: { id },
                data: {
                    metadata: {
                        emailPasswordless: next,
                    },
                },
            });
            return this.registrationResponse(challenge, next);
        });
        if (typeof result === 'object' &&
            result != null &&
            'emailCodeInvalid' in result) {
            throw this.invalidCode();
        }
        return result;
    }
    async complete(payload, source = {}) {
        const id = this.parseRegistrationToken(payload.registrationToken);
        await Promise.all([
            this.rateLimit.consumeOrThrow(`email-auth:complete:${id}`, {
                limit: 6,
                windowMs: 10 * 60_000,
            }),
            this.rateLimit.consumeOrThrow(`email-auth:complete-ip:${this.digest(source.ip ?? 'unknown')}`, { limit: 12, windowMs: 10 * 60_000 }),
        ]);
        if (payload.legalDocumentVersion &&
            payload.legalDocumentVersion !== legal_document_version_1.LEGAL_DOCUMENT_VERSION) {
            throw new common_1.BadRequestException('Unsupported legal document version');
        }
        const result = await this.prisma.$transaction(async (tx) => {
            const challenge = await this.lockChallenge(tx, id);
            const capability = this.capability(challenge.metadata);
            if (capability.state === 'consumed') {
                if (!capability.authResponse)
                    throw this.invalidToken();
                return { response: capability.authResponse, created: false };
            }
            if (capability.state !== 'registration')
                throw this.invalidToken();
            this.assertLive(challenge);
            if (!capability.registrationExpiresAt ||
                Date.parse(capability.registrationExpiresAt) <= Date.now()) {
                throw this.invalidToken();
            }
            await tx.$queryRaw `
        SELECT pg_advisory_xact_lock(
          hashtextextended(${challenge.targetEmail}, 0)
        )::text
      `;
            const existed = await tx.user.findFirst({
                where: {
                    email: { equals: challenge.targetEmail, mode: 'insensitive' },
                },
                select: { id: true },
            });
            const response = await this.auth.authenticateEmailPasswordless(challenge.targetEmail, tx, payload);
            if (!response)
                throw this.invalidToken();
            await tx.emailChallenge.update({
                where: { id },
                data: {
                    consumedAt: new Date(),
                    metadata: {
                        emailPasswordless: {
                            ...capability,
                            state: 'consumed',
                            authResponse: response,
                        },
                    },
                },
            });
            return { response, created: existed == null };
        });
        if (result.created)
            this.adminDashboardSignal?.changed('users', 'usage');
        return result.response;
    }
    async lockChallenge(tx, id) {
        await tx.$queryRaw `
      SELECT id FROM email_challenges WHERE id = ${id}::uuid FOR UPDATE
    `;
        const challenge = await tx.emailChallenge.findFirst({
            where: { id, purpose: PURPOSE },
        });
        if (!challenge)
            throw this.invalidCode();
        return challenge;
    }
    async isCodeCorrect(tx, challenge, code) {
        if (!/^\d{6}$/.test(code) || challenge.attempts >= challenge.maxAttempts) {
            return false;
        }
        const actual = Buffer.from(this.codeDigest(challenge.id, code), 'hex');
        const expected = Buffer.from(challenge.codeHash, 'hex');
        const correct = actual.length === expected.length && (0, crypto_1.timingSafeEqual)(actual, expected);
        if (!correct) {
            await tx.emailChallenge.update({
                where: { id: challenge.id },
                data: { attempts: { increment: 1 } },
            });
            return false;
        }
        return true;
    }
    assertLive(challenge) {
        if (challenge.consumedAt ||
            challenge.expiresAt.getTime() <= Date.now() ||
            challenge.attempts >= challenge.maxAttempts) {
            throw this.invalidCode();
        }
    }
    capability(metadata) {
        const raw = metadata?.emailPasswordless;
        if (raw?.version !== 1 ||
            !['pending', 'registration', 'consumed'].includes(raw.state ?? '')) {
            throw this.invalidCode();
        }
        return raw;
    }
    registrationResponse(challenge, capability) {
        if (capability.state !== 'registration' ||
            !capability.registrationExpiresAt ||
            Date.parse(capability.registrationExpiresAt) <= Date.now()) {
            throw this.invalidToken();
        }
        return {
            status: 'registration_required',
            registrationToken: this.registrationToken(challenge.id),
            expiresAt: capability.registrationExpiresAt,
            ttlSeconds: Math.max(0, Math.floor((Date.parse(capability.registrationExpiresAt) - Date.now()) / 1000)),
        };
    }
    registrationToken(id) {
        return `${id}.${this.hmac(`registration:${id}`, 'base64url')}`;
    }
    parseRegistrationToken(value) {
        const match = value.match(/^([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.([A-Za-z0-9_-]{43})$/i);
        if (!match)
            throw this.invalidToken();
        const expected = Buffer.from(this.hmac(`registration:${match[1]}`), 'base64url');
        const actual = Buffer.from(match[2], 'base64url');
        if (actual.length !== expected.length || !(0, crypto_1.timingSafeEqual)(actual, expected)) {
            throw this.invalidToken();
        }
        return match[1];
    }
    async limitStart(email, source) {
        await Promise.all([
            this.rateLimit.consumeOrThrow(`email-auth:start-ip:${this.digest(source.ip ?? 'unknown')}`, { limit: 8, windowMs: 60 * 60_000 }),
            this.rateLimit.consumeOrThrow(`email-auth:start-address:${this.digest(email)}`, { limit: 5, windowMs: 60 * 60_000 }),
            this.rateLimit.consumeOrThrow(`email-auth:start-device:${this.digest(source.deviceId || 'unknown')}`, { limit: 8, windowMs: 60 * 60_000 }),
        ]);
    }
    startResponse(id, email, resendAfter) {
        return {
            status: 'ok',
            message: NEUTRAL_MESSAGE,
            challengeId: id,
            maskedEmail: this.maskEmail(email),
            expiresIn: 600,
            resendAfter,
        };
    }
    normalizeEmail(value) {
        return value.trim().toLowerCase();
    }
    maskEmail(value) {
        const [local, domain] = value.split('@');
        return `${local.slice(0, 1)}***@${domain}`;
    }
    assertUuid(value) {
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
            throw this.invalidCode();
        }
    }
    codeDigest(id, code) {
        return this.hmac(`code:${id}:${code}`, 'hex');
    }
    hmac(value, encoding = 'base64url') {
        return (0, crypto_1.createHmac)('sha256', env_1.env.JWT_REFRESH_SECRET)
            .update(`atta-email-auth-v1:${value}`)
            .digest(encoding);
    }
    digest(value) {
        return (0, crypto_1.createHash)('sha256').update(value).digest('hex');
    }
    invalidCode() {
        return new common_1.BadRequestException({
            code: 'EMAIL_CODE_INVALID',
            message: 'Неверный или истёкший код',
        });
    }
    invalidToken() {
        return new common_1.ConflictException({
            code: 'EMAIL_REGISTRATION_INVALID',
            message: 'Подтверждение регистрации недействительно или истекло',
        });
    }
};
exports.EmailPasswordlessService = EmailPasswordlessService;
exports.EmailPasswordlessService = EmailPasswordlessService = __decorate([
    (0, common_1.Injectable)(),
    __param(4, (0, common_1.Optional)()),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        rate_limit_service_1.RateLimitService,
        email_service_1.EmailService,
        auth_service_1.AuthService,
        admin_dashboard_signal_1.AdminDashboardSignal])
], EmailPasswordlessService);
//# sourceMappingURL=email-passwordless.service.js.map