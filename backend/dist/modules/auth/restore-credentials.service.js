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
var RestoreCredentialsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.RestoreCredentialsService = void 0;
const common_1 = require("@nestjs/common");
const server_1 = require("@simplewebauthn/server");
const helpers_1 = require("@simplewebauthn/server/helpers");
const client_1 = require("@prisma/client");
const env_1 = require("../../config/env");
const prisma_service_1 = require("../prisma/prisma.service");
const redis_service_1 = require("../redis/redis.service");
const user_blocks_service_1 = require("../user-blocks/user-blocks.service");
const auth_service_1 = require("./auth.service");
const challengeTtlSeconds = 5 * 60;
let RestoreCredentialsService = RestoreCredentialsService_1 = class RestoreCredentialsService {
    constructor(prisma, redisService, userBlocksService, authService) {
        this.prisma = prisma;
        this.redisService = redisService;
        this.userBlocksService = userBlocksService;
        this.authService = authService;
        this.logger = new common_1.Logger(RestoreCredentialsService_1.name);
        this.webAuthn = {
            generateRegistrationOptions: server_1.generateRegistrationOptions,
            verifyRegistrationResponse: server_1.verifyRegistrationResponse,
            generateAuthenticationOptions: server_1.generateAuthenticationOptions,
            verifyAuthenticationResponse: server_1.verifyAuthenticationResponse,
        };
        this.restoreOrigins = env_1.parseRestoreCredentialOrigins;
        this.memoryChallenges = new Map();
    }
    async createRegistrationOptions(authUser) {
        const user = await this.authService.findActiveUserByIdOrThrow(authUser.userId);
        const existingCredentials = await this.prisma.restoreCredential.findMany({
            where: {
                userId: user.id,
                revokedAt: null,
                type: client_1.RestoreCredentialType.RESTORE,
            },
            select: {
                credentialId: true,
                transports: true,
            },
        });
        const options = await this.webAuthn.generateRegistrationOptions({
            rpName: env_1.env.RESTORE_CREDENTIALS_RP_NAME,
            rpID: env_1.env.RESTORE_CREDENTIALS_RP_ID,
            userID: Buffer.from(user.id, 'utf8'),
            userName: user.phone ?? user.email ?? user.id,
            userDisplayName: user.displayName || user.name || 'ATTA',
            timeout: 60_000,
            attestationType: 'none',
            authenticatorSelection: {
                residentKey: 'required',
                requireResidentKey: true,
                userVerification: 'preferred',
            },
            excludeCredentials: existingCredentials.map((credential) => ({
                id: credential.credentialId,
                transports: this.toAuthenticatorTransports(credential.transports),
            })),
        });
        await this.storeChallenge({
            purpose: 'registration',
            challenge: options.challenge,
            userId: user.id,
            createdAt: new Date().toISOString(),
        });
        return options;
    }
    async verifyRegistration(authUser, response) {
        const challenge = await this.consumeChallenge('registration', this.extractChallenge(response));
        if (!challenge.userId || challenge.userId !== authUser.userId) {
            throw new common_1.UnauthorizedException('Restore credential challenge is invalid');
        }
        const verification = await this.verifyRegistrationResponseOrThrow({
            response: response,
            expectedChallenge: challenge.challenge,
            expectedOrigin: this.expectedOrigins(),
            expectedRPID: env_1.env.RESTORE_CREDENTIALS_RP_ID,
            requireUserPresence: false,
            requireUserVerification: false,
        });
        if (!verification.verified || !verification.registrationInfo) {
            throw new common_1.UnauthorizedException('Restore credential registration rejected');
        }
        const info = verification.registrationInfo;
        await this.prisma.restoreCredential.upsert({
            where: {
                credentialId: info.credential.id,
            },
            create: {
                userId: authUser.userId,
                credentialId: info.credential.id,
                publicKey: Buffer.from(info.credential.publicKey),
                counter: info.credential.counter,
                transports: this.toStringArray(response.response?.transports),
                type: client_1.RestoreCredentialType.RESTORE,
                deviceType: info.credentialDeviceType,
                backedUp: info.credentialBackedUp,
            },
            update: {
                userId: authUser.userId,
                publicKey: Buffer.from(info.credential.publicKey),
                counter: info.credential.counter,
                transports: this.toStringArray(response.response?.transports),
                type: client_1.RestoreCredentialType.RESTORE,
                deviceType: info.credentialDeviceType,
                backedUp: info.credentialBackedUp,
                revokedAt: null,
            },
        });
        return {
            registered: true,
            credential_id: info.credential.id,
        };
    }
    async createAuthenticationOptions() {
        const options = await this.webAuthn.generateAuthenticationOptions({
            rpID: env_1.env.RESTORE_CREDENTIALS_RP_ID,
            timeout: 60_000,
            userVerification: 'preferred',
        });
        await this.storeChallenge({
            purpose: 'authentication',
            challenge: options.challenge,
            createdAt: new Date().toISOString(),
        });
        return options;
    }
    async verifyAuthentication(response) {
        const responseJson = response;
        const credentialId = (responseJson.id || responseJson.rawId || '').trim();
        if (!credentialId) {
            throw new common_1.BadRequestException('Restore credential id is required');
        }
        const challenge = await this.consumeChallenge('authentication', this.extractChallenge(response));
        const credential = await this.prisma.restoreCredential.findUnique({
            where: {
                credentialId,
            },
            include: {
                user: {
                    include: {
                        adminProfile: true,
                    },
                },
            },
        });
        if (!credential ||
            credential.revokedAt ||
            credential.type !== client_1.RestoreCredentialType.RESTORE) {
            throw new common_1.UnauthorizedException('Restore credential is not active');
        }
        const verification = await this.verifyAuthenticationResponseOrThrow({
            response: responseJson,
            expectedChallenge: challenge.challenge,
            expectedOrigin: this.expectedOrigins(),
            expectedRPID: env_1.env.RESTORE_CREDENTIALS_RP_ID,
            credential: {
                id: credential.credentialId,
                publicKey: new Uint8Array(credential.publicKey),
                counter: credential.counter,
                transports: this.toAuthenticatorTransports(credential.transports),
            },
            requireUserVerification: false,
        });
        if (!verification.verified) {
            throw new common_1.UnauthorizedException('Restore credential authentication rejected');
        }
        if (credential.user.deletedAt ||
            credential.user.status !== client_1.UserStatus.ACTIVE) {
            throw new common_1.UnauthorizedException('User account is not active');
        }
        const activeBlock = await this.userBlocksService.getActiveBlock(credential.userId);
        if (activeBlock) {
            throw new common_1.UnauthorizedException({
                code: 'ACCOUNT_BLOCKED',
                message: 'Аккаунт заблокирован',
            });
        }
        const now = new Date();
        const user = await this.prisma.user.update({
            where: {
                id: credential.userId,
            },
            data: {
                lastLoginAt: now,
            },
            include: {
                adminProfile: true,
            },
        });
        await this.prisma.restoreCredential.update({
            where: {
                id: credential.id,
            },
            data: {
                counter: verification.authenticationInfo.newCounter,
                deviceType: verification.authenticationInfo.credentialDeviceType,
                backedUp: verification.authenticationInfo.credentialBackedUp,
                lastUsedAt: now,
            },
        });
        return this.authService.createSessionForUser(user);
    }
    async revoke(authUser, credentialId) {
        const where = {
            userId: authUser.userId,
            revokedAt: null,
            type: client_1.RestoreCredentialType.RESTORE,
            ...(credentialId ? { credentialId } : {}),
        };
        const result = await this.prisma.restoreCredential.updateMany({
            where,
            data: {
                revokedAt: new Date(),
            },
        });
        return {
            revoked: result.count,
        };
    }
    expectedOrigins() {
        const origins = this.restoreOrigins();
        if (origins.length === 0) {
            throw new common_1.ServiceUnavailableException('Restore credential Android origins are not configured');
        }
        return origins;
    }
    async verifyRegistrationResponseOrThrow(options) {
        try {
            return await this.webAuthn.verifyRegistrationResponse(options);
        }
        catch {
            throw new common_1.UnauthorizedException('Restore credential registration rejected');
        }
    }
    async verifyAuthenticationResponseOrThrow(options) {
        try {
            return await this.webAuthn.verifyAuthenticationResponse(options);
        }
        catch {
            throw new common_1.UnauthorizedException('Restore credential authentication rejected');
        }
    }
    async storeChallenge(challenge) {
        const key = this.challengeKey(challenge.purpose, challenge.challenge);
        try {
            await this.redisService.setWithTtl(key, JSON.stringify(challenge), challengeTtlSeconds);
            return;
        }
        catch (error) {
            this.warnRedisFallback(error);
            this.memoryChallenges.set(key, {
                ...challenge,
                expiresAt: Date.now() + challengeTtlSeconds * 1000,
            });
        }
    }
    async consumeChallenge(purpose, challenge) {
        const key = this.challengeKey(purpose, challenge);
        try {
            const raw = await this.redisService.get(key);
            await this.redisService.del(key);
            if (!raw) {
                throw new common_1.UnauthorizedException('Restore credential challenge expired');
            }
            return JSON.parse(raw);
        }
        catch (error) {
            if (error instanceof common_1.UnauthorizedException) {
                throw error;
            }
            this.warnRedisFallback(error);
            const stored = this.memoryChallenges.get(key);
            this.memoryChallenges.delete(key);
            if (!stored || stored.expiresAt <= Date.now()) {
                throw new common_1.UnauthorizedException('Restore credential challenge expired');
            }
            return stored;
        }
    }
    extractChallenge(response) {
        const rawClientData = response.response?.clientDataJSON;
        if (typeof rawClientData !== 'string' || !rawClientData.trim()) {
            throw new common_1.BadRequestException('Restore credential clientDataJSON is required');
        }
        try {
            const decoded = JSON.parse(helpers_1.isoBase64URL.toUTF8String(rawClientData));
            const challenge = decoded?.challenge;
            if (typeof challenge !== 'string' || !challenge.trim()) {
                throw new Error('missing challenge');
            }
            return challenge;
        }
        catch {
            throw new common_1.BadRequestException('Restore credential challenge is invalid');
        }
    }
    challengeKey(purpose, challenge) {
        return `auth:restore-credentials:${purpose}:${challenge}`;
    }
    toStringArray(value) {
        if (!Array.isArray(value)) {
            return [];
        }
        return value
            .map((item) => (typeof item === 'string' ? item.trim() : ''))
            .filter((item) => item.length > 0);
    }
    toAuthenticatorTransports(transports) {
        if (transports.length === 0) {
            return undefined;
        }
        return transports;
    }
    warnRedisFallback(error) {
        this.logger.warn(`Redis restore challenge storage unavailable; using local fallback: ${error instanceof Error ? error.message : String(error)}`);
    }
};
exports.RestoreCredentialsService = RestoreCredentialsService;
exports.RestoreCredentialsService = RestoreCredentialsService = RestoreCredentialsService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        redis_service_1.RedisService,
        user_blocks_service_1.UserBlocksService,
        auth_service_1.AuthService])
], RestoreCredentialsService);
//# sourceMappingURL=restore-credentials.service.js.map