import {
  BadRequestException,
  Injectable,
  Logger,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from '@simplewebauthn/server';
import { isoBase64URL } from '@simplewebauthn/server/helpers';
import type {
  AuthenticationResponseJSON,
  AuthenticatorTransportFuture,
  RegistrationResponseJSON,
} from '@simplewebauthn/server';
import { RestoreCredentialType, UserStatus } from '@prisma/client';

import { env, parseRestoreCredentialOrigins } from '../../config/env';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { UserBlocksService } from '../user-blocks/user-blocks.service';
import { AuthenticatedUser } from './auth.types';
import { AuthService } from './auth.service';

type RestoreChallengePurpose = 'registration' | 'authentication';

type StoredChallenge = {
  purpose: RestoreChallengePurpose;
  challenge: string;
  userId?: string;
  createdAt: string;
};

const challengeTtlSeconds = 5 * 60;

@Injectable()
export class RestoreCredentialsService {
  private readonly logger = new Logger(RestoreCredentialsService.name);
  private readonly webAuthn = {
    generateRegistrationOptions,
    verifyRegistrationResponse,
    generateAuthenticationOptions,
    verifyAuthenticationResponse,
  };
  private readonly restoreOrigins = parseRestoreCredentialOrigins;
  private readonly memoryChallenges = new Map<
    string,
    StoredChallenge & { expiresAt: number }
  >();

  constructor(
    private readonly prisma: PrismaService,
    private readonly redisService: RedisService,
    private readonly userBlocksService: UserBlocksService,
    private readonly authService: AuthService,
  ) {}

  async createRegistrationOptions(authUser: AuthenticatedUser) {
    const user = await this.authService.findActiveUserByIdOrThrow(authUser.userId);
    const existingCredentials = await this.prisma.restoreCredential.findMany({
      where: {
        userId: user.id,
        revokedAt: null,
        type: RestoreCredentialType.RESTORE,
      },
      select: {
        credentialId: true,
        transports: true,
      },
    });

    const options = await this.webAuthn.generateRegistrationOptions({
      rpName: env.RESTORE_CREDENTIALS_RP_NAME,
      rpID: env.RESTORE_CREDENTIALS_RP_ID,
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

  async verifyRegistration(
    authUser: AuthenticatedUser,
    response: Record<string, unknown>,
  ) {
    const challenge = await this.consumeChallenge(
      'registration',
      this.extractChallenge(response),
    );
    if (!challenge.userId || challenge.userId !== authUser.userId) {
      throw new UnauthorizedException('Restore credential challenge is invalid');
    }

    const verification = await this.verifyRegistrationResponseOrThrow({
      response: response as unknown as RegistrationResponseJSON,
      expectedChallenge: challenge.challenge,
      expectedOrigin: this.expectedOrigins(),
      expectedRPID: env.RESTORE_CREDENTIALS_RP_ID,
      requireUserPresence: false,
      requireUserVerification: false,
    });

    if (!verification.verified || !verification.registrationInfo) {
      throw new UnauthorizedException('Restore credential registration rejected');
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
        transports: this.toStringArray(
          (response.response as Record<string, unknown> | undefined)?.transports,
        ),
        type: RestoreCredentialType.RESTORE,
        deviceType: info.credentialDeviceType,
        backedUp: info.credentialBackedUp,
      },
      update: {
        userId: authUser.userId,
        publicKey: Buffer.from(info.credential.publicKey),
        counter: info.credential.counter,
        transports: this.toStringArray(
          (response.response as Record<string, unknown> | undefined)?.transports,
        ),
        type: RestoreCredentialType.RESTORE,
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
      rpID: env.RESTORE_CREDENTIALS_RP_ID,
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

  async verifyAuthentication(response: Record<string, unknown>) {
    const responseJson = response as unknown as AuthenticationResponseJSON;
    const credentialId = (responseJson.id || responseJson.rawId || '').trim();
    if (!credentialId) {
      throw new BadRequestException('Restore credential id is required');
    }

    const challenge = await this.consumeChallenge(
      'authentication',
      this.extractChallenge(response),
    );
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

    if (
      !credential ||
      credential.revokedAt ||
      credential.type !== RestoreCredentialType.RESTORE
    ) {
      throw new UnauthorizedException('Restore credential is not active');
    }

    const verification = await this.verifyAuthenticationResponseOrThrow({
      response: responseJson,
      expectedChallenge: challenge.challenge,
      expectedOrigin: this.expectedOrigins(),
      expectedRPID: env.RESTORE_CREDENTIALS_RP_ID,
      credential: {
        id: credential.credentialId,
        publicKey: new Uint8Array(credential.publicKey),
        counter: credential.counter,
        transports: this.toAuthenticatorTransports(credential.transports),
      },
      requireUserVerification: false,
    });

    if (!verification.verified) {
      throw new UnauthorizedException('Restore credential authentication rejected');
    }

    if (
      credential.user.deletedAt ||
      credential.user.status !== UserStatus.ACTIVE
    ) {
      throw new UnauthorizedException('User account is not active');
    }
    const activeBlock = await this.userBlocksService.getActiveBlock(
      credential.userId,
    );
    if (activeBlock) {
      throw new UnauthorizedException({
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

  async revoke(authUser: AuthenticatedUser, credentialId?: string) {
    const where = {
      userId: authUser.userId,
      revokedAt: null,
      type: RestoreCredentialType.RESTORE,
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

  private expectedOrigins() {
    const origins = this.restoreOrigins();
    if (origins.length === 0) {
      throw new ServiceUnavailableException(
        'Restore credential Android origins are not configured',
      );
    }
    return origins;
  }

  private async verifyRegistrationResponseOrThrow(
    options: Parameters<typeof verifyRegistrationResponse>[0],
  ) {
    try {
      return await this.webAuthn.verifyRegistrationResponse(options);
    } catch {
      throw new UnauthorizedException('Restore credential registration rejected');
    }
  }

  private async verifyAuthenticationResponseOrThrow(
    options: Parameters<typeof verifyAuthenticationResponse>[0],
  ) {
    try {
      return await this.webAuthn.verifyAuthenticationResponse(options);
    } catch {
      throw new UnauthorizedException('Restore credential authentication rejected');
    }
  }

  private async storeChallenge(challenge: StoredChallenge) {
    const key = this.challengeKey(challenge.purpose, challenge.challenge);
    try {
      await this.redisService.setWithTtl(
        key,
        JSON.stringify(challenge),
        challengeTtlSeconds,
      );
      return;
    } catch (error) {
      this.warnRedisFallback(error);
      this.memoryChallenges.set(key, {
        ...challenge,
        expiresAt: Date.now() + challengeTtlSeconds * 1000,
      });
    }
  }

  private async consumeChallenge(
    purpose: RestoreChallengePurpose,
    challenge: string,
  ) {
    const key = this.challengeKey(purpose, challenge);
    try {
      const raw = await this.redisService.get(key);
      await this.redisService.del(key);
      if (!raw) {
        throw new UnauthorizedException('Restore credential challenge expired');
      }
      return JSON.parse(raw) as StoredChallenge;
    } catch (error) {
      if (error instanceof UnauthorizedException) {
        throw error;
      }
      this.warnRedisFallback(error);
      const stored = this.memoryChallenges.get(key);
      this.memoryChallenges.delete(key);
      if (!stored || stored.expiresAt <= Date.now()) {
        throw new UnauthorizedException('Restore credential challenge expired');
      }
      return stored;
    }
  }

  private extractChallenge(response: Record<string, unknown>) {
    const rawClientData =
      (response.response as Record<string, unknown> | undefined)?.clientDataJSON;
    if (typeof rawClientData !== 'string' || !rawClientData.trim()) {
      throw new BadRequestException('Restore credential clientDataJSON is required');
    }
    try {
      const decoded = JSON.parse(isoBase64URL.toUTF8String(rawClientData));
      const challenge = decoded?.challenge;
      if (typeof challenge !== 'string' || !challenge.trim()) {
        throw new Error('missing challenge');
      }
      return challenge;
    } catch {
      throw new BadRequestException('Restore credential challenge is invalid');
    }
  }

  private challengeKey(purpose: RestoreChallengePurpose, challenge: string) {
    return `auth:restore-credentials:${purpose}:${challenge}`;
  }

  private toStringArray(value: unknown) {
    if (!Array.isArray(value)) {
      return [];
    }
    return value
      .map((item) => (typeof item === 'string' ? item.trim() : ''))
      .filter((item) => item.length > 0);
  }

  private toAuthenticatorTransports(
    transports: string[],
  ): AuthenticatorTransportFuture[] | undefined {
    if (transports.length === 0) {
      return undefined;
    }
    return transports as AuthenticatorTransportFuture[];
  }

  private warnRedisFallback(error: unknown) {
    this.logger.warn(
      `Redis restore challenge storage unavailable; using local fallback: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
  }
}
