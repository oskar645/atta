import { BadRequestException, ConflictException, HttpException, Injectable } from '@nestjs/common';
import { PhoneVerification, Prisma } from '@prisma/client';
import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'crypto';

import { normalizeRussianPhone, validateRussianPhoneOrThrow } from '../../common/phone';
import { PhoneVerificationService } from '../phone-verification/phone-verification.service';
import { PrismaService } from '../prisma/prisma.service';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { AuthService } from './auth.service';
import { PasswordlessCompleteDto } from './dto/passwordless.dto';
import { LEGAL_DOCUMENT_VERSION } from './legal-document-version';

type Capability = {
  version: 1;
  state: 'pending' | 'registration' | 'consumed';
  challengeHash: string;
  registrationHash?: string;
  registrationToken?: string;
  registrationExpiresAt?: string;
  authResponse?: PasswordlessAuthResponse;
  nextProviderPollAt?: number;
  referralCode?: string;
  referralId?: string;
};

const PROVIDER_POLL_COOLDOWN_MS = 5_000;

type PasswordlessAuthResponse = {
  user: { id: string; [key: string]: unknown };
  admin_profile: unknown;
  is_admin: boolean;
  isAdmin: boolean;
  auth: {
    access_token: string;
    refresh_token: string;
    token_type: string;
    expires_in: number;
    user_id: string;
    session_id: string;
  };
};

@Injectable()
export class PasswordlessService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly phoneVerification: PhoneVerificationService,
    private readonly rateLimit: RateLimitService,
    private readonly auth: AuthService,
  ) {}

  async start(phone: string, source?: { ip?: string; deviceId?: string; userAgent?: string }, referral?: { referralCode?: string; referralId?: string }) {
    const normalized = normalizeRussianPhone(phone);
    validateRussianPhoneOrThrow(normalized);
    await this.rateLimit.consumeOrThrow(`passwordless:start:${this.digest(normalized)}`, {
      limit: 1, windowMs: 60_000,
    });
    const id = randomUUID();
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

  async check(challenge: string) {
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
        result = await this.phoneVerification.checkCallVerification(
          verification.phone, verification.checkId!, 'login', { tx, id: verification.id },
        );
      } catch (error) {
        // Commit the cooldown even on provider outages; throwing here would roll
        // it back and let queued checks immediately retry the same provider.
        if (!(error instanceof HttpException) || error.getStatus() !== 503) throw error;
        result = { status: 'pending' };
      }
      if (result.status === 'pending') {
        const current = await tx.phoneVerification.findUniqueOrThrow({ where: { id } });
        await tx.phoneVerification.update({ where: { id }, data: { metadata: {
          ...(current.metadata as Prisma.JsonObject),
          passwordless: { ...capability, nextProviderPollAt: Date.now() + PROVIDER_POLL_COOLDOWN_MS },
        } as Prisma.InputJsonValue } });
        return { ...result, retryAfterSeconds: PROVIDER_POLL_COOLDOWN_MS / 1000 };
      }
      if (result.status !== 'confirmed') return result;
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
        ...(current.metadata as Prisma.JsonObject),
        passwordless: { ...capability, state: 'registration' as const,
          registrationHash: this.digest(registrationToken), registrationToken,
          registrationExpiresAt: expiresAt.toISOString() },
      } as Prisma.InputJsonValue } });
      return this.registrationResponse({ ...capability, state: 'registration',
        registrationHash: this.digest(registrationToken), registrationToken,
        registrationExpiresAt: expiresAt.toISOString() });
    });
  }

  async complete(payload: PasswordlessCompleteDto) {
    const id = this.parse(payload.registrationToken);
    await this.rateLimit.consumeOrThrow(`passwordless:complete:${id}`, { limit: 6, windowMs: 60_000 });
    return this.transaction(async (tx) => {
      const { verification, capability } = await this.lockAndValidate(
        tx, id, payload.registrationToken, 'registration',
      );
      if (capability.state === 'consumed') {
        return this.replayResponse(capability);
      }
      if (verification.status !== 'CONFIRMED') throw this.invalid();
      if (payload.legalDocumentVersion && payload.legalDocumentVersion !== LEGAL_DOCUMENT_VERSION) {
        throw new BadRequestException('Unsupported legal document version');
      }
      // Separate challenges for the same phone serialize too. Legacy signup races are
      // handled by the unique constraint and a fresh transaction below.
      await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended(${verification.phone}, 0))::text`;
      const response = await this.auth.authenticatePasswordless(verification.phone, tx, {
        ...payload, referralCode: capability.referralCode, referralId: capability.referralId,
        verificationId: verification.id,
      });
      if (!response) throw this.invalid();
      await this.consume(tx, verification, capability, response);
      return response;
    });
  }

  private async transaction<T>(handler: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    for (let attempt = 0; ; attempt++) {
      try {
        return await this.prisma.$transaction(handler, { maxWait: 5_000, timeout: 20_000 });
      } catch (error) {
        // A concurrent legacy signup may win User.phone. Roll back every effect and
        // reread the account with all access checks; never update its signup data.
        if (attempt === 0 && error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === 'P2002' && Array.isArray(error.meta?.target) && error.meta.target.includes('phone')) continue;
        throw error;
      }
    }
  }

  private async lockAndValidate(
    tx: Prisma.TransactionClient, id: string, secret: string, expected: 'pending' | 'registration',
  ) {
    await tx.$queryRaw`SELECT id FROM phone_verifications WHERE id = ${id}::uuid FOR UPDATE`;
    const verification = await tx.phoneVerification.findUnique({ where: { id } });
    if (!verification || verification.purpose !== 'LOGIN' || !verification.checkId) throw this.invalid();
    this.assertLive(verification);
    const metadata = verification.metadata as Prisma.JsonObject;
    const capability = metadata?.passwordless as unknown as Capability | undefined;
    const expectedHash = expected === 'pending' ? capability?.challengeHash : capability?.registrationHash;
    if (!capability || capability.version !== 1 || !expectedHash ||
      !/^[a-f0-9]{64}$/.test(expectedHash) ||
      !timingSafeEqual(Buffer.from(expectedHash, 'hex'), Buffer.from(this.digest(secret), 'hex'))) throw this.invalid();
    if (capability.state === 'registration' && expected === 'pending') {
      if (!this.hasRegistrationReplay(capability)) throw this.invalid();
    } else if (capability.state === 'consumed') {
      if (!this.hasAuthReplay(capability)) throw this.invalid();
    } else if (capability.state !== expected) {
      throw new ConflictException({ code: 'PASSWORDLESS_ALREADY_USED', message: 'Начните подтверждение заново' });
    }
    if (expected === 'registration' &&
      !(Date.parse(capability.registrationExpiresAt ?? '') > Date.now())) throw this.invalid();
    return { verification, capability, metadata };
  }

  private async consume(
    tx: Prisma.TransactionClient, verification: PhoneVerification,
    capability: Capability, response: PasswordlessAuthResponse,
  ) {
    // Check TTL again after bcrypt/session work; throwing rolls back all effects.
    this.assertLive(verification);
    if (capability.registrationExpiresAt && Date.parse(capability.registrationExpiresAt) <= Date.now()) throw this.invalid();
    const current = await tx.phoneVerification.findUniqueOrThrow({ where: { id: verification.id } });
    await tx.phoneVerification.update({ where: { id: verification.id }, data: {
      createdUserId: response.auth.user_id,
      metadata: { ...(current.metadata as Prisma.JsonObject), passwordless: { ...capability, state: 'consumed',
        authResponse: response as unknown as Prisma.InputJsonValue } },
    } });
  }

  private registrationResponse(capability: Capability) {
    if (!this.hasRegistrationReplay(capability)) throw this.invalid();
    const expiresAt = new Date(capability.registrationExpiresAt);
    if (expiresAt.getTime() <= Date.now()) throw this.invalid();
    return { status: 'registration_required', registrationToken: capability.registrationToken,
      expiresAt: expiresAt.toISOString(),
      ttlSeconds: Math.max(0, Math.floor((expiresAt.getTime() - Date.now()) / 1000)) };
  }

  private replayResponse(capability: Capability) {
    if (!this.hasAuthReplay(capability)) throw this.invalid();
    return capability.authResponse;
  }

  private hasRegistrationReplay(capability: Capability): capability is Capability & {
    registrationToken: string;
    registrationExpiresAt: string;
  } {
    return typeof capability.registrationToken === 'string' &&
      typeof capability.registrationExpiresAt === 'string' &&
      Date.parse(capability.registrationExpiresAt) > Date.now();
  }

  private hasAuthReplay(capability: Capability): capability is Capability & { authResponse: PasswordlessAuthResponse } {
    const response = capability.authResponse;
    return !!response && typeof response === 'object' && typeof response.auth?.user_id === 'string' &&
      typeof response.auth?.session_id === 'string' && typeof response.auth?.refresh_token === 'string';
  }

  private assertLive(verification: PhoneVerification) {
    if (verification.expiresAt.getTime() <= Date.now() ||
      verification.status === 'EXPIRED' || verification.status === 'FAILED') throw this.invalid();
  }

  private parse(value: string) {
    if (typeof value !== 'string' ||
      !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}\.[A-Za-z0-9_-]{43}$/.test(value)) throw this.invalid();
    return value.slice(0, 36);
  }

  private secret(id: string) { return `${id}.${randomBytes(32).toString('base64url')}`; }
  private digest(value: string) { return createHash('sha256').update(value).digest('hex'); }
  private invalid() { return new BadRequestException({ code: 'PASSWORDLESS_INVALID', message: 'Подтверждение недействительно или истекло' }); }
}
