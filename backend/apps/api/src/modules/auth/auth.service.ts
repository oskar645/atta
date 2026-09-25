import { AccountDeletionService } from './account-deletion.service';
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import {
  AdminUser,
  DevicePlatform,
  ListingStatus,
  PhoneVerificationPurpose,
  PhoneVerificationStatus,
  Prisma,
  ReferralRewardStatus,
  UserStatus,
} from '@prisma/client';
import { compare, hash } from 'bcryptjs';
import { randomBytes, randomUUID } from 'crypto';

import { env } from '../../config/env';
import { normalizeRussianPhone, validateRussianPhoneOrThrow } from '../../common/phone';
import { resolveReferralUserId } from '../../common/referral-code';
import { parseAdminPhoneNumbers } from '../../config/env';
import { serializeAdminProfile, serializeUser } from '../../common/serializers';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { UserBlocksService } from '../user-blocks/user-blocks.service';
import { WalletService } from '../wallet/wallet.service';
import { LoginDto } from './dto/login.dto';
import { LoginPhoneDto } from './dto/login-phone.dto';
import { LogoutDto } from './dto/logout.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';
import { ResetPasswordPhoneDto } from './dto/reset-password-phone.dto';
import { SignupDto } from './dto/signup.dto';
import { SignupPhoneDto } from './dto/signup-phone.dto';
import { AuthenticatedUser, AuthTokenPayload } from './auth.types';
import { LEGAL_DOCUMENT_VERSION } from './legal-document-version';

type UserWithAdminProfile = {
  id: string;
  email: string | null;
  emailVerifiedAt: Date | null;
  phone: string | null;
  phoneVerified: boolean;
  displayName: string;
  name: string;
  avatarUrl: string | null;
  photoUrl: string | null;
  status: UserStatus;
  blockedAt: Date | null;
  blockReason: string | null;
  lastLoginAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
  passwordHash: string;
  adminProfile: AdminUser | null;
};

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    private readonly storageService: StorageService,
    private readonly walletService: WalletService,
    private readonly userBlocksService: UserBlocksService,
    private readonly accountDeletion: AccountDeletionService,
  ) {}

  async signup(payload: SignupDto) {
    const email = payload.email?.trim().toLowerCase();
    if (!email) {
      throw new ConflictException('Email is required for signup');
    }

    const existingUser = await this.prisma.user.findFirst({
      where: {
        OR: [
          { email },
          payload.phone?.trim() ? { phone: payload.phone.trim() } : undefined,
        ].filter(Boolean) as Array<{ email?: string; phone?: string }>,
      },
      include: {
        adminProfile: true,
      },
    });

    if (existingUser) {
      throw new ConflictException('User already exists');
    }

    const displayName = (payload.display_name ?? payload.displayName ?? '').trim();
    this.assertRequiredSignupConsents(payload);
    const passwordHash = await hash(payload.password, 10);
    const { user, session } = await this.prisma.$transaction(async (tx) => {
      const created = await tx.user.create({
        data: {
          id: randomUUID(),
          email,
          phone: payload.phone?.trim() || null,
          displayName,
          name: displayName,
          passwordHash,
        },
        include: {
          adminProfile: true,
        },
      });
      const userWithAdmin = await this.ensureAdminBootstrapForUser(created, tx);
      await this.recordSignupConsents(userWithAdmin.id, payload, tx);
      return {
        user: userWithAdmin,
        session: await this.createSession(userWithAdmin, tx),
      };
    });
    await this.ensureWalletBootstrapSafely(user.id);

    return this.buildAuthResponse(user, session.auth);
  }

  async login(payload: LoginDto) {
    const email = payload.email?.trim().toLowerCase();
    if (!email) {
      throw new UnauthorizedException('Email login is required');
    }

    const user = await this.prisma.user.findUnique({
      where: {
        email,
      },
      include: {
        adminProfile: true,
      },
    });

    if (!user || user.deletedAt || user.status === UserStatus.DELETED) {
      throw new UnauthorizedException('Invalid login credentials');
    }

    const activeBlock = await this.userBlocksService.getActiveBlock(user.id);
    if (activeBlock) {
      throw this.createUnauthorizedError(
        'ACCOUNT_BLOCKED',
        'Аккаунт заблокирован',
      );
    }

    const isPasswordValid = await compare(payload.password, user.passwordHash);
    if (!isPasswordValid) {
      throw new UnauthorizedException('Invalid login credentials');
    }

    await this.prisma.user.update({
      where: {
        id: user.id,
      },
      data: {
        lastLoginAt: new Date(),
      },
    });

    const userWithAdmin = await this.ensureAdminBootstrapForUser({
      ...user,
      lastLoginAt: new Date(),
    });
    const session = await this.createSession(userWithAdmin);
    await this.ensureWalletBootstrapSafely(user.id);

    return this.buildAuthResponse(userWithAdmin, session.auth);
  }

  async signupPhone(payload: SignupPhoneDto) {
    const normalizedPhone = this.normalizePhoneOrThrow(payload.phone);
    await this.assertPhoneRegistrationAllowed(normalizedPhone);

    const verificationCheckId = this.pickVerificationCheckId(
      payload.verificationCheckId,
      payload.verification_check_id,
    );
    const referralCode = this.pickOptionalReferralCode(
      payload.referralCode,
      payload.referral_code,
    );
    const referralId = this.pickOptionalReferralCode(
      payload.referralId,
      payload.referral_id,
    );
    const displayName = (payload.displayName ?? payload.display_name ?? '').trim();
    this.assertRequiredSignupConsents(payload);

    if (!displayName) {
      throw new BadRequestException('Display name is required');
    }

    const verification = await this.assertConfirmedPhoneVerification({
      phone: normalizedPhone,
      purpose: PhoneVerificationPurpose.SIGNUP,
      checkId: verificationCheckId,
    });

    const existingUser = await this.prisma.user.findUnique({
      where: {
        phone: normalizedPhone,
      },
      include: {
        adminProfile: true,
      },
    });

    if (existingUser && !existingUser.deletedAt && existingUser.status !== UserStatus.DELETED) {
      await this.markReferralFailureById(referralId, 'USER_ALREADY_REGISTERED');
      throw new ConflictException('Phone is already registered');
    }

    const passwordHash = await hash(payload.password, 10);
    const { userWithAdmin, session } = await this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          id: randomUUID(),
          phone: normalizedPhone,
          phoneVerified: true,
          displayName,
          name: displayName,
          passwordHash,
        },
        include: {
          adminProfile: true,
        },
      });

      const createdUserWithAdmin = await this.ensureAdminBootstrapForUser(user, tx);
      const createdSession = await this.createSession(createdUserWithAdmin, tx);
      await this.recordSignupConsents(createdUserWithAdmin.id, payload, tx);
      await tx.phoneVerification.update({
        where: {
          id: verification.id,
        },
        data: {
          createdUserId: createdUserWithAdmin.id,
        },
      });
      await this.walletService.ensureWalletAndBonuses(createdUserWithAdmin.id, tx);
      await this.applyReferralBonusIfEligible({
        newUser: createdUserWithAdmin,
        normalizedPhone,
        referralCode,
        referralId,
        verificationId: verification.id,
        tx,
      });

      return {
        userWithAdmin: createdUserWithAdmin,
        session: createdSession,
      };
    });

    return this.buildAuthResponse(userWithAdmin, session.auth);
  }

  // Called only after the passwordless service locks and validates its capability.
  // Reuses the existing consent, wallet, admin and session implementation in one transaction.
  async authenticatePasswordless(
    phone: string,
    tx: Prisma.TransactionClient,
    registration?: {
      displayName: string;
      acceptedLegal: boolean;
      acceptedPersonalData: boolean;
      acceptedMarketing?: boolean;
      platform?: string;
      referralCode?: string;
      referralId?: string;
      verificationId: string;
    },
  ) {
    const now = new Date();
    const identity = await tx.blockedIdentity.findFirst({
      where: { normalizedPhone: phone, liftedAt: null,
        OR: [{ permanent: true }, { bannedUntil: { gt: now } }] },
    });
    if (identity) throw this.createUnauthorizedError('PHONE_BLOCKED', 'Этот номер заблокирован');

    // Serialize changes to an existing account with deletion/status updates.
    await tx.$queryRaw`SELECT id FROM users WHERE phone = ${phone} FOR UPDATE`;
    let user = await tx.user.findUnique({ where: { phone }, include: { adminProfile: true } });
    if (user) {
      const block = await this.userBlocksService.getActiveBlock(user.id, tx);
      user = await tx.user.findUniqueOrThrow({ where: { id: user.id }, include: { adminProfile: true } });
      if (user.deletedAt || user.status !== UserStatus.ACTIVE || block) {
        throw this.createUnauthorizedError('ACCOUNT_BLOCKED', 'Аккаунт недоступен');
      }
      user = await tx.user.update({ where: { id: user.id },
        data: { lastLoginAt: now }, include: { adminProfile: true } });
    } else {
      if (!registration) return null;
      this.assertRequiredSignupConsents(registration);
      const displayName = registration.displayName.trim();
      if (!displayName) throw new BadRequestException('Display name is required');
      user = await tx.user.create({
        data: { id: randomUUID(), phone, phoneVerified: true, displayName, name: displayName,
          passwordHash: await hash(randomBytes(32).toString('base64url'), 10) },
        include: { adminProfile: true },
      });
      await this.recordSignupConsents(user.id, registration, tx);
      await this.walletService.ensureWalletAndBonuses(user.id, tx);
      await this.applyReferralBonusIfEligible({
        newUser: user, normalizedPhone: phone,
        referralCode: registration.referralCode ?? '', referralId: registration.referralId ?? '',
        verificationId: registration.verificationId, tx,
      });
    }
    const userWithAdmin = await this.ensureAdminBootstrapForUser(user, tx);
    const session = await this.createSession(userWithAdmin, tx);
    return this.buildAuthResponse(userWithAdmin, session.auth);
  }

  async getMarketingConsent(authUser: AuthenticatedUser) {
    const consent = await (this.prisma as any).userConsent.findFirst({
      where: {
        userId: authUser.userId,
        consentType: 'MARKETING_MESSAGES',
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    return {
      accepted: Boolean(consent?.acceptedAt && !consent?.withdrawnAt),
      documentVersion: consent?.documentVersion ?? LEGAL_DOCUMENT_VERSION,
      acceptedAt: consent?.acceptedAt ?? null,
      withdrawnAt: consent?.withdrawnAt ?? null,
    };
  }

  async updateMarketingConsent(
    authUser: AuthenticatedUser,
    payload: { accepted?: boolean; platform?: string },
    request?: any,
  ) {
    const now = new Date();
    const accepted = payload.accepted === true;
    const platform = this.parseConsentPlatform(payload.platform);
    const technicalInfo = {
      source: 'settings',
      ip: this.pickRequestIp(request),
      userAgent: request?.headers?.['user-agent']?.toString() ?? null,
    };

    const consent = await (this.prisma as any).userConsent.create({
      data: {
        userId: authUser.userId,
        consentType: 'MARKETING_MESSAGES',
        documentVersion: LEGAL_DOCUMENT_VERSION,
        acceptedAt: accepted ? now : null,
        withdrawnAt: accepted ? null : now,
        platform,
        technicalInfo,
      },
    });

    return {
      accepted,
      documentVersion: consent.documentVersion,
      acceptedAt: consent.acceptedAt,
      withdrawnAt: consent.withdrawnAt,
    };
  }

  private assertRequiredSignupConsents(payload: {
    acceptedLegal?: boolean;
    acceptedPersonalData?: boolean;
  }) {
    if (payload.acceptedLegal !== true) {
      throw new BadRequestException('Terms acceptance is required');
    }
    if (payload.acceptedPersonalData !== true) {
      throw new BadRequestException('Personal data consent is required');
    }
  }

  private async recordSignupConsents(
    userId: string,
    payload: {
      acceptedLegal?: boolean;
      acceptedPersonalData?: boolean;
      acceptedMarketing?: boolean;
      platform?: string;
    },
    tx: Prisma.TransactionClient,
  ) {
    const acceptedAt = new Date();
    const platform = this.parseConsentPlatform(payload.platform);
    const technicalInfo = {
      source: 'signup',
      marketingDefaultFalse: payload.acceptedMarketing !== true,
    };

    await (tx as any).userConsent.createMany({
      data: [
        {
          userId,
          consentType: 'TERMS_ACCEPTANCE',
          documentVersion: LEGAL_DOCUMENT_VERSION,
          acceptedAt,
          platform,
          technicalInfo,
        },
        {
          userId,
          consentType: 'PERSONAL_DATA_PROCESSING',
          documentVersion: LEGAL_DOCUMENT_VERSION,
          acceptedAt,
          platform,
          technicalInfo,
        },
        ...(payload.acceptedMarketing === true
          ? [
              {
                userId,
                consentType: 'MARKETING_MESSAGES',
                documentVersion: LEGAL_DOCUMENT_VERSION,
                acceptedAt,
                platform,
                technicalInfo,
              },
            ]
          : []),
      ],
    });
  }

  private parseConsentPlatform(value?: string): DevicePlatform | undefined {
    switch ((value ?? '').trim().toUpperCase()) {
      case 'IOS':
        return DevicePlatform.IOS;
      case 'ANDROID':
        return DevicePlatform.ANDROID;
      case 'WEB':
        return DevicePlatform.WEB;
      default:
        return undefined;
    }
  }

  private pickRequestIp(request?: any) {
    const forwarded = request?.headers?.['x-forwarded-for']?.toString() ?? '';
    return (
      request?.ip?.toString().trim() ||
      forwarded.split(',')[0]?.trim() ||
      null
    );
  }

  async loginPhone(payload: LoginPhoneDto) {
    const rawPhone = (payload.phone ?? '').trim();
    const password = (payload.password ?? '').trim();
    if (!rawPhone) {
      throw this.createBadRequestError(
        'PHONE_REQUIRED',
        'Введите номер телефона',
      );
    }
    if (!password) {
      throw this.createBadRequestError(
        'PASSWORD_REQUIRED',
        'Введите пароль',
      );
    }
    if (password.length < 8) {
      throw this.createBadRequestError(
        'PASSWORD_REQUIRED',
        'Введите пароль',
      );
    }

    const normalizedPhone = this.normalizePhoneOrThrow(rawPhone);
    const verificationCheckId = this.pickOptionalVerificationCheckId(
      payload.verificationCheckId,
      payload.verification_check_id,
    );

    if (verificationCheckId) {
      await this.assertConfirmedPhoneVerification({
        phone: normalizedPhone,
        purpose: PhoneVerificationPurpose.LOGIN,
        checkId: verificationCheckId,
      });
    }

    const user = await this.prisma.user.findUnique({
      where: {
        phone: normalizedPhone,
      },
      include: {
        adminProfile: true,
      },
    });

    if (!user || user.deletedAt || user.status === UserStatus.DELETED) {
      throw this.createUserNotFoundError();
    }

    const activeBlock = await this.userBlocksService.getActiveBlock(user.id);
    if (activeBlock) {
      throw this.createUnauthorizedError(
        'ACCOUNT_BLOCKED',
        'Аккаунт заблокирован',
      );
    }

    const isPasswordValid = await compare(password, user.passwordHash);
    if (!isPasswordValid) {
      throw this.createUnauthorizedError(
        'INVALID_PHONE_OR_PASSWORD',
        'Неверный номер телефона или пароль',
      );
    }

    const lastLoginAt = new Date();
    await this.prisma.user.update({
      where: {
        id: user.id,
      },
      data: {
        lastLoginAt,
      },
    });

    const userWithAdmin = await this.ensureAdminBootstrapForUser({
      ...user,
      lastLoginAt,
    });
    const session = await this.createSession(userWithAdmin);
    await this.ensureWalletBootstrapSafely(userWithAdmin.id);

    return this.buildAuthResponse(userWithAdmin, session.auth);
  }

  async resetPasswordPhone(payload: ResetPasswordPhoneDto) {
    const normalizedPhone = this.normalizePhoneOrThrow(payload.phone);
    const verificationCheckId = this.pickVerificationCheckId(
      payload.verificationCheckId,
      payload.verification_check_id,
    );
    const newPassword = (payload.newPassword ?? payload.new_password ?? '').trim();

    if (newPassword.length < 8) {
      throw this.createBadRequestError(
        'PASSWORD_TOO_SHORT',
        'Пароль должен быть не короче 8 символов',
      );
    }

    await this.assertConfirmedPhoneVerification({
      phone: normalizedPhone,
      purpose: PhoneVerificationPurpose.RESET_PASSWORD,
      checkId: verificationCheckId,
    });

    const user = await this.prisma.user.findUnique({
      where: {
        phone: normalizedPhone,
      },
      select: {
        id: true,
        status: true,
        deletedAt: true,
      },
    });

    if (!user || user.deletedAt || user.status === UserStatus.DELETED) {
      throw this.createUserNotFoundError();
    }

    await this.prisma.user.update({
      where: {
        id: user.id,
      },
      data: {
        passwordHash: await hash(newPassword, 10),
        phoneVerified: true,
      },
    });

    return {
      status: 'ok',
    };
  }

  async getMe(authUser: AuthenticatedUser) {
    await this.ensureWalletBootstrapSafely(authUser.userId);
    const user = await this.ensureAdminBootstrapForUserId(authUser.userId);
    const block = await this.userBlocksService.getActiveBlock(authUser.userId);

    return {
      ...this.buildUserEnvelope(user),
      block_status: this.userBlocksService.serializeBlock(block),
    };
  }

  async refresh(payload: RefreshTokenDto) {
    let tokenPayload: AuthTokenPayload;
    try {
      tokenPayload = await this.jwtService.verifyAsync<AuthTokenPayload>(
        payload.refreshToken,
        {
          secret: env.JWT_REFRESH_SECRET,
        },
      );
    } catch {
      throw new UnauthorizedException('Refresh token is invalid or expired');
    }

    if (tokenPayload.type !== 'refresh') {
      throw new UnauthorizedException('Refresh token type is invalid');
    }

    const session = await this.prisma.userSession.findUnique({
      where: {
        id: tokenPayload.sessionId,
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
      !session ||
      session.userId !== tokenPayload.sub ||
      session.revokedAt ||
      session.expiresAt.getTime() <= Date.now()
    ) {
      throw new UnauthorizedException('Refresh session is not active');
    }

    const isRefreshTokenValid = await compare(
      payload.refreshToken,
      session.refreshTokenHash,
    );
    if (!isRefreshTokenValid) {
      throw new UnauthorizedException('Refresh token does not match session');
    }

    if (
      session.user.deletedAt ||
      session.user.status === UserStatus.DELETED
    ) {
      throw new UnauthorizedException('User account is deleted');
    }

    const userWithAdmin = await this.ensureAdminBootstrapForUser(session.user);
    const tokens = await this.buildAuthTokens(
      userWithAdmin,
      session.id,
      userWithAdmin.adminProfile,
    );

    await this.prisma.userSession.update({
      where: {
        id: session.id,
      },
      data: {
        refreshTokenHash: await hash(tokens.refresh_token, 10),
        expiresAt: this.computeExpiry(env.JWT_REFRESH_TTL),
      },
    });

    return this.buildAuthResponse(userWithAdmin, tokens);
  }

  async logout(authUser: AuthenticatedUser, payload?: LogoutDto) {
    await this.prisma.userDevice.updateMany({
      where: { userId: authUser.userId, sessionId: authUser.sessionId },
      data: { isActive: false },
    });
    if (payload?.refreshToken) {
      await this.revokeSessionByRefreshToken(payload.refreshToken, authUser.userId);
    } else {
      await this.prisma.userSession.updateMany({
        where: {
          id: authUser.sessionId,
          userId: authUser.userId,
          revokedAt: null,
        },
        data: {
          revokedAt: new Date(),
        },
      });
    }

    return {
      revoked: true,
    };
  }

  async revokeOtherSessions(authUser: AuthenticatedUser) {
    const result = await this.prisma.userSession.updateMany({
      where: {
        userId: authUser.userId,
        id: {
          not: authUser.sessionId,
        },
        revokedAt: null,
      },
      data: {
        revokedAt: new Date(),
      },
    });

    return {
      revoked: result.count,
    };
  }

  async revokeAllSessions(authUser: AuthenticatedUser) {
    const result = await this.prisma.userSession.updateMany({
      where: {
        userId: authUser.userId,
        revokedAt: null,
      },
      data: {
        revokedAt: new Date(),
      },
    });

    return {
      revoked: result.count,
    };
  }

  async deleteAccount(authUser: AuthenticatedUser) {
    return this.accountDeletion.deleteUser(authUser.userId);
  }

  async createSessionForUser(user: UserWithAdminProfile) {
    const userWithAdmin = await this.ensureAdminBootstrapForUser(user);
    const session = await this.createSession(userWithAdmin);
    await this.ensureWalletBootstrapSafely(userWithAdmin.id);

    return this.buildAuthResponse(userWithAdmin, session.auth);
  }

  async completeAccountRecovery(grantId: string, tokenHash: string, phone: string) {
    return this.prisma.$transaction(async (tx) => {
      const grants = await tx.$queryRaw<Array<{ id: string; user_id: string; expires_at: Date }>>(Prisma.sql`
        SELECT id, user_id, expires_at FROM account_recovery_grants
        WHERE id = ${grantId}::uuid AND token_hash = ${tokenHash}
          AND consumed_at IS NULL
        FOR UPDATE
      `);
      const grant = grants[0];
      if (!grant || grant.expires_at.getTime() <= Date.now()) {
        throw new BadRequestException('Сессия восстановления недействительна или истекла');
      }
      const occupied = await tx.user.findFirst({ where: { phone, id: { not: grant.user_id }, deletedAt: null }, select: { id: true } });
      if (occupied) throw new ConflictException('Этот номер уже используется');
      const user = await tx.user.update({
        where: { id: grant.user_id },
        data: { phone, phoneVerified: true, lastLoginAt: new Date() },
        include: { adminProfile: true },
      });
      const recoveredAt = new Date();
      await tx.userSession.updateMany({ where: { userId: user.id, revokedAt: null }, data: { revokedAt: recoveredAt } });
      await tx.restoreCredential.updateMany({ where: { userId: user.id, revokedAt: null }, data: { revokedAt: recoveredAt } });
      await tx.accountRecoveryGrant.update({ where: { id: grantId }, data: { consumedAt: recoveredAt } });
      const session = await this.createSession(user, tx);
      return this.buildAuthResponse(user, session.auth);
    });
  }

  async findActiveUserByIdOrThrow(userId: string) {
    let user = await this.findActiveUserById(userId);
    const activeBlock = await this.userBlocksService.getActiveBlock(user.id);
    user = await this.findActiveUserById(userId);
    if (activeBlock || user.status !== UserStatus.ACTIVE) {
      throw this.createUnauthorizedError(
        'ACCOUNT_BLOCKED',
        'Аккаунт заблокирован',
      );
    }

    return user;
  }

  private async createSession(
    user: UserWithAdminProfile,
    tx?: Prisma.TransactionClient,
  ) {
    const prisma = tx ?? this.prisma;
    const sessionId = randomUUID();
    const auth = await this.buildAuthTokens(user, sessionId, user.adminProfile);

    await prisma.userSession.create({
      data: {
        id: sessionId,
        userId: user.id,
        refreshTokenHash: await hash(auth.refresh_token, 10),
        expiresAt: this.computeExpiry(env.JWT_REFRESH_TTL),
      },
    });

    return { auth };
  }

  private async ensureWalletBootstrapSafely(userId: string) {
    try {
      await this.walletService.ensureWalletAndBonusesSafely(userId);
    } catch {
      // Wallet bootstrap must never block auth/profile responses.
    }
  }

  private async buildAuthTokens(
    user: Pick<UserWithAdminProfile, 'id' | 'email'>,
    sessionId: string,
    adminProfile: AdminUser | null,
  ) {
    const role: 'admin' | 'user' = adminProfile?.isAdmin ? 'admin' : 'user';
    const basePayload = {
      sub: user.id,
      sessionId,
      email: user.email,
      role,
    };

    const [accessToken, refreshToken] = await Promise.all([
      this.jwtService.signAsync(
        {
          ...basePayload,
          type: 'access',
        },
        {
          secret: env.JWT_ACCESS_SECRET,
          expiresIn: env.JWT_ACCESS_TTL,
        },
      ),
      this.jwtService.signAsync(
        {
          ...basePayload,
          type: 'refresh',
        },
        {
          secret: env.JWT_REFRESH_SECRET,
          expiresIn: env.JWT_REFRESH_TTL,
        },
      ),
    ]);

    return {
      access_token: accessToken,
      refresh_token: refreshToken,
      token_type: 'Bearer',
      expires_in: this.ttlToSeconds(env.JWT_ACCESS_TTL),
      user_id: user.id,
      session_id: sessionId,
    };
  }

  private ttlToSeconds(ttl: string): number {
    const match = ttl.trim().match(/^(\d+)([smhd])$/i);
    if (!match) {
      return 0;
    }

    const value = Number(match[1]);
    const unit = match[2].toLowerCase();
    switch (unit) {
      case 'd':
        return value * 24 * 60 * 60;
      case 'h':
        return value * 60 * 60;
      case 'm':
        return value * 60;
      case 's':
      default:
        return value;
    }
  }

  private computeExpiry(ttl: string): Date {
    return new Date(Date.now() + this.ttlToSeconds(ttl) * 1000);
  }

  private async findActiveUserById(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: {
        id: userId,
      },
      include: {
        adminProfile: true,
      },
    });

    if (!user || user.deletedAt || user.status === UserStatus.DELETED) {
      throw new NotFoundException('User not found');
    }

    return user;
  }

  private async revokeSessionByRefreshToken(refreshToken: string, userId: string) {
    let tokenPayload: AuthTokenPayload;
    try {
      tokenPayload = await this.jwtService.verifyAsync<AuthTokenPayload>(
        refreshToken,
        {
          secret: env.JWT_REFRESH_SECRET,
        },
      );
    } catch {
      throw new UnauthorizedException('Refresh token is invalid or expired');
    }

    if (tokenPayload.sub !== userId || tokenPayload.type !== 'refresh') {
      throw new UnauthorizedException('Refresh token does not belong to user');
    }

    await this.prisma.userSession.updateMany({
      where: {
        id: tokenPayload.sessionId,
        userId,
        revokedAt: null,
      },
      data: {
        revokedAt: new Date(),
      },
    });
  }

  private buildAuthResponse(
    user: UserWithAdminProfile,
    auth: {
      access_token: string;
      refresh_token: string;
      token_type: string;
      expires_in: number;
      user_id: string;
      session_id: string;
    },
  ) {
    return {
      ...this.buildUserEnvelope(user),
      auth,
    };
  }

  private buildUserEnvelope(user: UserWithAdminProfile) {
    const isAdmin = user.adminProfile?.isAdmin === true;

    return {
      user: serializeUser(user, { includePrivate: true }),
      admin_profile: serializeAdminProfile(user.adminProfile),
      is_admin: isAdmin,
      isAdmin,
    };
  }

  private async assertPhoneRegistrationAllowed(normalizedPhone: string) {
    const now = new Date();
    await this.prisma.blockedIdentity.updateMany({
      where: {
        normalizedPhone,
        liftedAt: null,
        permanent: false,
        bannedUntil: {
          not: null,
          lte: now,
        },
      },
      data: {
        liftedAt: now,
      },
    });

    const blockedIdentity = await this.prisma.blockedIdentity.findFirst({
      where: {
        normalizedPhone,
        liftedAt: null,
        OR: [
          { permanent: true },
          {
            bannedUntil: {
              not: null,
              gt: now,
            },
          },
        ],
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    if (blockedIdentity) {
      throw this.createUnauthorizedError(
        'PHONE_BLOCKED',
        'Этот номер телефона заблокирован. Обратитесь в поддержку',
      );
    }
  }

  private normalizePhoneOrThrow(phone: string) {
    const normalizedPhone = normalizeRussianPhone(phone);
    if (!normalizedPhone) {
      throw this.createBadRequestError(
        'PHONE_REQUIRED',
        'Введите номер телефона',
      );
    }
    validateRussianPhoneOrThrow(normalizedPhone);
    return normalizedPhone;
  }

  private createBadRequestError(code: string, message: string) {
    return new BadRequestException({ code, message });
  }

  private createUnauthorizedError(code: string, message: string) {
    return new UnauthorizedException({ code, message });
  }

  private createUserNotFoundError() {
    return new NotFoundException({
      code: 'USER_NOT_FOUND',
      message: 'На этом номере аккаунта нет',
    });
  }

  private pickVerificationCheckId(...values: Array<string | undefined>) {
    const checkId = values.find((value) => value?.trim())?.trim() ?? '';
    if (!checkId) {
      throw new BadRequestException('verificationCheckId is required');
    }
    return checkId;
  }

  private pickOptionalVerificationCheckId(
    ...values: Array<string | undefined>
  ) {
    return values.find((value) => value?.trim())?.trim() ?? '';
  }

  private pickOptionalReferralCode(...values: Array<string | undefined>) {
    return values.find((value) => value?.trim())?.trim() ?? '';
  }

  async recordReferralAppOpen(payload: {
    referralCode?: string;
    referral_code?: string;
    appOpened?: boolean;
    app_opened?: boolean;
  }) {
    const referralCode = this.pickOptionalReferralCode(
      payload.referralCode,
      payload.referral_code,
    );
    const inviterUserId = resolveReferralUserId(referralCode);
    if (!referralCode || !inviterUserId) {
      return {
        source: 'timeweb',
        referralId: null,
        accepted: false,
        failureReason: 'INVALID_REFERRAL_CODE',
      };
    }

    const inviter = await this.prisma.user.findUnique({
      where: {
        id: inviterUserId,
      },
      select: {
        id: true,
        deletedAt: true,
        status: true,
      },
    });
    if (!inviter || inviter.deletedAt || inviter.status === UserStatus.DELETED) {
      return {
        source: 'timeweb',
        referralId: null,
        accepted: false,
        failureReason: 'INVITER_NOT_FOUND',
      };
    }

    const appOpened = payload.appOpened ?? payload.app_opened ?? true;
    const now = new Date();
    const referral = await this.prisma.referral.create({
      data: {
        inviterUserId: inviter.id,
        referralCode,
        openedAt: now,
        appOpenedAt: appOpened ? now : null,
        rewardStatus: ReferralRewardStatus.PENDING,
      },
      select: {
        id: true,
      },
    });

    return {
      source: 'timeweb',
      referralId: referral.id,
      accepted: true,
      failureReason: null,
    };
  }

  private async assertConfirmedPhoneVerification(params: {
    phone: string;
    purpose: PhoneVerificationPurpose;
    checkId: string;
  }) {
    const verification = await this.prisma.phoneVerification.findFirst({
      where: {
        phone: params.phone,
        purpose: params.purpose,
        checkId: params.checkId,
        status: PhoneVerificationStatus.CONFIRMED,
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    if (!verification || (verification.metadata as Prisma.JsonObject)?.passwordless) {
      throw new BadRequestException('Phone verification is not confirmed');
    }

    if (verification.expiresAt.getTime() <= Date.now()) {
      throw new BadRequestException('Phone verification has expired');
    }

    return verification;
  }

  private async applyReferralBonusIfEligible(params: {
    newUser: UserWithAdminProfile;
    normalizedPhone: string;
    referralCode: string;
    referralId: string;
    verificationId: string;
    tx?: Prisma.TransactionClient;
  }) {
    const normalizedReferralCode = params.referralCode.trim();
    if (!normalizedReferralCode) {
      await this.markReferralFailureById(
        params.referralId,
        'APP_OPENED_WITHOUT_REFERRAL_CODE',
        params.tx,
      );
      return;
    }

    const inviterUserId = resolveReferralUserId(normalizedReferralCode);
    if (!inviterUserId || inviterUserId === params.newUser.id) {
      await this.markReferralFailureById(
        params.referralId,
        inviterUserId === params.newUser.id
          ? 'SELF_REFERRAL'
          : 'INVALID_REFERRAL_CODE',
        params.tx,
      );
      return;
    }

    const prisma = params.tx ?? this.prisma;
    await this.markReferralSignupStarted(params.referralId, params.tx);
    const priorSignupForPhone = await prisma.phoneVerification.findFirst({
      where: {
        phone: params.normalizedPhone,
        purpose: { in: [PhoneVerificationPurpose.SIGNUP, PhoneVerificationPurpose.LOGIN] },
        status: PhoneVerificationStatus.CONFIRMED,
        createdUserId: {
          not: null,
        },
        id: {
          not: params.verificationId,
        },
      },
      select: {
        id: true,
      },
    });
    if (priorSignupForPhone) {
      await this.markReferralFailureById(
        params.referralId,
        'USER_ALREADY_REGISTERED',
        params.tx,
      );
      return;
    }

    const inviter = await prisma.user.findUnique({
      where: {
        id: inviterUserId,
      },
      include: {
        adminProfile: true,
      },
    });
    if (!inviter || inviter.deletedAt || inviter.status === UserStatus.DELETED) {
      await this.markReferralFailureById(
        params.referralId,
        'INVITER_NOT_FOUND',
        params.tx,
      );
      return;
    }

    const inviterPhone = normalizeRussianPhone(inviter.phone ?? '');
    if (inviterPhone && inviterPhone === params.normalizedPhone) {
      await this.markReferralFailureById(
        params.referralId,
        'SELF_REFERRAL',
        params.tx,
      );
      return;
    }

    try {
      await this.walletService.accrueReferralInviterBonusIfNeeded(
        inviter.id,
        {
          invitedUserId: params.newUser.id,
          referralCode: normalizedReferralCode,
          referralId: params.referralId,
        },
        params.tx,
      );
    } catch (error) {
      await this.markReferralFailureById(
        params.referralId,
        'REWARD_ERROR_RETRYABLE',
        params.tx,
        ReferralRewardStatus.FAILED_RETRYABLE,
      );
      throw error;
    }
  }

  private async markReferralSignupStarted(
    referralId: string,
    tx?: Prisma.TransactionClient,
  ) {
    const normalizedReferralId = referralId.trim();
    if (!normalizedReferralId) return;
    const prisma = tx ?? this.prisma;
    await prisma.referral
      .update({
        where: {
          id: normalizedReferralId,
        },
        data: {
          signupStartedAt: new Date(),
        },
      })
      .catch(() => undefined);
  }

  private async markReferralFailureById(
    referralId: string,
    failureReason: string,
    tx?: Prisma.TransactionClient,
    rewardStatus: ReferralRewardStatus = ReferralRewardStatus.NOT_REWARDED,
  ) {
    const normalizedReferralId = referralId.trim();
    if (!normalizedReferralId) return;
    const prisma = tx ?? this.prisma;
    await prisma.referral
      .update({
        where: {
          id: normalizedReferralId,
        },
        data: {
          rewardStatus,
          failureReason,
        },
      })
      .catch(() => undefined);
  }

  private async ensureAdminBootstrapForUserId(userId: string) {
    const user = await this.findActiveUserById(userId);
    return this.ensureAdminBootstrapForUser(user);
  }

  private async ensureAdminBootstrapForUser(
    user: UserWithAdminProfile,
    tx?: Prisma.TransactionClient,
  ) {
    const normalizedPhone = normalizeRussianPhone(user.phone ?? '');
    const adminPhones = new Set(parseAdminPhoneNumbers());
    if (normalizedPhone.length > 0 && adminPhones.has(normalizedPhone)) {
      const prisma = tx ?? this.prisma;
      await prisma.adminUser.upsert({
        where: {
          userId: user.id,
        },
        update: {
          isAdmin: true,
          role: 'admin',
        },
        create: {
          userId: user.id,
          isAdmin: true,
          role: 'admin',
          permissions: {},
        },
      });
    }

    const prisma = tx ?? this.prisma;
    const refreshedUser = await prisma.user.findUnique({
      where: {
        id: user.id,
      },
      include: {
        adminProfile: true,
      },
    });

    if (!refreshedUser) {
      throw new NotFoundException('User not found after signup');
    }

    return refreshedUser as UserWithAdminProfile;
  }
}
