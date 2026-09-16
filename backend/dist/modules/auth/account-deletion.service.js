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
var AccountDeletionService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.AccountDeletionService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const prisma_service_1 = require("../prisma/prisma.service");
const storage_service_1 = require("../storage/storage.service");
const redis_service_1 = require("../redis/redis.service");
const DELETED_NAME = 'Удалённый пользователь';
let AccountDeletionService = AccountDeletionService_1 = class AccountDeletionService {
    constructor(prisma, storage, redis) {
        this.prisma = prisma;
        this.storage = storage;
        this.redis = redis;
        this.logger = new common_1.Logger(AccountDeletionService_1.name);
        this.running = false;
        this.listeners = new Set();
    }
    onDeleted(listener) {
        this.listeners.add(listener);
        return () => this.listeners.delete(listener);
    }
    onModuleInit() {
        this.timer = setInterval(() => {
            void this.retryCleanup().catch(() => this.logger.warn('Account cleanup retry failed'));
        }, 30_000);
        this.timer.unref?.();
    }
    onModuleDestroy() {
        if (this.timer)
            clearInterval(this.timer);
    }
    async deleteUser(userId, options = {}) {
        const now = new Date();
        const reason = options.reason ?? 'Account deleted by user';
        for (let attempt = 0;; attempt++) {
            try {
                await this.prisma.$transaction(async (tx) => {
                    const user = await tx.user.findUnique({ where: { id: userId }, include: { adminProfile: true } });
                    if (!user)
                        throw new common_1.NotFoundException('User not found');
                    if (!options.actorUserId && user.adminProfile?.isAdmin) {
                        throw new common_1.BadRequestException('Удаление admin-аккаунта через этот endpoint запрещено');
                    }
                    // Retried cleanup must not reset deletion time or recreate a completed job.
                    if (user.deletedAt || user.status === client_1.UserStatus.DELETED)
                        return;
                    // Keep the tombstone: finance, referrals, moderation and the peer's history reference it.
                    await tx.user.update({ where: { id: userId }, data: {
                            status: client_1.UserStatus.DELETED, deletedAt: now, blockedAt: now, blockReason: reason,
                            phone: null, phoneVerified: false, email: `deleted+${userId}@atta.local`,
                            displayName: DELETED_NAME, name: DELETED_NAME, avatarUrl: null, photoUrl: null,
                            passwordHash: '', lastLoginAt: null, lastNotificationsSeenAt: null,
                        } });
                    await tx.accountDeletionCleanup.create({ data: {
                            userId,
                            avatarUrls: [...new Set([user.avatarUrl, user.photoUrl].filter((url) => !!url))],
                        } });
                    await tx.userDevice.deleteMany({ where: { userId } });
                    await tx.restoreCredential.deleteMany({ where: { userId } });
                    await tx.userSession.updateMany({ where: { userId }, data: {
                            revokedAt: now, refreshTokenHash: '', ip: null, userAgent: null, deviceId: null, deviceName: null,
                        } });
                    await tx.userPresence.deleteMany({ where: { userId } });
                    await tx.favorite.deleteMany({ where: { userId } });
                    await tx.savedSearch.deleteMany({ where: { userId } });
                    await tx.viewedListing.deleteMany({ where: { userId } });
                    await tx.appDailyVisit.deleteMany({ where: { userId } });
                    await tx.listingView.updateMany({ where: { viewerUserId: userId }, data: {
                            viewerUserId: null, viewerDeviceId: null, ip: null,
                        } });
                    await tx.userFollow.deleteMany({ where: { OR: [{ followerId: userId }, { sellerId: userId }] } });
                    await tx.chatPeerBlock.deleteMany({ where: { OR: [{ blockerUserId: userId }, { blockedUserId: userId }] } });
                    await tx.userNotification.deleteMany({ where: { userId } });
                    // Review notifications copy the author's name into another user's inbox.
                    await tx.userNotification.updateMany({ where: {
                            type: 'GENERIC', AND: [
                                { payload: { path: ['actionType'], equals: 'review_new' } },
                                { payload: { path: ['authorId'], equals: userId } },
                            ],
                        }, data: { body: `${DELETED_NAME} оставил новый отзыв.` } });
                    // Do not hide the other participant's messages, unread count or attachments.
                    await tx.chat.updateMany({ where: { buyerId: userId }, data: { deletedByBuyerAt: now, unreadForBuyer: 0 } });
                    await tx.chat.updateMany({ where: { sellerId: userId }, data: { deletedBySellerAt: now, unreadForSeller: 0 } });
                    await tx.review.updateMany({ where: { reviewerId: userId }, data: {
                            reviewerName: DELETED_NAME, deletedAt: now, updatedAt: now,
                        } });
                    await tx.supportTicket.updateMany({ where: { userId }, data: { name: DELETED_NAME } });
                    await tx.supportMessage.updateMany({ where: { senderUserId: userId }, data: { senderUserId: null } });
                    await tx.listing.updateMany({ where: { ownerId: userId }, data: {
                            ownerName: DELETED_NAME, ownerEmail: null, phone: '', phoneHidden: true,
                            address: '', latitude: null, longitude: null, locationJson: {},
                        } });
                    await tx.listing.updateMany({ where: { ownerId: userId, deletedAt: null }, data: {
                            status: client_1.ListingStatus.DELETED, deletedAt: now, publishedAt: null,
                            rejectionReason: options.reason ?? 'Удалено вместе с аккаунтом владельца',
                            ...(options.actorUserId ? { moderatedBy: options.actorUserId, moderatedAt: now } : {}),
                        } });
                    await tx.promotion.updateMany({ where: { userId, status: 'ACTIVE' }, data: { status: 'CANCELLED' } });
                    await tx.listingRaiseCampaign.updateMany({ where: { userId, status: 'ACTIVE' }, data: {
                            status: 'CANCELLED', nextRaiseAt: null, cancelReason: 'ACCOUNT_DELETED',
                        } });
                    await tx.userConsent.updateMany({ where: { userId, consentType: 'MARKETING_MESSAGES', withdrawnAt: null }, data: { withdrawnAt: now } });
                    // Keep phone + confirmed signup evidence for existing referral and block enforcement.
                    await tx.phoneVerification.updateMany({ where: { createdUserId: userId }, data: {
                            requestedByIp: null, requestedByDeviceId: null,
                            expiresAt: now,
                        } });
                    await tx.report.updateMany({ where: { listingOwnerId: userId }, data: { listingOwnerId: null } });
                }, { isolationLevel: client_1.Prisma.TransactionIsolationLevel.Serializable });
                break;
            }
            catch (error) {
                if (error instanceof client_1.Prisma.PrismaClientKnownRequestError && error.code === 'P2034' && attempt < 2)
                    continue;
                throw error;
            }
        }
        // Failures beyond this boundary must never turn committed deletion into an API failure.
        for (const listener of this.listeners) {
            try {
                listener(userId);
            }
            catch {
                this.logger.warn('Deleted account socket disconnect failed');
            }
        }
        await this.cleanupUser(userId);
        return { deleted: true, user_id: userId };
    }
    async cleanupUser(userId) {
        try {
            const job = await this.prisma.accountDeletionCleanup.findUnique({ where: { userId } });
            if (!job)
                return;
            const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { status: true, deletedAt: true } });
            if (!user || user.status !== client_1.UserStatus.DELETED || !user.deletedAt)
                return;
            await this.redis.del(`presence:user:${userId}`);
            for (const url of job.avatarUrls)
                await this.storage.deleteAccountAvatar(userId, url);
            await this.prisma.accountDeletionCleanup.deleteMany({ where: { userId } });
        }
        catch {
            this.logger.warn(`Account cleanup pending: ${userId}`);
            // No provider exception/body/URL in logs. Retain the job across process restarts.
            await this.prisma.accountDeletionCleanup.updateMany({ where: { userId }, data: {
                    retryAt: new Date(Date.now() + 60_000),
                } }).catch(() => undefined);
        }
    }
    async retryCleanup() {
        if (this.running)
            return;
        this.running = true;
        try {
            const jobs = await this.prisma.accountDeletionCleanup.findMany({
                where: { retryAt: { lte: new Date() } }, orderBy: { retryAt: 'asc' }, take: 20,
            });
            for (const job of jobs)
                await this.cleanupUser(job.userId);
        }
        finally {
            this.running = false;
        }
    }
};
exports.AccountDeletionService = AccountDeletionService;
exports.AccountDeletionService = AccountDeletionService = AccountDeletionService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        storage_service_1.StorageService,
        redis_service_1.RedisService])
], AccountDeletionService);
//# sourceMappingURL=account-deletion.service.js.map