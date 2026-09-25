import { BadRequestException, ConflictException, Injectable } from '@nestjs/common';
import { EmailChallengePurpose, Prisma, UserStatus } from '@prisma/client';
import { createHash, randomInt, randomUUID, randomBytes, timingSafeEqual } from 'crypto';

import { normalizeRussianPhone, validateRussianPhoneOrThrow } from '../../common/phone';
import { EmailService } from '../email/email.service';
import { PhoneVerificationService } from '../phone-verification/phone-verification.service';
import { PrismaService } from '../prisma/prisma.service';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { AuthService } from './auth.service';

const CODE_TTL_MS = 10 * 60_000;
const RESEND_MS = 60_000;
const GRANT_TTL_MS = 15 * 60_000;
const NEUTRAL_MESSAGE = 'Если этот email был подтверждён в ATTA, мы отправили код.';
type Source = { ip?: string; deviceId?: string; userAgent?: string };

@Injectable()
export class AccountRecoveryService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rateLimit: RateLimitService,
    private readonly email: EmailService,
    private readonly phoneVerification: PhoneVerificationService,
    private readonly auth: AuthService,
  ) {}

  async startRecoveryEmail(userId: string, rawEmail: string, source: Source = {}) {
    this.email.ensureAvailable();
    const email = this.normalizeEmail(rawEmail);
    await this.limitStart('settings', email, userId, source);
    const duplicate = await this.prisma.user.findFirst({
      where: { email: { equals: email, mode: 'insensitive' }, id: { not: userId } },
      select: { id: true },
    });
    if (duplicate) throw new ConflictException('Этот email уже используется');
    const challenge = await this.createChallenge(userId, EmailChallengePurpose.RECOVERY_EMAIL, email, source);
    // A client can lose the HTTP response after SMTP has accepted the email.
    // During the cooldown, acknowledge the already-created challenge instead
    // of creating/sending another one. This also lets older clients recover by
    // pressing the button again after a transport timeout.
    if (challenge.code) await this.email.sendVerificationCode({ to: email, code: challenge.code });
    return this.challengeResponse(challenge.id, email, 'Код отправлен', challenge.resendAfter);
  }

  async verifyRecoveryEmail(userId: string, challengeId: string, code: string) {
    const challenge = await this.consumeCode(challengeId, code, EmailChallengePurpose.RECOVERY_EMAIL, userId);
    const previous = await this.prisma.$transaction(async (tx) => {
      const user = await tx.user.findUniqueOrThrow({ where: { id: userId }, select: { email: true, emailVerifiedAt: true } });
      const duplicate = await tx.user.findFirst({ where: { email: { equals: challenge.targetEmail, mode: 'insensitive' }, id: { not: userId } }, select: { id: true } });
      if (duplicate) throw new ConflictException('Этот email уже используется');
      await tx.user.update({ where: { id: userId }, data: { email: challenge.targetEmail, emailVerifiedAt: new Date() } });
      const consumed = await tx.emailChallenge.updateMany({ where: { id: challenge.id, consumedAt: null }, data: { consumedAt: new Date() } });
      if (consumed.count !== 1) throw this.invalidCode();
      return user.emailVerifiedAt ? user.email : null;
    });
    if (previous && previous.toLowerCase() !== challenge.targetEmail) {
      this.email.sendRecoveryEmailChanged({ to: previous }).catch(() => undefined);
    }
    return { verified: true, email: this.maskEmail(challenge.targetEmail), emailVerifiedAt: new Date().toISOString() };
  }

  async startAccountRecovery(rawEmail: string, source: Source = {}) {
    this.email.ensureAvailable();
    const email = this.normalizeEmail(rawEmail);
    await this.limitStart('account', email, undefined, source);
    const user = await this.prisma.user.findFirst({
      where: { email: { equals: email, mode: 'insensitive' }, emailVerifiedAt: { not: null }, deletedAt: null, status: UserStatus.ACTIVE },
      select: { id: true },
    });
    const publicChallengeId = randomUUID();
    if (!user) return { status: 'ok', message: NEUTRAL_MESSAGE, challengeId: publicChallengeId, expiresIn: 600, resendAfter: 60 };
    const challenge = await this.createChallenge(user.id, EmailChallengePurpose.ACCOUNT_RECOVERY, email, source, publicChallengeId);
    // Keep the public response indistinguishable even during a transient SMTP
    // delivery failure. Missing SMTP configuration was rejected above for all
    // addresses before the account lookup.
    await this.email.sendVerificationCode({ to: email, code: challenge.code! }).catch(() => undefined);
    return { status: 'ok', message: NEUTRAL_MESSAGE, challengeId: challenge.id, expiresIn: 600, resendAfter: 60 };
  }

  async verifyAccountRecoveryEmail(challengeId: string, code: string, source: Source = {}) {
    await this.rateLimit.consumeOrThrow(`recovery:verify:${this.digest(source.ip ?? 'unknown')}`, { limit: 20, windowMs: 60_000 });
    const challenge = await this.consumeCode(challengeId, code, EmailChallengePurpose.ACCOUNT_RECOVERY);
    if (!challenge.userId) throw this.invalidCode();
    const token = randomBytes(32).toString('base64url');
    await this.prisma.$transaction(async (tx) => {
      const consumed = await tx.emailChallenge.updateMany({ where: { id: challenge.id, consumedAt: null }, data: { consumedAt: new Date() } });
      if (consumed.count !== 1) throw this.invalidCode();
      await tx.accountRecoveryGrant.create({ data: { userId: challenge.userId!, tokenHash: this.digest(token), expiresAt: new Date(Date.now() + GRANT_TTL_MS) } });
    });
    return { recoveryToken: token, expiresIn: 900 };
  }

  async startPhone(token: string, rawPhone: string, source: Source = {}) {
    const grant = await this.validGrant(token);
    const phone = normalizeRussianPhone(rawPhone);
    validateRussianPhoneOrThrow(phone);
    await this.assertPhoneAvailable(phone, grant.userId);
    const result = await this.phoneVerification.startCallVerification(phone, 'change_phone', source, {
      id: randomUUID(), metadata: { accountRecovery: { grantId: grant.id } },
    });
    return { ...result, phone };
  }

  async completePhone(token: string, rawPhone: string, checkId: string) {
    const grant = await this.validGrant(token);
    const phone = normalizeRussianPhone(rawPhone);
    validateRussianPhoneOrThrow(phone);
    await this.assertPhoneAvailable(phone, grant.userId);
    const verification = await this.phoneVerification.checkCallVerification(phone, checkId, 'change_phone');
    if (verification.status !== 'confirmed') return verification;
    const response = await this.auth.completeAccountRecovery(grant.id, this.digest(token), phone);
    const user = await this.prisma.user.findUnique({ where: { id: grant.userId }, select: { email: true, emailVerifiedAt: true } });
    if (user?.email && user.emailVerifiedAt) this.email.sendRecoveryCompleted({ to: user.email }).catch(() => undefined);
    return response;
  }

  private async createChallenge(userId: string, purpose: EmailChallengePurpose, email: string, source: Source, id = randomUUID()) {
    const latest = await this.prisma.emailChallenge.findFirst({ where: { userId, purpose, targetEmail: email }, orderBy: { createdAt: 'desc' } });
    if (latest && latest.resendAvailableAt.getTime() > Date.now()) {
      const retryAfter = Math.ceil((latest.resendAvailableAt.getTime() - Date.now()) / 1000);
      if (purpose === EmailChallengePurpose.RECOVERY_EMAIL) return { id: latest.id, resendAfter: retryAfter };
      throw new BadRequestException({ code: 'EMAIL_COOLDOWN', retryAfter: Math.ceil((latest.resendAvailableAt.getTime() - Date.now()) / 1000), message: 'Код уже отправлен' });
    }
    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    await this.prisma.emailChallenge.create({ data: { id, userId, purpose, targetEmail: email, codeHash: this.digest(`${id}:${code}`), expiresAt: new Date(Date.now() + CODE_TTL_MS), resendAvailableAt: new Date(Date.now() + RESEND_MS), requestedByIp: source.ip, requestedByDevice: source.deviceId, metadata: {} } });
    return { id, code, resendAfter: RESEND_MS / 1000 };
  }

  private async consumeCode(id: string, code: string, purpose: EmailChallengePurpose, userId?: string) {
    const challenge = await this.prisma.emailChallenge.findFirst({ where: { id, purpose, ...(userId ? { userId } : {}) } });
    if (!challenge || challenge.consumedAt || challenge.expiresAt.getTime() <= Date.now() || challenge.attempts >= challenge.maxAttempts) throw this.invalidCode();
    const actual = Buffer.from(this.digest(`${id}:${code}`));
    const expected = Buffer.from(challenge.codeHash);
    const correct = actual.length === expected.length && timingSafeEqual(actual, expected);
    if (!correct) {
      await this.prisma.emailChallenge.update({ where: { id }, data: { attempts: { increment: 1 } } });
      throw this.invalidCode();
    }
    return challenge;
  }

  private async validGrant(token: string) {
    const grant = await this.prisma.accountRecoveryGrant.findUnique({ where: { tokenHash: this.digest(token) } });
    if (!grant || grant.consumedAt || grant.expiresAt.getTime() <= Date.now()) throw new BadRequestException('Сессия восстановления недействительна или истекла');
    return grant;
  }

  private async assertPhoneAvailable(phone: string, userId: string) {
    const occupied = await this.prisma.user.findFirst({ where: { phone, id: { not: userId }, deletedAt: null }, select: { id: true } });
    if (occupied) throw new ConflictException('Этот номер уже используется');
  }

  private async limitStart(scope: string, email: string, userId?: string, source: Source = {}) {
    await Promise.all([
      this.rateLimit.consumeOrThrow(`email:${scope}:ip:${this.digest(source.ip ?? 'unknown')}`, { limit: 8, windowMs: 60 * 60_000 }),
      this.rateLimit.consumeOrThrow(`email:${scope}:address:${this.digest(email)}`, { limit: 5, windowMs: 60 * 60_000 }),
      ...(userId ? [this.rateLimit.consumeOrThrow(`email:${scope}:user:${userId}`, { limit: 5, windowMs: 60 * 60_000 })] : []),
    ]);
  }

  private normalizeEmail(value: string) { return value.trim().toLowerCase(); }
  private digest(value: string) { return createHash('sha256').update(value).digest('hex'); }
  private maskEmail(value: string) { const [local, domain] = value.split('@'); return `${local[0]}***@${domain}`; }
  private invalidCode() { return new BadRequestException('Неверный или истёкший код'); }
  private challengeResponse(id: string, email: string, message: string, resendAfter = 60) { return { challengeId: id, maskedEmail: this.maskEmail(email), expiresIn: 600, resendAfter, message }; }
}
