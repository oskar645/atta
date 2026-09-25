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
exports.PasswordlessService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const crypto_1 = require("crypto");
const phone_1 = require("../../common/phone");
const phone_verification_service_1 = require("../phone-verification/phone-verification.service");
const prisma_service_1 = require("../prisma/prisma.service");
const rate_limit_service_1 = require("../rate-limit/rate-limit.service");
const auth_service_1 = require("./auth.service");
const legal_document_version_1 = require("./legal-document-version");
const PROVIDER_POLL_COOLDOWN_MS = 5_000;
let PasswordlessService = class PasswordlessService {
    constructor(prisma, phoneVerification, rateLimit, auth) {
        this.prisma = prisma;
        this.phoneVerification = phoneVerification;
        this.rateLimit = rateLimit;
        this.auth = auth;
    }
    async start(phone, source, referral) {
        const normalized = (0, phone_1.normalizeRussianPhone)(phone);
        (0, phone_1.validateRussianPhoneOrThrow)(normalized);
        await this.rateLimit.consumeOrThrow(`passwordless:start:${this.digest(normalized)}`, {
            limit: 1, windowMs: 60_000,
        });
        const id = (0, crypto_1.randomUUID)();
        const challenge = this.secret(id);
        const result = await this.phoneVerification.startCallVerification(normalized, 'login', source, {
            id,
            metadata: { passwordless: {
                    version: 1, state: 'pending', challengeHash: this.digest(challenge),
                    referralCode: referral?.referralCode?.trim() ?? '',
                    referralId: referral?.referralId?.trim() ?? '',
                } },
        });
        // Never look up User (including blocked identities) before proof of phone possession.
        return { status: 'pending', challenge, callToPhone: result.callToPhone,
            expiresAt: result.expiresAt,
            ttlSeconds: Math.max(0, Math.floor((Date.parse(result.expiresAt) - Date.now()) / 1000)) };
    }
    async check(challenge) {
        const id = this.parse(challenge);
        await this.rateLimit.consumeOrThrow(`passwordless:check:${id}`, { limit: 20, windowMs: 60_000 });
        return this.transaction(async (tx) => {
            const { verification, capability } = await this.lockAndValidate(tx, id, challenge, 'pending');
            if (capability.state === 'registration') {
                return this.registrationResponse(capability);
            }
            if (capability.state === 'consumed') {
                return this.replayResponse(capability);
            }
            const remaining = (capability.nextProviderPollAt ?? 0) - Date.now();
            if (remaining > 0) {
                return { status: 'pending', retryAfterSeconds: Math.ceil(remaining / 1000) };
            }
            // The row lock spans provider polling and state transitions across all API processes.
            let result;
            try {
                result = await this.phoneVerification.checkCallVerification(verification.phone, verification.checkId, 'login', { tx, id: verification.id });
            }
            catch (error) {
                // Commit the cooldown even on provider outages; throwing here would roll
                // it back and let queued checks immediately retry the same provider.
                if (!(error instanceof common_1.HttpException) || error.getStatus() !== 503)
                    throw error;
                result = { status: 'pending' };
            }
            if (result.status === 'pending') {
                const current = await tx.phoneVerification.findUniqueOrThrow({ where: { id } });
                await tx.phoneVerification.update({ where: { id }, data: { metadata: {
                            ...current.metadata,
                            passwordless: { ...capability, nextProviderPollAt: Date.now() + PROVIDER_POLL_COOLDOWN_MS },
                        } } });
                return { ...result, retryAfterSeconds: PROVIDER_POLL_COOLDOWN_MS / 1000 };
            }
            if (result.status !== 'confirmed')
                return result;
            this.assertLive(verification);
            const response = await this.auth.authenticatePasswordless(verification.phone, tx);
            if (response) {
                await this.consume(tx, verification, capability, response);
                return response;
            }
            const registrationToken = this.secret(id);
            const expiresAt = new Date(Math.min(verification.expiresAt.getTime(), Date.now() + 180_000));
            // Read the metadata written by the provider before adding our transition.
            const current = await tx.phoneVerification.findUniqueOrThrow({ where: { id } });
            await tx.phoneVerification.update({ where: { id }, data: { metadata: {
                        ...current.metadata,
                        passwordless: { ...capability, state: 'registration',
                            registrationHash: this.digest(registrationToken), registrationToken,
                            registrationExpiresAt: expiresAt.toISOString() },
                    } } });
            return this.registrationResponse({ ...capability, state: 'registration',
                registrationHash: this.digest(registrationToken), registrationToken,
                registrationExpiresAt: expiresAt.toISOString() });
        });
    }
    async complete(payload) {
        const id = this.parse(payload.registrationToken);
        await this.rateLimit.consumeOrThrow(`passwordless:complete:${id}`, { limit: 6, windowMs: 60_000 });
        return this.transaction(async (tx) => {
            const { verification, capability } = await this.lockAndValidate(tx, id, payload.registrationToken, 'registration');
            if (capability.state === 'consumed') {
                return this.replayResponse(capability);
            }
            if (verification.status !== 'CONFIRMED')
                throw this.invalid();
            if (payload.legalDocumentVersion && payload.legalDocumentVersion !== legal_document_version_1.LEGAL_DOCUMENT_VERSION) {
                throw new common_1.BadRequestException('Unsupported legal document version');
            }
            // Separate challenges for the same phone serialize too. Legacy signup races are
            // handled by the unique constraint and a fresh transaction below.
            await tx.$queryRaw `SELECT pg_advisory_xact_lock(hashtextextended(${verification.phone}, 0))::text`;
            const response = await this.auth.authenticatePasswordless(verification.phone, tx, {
                ...payload, referralCode: capability.referralCode, referralId: capability.referralId,
                verificationId: verification.id,
            });
            if (!response)
                throw this.invalid();
            await this.consume(tx, verification, capability, response);
            return response;
        });
    }
    async transaction(handler) {
        for (let attempt = 0;; attempt++) {
            try {
                return await this.prisma.$transaction(handler, { maxWait: 5_000, timeout: 20_000 });
            }
            catch (error) {
                // A concurrent legacy signup may win User.phone. Roll back every effect and
                // reread the account with all access checks; never update its signup data.
                if (attempt === 0 && error instanceof client_1.Prisma.PrismaClientKnownRequestError &&
                    error.code === 'P2002' && Array.isArray(error.meta?.target) && error.meta.target.includes('phone'))
                    continue;
                throw error;
            }
        }
    }
    async lockAndValidate(tx, id, secret, expected) {
        await tx.$queryRaw `SELECT id FROM phone_verifications WHERE id = ${id}::uuid FOR UPDATE`;
        const verification = await tx.phoneVerification.findUnique({ where: { id } });
        if (!verification || verification.purpose !== 'LOGIN' || !verification.checkId)
            throw this.invalid();
        this.assertLive(verification);
        const metadata = verification.metadata;
        const capability = metadata?.passwordless;
        const expectedHash = expected === 'pending' ? capability?.challengeHash : capability?.registrationHash;
        if (!capability || capability.version !== 1 || !expectedHash ||
            !/^[a-f0-9]{64}$/.test(expectedHash) ||
            !(0, crypto_1.timingSafeEqual)(Buffer.from(expectedHash, 'hex'), Buffer.from(this.digest(secret), 'hex')))
            throw this.invalid();
        if (capability.state === 'registration' && expected === 'pending') {
            if (!this.hasRegistrationReplay(capability))
                throw this.invalid();
        }
        else if (capability.state === 'consumed') {
            if (!this.hasAuthReplay(capability))
                throw this.invalid();
        }
        else if (capability.state !== expected) {
            throw new common_1.ConflictException({ code: 'PASSWORDLESS_ALREADY_USED', message: 'Начните подтверждение заново' });
        }
        if (expected === 'registration' &&
            !(Date.parse(capability.registrationExpiresAt ?? '') > Date.now()))
            throw this.invalid();
        return { verification, capability, metadata };
    }
    async consume(tx, verification, capability, response) {
        // Check TTL again after bcrypt/session work; throwing rolls back all effects.
        this.assertLive(verification);
        if (capability.registrationExpiresAt && Date.parse(capability.registrationExpiresAt) <= Date.now())
            throw this.invalid();
        const current = await tx.phoneVerification.findUniqueOrThrow({ where: { id: verification.id } });
        await tx.phoneVerification.update({ where: { id: verification.id }, data: {
                createdUserId: response.auth.user_id,
                metadata: { ...current.metadata, passwordless: { ...capability, state: 'consumed',
                        authResponse: response } },
            } });
    }
    registrationResponse(capability) {
        if (!this.hasRegistrationReplay(capability))
            throw this.invalid();
        const expiresAt = new Date(capability.registrationExpiresAt);
        if (expiresAt.getTime() <= Date.now())
            throw this.invalid();
        return { status: 'registration_required', registrationToken: capability.registrationToken,
            expiresAt: expiresAt.toISOString(),
            ttlSeconds: Math.max(0, Math.floor((expiresAt.getTime() - Date.now()) / 1000)) };
    }
    replayResponse(capability) {
        if (!this.hasAuthReplay(capability))
            throw this.invalid();
        return capability.authResponse;
    }
    hasRegistrationReplay(capability) {
        return typeof capability.registrationToken === 'string' &&
            typeof capability.registrationExpiresAt === 'string' &&
            Date.parse(capability.registrationExpiresAt) > Date.now();
    }
    hasAuthReplay(capability) {
        const response = capability.authResponse;
        return !!response && typeof response === 'object' && typeof response.auth?.user_id === 'string' &&
            typeof response.auth?.session_id === 'string' && typeof response.auth?.refresh_token === 'string';
    }
    assertLive(verification) {
        if (verification.expiresAt.getTime() <= Date.now() ||
            verification.status === 'EXPIRED' || verification.status === 'FAILED')
            throw this.invalid();
    }
    parse(value) {
        if (typeof value !== 'string' ||
            !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}\.[A-Za-z0-9_-]{43}$/.test(value))
            throw this.invalid();
        return value.slice(0, 36);
    }
    secret(id) { return `${id}.${(0, crypto_1.randomBytes)(32).toString('base64url')}`; }
    digest(value) { return (0, crypto_1.createHash)('sha256').update(value).digest('hex'); }
    invalid() { return new common_1.BadRequestException({ code: 'PASSWORDLESS_INVALID', message: 'Подтверждение недействительно или истекло' }); }
};
exports.PasswordlessService = PasswordlessService;
exports.PasswordlessService = PasswordlessService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        phone_verification_service_1.PhoneVerificationService,
        rate_limit_service_1.RateLimitService,
        auth_service_1.AuthService])
], PasswordlessService);
//# sourceMappingURL=passwordless.service.js.map