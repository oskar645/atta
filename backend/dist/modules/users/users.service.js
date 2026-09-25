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
exports.UsersService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const serializers_1 = require("../../common/serializers");
const seller_level_1 = require("../../common/seller-level");
const phone_1 = require("../../common/phone");
const env_1 = require("../../config/env");
const prisma_service_1 = require("../prisma/prisma.service");
const storage_service_1 = require("../storage/storage.service");
const wallet_service_1 = require("../wallet/wallet.service");
let UsersService = class UsersService {
    constructor(prisma, storageService, walletService) {
        this.prisma = prisma;
        this.storageService = storageService;
        this.walletService = walletService;
    }
    async getMe(authUser) {
        try {
            await this.walletService.ensureWalletAndBonusesSafely(authUser.userId);
        }
        catch {
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
            throw new common_1.NotFoundException('Current user was not found');
        }
        const normalizedPhone = (0, phone_1.normalizeRussianPhone)(user.phone ?? '');
        if (normalizedPhone.length > 0 &&
            new Set((0, env_1.parseAdminPhoneNumbers)()).has(normalizedPhone) &&
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
                throw new common_1.NotFoundException('Current user was not found');
            }
        }
        const sellerLevel = await this.getSellerLevel(user.id);
        return {
            user: this.withSellerLevel((0, serializers_1.serializeUser)(user, { includePrivate: true }), sellerLevel),
            admin_profile: (0, serializers_1.serializeAdminProfile)(user.adminProfile),
            is_admin: user.adminProfile?.isAdmin === true,
            isAdmin: user.adminProfile?.isAdmin === true,
        };
    }
    async updateMe(authUser, dto) {
        const trimmedPhone = dto.phone?.trim();
        let nextPhone;
        if (trimmedPhone != null) {
            if (trimmedPhone.length > 0) {
                nextPhone = (0, phone_1.normalizeRussianPhone)(trimmedPhone);
                (0, phone_1.validateRussianPhoneOrThrow)(nextPhone);
            }
            else {
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
                throw new common_1.NotFoundException('Current user was not found');
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
                            not: client_1.UserStatus.DELETED,
                        },
                    },
                    select: {
                        id: true,
                    },
                });
                if (existingUser) {
                    throw new common_1.BadRequestException('PHONE_ALREADY_REGISTERED');
                }
                await this.assertConfirmedPhoneChangeVerification(nextPhone, dto.verificationCheckId ?? dto.verification_check_id);
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
        const sellerLevel = await this.getSellerLevel(user.id);
        return {
            user: this.withSellerLevel((0, serializers_1.serializeUser)(user, { includePrivate: true }), sellerLevel),
            admin_profile: (0, serializers_1.serializeAdminProfile)(user.adminProfile),
            is_admin: user.adminProfile?.isAdmin === true,
            isAdmin: user.adminProfile?.isAdmin === true,
        };
    }
    async getSellerPublicProfile(userId) {
        const user = await this.prisma.user.findUnique({
            where: {
                id: userId,
            },
        });
        if (!user) {
            throw new common_1.NotFoundException('Seller not found');
        }
        const sellerLevel = await this.getSellerLevel(user.id);
        return {
            user: this.withSellerLevel((0, serializers_1.serializeUser)(user), sellerLevel),
        };
    }
    async getAdminUsersList(authUser) {
        if (authUser.role !== 'admin') {
            throw new common_1.ForbiddenException('Admin access is required');
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
                ...(0, serializers_1.serializeUser)(user, { includePrivate: true }),
                admin_profile: (0, serializers_1.serializeAdminProfile)(user.adminProfile),
            })),
        };
    }
    async uploadAvatar(authUser, file) {
        if (!file.mimetype.startsWith('image/')) {
            throw new common_1.BadRequestException('Avatar file must be an image');
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
            throw new common_1.NotFoundException('Current user was not found');
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
        const sellerLevel = await this.getSellerLevel(user.id);
        return {
            user: this.withSellerLevel((0, serializers_1.serializeUser)(user, { includePrivate: true }), sellerLevel),
            avatar_url: uploaded.url,
            photo_url: uploaded.url,
            admin_profile: (0, serializers_1.serializeAdminProfile)(user.adminProfile),
            is_admin: user.adminProfile?.isAdmin === true,
            isAdmin: user.adminProfile?.isAdmin === true,
        };
    }
    async getSellerLevel(userId) {
        const [activeListingsCount, reviews] = await Promise.all([
            this.prisma.listing.count({
                where: {
                    ownerId: userId,
                    status: client_1.ListingStatus.APPROVED,
                    publishedAt: {
                        not: null,
                    },
                    deletedAt: null,
                },
            }),
            this.prisma.review.findMany({
                where: {
                    sellerId: userId,
                    reviewerId: { not: userId },
                    deletedAt: null,
                },
                select: {
                    id: true,
                    reviewerId: true,
                    rating: true,
                    createdAt: true,
                },
            }),
        ]);
        return (0, seller_level_1.sellerLevelFromMetrics)(activeListingsCount, reviews, userId);
    }
    withSellerLevel(user, sellerLevel) {
        return {
            ...user,
            seller_level: sellerLevel,
            sellerLevel,
        };
    }
    async assertConfirmedPhoneChangeVerification(phone, rawCheckId) {
        const checkId = rawCheckId?.trim() ?? '';
        if (!checkId) {
            throw new common_1.BadRequestException('PHONE_VERIFICATION_REQUIRED');
        }
        const verification = await this.prisma.phoneVerification.findFirst({
            where: {
                phone,
                purpose: client_1.PhoneVerificationPurpose.CHANGE_PHONE,
                checkId,
                status: client_1.PhoneVerificationStatus.CONFIRMED,
            },
            orderBy: {
                createdAt: 'desc',
            },
        });
        if (!verification) {
            throw new common_1.BadRequestException('PHONE_VERIFICATION_REQUIRED');
        }
        if (verification.expiresAt.getTime() <= Date.now()) {
            throw new common_1.BadRequestException('PHONE_VERIFICATION_EXPIRED');
        }
    }
};
exports.UsersService = UsersService;
exports.UsersService = UsersService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        storage_service_1.StorageService,
        wallet_service_1.WalletService])
], UsersService);
//# sourceMappingURL=users.service.js.map