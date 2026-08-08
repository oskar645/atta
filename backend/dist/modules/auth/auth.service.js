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
exports.AuthService = void 0;
const common_1 = require("@nestjs/common");
const jwt_1 = require("@nestjs/jwt");
const client_1 = require("@prisma/client");
const bcryptjs_1 = require("bcryptjs");
const crypto_1 = require("crypto");
const env_1 = require("../../config/env");
const phone_1 = require("../../common/phone");
const referral_code_1 = require("../../common/referral-code");
const env_2 = require("../../config/env");
const serializers_1 = require("../../common/serializers");
const prisma_service_1 = require("../prisma/prisma.service");
const storage_service_1 = require("../storage/storage.service");
const user_blocks_service_1 = require("../user-blocks/user-blocks.service");
const wallet_service_1 = require("../wallet/wallet.service");
let AuthService = class AuthService {
    constructor(prisma, jwtService, storageService, walletService, userBlocksService) {
        this.prisma = prisma;
        this.jwtService = jwtService;
        this.storageService = storageService;
        this.walletService = walletService;
        this.userBlocksService = userBlocksService;
    }
    async signup(payload) {
        const email = payload.email?.trim().toLowerCase();
        if (!email) {
            throw new common_1.ConflictException('Email is required for signup');
        }
        const existingUser = await this.prisma.user.findFirst({
            where: {
                OR: [
                    { email },
                    payload.phone?.trim() ? { phone: payload.phone.trim() } : undefined,
                ].filter(Boolean),
            },
            include: {
                adminProfile: true,
            },
        });
        if (existingUser) {
            throw new common_1.ConflictException('User already exists');
        }
        const displayName = (payload.display_name ?? payload.displayName ?? '').trim();
        const passwordHash = await (0, bcryptjs_1.hash)(payload.password, 10);
        const user = await this.prisma.user.create({
            data: {
                id: (0, crypto_1.randomUUID)(),
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
    async login(payload) {
        const email = payload.email?.trim().toLowerCase();
        if (!email) {
            throw new common_1.UnauthorizedException('Email login is required');
        }
        const user = await this.prisma.user.findUnique({
            where: {
                email,
            },
            include: {
                adminProfile: true,
            },
        });
        if (!user || user.deletedAt || user.status === client_1.UserStatus.DELETED) {
            throw new common_1.UnauthorizedException('Invalid login credentials');
        }
        const activeBlock = await this.userBlocksService.getActiveBlock(user.id);
        if (activeBlock) {
            throw this.createUnauthorizedError('ACCOUNT_BLOCKED', 'Аккаунт заблокирован');
        }
        const isPasswordValid = await (0, bcryptjs_1.compare)(payload.password, user.passwordHash);
        if (!isPasswordValid) {
            throw new common_1.UnauthorizedException('Invalid login credentials');
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
    async signupPhone(payload) {
        const normalizedPhone = this.normalizePhoneOrThrow(payload.phone);
        await this.assertPhoneRegistrationAllowed(normalizedPhone);
        const verificationCheckId = this.pickVerificationCheckId(payload.verificationCheckId, payload.verification_check_id);
        const referralCode = this.pickOptionalReferralCode(payload.referralCode, payload.referral_code);
        const referralId = this.pickOptionalReferralCode(payload.referralId, payload.referral_id);
        const displayName = (payload.displayName ?? payload.display_name ?? '').trim();
        if (!displayName) {
            throw new common_1.BadRequestException('Display name is required');
        }
        const verification = await this.assertConfirmedPhoneVerification({
            phone: normalizedPhone,
            purpose: client_1.PhoneVerificationPurpose.SIGNUP,
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
        if (existingUser && !existingUser.deletedAt && existingUser.status !== client_1.UserStatus.DELETED) {
            await this.markReferralFailureById(referralId, 'USER_ALREADY_REGISTERED');
            throw new common_1.ConflictException('Phone is already registered');
        }
        const passwordHash = await (0, bcryptjs_1.hash)(payload.password, 10);
        const { userWithAdmin, session } = await this.prisma.$transaction(async (tx) => {
            const user = await tx.user.create({
                data: {
                    id: (0, crypto_1.randomUUID)(),
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
    async loginPhone(payload) {
        const rawPhone = (payload.phone ?? '').trim();
        const password = (payload.password ?? '').trim();
        if (!rawPhone) {
            throw this.createBadRequestError('PHONE_REQUIRED', 'Введите номер телефона');
        }
        if (!password) {
            throw this.createBadRequestError('PASSWORD_REQUIRED', 'Введите пароль');
        }
        if (password.length < 8) {
            throw this.createBadRequestError('PASSWORD_REQUIRED', 'Введите пароль');
        }
        const normalizedPhone = this.normalizePhoneOrThrow(rawPhone);
        const verificationCheckId = this.pickOptionalVerificationCheckId(payload.verificationCheckId, payload.verification_check_id);
        if (verificationCheckId) {
            await this.assertConfirmedPhoneVerification({
                phone: normalizedPhone,
                purpose: client_1.PhoneVerificationPurpose.LOGIN,
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
        if (!user || user.deletedAt || user.status === client_1.UserStatus.DELETED) {
            throw this.createUserNotFoundError();
        }
        const activeBlock = await this.userBlocksService.getActiveBlock(user.id);
        if (activeBlock) {
            throw this.createUnauthorizedError('ACCOUNT_BLOCKED', 'Аккаунт заблокирован');
        }
        const isPasswordValid = await (0, bcryptjs_1.compare)(password, user.passwordHash);
        if (!isPasswordValid) {
            throw this.createUnauthorizedError('INVALID_PHONE_OR_PASSWORD', 'Неверный номер телефона или пароль');
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
    async resetPasswordPhone(payload) {
        const normalizedPhone = this.normalizePhoneOrThrow(payload.phone);
        const verificationCheckId = this.pickVerificationCheckId(payload.verificationCheckId, payload.verification_check_id);
        const newPassword = (payload.newPassword ?? payload.new_password ?? '').trim();
        if (newPassword.length < 8) {
            throw this.createBadRequestError('PASSWORD_TOO_SHORT', 'Пароль должен быть не короче 8 символов');
        }
        await this.assertConfirmedPhoneVerification({
            phone: normalizedPhone,
            purpose: client_1.PhoneVerificationPurpose.RESET_PASSWORD,
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
        if (!user || user.deletedAt || user.status === client_1.UserStatus.DELETED) {
            throw this.createUserNotFoundError();
        }
        await this.prisma.user.update({
            where: {
                id: user.id,
            },
            data: {
                passwordHash: await (0, bcryptjs_1.hash)(newPassword, 10),
                phoneVerified: true,
            },
        });
        return {
            status: 'ok',
        };
    }
    async getMe(authUser) {
        await this.ensureWalletBootstrapSafely(authUser.userId);
        const user = await this.ensureAdminBootstrapForUserId(authUser.userId);
        const block = await this.userBlocksService.getActiveBlock(authUser.userId);
        return {
            ...this.buildUserEnvelope(user),
            block_status: this.userBlocksService.serializeBlock(block),
        };
    }
    async refresh(payload) {
        let tokenPayload;
        try {
            tokenPayload = await this.jwtService.verifyAsync(payload.refreshToken, {
                secret: env_1.env.JWT_REFRESH_SECRET,
            });
        }
        catch {
            throw new common_1.UnauthorizedException('Refresh token is invalid or expired');
        }
        if (tokenPayload.type !== 'refresh') {
            throw new common_1.UnauthorizedException('Refresh token type is invalid');
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
        if (!session ||
            session.userId !== tokenPayload.sub ||
            session.revokedAt ||
            session.expiresAt.getTime() <= Date.now()) {
            throw new common_1.UnauthorizedException('Refresh session is not active');
        }
        const isRefreshTokenValid = await (0, bcryptjs_1.compare)(payload.refreshToken, session.refreshTokenHash);
        if (!isRefreshTokenValid) {
            throw new common_1.UnauthorizedException('Refresh token does not match session');
        }
        if (session.user.deletedAt ||
            session.user.status === client_1.UserStatus.DELETED) {
            throw new common_1.UnauthorizedException('User account is deleted');
        }
        const userWithAdmin = await this.ensureAdminBootstrapForUser(session.user);
        const tokens = await this.buildAuthTokens(userWithAdmin, session.id, userWithAdmin.adminProfile);
        await this.prisma.userSession.update({
            where: {
                id: session.id,
            },
            data: {
                refreshTokenHash: await (0, bcryptjs_1.hash)(tokens.refresh_token, 10),
                expiresAt: this.computeExpiry(env_1.env.JWT_REFRESH_TTL),
            },
        });
        return this.buildAuthResponse(userWithAdmin, tokens);
    }
    async logout(authUser, payload) {
        if (payload?.refreshToken) {
            await this.revokeSessionByRefreshToken(payload.refreshToken, authUser.userId);
        }
        else {
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
    async deleteAccount(authUser) {
        const user = await this.prisma.user.findUnique({
            where: {
                id: authUser.userId,
            },
            include: {
                adminProfile: true,
            },
        });
        if (!user || user.deletedAt || user.status === client_1.UserStatus.DELETED) {
            throw new common_1.NotFoundException('User not found');
        }
        if (user.adminProfile?.isAdmin === true) {
            throw new common_1.BadRequestException('Удаление admin-аккаунта через этот endpoint запрещено');
        }
        const now = new Date();
        const userId = authUser.userId;
        const deletedEmail = `deleted+${userId}@atta.local`;
        const listingIds = (await this.prisma.listing.findMany({
            where: {
                ownerId: userId,
            },
            select: {
                id: true,
            },
        })).map((item) => item.id);
        const chatIds = (await this.prisma.chat.findMany({
            where: {
                OR: [{ buyerId: userId }, { sellerId: userId }],
            },
            select: {
                id: true,
            },
        })).map((item) => item.id);
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
                    status: client_1.ListingStatus.DELETED,
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
                    status: client_1.UserStatus.DELETED,
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
    async createSession(user, tx) {
        const prisma = tx ?? this.prisma;
        const sessionId = (0, crypto_1.randomUUID)();
        const auth = await this.buildAuthTokens(user, sessionId, user.adminProfile);
        await prisma.userSession.create({
            data: {
                id: sessionId,
                userId: user.id,
                refreshTokenHash: await (0, bcryptjs_1.hash)(auth.refresh_token, 10),
                expiresAt: this.computeExpiry(env_1.env.JWT_REFRESH_TTL),
            },
        });
        return { auth };
    }
    async ensureWalletBootstrapSafely(userId) {
        try {
            await this.walletService.ensureWalletAndBonusesSafely(userId);
        }
        catch {
            // Wallet bootstrap must never block auth/profile responses.
        }
    }
    async buildAuthTokens(user, sessionId, adminProfile) {
        const role = adminProfile?.isAdmin ? 'admin' : 'user';
        const basePayload = {
            sub: user.id,
            sessionId,
            email: user.email,
            role,
        };
        const [accessToken, refreshToken] = await Promise.all([
            this.jwtService.signAsync({
                ...basePayload,
                type: 'access',
            }, {
                secret: env_1.env.JWT_ACCESS_SECRET,
                expiresIn: env_1.env.JWT_ACCESS_TTL,
            }),
            this.jwtService.signAsync({
                ...basePayload,
                type: 'refresh',
            }, {
                secret: env_1.env.JWT_REFRESH_SECRET,
                expiresIn: env_1.env.JWT_REFRESH_TTL,
            }),
        ]);
        return {
            access_token: accessToken,
            refresh_token: refreshToken,
            token_type: 'Bearer',
            expires_in: this.ttlToSeconds(env_1.env.JWT_ACCESS_TTL),
            user_id: user.id,
            session_id: sessionId,
        };
    }
    ttlToSeconds(ttl) {
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
    computeExpiry(ttl) {
        return new Date(Date.now() + this.ttlToSeconds(ttl) * 1000);
    }
    async findActiveUserById(userId) {
        const user = await this.prisma.user.findUnique({
            where: {
                id: userId,
            },
            include: {
                adminProfile: true,
            },
        });
        if (!user || user.deletedAt || user.status === client_1.UserStatus.DELETED) {
            throw new common_1.NotFoundException('User not found');
        }
        return user;
    }
    async revokeSessionByRefreshToken(refreshToken, userId) {
        let tokenPayload;
        try {
            tokenPayload = await this.jwtService.verifyAsync(refreshToken, {
                secret: env_1.env.JWT_REFRESH_SECRET,
            });
        }
        catch {
            throw new common_1.UnauthorizedException('Refresh token is invalid or expired');
        }
        if (tokenPayload.sub !== userId || tokenPayload.type !== 'refresh') {
            throw new common_1.UnauthorizedException('Refresh token does not belong to user');
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
    buildAuthResponse(user, auth) {
        return {
            ...this.buildUserEnvelope(user),
            auth,
        };
    }
    buildUserEnvelope(user) {
        const isAdmin = user.adminProfile?.isAdmin === true;
        return {
            user: (0, serializers_1.serializeUser)(user, { includePrivate: true }),
            admin_profile: (0, serializers_1.serializeAdminProfile)(user.adminProfile),
            is_admin: isAdmin,
            isAdmin,
        };
    }
    async assertPhoneRegistrationAllowed(normalizedPhone) {
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
            throw this.createUnauthorizedError('PHONE_BLOCKED', 'Этот номер телефона заблокирован. Обратитесь в поддержку');
        }
    }
    normalizePhoneOrThrow(phone) {
        const normalizedPhone = (0, phone_1.normalizeRussianPhone)(phone);
        if (!normalizedPhone) {
            throw this.createBadRequestError('PHONE_REQUIRED', 'Введите номер телефона');
        }
        (0, phone_1.validateRussianPhoneOrThrow)(normalizedPhone);
        return normalizedPhone;
    }
    createBadRequestError(code, message) {
        return new common_1.BadRequestException({ code, message });
    }
    createUnauthorizedError(code, message) {
        return new common_1.UnauthorizedException({ code, message });
    }
    createUserNotFoundError() {
        return new common_1.NotFoundException({
            code: 'USER_NOT_FOUND',
            message: 'На этом номере аккаунта нет',
        });
    }
    pickVerificationCheckId(...values) {
        const checkId = values.find((value) => value?.trim())?.trim() ?? '';
        if (!checkId) {
            throw new common_1.BadRequestException('verificationCheckId is required');
        }
        return checkId;
    }
    pickOptionalVerificationCheckId(...values) {
        return values.find((value) => value?.trim())?.trim() ?? '';
    }
    pickOptionalReferralCode(...values) {
        return values.find((value) => value?.trim())?.trim() ?? '';
    }
    async recordReferralAppOpen(payload) {
        const referralCode = this.pickOptionalReferralCode(payload.referralCode, payload.referral_code);
        const inviterUserId = (0, referral_code_1.resolveReferralUserId)(referralCode);
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
        if (!inviter || inviter.deletedAt || inviter.status === client_1.UserStatus.DELETED) {
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
                rewardStatus: client_1.ReferralRewardStatus.PENDING,
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
    async assertConfirmedPhoneVerification(params) {
        const verification = await this.prisma.phoneVerification.findFirst({
            where: {
                phone: params.phone,
                purpose: params.purpose,
                checkId: params.checkId,
                status: client_1.PhoneVerificationStatus.CONFIRMED,
            },
            orderBy: {
                createdAt: 'desc',
            },
        });
        if (!verification) {
            throw new common_1.BadRequestException('Phone verification is not confirmed');
        }
        if (verification.expiresAt.getTime() <= Date.now()) {
            throw new common_1.BadRequestException('Phone verification has expired');
        }
        return verification;
    }
    async applyReferralBonusIfEligible(params) {
        const normalizedReferralCode = params.referralCode.trim();
        if (!normalizedReferralCode) {
            await this.markReferralFailureById(params.referralId, 'APP_OPENED_WITHOUT_REFERRAL_CODE', params.tx);
            return;
        }
        const inviterUserId = (0, referral_code_1.resolveReferralUserId)(normalizedReferralCode);
        if (!inviterUserId || inviterUserId === params.newUser.id) {
            await this.markReferralFailureById(params.referralId, inviterUserId === params.newUser.id
                ? 'SELF_REFERRAL'
                : 'INVALID_REFERRAL_CODE', params.tx);
            return;
        }
        const prisma = params.tx ?? this.prisma;
        await this.markReferralSignupStarted(params.referralId, params.tx);
        const priorSignupForPhone = await prisma.phoneVerification.findFirst({
            where: {
                phone: params.normalizedPhone,
                purpose: client_1.PhoneVerificationPurpose.SIGNUP,
                status: client_1.PhoneVerificationStatus.CONFIRMED,
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
            await this.markReferralFailureById(params.referralId, 'USER_ALREADY_REGISTERED', params.tx);
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
        if (!inviter || inviter.deletedAt || inviter.status === client_1.UserStatus.DELETED) {
            await this.markReferralFailureById(params.referralId, 'INVITER_NOT_FOUND', params.tx);
            return;
        }
        const inviterPhone = (0, phone_1.normalizeRussianPhone)(inviter.phone ?? '');
        if (inviterPhone && inviterPhone === params.normalizedPhone) {
            await this.markReferralFailureById(params.referralId, 'SELF_REFERRAL', params.tx);
            return;
        }
        try {
            await this.walletService.accrueReferralInviterBonusIfNeeded(inviter.id, {
                invitedUserId: params.newUser.id,
                referralCode: normalizedReferralCode,
                referralId: params.referralId,
            }, params.tx);
        }
        catch (error) {
            await this.markReferralFailureById(params.referralId, 'REWARD_ERROR_RETRYABLE', params.tx, client_1.ReferralRewardStatus.FAILED_RETRYABLE);
            throw error;
        }
    }
    async markReferralSignupStarted(referralId, tx) {
        const normalizedReferralId = referralId.trim();
        if (!normalizedReferralId)
            return;
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
    async markReferralFailureById(referralId, failureReason, tx, rewardStatus = client_1.ReferralRewardStatus.NOT_REWARDED) {
        const normalizedReferralId = referralId.trim();
        if (!normalizedReferralId)
            return;
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
    async ensureAdminBootstrapForUserId(userId) {
        const user = await this.findActiveUserById(userId);
        return this.ensureAdminBootstrapForUser(user);
    }
    async ensureAdminBootstrapForUser(user, tx) {
        const normalizedPhone = (0, phone_1.normalizeRussianPhone)(user.phone ?? '');
        const adminPhones = new Set((0, env_2.parseAdminPhoneNumbers)());
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
            throw new common_1.NotFoundException('User not found after signup');
        }
        return refreshedUser;
    }
};
exports.AuthService = AuthService;
exports.AuthService = AuthService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        jwt_1.JwtService,
        storage_service_1.StorageService,
        wallet_service_1.WalletService,
        user_blocks_service_1.UserBlocksService])
], AuthService);
//# sourceMappingURL=auth.service.js.map