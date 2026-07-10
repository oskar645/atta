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
  ListingStatus,
  PhoneVerificationPurpose,
  PhoneVerificationStatus,
  UserStatus,
} from '@prisma/client';
import { compare, hash } from 'bcryptjs';
import { randomUUID } from 'crypto';

import { env } from '../../config/env';
import { normalizeRussianPhone, validateRussianPhoneOrThrow } from '../../common/phone';
import { resolveReferralUserId } from '../../common/referral-code';
import { parseAdminPhoneNumbers } from '../../config/env';
import { serializeAdminProfile, serializeUser } from '../../common/serializers';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { WalletService } from '../wallet/wallet.service';
import { LoginDto } from './dto/login.dto';
import { LoginPhoneDto } from './dto/login-phone.dto';
import { LogoutDto } from './dto/logout.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';
import { ResetPasswordPhoneDto } from './dto/reset-password-phone.dto';
import { SignupDto } from './dto/signup.dto';
import { SignupPhoneDto } from './dto/signup-phone.dto';
import { AuthenticatedUser, AuthTokenPayload } from './auth.types';

type UserWithAdminProfile = {
  id: string;
  email: string | null;
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
    const passwordHash = await hash(payload.password, 10);
    const user = await this.prisma.user.create({
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

    const userWithAdmin = await this.ensureAdminBootstrapForUser(user);
    const session = await this.createSession(userWithAdmin);
    await this.ensureWalletBootstrapSafely(user.id);

    return this.buildAuthResponse(userWithAdmin, session.auth);
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
    const verificationCheckId = this.pickVerificationCheckId(
      payload.verificationCheckId,
      payload.verification_check_id,
    );
    const referralCode = this.pickOptionalReferralCode(
      payload.referralCode,
      payload.referral_code,
    );
    const displayName = (payload.displayName ?? payload.display_name ?? '').trim();

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
      throw new ConflictException('Phone is already registered');
    }

    const passwordHash = await hash(payload.password, 10);
    const user = await this.prisma.user.create({
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

    const userWithAdmin = await this.ensureAdminBootstrapForUser(user);
    const session = await this.createSession(userWithAdmin);
    await this.prisma.phoneVerification.update({
      where: {
        id: verification.id,
      },
      data: {
        createdUserId: userWithAdmin.id,
      },
    });
    await this.ensureWalletBootstrapSafely(userWithAdmin.id);
    await this.applyReferralBonusSafely({
      newUser: userWithAdmin,
      normalizedPhone,
      referralCode,
      verificationId: verification.id,
    });

    return this.buildAuthResponse(userWithAdmin, session.auth);
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

    if (user.blockedAt) {
      throw this.createUnauthorizedError(
        'ACCOUNT_DISABLED',
        'Аккаунт временно недоступен',
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

    return this.buildUserEnvelope(user);
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

  async deleteAccount(authUser: AuthenticatedUser) {
    const user = await this.prisma.user.findUnique({
      where: {
        id: authUser.userId,
      },
      include: {
        adminProfile: true,
      },
    });

    if (!user || user.deletedAt || user.status === UserStatus.DELETED) {
      throw new NotFoundException('User not found');
    }

    if (user.adminProfile?.isAdmin === true) {
      throw new BadRequestException(
        'Удаление admin-аккаунта через этот endpoint запрещено',
      );
    }

    const now = new Date();
    const userId = authUser.userId;
    const deletedEmail = `deleted+${userId}@atta.local`;
    const listingIds = (
      await this.prisma.listing.findMany({
        where: {
          ownerId: userId,
        },
        select: {
          id: true,
        },
      })
    ).map((item) => item.id);
    const chatIds = (
      await this.prisma.chat.findMany({
        where: {
          OR: [{ buyerId: userId }, { sellerId: userId }],
        },
        select: {
          id: true,
        },
      })
    ).map((item) => item.id);

    await this.storageService.deleteAvatarUrl(user.avatarUrl);
    await this.storageService.deleteListingPhotosForListings(listingIds);
    await this.storageService.deleteChatImagesForChats(chatIds);

    await this.prisma.$transaction(async (tx) => {
      if (chatIds.length > 0) {
        await tx.chatMessage.updateMany({
          where: {
            chatId: {
              in: chatIds,
            },
            deletedAt: null,
          },
          data: {
            deletedAt: now,
          },
        });
        await tx.chat.updateMany({
          where: {
            id: {
              in: chatIds,
            },
          },
          data: {
            deletedByBuyerAt: now,
            deletedBySellerAt: now,
            unreadForBuyer: 0,
            unreadForSeller: 0,
            lastMessage: '',
          },
        });
      }

      await tx.favorite.deleteMany({ where: { userId } });
      await tx.savedSearch.deleteMany({ where: { userId } });
      await tx.viewedListing.deleteMany({ where: { userId } });
      await tx.userFollow.deleteMany({
        where: {
          OR: [{ followerId: userId }, { sellerId: userId }],
        },
      });
      await tx.review.updateMany({
        where: {
          reviewerId: userId,
          deletedAt: null,
        },
        data: {
          deletedAt: now,
          updatedAt: now,
        },
      });
      await tx.userNotification.deleteMany({
        where: {
          userId,
        },
      });
      await tx.supportMessage.updateMany({
        where: {
          senderUserId: userId,
        },
        data: {
          senderUserId: null,
        },
      });
      await tx.supportTicket.updateMany({
        where: {
          userId,
        },
        data: {
          name: 'Удалённый пользователь',
        },
      });
      await tx.listing.updateMany({
        where: {
          ownerId: userId,
          deletedAt: null,
        },
        data: {
          status: ListingStatus.DELETED,
          deletedAt: now,
          publishedAt: null,
          rejectionReason: 'Deleted with owner account',
        },
      });
      await tx.userSession.updateMany({
        where: {
          userId,
          revokedAt: null,
        },
        data: {
          revokedAt: now,
        },
      });
      await tx.user.update({
        where: {
          id: userId,
        },
        data: {
          status: UserStatus.DELETED,
          deletedAt: now,
          blockedAt: now,
          blockReason: 'Account deleted by user',
          phoneVerified: false,
          phone: null,
          email: deletedEmail,
          displayName: 'Удалённый пользователь',
          name: 'Удалённый пользователь',
          avatarUrl: null,
          photoUrl: null,
        },
      });
      if (listingIds.length > 0) {
        await tx.report.updateMany({
          where: {
            listingId: {
              in: listingIds,
            },
          },
          data: {
            listingOwnerId: null,
          },
        });
      }
    });

    return {
      deleted: true,
      user_id: userId,
    };
  }

  private async createSession(user: UserWithAdminProfile) {
    const sessionId = randomUUID();
    const auth = await this.buildAuthTokens(user, sessionId, user.adminProfile);

    await this.prisma.userSession.create({
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

    if (!verification) {
      throw new BadRequestException('Phone verification is not confirmed');
    }

    if (verification.expiresAt.getTime() <= Date.now()) {
      throw new BadRequestException('Phone verification has expired');
    }

    return verification;
  }

  private async applyReferralBonusSafely(params: {
    newUser: UserWithAdminProfile;
    normalizedPhone: string;
    referralCode: string;
    verificationId: string;
  }) {
    try {
      await this.applyReferralBonusIfEligible(params);
    } catch (error) {
      console.warn(
        `[AuthService] referral bonus skipped for user=${params.newUser.id}: ${
          error instanceof Error ? error.message : 'unknown error'
        }`,
      );
    }
  }

  private async applyReferralBonusIfEligible(params: {
    newUser: UserWithAdminProfile;
    normalizedPhone: string;
    referralCode: string;
    verificationId: string;
  }) {
    const normalizedReferralCode = params.referralCode.trim();
    if (!normalizedReferralCode) {
      return;
    }

    const inviterUserId = resolveReferralUserId(normalizedReferralCode);
    if (!inviterUserId || inviterUserId === params.newUser.id) {
      return;
    }

    const priorSignupForPhone = await this.prisma.phoneVerification.findFirst({
      where: {
        phone: params.normalizedPhone,
        purpose: PhoneVerificationPurpose.SIGNUP,
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
      return;
    }

    const inviter = await this.prisma.user.findUnique({
      where: {
        id: inviterUserId,
      },
      include: {
        adminProfile: true,
      },
    });
    if (!inviter || inviter.deletedAt || inviter.status === UserStatus.DELETED) {
      return;
    }

    const inviterPhone = normalizeRussianPhone(inviter.phone ?? '');
    if (inviterPhone && inviterPhone === params.normalizedPhone) {
      return;
    }

    await this.walletService.accrueManualBonusIfNeeded(inviter.id, {
      amount: 100,
      reference: `REFERRAL_INVITER_BONUS:${params.newUser.id}`,
      description: 'Бонус за приглашение друга',
      source: 'referral_bonus',
      metadata: {
        referralCode: normalizedReferralCode,
        invitedUserId: params.newUser.id,
        invitedPhone: params.normalizedPhone,
      },
    });
  }

  private async ensureAdminBootstrapForUserId(userId: string) {
    const user = await this.findActiveUserById(userId);
    return this.ensureAdminBootstrapForUser(user);
  }

  private async ensureAdminBootstrapForUser(user: UserWithAdminProfile) {
    const normalizedPhone = normalizeRussianPhone(user.phone ?? '');
    const adminPhones = new Set(parseAdminPhoneNumbers());
    if (normalizedPhone.length > 0 && adminPhones.has(normalizedPhone)) {
      await this.prisma.adminUser.upsert({
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

    const refreshedUser = await this.prisma.user.findUnique({
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
