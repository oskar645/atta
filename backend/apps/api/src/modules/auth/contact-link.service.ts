import {
  BadRequestException,
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { PhoneVerificationPurpose, Prisma, UserStatus } from '@prisma/client';
import { randomUUID } from 'crypto';

import { normalizeRussianPhone, validateRussianPhoneOrThrow } from '../../common/phone';
import { PhoneVerificationService } from '../phone-verification/phone-verification.service';
import { PrismaService } from '../prisma/prisma.service';
import { AuthenticatedUser } from './auth.types';

const RECENT_AUTH_MS = 15 * 60_000;

@Injectable()
export class ContactLinkService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly phoneVerification: PhoneVerificationService,
  ) {}

  async startPhone(
    authUser: AuthenticatedUser,
    rawPhone: string,
    source: { ip?: string; deviceId?: string; userAgent?: string },
  ) {
    await this.assertRecentAuthentication(authUser);
    const phone = normalizeRussianPhone(rawPhone);
    validateRussianPhoneOrThrow(phone);
    await this.assertPhoneAvailable(phone, authUser.userId);
    return this.phoneVerification.startCallVerification(
      phone,
      'change_phone',
      source,
      {
        id: randomUUID(),
        metadata: {
          contactLink: {
            version: 1,
            userId: authUser.userId,
            sessionId: authUser.sessionId,
            state: 'pending',
          },
        },
      },
    );
  }

  async completePhone(
    authUser: AuthenticatedUser,
    rawPhone: string,
    verificationId: string,
  ) {
    await this.assertRecentAuthentication(authUser);
    const phone = normalizeRussianPhone(rawPhone);
    validateRussianPhoneOrThrow(phone);
    await this.assertPhoneAvailable(phone, authUser.userId);
    const result = await this.phoneVerification.checkCallVerification(
      phone,
      verificationId,
      'change_phone',
    );
    if (result.status !== 'confirmed') return result;

    return this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`
        SELECT id FROM phone_verifications
        WHERE phone = ${phone} AND provider_check_id = ${verificationId}
        FOR UPDATE
      `;
      const verification = await tx.phoneVerification.findFirst({
        where: {
          phone,
          checkId: verificationId,
          purpose: PhoneVerificationPurpose.CHANGE_PHONE,
          status: 'CONFIRMED',
        },
      });
      const metadata = verification?.metadata as Prisma.JsonObject | undefined;
      const link = metadata?.contactLink as Prisma.JsonObject | undefined;
      if (
        !verification ||
        verification.expiresAt.getTime() <= Date.now() ||
        link?.version !== 1 ||
        link?.userId !== authUser.userId ||
        link?.sessionId !== authUser.sessionId ||
        link?.state !== 'pending'
      ) {
        throw new BadRequestException('PHONE_LINK_VERIFICATION_INVALID');
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

  private async assertRecentAuthentication(authUser: AuthenticatedUser) {
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
      throw new UnauthorizedException({
        code: 'RECENT_AUTH_REQUIRED',
        message: 'Для изменения способов входа войдите в аккаунт заново.',
      });
    }
  }

  private async assertPhoneAvailable(
    phone: string,
    userId: string,
    tx?: Prisma.TransactionClient,
  ) {
    const prisma = tx ?? this.prisma;
    const occupied = await prisma.user.findFirst({
      where: {
        phone,
        id: { not: userId },
        deletedAt: null,
        status: { not: UserStatus.DELETED },
      },
      select: { id: true },
    });
    if (occupied) throw new ConflictException('Этот номер уже используется');
  }
}
