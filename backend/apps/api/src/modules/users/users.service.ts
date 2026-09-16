import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import {
  PhoneVerificationPurpose,
  PhoneVerificationStatus,
  UserStatus,
} from '@prisma/client';

import {
  serializeAdminProfile,
  serializeUser,
} from '../../common/serializers';
import { normalizeRussianPhone, validateRussianPhoneOrThrow } from '../../common/phone';
import { parseAdminPhoneNumbers } from '../../config/env';
import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { UploadedImageFile } from '../storage/uploaded-image-file.type';
import { WalletService } from '../wallet/wallet.service';
import { UpdateProfileDto } from './dto/update-profile.dto';

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storageService: StorageService,
    private readonly walletService: WalletService,
  ) {}

  async getMe(authUser: AuthenticatedUser) {
    try {
      await this.walletService.ensureWalletAndBonusesSafely(authUser.userId);
    } catch {
      // Wallet bootstrap must not break profile loading.
    }
    let user = await this.prisma.user.findUnique({
      where: {
        id: authUser.userId,
      },
      include: {
        adminProfile: true,
      },
    });

    if (!user) {
      throw new NotFoundException('Current user was not found');
    }

    const normalizedPhone = normalizeRussianPhone(user.phone ?? '');
    if (normalizedPhone.length > 0 &&
        new Set(parseAdminPhoneNumbers()).has(normalizedPhone) &&
        user.adminProfile?.isAdmin !== true) {
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
      user = await this.prisma.user.findUnique({
        where: {
          id: authUser.userId,
        },
        include: {
          adminProfile: true,
        },
      });
      if (!user) {
        throw new NotFoundException('Current user was not found');
      }
    }

    return {
      user: serializeUser(user, { includePrivate: true }),
      admin_profile: serializeAdminProfile(user.adminProfile),
      is_admin: user.adminProfile?.isAdmin === true,
      isAdmin: user.adminProfile?.isAdmin === true,
    };
  }

  async updateMe(authUser: AuthenticatedUser, dto: UpdateProfileDto) {
    const trimmedPhone = dto.phone?.trim();
    let nextPhone: string | undefined;
    if (trimmedPhone != null) {
      if (trimmedPhone.length > 0) {
        nextPhone = normalizeRussianPhone(trimmedPhone);
        validateRussianPhoneOrThrow(nextPhone);
      } else {
        nextPhone = undefined;
      }
    }

    if (nextPhone != null) {
      const currentUser = await this.prisma.user.findUnique({
        where: {
          id: authUser.userId,
        },
        select: {
          phone: true,
        },
      });

      if (!currentUser) {
        throw new NotFoundException('Current user was not found');
      }

      if (currentUser.phone !== nextPhone) {
        const existingUser = await this.prisma.user.findFirst({
          where: {
            phone: nextPhone,
            id: {
              not: authUser.userId,
            },
            deletedAt: null,
            status: {
              not: UserStatus.DELETED,
            },
          },
          select: {
            id: true,
          },
        });

        if (existingUser) {
          throw new BadRequestException('PHONE_ALREADY_REGISTERED');
        }

        await this.assertConfirmedPhoneChangeVerification(
          nextPhone,
          dto.verificationCheckId ?? dto.verification_check_id,
        );
      }
    }

    const user = await this.prisma.user.update({
      where: {
        id: authUser.userId,
      },
      data: {
        displayName: dto.display_name?.trim(),
        name: dto.name?.trim() || dto.display_name?.trim(),
        avatarUrl: dto.avatar_url?.trim(),
        photoUrl: dto.photo_url?.trim() || dto.avatar_url?.trim(),
        phone: nextPhone,
        phoneVerified: nextPhone == null ? undefined : true,
      },
      include: {
        adminProfile: true,
      },
    });

    return {
      user: serializeUser(user, { includePrivate: true }),
      admin_profile: serializeAdminProfile(user.adminProfile),
      is_admin: user.adminProfile?.isAdmin === true,
      isAdmin: user.adminProfile?.isAdmin === true,
    };
  }

  async getSellerPublicProfile(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: {
        id: userId,
      },
    });

    if (!user) {
      throw new NotFoundException('Seller not found');
    }

    return {
      user: serializeUser(user),
    };
  }

  async getAdminUsersList(authUser: AuthenticatedUser) {
    if (authUser.role !== 'admin') {
      throw new ForbiddenException('Admin access is required');
    }

    const users = await this.prisma.user.findMany({
      include: {
        adminProfile: true,
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    return {
      items: users.map((user) => ({
        ...serializeUser(user, { includePrivate: true }),
        admin_profile: serializeAdminProfile(user.adminProfile),
      })),
    };
  }

  async uploadAvatar(
    authUser: AuthenticatedUser,
    file: UploadedImageFile,
  ) {
    if (!file.mimetype.startsWith('image/')) {
      throw new BadRequestException('Avatar file must be an image');
    }

    const currentUser = await this.prisma.user.findUnique({
      where: {
        id: authUser.userId,
      },
      include: {
        adminProfile: true,
      },
    });
    if (!currentUser) {
      throw new NotFoundException('Current user was not found');
    }

    const uploaded = await this.storageService.saveUploadedFile({
      buffer: file.buffer,
      category: 'avatars',
      contentType: file.mimetype,
      context: {
        userId: authUser.userId,
      },
      originalName: file.originalname,
    });

    await this.storageService.deleteAvatarUrl(currentUser.avatarUrl);

    const user = await this.prisma.user.update({
      where: {
        id: authUser.userId,
      },
      data: {
        avatarUrl: uploaded.url,
        photoUrl: uploaded.url,
      },
      include: {
        adminProfile: true,
      },
    });

    return {
      user: serializeUser(user, { includePrivate: true }),
      avatar_url: uploaded.url,
      photo_url: uploaded.url,
      admin_profile: serializeAdminProfile(user.adminProfile),
      is_admin: user.adminProfile?.isAdmin === true,
      isAdmin: user.adminProfile?.isAdmin === true,
    };
  }

  private async assertConfirmedPhoneChangeVerification(
    phone: string,
    rawCheckId?: string,
  ) {
    const checkId = rawCheckId?.trim() ?? '';
    if (!checkId) {
      throw new BadRequestException('PHONE_VERIFICATION_REQUIRED');
    }

    const verification = await this.prisma.phoneVerification.findFirst({
      where: {
        phone,
        purpose: PhoneVerificationPurpose.CHANGE_PHONE,
        checkId,
        status: PhoneVerificationStatus.CONFIRMED,
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    if (!verification) {
      throw new BadRequestException('PHONE_VERIFICATION_REQUIRED');
    }

    if (verification.expiresAt.getTime() <= Date.now()) {
      throw new BadRequestException('PHONE_VERIFICATION_EXPIRED');
    }
  }
}
