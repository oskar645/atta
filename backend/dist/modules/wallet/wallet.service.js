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
exports.WalletService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const prisma_service_1 = require("../prisma/prisma.service");
const wallet_constants_1 = require("./wallet.constants");
const DAILY_LOGIN_BONUS_REASON = client_1.WalletTransactionReason.DAILY_LOGIN_BONUS;
const reasonToResponse = (reason) => reason.toLowerCase();
const typeToResponse = (type) => type.toLowerCase();
let WalletService = class WalletService {
    constructor(prisma) {
        this.prisma = prisma;
        this.walletReasonSupportCache = new Map();
    }
    async getWallet(authUser) {
        try {
            await this.ensureWalletAndBonuses(authUser.userId);
            const wallet = await this.findWalletOrThrow(authUser.userId);
            const transactionsPreview = await this.listTransactions(authUser.userId, 5);
            return this.buildWalletResponse(authUser.userId, wallet, transactionsPreview);
        }
        catch (error) {
            throw this.wrapWalletError(error);
        }
    }
    async getTransactions(authUser) {
        try {
            await this.ensureWalletAndBonuses(authUser.userId);
            const wallet = await this.findWalletOrThrow(authUser.userId);
            const transactions = await this.listTransactions(authUser.userId);
            return {
                wallet: await this.buildWalletResponse(authUser.userId, wallet, transactions.slice(0, 5)),
                items: transactions.map((transaction) => this.serializeTransaction(transaction)),
            };
        }
        catch (error) {
            throw this.wrapWalletError(error);
        }
    }
    async checkAccrual(authUser) {
        try {
            const wallet = await this.ensureWalletAndBonuses(authUser.userId);
            return {
                wallet: await this.buildWalletResponse(authUser.userId, wallet),
            };
        }
        catch (error) {
            throw this.wrapWalletError(error);
        }
    }
    async ensureWalletForUser(userId, tx) {
        const prisma = tx ?? this.prisma;
        return prisma.wallet.upsert({
            where: {
                userId,
            },
            update: {},
            create: {
                userId,
            },
        });
    }
    async accrueWelcomeBonusIfNeeded(userId) {
        return this.runInTransaction(async (tx) => {
            const wallet = await this.ensureWalletForUser(userId, tx);
            await this.lockWalletRow(tx, userId);
            const existing = await tx.walletTransaction.findFirst({
                where: {
                    userId,
                    reason: client_1.WalletTransactionReason.WELCOME_BONUS,
                },
                select: {
                    id: true,
                },
            });
            if (existing) {
                return tx.wallet.findUniqueOrThrow({
                    where: {
                        userId,
                    },
                });
            }
            const nextBalance = Math.min(wallet_constants_1.WALLET_MAX_BALANCE, wallet.bonusBalance + wallet_constants_1.WALLET_WELCOME_BONUS);
            const accruedAmount = nextBalance - wallet.bonusBalance;
            const accrualAt = new Date();
            const updatedWallet = await tx.wallet.update({
                where: {
                    id: wallet.id,
                },
                data: {
                    bonusBalance: nextBalance,
                },
            });
            await tx.walletTransaction.create({
                data: {
                    userId,
                    walletId: wallet.id,
                    type: client_1.WalletTransactionType.ACCRUAL,
                    amount: accruedAmount,
                    reason: client_1.WalletTransactionReason.WELCOME_BONUS,
                    metadata: this.buildTransactionMetadata({
                        description: 'Бонус за регистрацию',
                        source: 'welcome_bonus',
                    }),
                },
            });
            return updatedWallet;
        });
    }
    async checkAndAccrueDailyBonus(userId) {
        return this.runInTransaction(async (tx) => {
            const wallet = await this.ensureWalletForUser(userId, tx);
            await this.lockWalletRow(tx, userId);
            const now = new Date();
            const dayWindow = this.getUtcDayWindow(now);
            const latestDailyBonus = await tx.walletTransaction.findFirst({
                where: {
                    userId,
                    reason: DAILY_LOGIN_BONUS_REASON,
                },
                orderBy: {
                    createdAt: 'desc',
                },
                select: {
                    id: true,
                    createdAt: true,
                },
            });
            if (latestDailyBonus &&
                latestDailyBonus.createdAt >= dayWindow.start &&
                latestDailyBonus.createdAt < dayWindow.end) {
                return tx.wallet.findUniqueOrThrow({
                    where: {
                        userId,
                    },
                });
            }
            if (wallet.bonusBalance >= wallet_constants_1.WALLET_MAX_BALANCE) {
                return tx.wallet.findUniqueOrThrow({
                    where: {
                        userId,
                    },
                });
            }
            const nextBalance = Math.min(wallet_constants_1.WALLET_MAX_BALANCE, wallet.bonusBalance + wallet_constants_1.WALLET_DAILY_BONUS_AMOUNT);
            const accruedAmount = nextBalance - wallet.bonusBalance;
            if (accruedAmount <= 0) {
                return tx.wallet.findUniqueOrThrow({
                    where: {
                        userId,
                    },
                });
            }
            const accrualAt = now;
            const updatedWallet = await tx.wallet.update({
                where: {
                    id: wallet.id,
                },
                data: {
                    bonusBalance: nextBalance,
                    lastBonusAccrualAt: accrualAt,
                },
            });
            await tx.walletTransaction.create({
                data: {
                    userId,
                    walletId: wallet.id,
                    type: client_1.WalletTransactionType.ACCRUAL,
                    amount: accruedAmount,
                    reason: DAILY_LOGIN_BONUS_REASON,
                    metadata: this.buildTransactionMetadata(),
                },
            });
            return updatedWallet;
        });
    }
    async spendBonus(userId, amount, reason, metadata, tx) {
        if (amount <= 0) {
            throw new common_1.BadRequestException('Bonus amount must be positive');
        }
        return this.runInTransaction(async (transaction) => {
            const wallet = await this.ensureWalletForUser(userId, transaction);
            await this.lockWalletRow(transaction, userId);
            const currentWallet = await transaction.wallet.findUniqueOrThrow({
                where: {
                    userId,
                },
            });
            if (currentWallet.bonusBalance < amount) {
                throw new common_1.BadRequestException('Недостаточно бонусов');
            }
            const updatedWallet = await transaction.wallet.update({
                where: {
                    id: wallet.id,
                },
                data: {
                    bonusBalance: {
                        decrement: amount,
                    },
                },
            });
            await transaction.walletTransaction.create({
                data: {
                    userId,
                    walletId: wallet.id,
                    type: client_1.WalletTransactionType.SPEND,
                    amount,
                    reason,
                    metadata: this.buildTransactionMetadata(metadata),
                },
            });
            return updatedWallet;
        }, tx);
    }
    async resolveSpendReason(preferred, tx) {
        if (preferred === client_1.WalletTransactionReason.RECURRING_BONUS) {
            return preferred;
        }
        const isSupported = await this.supportsWalletTransactionReason(preferred, tx);
        if (isSupported) {
            return preferred;
        }
        console.warn(`[WalletService] WalletTransactionReason ${preferred} is missing in database enum. Falling back to RECURRING_BONUS.`);
        return client_1.WalletTransactionReason.RECURRING_BONUS;
    }
    async refundBonus(userId, amount, reason, metadata, tx) {
        if (amount <= 0) {
            throw new common_1.BadRequestException('Bonus amount must be positive');
        }
        return this.runInTransaction(async (transaction) => {
            const wallet = await this.ensureWalletForUser(userId, transaction);
            await this.lockWalletRow(transaction, userId);
            const currentWallet = await transaction.wallet.findUniqueOrThrow({
                where: {
                    userId,
                },
            });
            const nextBalance = Math.min(wallet_constants_1.WALLET_MAX_BALANCE, currentWallet.bonusBalance + amount);
            const refundAmount = nextBalance - currentWallet.bonusBalance;
            const updatedWallet = await transaction.wallet.update({
                where: {
                    id: wallet.id,
                },
                data: {
                    bonusBalance: nextBalance,
                },
            });
            await transaction.walletTransaction.create({
                data: {
                    userId,
                    walletId: wallet.id,
                    type: client_1.WalletTransactionType.REFUND,
                    amount: refundAmount,
                    reason,
                    metadata: this.buildTransactionMetadata(metadata),
                },
            });
            return updatedWallet;
        }, tx);
    }
    async accrueManualBonusIfNeeded(userId, { amount, reference, description, source, metadata, }, tx) {
        if (amount <= 0) {
            throw new common_1.BadRequestException('Bonus amount must be positive');
        }
        const normalizedReference = reference.trim();
        const normalizedDescription = description.trim();
        if (!normalizedReference) {
            throw new common_1.BadRequestException('Bonus reference is required');
        }
        return this.runInTransaction(async (transaction) => {
            const wallet = await this.ensureWalletForUser(userId, transaction);
            await this.lockWalletRow(transaction, userId);
            const currentWallet = await transaction.wallet.findUniqueOrThrow({
                where: {
                    userId,
                },
            });
            const existingTransactions = await transaction.walletTransaction.findMany({
                where: {
                    userId,
                    reason: client_1.WalletTransactionReason.RECURRING_BONUS,
                },
            });
            const alreadyApplied = existingTransactions.some((item) => {
                if (!item.metadata || typeof item.metadata !== 'object' || Array.isArray(item.metadata)) {
                    return false;
                }
                return item.metadata.reference === normalizedReference;
            });
            if (alreadyApplied) {
                return {
                    applied: false,
                    wallet: currentWallet,
                };
            }
            const updatedWallet = await transaction.wallet.update({
                where: {
                    id: wallet.id,
                },
                data: {
                    bonusBalance: {
                        increment: amount,
                    },
                },
            });
            await transaction.walletTransaction.create({
                data: {
                    userId,
                    walletId: wallet.id,
                    type: client_1.WalletTransactionType.ACCRUAL,
                    amount,
                    reason: client_1.WalletTransactionReason.RECURRING_BONUS,
                    metadata: this.buildTransactionMetadata({
                        reference: normalizedReference,
                        description: normalizedDescription,
                        source: source?.trim().length
                            ? source.trim()
                            : 'manual_bonus',
                        ...(metadata && typeof metadata === 'object' && !Array.isArray(metadata)
                            ? metadata
                            : {}),
                    }),
                },
            });
            return {
                applied: true,
                wallet: updatedWallet,
            };
        }, tx);
    }
    async ensureWalletAndBonuses(userId) {
        await this.ensureWalletForUser(userId);
        await this.accrueWelcomeBonusIfNeeded(userId);
        return this.checkAndAccrueDailyBonus(userId);
    }
    async ensureWalletAndBonusesSafely(userId) {
        try {
            return await this.ensureWalletAndBonuses(userId);
        }
        catch {
            return null;
        }
    }
    async buildWalletResponse(userId, wallet, transactionsPreview) {
        const now = new Date();
        const dayWindow = this.getUtcDayWindow(now);
        const lastDailyBonusAt = wallet.lastBonusAccrualAt;
        const claimedToday = lastDailyBonusAt != null &&
            lastDailyBonusAt >= dayWindow.start &&
            lastDailyBonusAt < dayWindow.end;
        const canClaimDailyBonus = wallet.bonusBalance < wallet_constants_1.WALLET_MAX_BALANCE && !claimedToday;
        const nextDailyBonusAt = canClaimDailyBonus ? now : dayWindow.end;
        const preview = transactionsPreview ?? (await this.listTransactions(userId, 5));
        return {
            balance: wallet.bonusBalance,
            maxBalance: wallet_constants_1.WALLET_MAX_BALANCE,
            welcomeBonus: wallet_constants_1.WALLET_WELCOME_BONUS,
            dailyBonusAmount: wallet_constants_1.WALLET_DAILY_BONUS_AMOUNT,
            lastDailyBonusAt: lastDailyBonusAt?.toISOString() ?? null,
            canClaimDailyBonus,
            nextDailyBonusAt: nextDailyBonusAt.toISOString(),
            lastBonusAccrualAt: lastDailyBonusAt?.toISOString() ?? null,
            nextAccrualAt: nextDailyBonusAt.toISOString(),
            daysUntilNextAccrual: Math.max(0, Math.ceil((nextDailyBonusAt.getTime() - now.getTime()) / (24 * 60 * 60 * 1000))),
            secondsUntilNextAccrual: Math.max(0, Math.ceil((nextDailyBonusAt.getTime() - now.getTime()) / 1000)),
            transactionsPreview: preview.map((transaction) => this.serializeTransaction(transaction)),
        };
    }
    async findWalletOrThrow(userId) {
        const wallet = await this.prisma.wallet.findUnique({
            where: {
                userId,
            },
        });
        if (!wallet) {
            throw new common_1.NotFoundException('Wallet not found');
        }
        return wallet;
    }
    async lockWalletRow(tx, userId) {
        await tx.$queryRaw `
      SELECT id
      FROM "wallets"
      WHERE "user_id" = ${userId}::uuid
      FOR UPDATE
    `;
    }
    runInTransaction(handler, tx) {
        if (tx) {
            return handler(tx);
        }
        return this.prisma.$transaction((transaction) => handler(transaction));
    }
    async supportsWalletTransactionReason(reason, tx) {
        const cached = this.walletReasonSupportCache.get(reason);
        if (cached != null) {
            return cached;
        }
        const prisma = tx ?? this.prisma;
        try {
            const result = await prisma.$queryRaw `
        SELECT EXISTS (
          SELECT 1
          FROM pg_type t
          JOIN pg_enum e ON e.enumtypid = t.oid
          WHERE t.typname = 'WalletTransactionReason'
            AND e.enumlabel = ${reason}
        ) AS "exists"
      `;
            const isSupported = result[0]?.exists === true;
            this.walletReasonSupportCache.set(reason, isSupported);
            return isSupported;
        }
        catch {
            return true;
        }
    }
    buildTransactionMetadata(metadata) {
        const base = {
            source: 'bonus',
            futurePaymentId: null,
            futureMoneyAmount: null,
        };
        if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) {
            return base;
        }
        return {
            ...base,
            ...metadata,
        };
    }
    listTransactions(userId, take) {
        return this.prisma.walletTransaction.findMany({
            where: {
                userId,
            },
            orderBy: {
                createdAt: 'desc',
            },
            ...(take == null ? {} : { take }),
        });
    }
    serializeTransaction(transaction) {
        return {
            id: transaction.id,
            user_id: transaction.userId,
            wallet_id: transaction.walletId,
            type: typeToResponse(transaction.type),
            amount: transaction.amount,
            reason: reasonToResponse(transaction.reason),
            metadata: transaction.metadata,
            created_at: transaction.createdAt.toISOString(),
        };
    }
    getUtcDayWindow(date) {
        const start = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
        const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
        return { start, end };
    }
    wrapWalletError(error) {
        if (error instanceof common_1.HttpException) {
            return error;
        }
        return new common_1.ServiceUnavailableException('Кошелёк временно недоступен. Попробуйте позже.');
    }
};
exports.WalletService = WalletService;
exports.WalletService = WalletService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], WalletService);
//# sourceMappingURL=wallet.service.js.map