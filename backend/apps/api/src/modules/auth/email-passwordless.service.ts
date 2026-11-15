import {
  BadRequestException,
  ConflictException,
  Injectable,
  Optional,
} from '@nestjs/common';
import { EmailChallengePurpose, Prisma, UserStatus } from '@prisma/client';
import {
  createHash,
  createHmac,
  randomInt,
  randomUUID,
  timingSafeEqual,
} from 'crypto';

import { AdminDashboardSignal } from '../../common/admin-dashboard-signal';
import { env } from '../../config/env';
import { EmailService } from '../email/email.service';
import { PrismaService } from '../prisma/prisma.service';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { AuthService } from './auth.service';
import { CompleteEmailPasswordlessDto } from './dto/email-passwordless.dto';
import { LEGAL_DOCUMENT_VERSION } from './legal-document-version';

const CODE_TTL_MS = 10 * 60_000;
const RESEND_MS = 60_000;
const REGISTRATION_TTL_MS = 5 * 60_000;
const PURPOSE = EmailChallengePurpose.EMAIL_AUTH;
const NEUTRAL_MESSAGE = 'Если адрес доступен для входа, мы отправили код.';

type Source = { ip?: string; deviceId?: string };
type Capability = {
  version: 1;
  state: 'pending' | 'registration' | 'consumed';
  registrationExpiresAt?: string;
  authResponse?: Record<string, unknown>;
};

@Injectable()
export class EmailPasswordlessService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rateLimit: RateLimitService,
    private readonly emailService: EmailService,
    private readonly auth: AuthService,
    @Optional() private readonly adminDashboardSignal?: AdminDashboardSignal,
  ) {}

  async start(rawEmail: string, source: Source = {}) {
    this.emailService.ensureAvailable();
    const email = this.normalizeEmail(rawEmail);
    await this.limitStart(email, source);

    const latest = await this.prisma.emailChallenge.findFirst({
      where: { purpose: PURPOSE, targetEmail: email, consumedAt: null },
      orderBy: { createdAt: 'desc' },
    });
    if (latest && latest.resendAvailableAt.getTime() > Date.now()) {
      return this.startResponse(
        latest.id,
        email,
        Math.ceil((latest.resendAvailableAt.getTime() - Date.now()) / 1000),
      );
    }

    const user = await this.prisma.user.findFirst({
      where: {
        email: { equals: email, mode: 'insensitive' },
        emailVerifiedAt: { not: null },
        deletedAt: null,
        status: UserStatus.ACTIVE,
      },
      select: { id: true },
    });
    const id = randomUUID();
    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
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

  async check(id: string, code: string, source: Source = {}) {
    this.assertUuid(id);
    await Promise.all([
      this.rateLimit.consumeOrThrow(`email-auth:check:${id}`, {
        limit: 10,
        windowMs: 10 * 60_000,
      }),
      this.rateLimit.consumeOrThrow(
        `email-auth:check-ip:${this.digest(source.ip ?? 'unknown')}`,
        { limit: 30, windowMs: 10 * 60_000 },
      ),
    ]);

    const result = await this.prisma.$transaction(async (tx) => {
      const challenge = await this.lockChallenge(tx, id);
      const capability = this.capability(challenge.metadata);
      if (capability.state === 'consumed') {
        if (!capability.authResponse) throw this.invalidCode();
        return capability.authResponse;
      }
      this.assertLive(challenge);
      const codeCorrect = await this.isCodeCorrect(tx, challenge, code);
      if (!codeCorrect) return { emailCodeInvalid: true };

      if (capability.state === 'registration') {
        return this.registrationResponse(challenge, capability);
      }

      const user = await tx.user.findFirst({
        where: {
          email: { equals: challenge.targetEmail, mode: 'insensitive' },
          emailVerifiedAt: { not: null },
          deletedAt: null,
          status: UserStatus.ACTIVE,
        },
        include: { adminProfile: true },
      });
      if (user) {
        const response = await this.auth.authenticateEmailPasswordless(
          challenge.targetEmail,
          tx,
        );
        if (!response) throw this.invalidCode();
        await tx.emailChallenge.update({
          where: { id },
          data: {
            consumedAt: new Date(),
            metadata: {
              emailPasswordless: {
                ...capability,
                state: 'consumed',
                authResponse: response as unknown as Prisma.InputJsonValue,
              },
            },
          },
        });
        return response;
      }

      const registrationExpiresAt = new Date(
        Math.min(challenge.expiresAt.getTime(), Date.now() + REGISTRATION_TTL_MS),
      );
      const next: Capability = {
        ...capability,
        state: 'registration',
        registrationExpiresAt: registrationExpiresAt.toISOString(),
      };
      await tx.emailChallenge.update({
        where: { id },
        data: {
          metadata: {
            emailPasswordless: next as unknown as Prisma.InputJsonValue,
          },
        },
      });
      return this.registrationResponse(challenge, next);
    });
    if (
      typeof result === 'object' &&
      result != null &&
      'emailCodeInvalid' in result
    ) {
      throw this.invalidCode();
    }
    return result;
  }

  async complete(payload: CompleteEmailPasswordlessDto, source: Source = {}) {
    const id = this.parseRegistrationToken(payload.registrationToken);
    await Promise.all([
      this.rateLimit.consumeOrThrow(`email-auth:complete:${id}`, {
        limit: 6,
        windowMs: 10 * 60_000,
      }),
      this.rateLimit.consumeOrThrow(
        `email-auth:complete-ip:${this.digest(source.ip ?? 'unknown')}`,
        { limit: 12, windowMs: 10 * 60_000 },
      ),
    ]);
    if (
      payload.legalDocumentVersion &&
      payload.legalDocumentVersion !== LEGAL_DOCUMENT_VERSION
    ) {
      throw new BadRequestException('Unsupported legal document version');
    }

    const result = await this.prisma.$transaction(async (tx) => {
      const challenge = await this.lockChallenge(tx, id);
      const capability = this.capability(challenge.metadata);
      if (capability.state === 'consumed') {
        if (!capability.authResponse) throw this.invalidToken();
        return { response: capability.authResponse, created: false };
      }
      if (capability.state !== 'registration') throw this.invalidToken();
      this.assertLive(challenge);
      if (
        !capability.registrationExpiresAt ||
        Date.parse(capability.registrationExpiresAt) <= Date.now()
      ) {
        throw this.invalidToken();
      }

      await tx.$queryRaw`
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
      const response = await this.auth.authenticateEmailPasswordless(
        challenge.targetEmail,
        tx,
        payload,
      );
      if (!response) throw this.invalidToken();
      await tx.emailChallenge.update({
        where: { id },
        data: {
          consumedAt: new Date(),
          metadata: {
            emailPasswordless: {
              ...capability,
              state: 'consumed',
              authResponse: response as unknown as Prisma.InputJsonValue,
            },
          },
        },
      });
      return { response, created: existed == null };
    });
    if (result.created) this.adminDashboardSignal?.changed('users', 'usage');
    return result.response;
  }

  private async lockChallenge(tx: Prisma.TransactionClient, id: string) {
    await tx.$queryRaw`
      SELECT id FROM email_challenges WHERE id = ${id}::uuid FOR UPDATE
    `;
    const challenge = await tx.emailChallenge.findFirst({
      where: { id, purpose: PURPOSE },
    });
    if (!challenge) throw this.invalidCode();
    return challenge;
  }

  private async isCodeCorrect(
    tx: Prisma.TransactionClient,
    challenge: { id: string; codeHash: string; attempts: number; maxAttempts: number },
    code: string,
  ) {
    if (!/^\d{6}$/.test(code) || challenge.attempts >= challenge.maxAttempts) {
      return false;
    }
    const actual = Buffer.from(this.codeDigest(challenge.id, code), 'hex');
    const expected = Buffer.from(challenge.codeHash, 'hex');
    const correct =
      actual.length === expected.length && timingSafeEqual(actual, expected);
    if (!correct) {
      await tx.emailChallenge.update({
        where: { id: challenge.id },
        data: { attempts: { increment: 1 } },
      });
      return false;
    }
    return true;
  }

  private assertLive(challenge: {
    consumedAt: Date | null;
    expiresAt: Date;
    attempts: number;
    maxAttempts: number;
  }) {
    if (
      challenge.consumedAt ||
      challenge.expiresAt.getTime() <= Date.now() ||
      challenge.attempts >= challenge.maxAttempts
    ) {
      throw this.invalidCode();
    }
  }

  private capability(metadata: Prisma.JsonValue): Capability {
    const raw = (metadata as Prisma.JsonObject)?.emailPasswordless as
      | Partial<Capability>
      | undefined;
    if (
      raw?.version !== 1 ||
      !['pending', 'registration', 'consumed'].includes(raw.state ?? '')
    ) {
      throw this.invalidCode();
    }
    return raw as Capability;
  }

  private registrationResponse(
    challenge: { id: string },
    capability: Capability,
  ) {
    if (
      capability.state !== 'registration' ||
      !capability.registrationExpiresAt ||
      Date.parse(capability.registrationExpiresAt) <= Date.now()
    ) {
      throw this.invalidToken();
    }
    return {
      status: 'registration_required',
      registrationToken: this.registrationToken(challenge.id),
      expiresAt: capability.registrationExpiresAt,
      ttlSeconds: Math.max(
        0,
        Math.floor(
          (Date.parse(capability.registrationExpiresAt) - Date.now()) / 1000,
        ),
      ),
    };
  }

  private registrationToken(id: string) {
    return `${id}.${this.hmac(`registration:${id}`, 'base64url')}`;
  }

  private parseRegistrationToken(value: string) {
    const match = value.match(
      /^([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.([A-Za-z0-9_-]{43})$/i,
    );
    if (!match) throw this.invalidToken();
    const expected = Buffer.from(
      this.hmac(`registration:${match[1]}`),
      'base64url',
    );
    const actual = Buffer.from(match[2], 'base64url');
    if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
      throw this.invalidToken();
    }
    return match[1];
  }

  private async limitStart(email: string, source: Source) {
    await Promise.all([
      this.rateLimit.consumeOrThrow(
        `email-auth:start-ip:${this.digest(source.ip ?? 'unknown')}`,
        { limit: 8, windowMs: 60 * 60_000 },
      ),
      this.rateLimit.consumeOrThrow(
        `email-auth:start-address:${this.digest(email)}`,
        { limit: 5, windowMs: 60 * 60_000 },
      ),
      this.rateLimit.consumeOrThrow(
        `email-auth:start-device:${this.digest(source.deviceId || 'unknown')}`,
        { limit: 8, windowMs: 60 * 60_000 },
      ),
    ]);
  }

  private startResponse(id: string, email: string, resendAfter: number) {
    return {
      status: 'ok',
      message: NEUTRAL_MESSAGE,
      challengeId: id,
      maskedEmail: this.maskEmail(email),
      expiresIn: 600,
      resendAfter,
    };
  }

  private normalizeEmail(value: string) {
    return value.trim().toLowerCase();
  }

  private maskEmail(value: string) {
    const [local, domain] = value.split('@');
    return `${local.slice(0, 1)}***@${domain}`;
  }

  private assertUuid(value: string) {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
      throw this.invalidCode();
    }
  }

  private codeDigest(id: string, code: string) {
    return this.hmac(`code:${id}:${code}`, 'hex');
  }

  private hmac(value: string, encoding: 'hex' | 'base64url' = 'base64url') {
    return createHmac('sha256', env.JWT_REFRESH_SECRET)
      .update(`atta-email-auth-v1:${value}`)
      .digest(encoding);
  }

  private digest(value: string) {
    return createHash('sha256').update(value).digest('hex');
  }

  private invalidCode() {
    return new BadRequestException({
      code: 'EMAIL_CODE_INVALID',
      message: 'Неверный или истёкший код',
    });
  }

  private invalidToken() {
    return new ConflictException({
      code: 'EMAIL_REGISTRATION_INVALID',
      message: 'Подтверждение регистрации недействительно или истекло',
    });
  }
}
