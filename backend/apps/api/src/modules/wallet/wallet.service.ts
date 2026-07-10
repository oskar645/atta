import {
  BadRequestException,
  HttpException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  Prisma,
  Wallet,
  WalletTransactionReason,
  WalletTransactionType,
} from '@prisma/client';

import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import {
  WALLET_DAILY_BONUS_AMOUNT,
  WALLET_MAX_BALANCE,
  WALLET_WELCOME_BONUS,
} from './wallet.constants';

type PrismaLike = PrismaService | Prisma.TransactionClient;
const DAILY_LOGIN_BONUS_REASON = WalletTransactionReason.DAILY_LOGIN_BONUS;

const reasonToResponse = (reason: WalletTransactionReason) =>
  reason.toLowerCase();

const typeToResponse = (type: WalletTransactionType) =>
  type.toLowerCase();

@Injectable()
export class WalletService {
  private readonly walletReasonSupportCache =
    new Map<WalletTransactionReason, boolean>();

  constructor(private readonly prisma: PrismaService) {}

  async getWallet(authUser: AuthenticatedUser) {
    try {
      await this.ensureWalletAndBonuses(authUser.userId);
      const wallet = await this.findWalletOrThrow(authUser.userId);
      const transactionsPreview = await this.listTransactions(authUser.userId, 5);

      return this.buildWalletResponse(authUser.userId, wallet, transactionsPreview);
    } catch (error) {
      throw this.wrapWalletError(error);
    }
  }

  async getTransactions(authUser: AuthenticatedUser) {
    try {
      await this.ensureWalletAndBonuses(authUser.userId);
      const wallet = await this.findWalletOrThrow(authUser.userId);
      const transactions = await this.listTransactions(authUser.userId);

      return {
        wallet: await this.buildWalletResponse(authUser.userId, wallet, transactions.slice(0, 5)),
        items: transactions.map((transaction) => this.serializeTransaction(transaction)),
      };
    } catch (error) {
      throw this.wrapWalletError(error);
    }
  }

  async checkAccrual(authUser: AuthenticatedUser) {
    try {
      const wallet = await this.ensureWalletAndBonuses(authUser.userId);
      return {
        wallet: await this.buildWalletResponse(authUser.userId, wallet),
      };
    } catch (error) {
      throw this.wrapWalletError(error);
    }
  }

  async ensureWalletForUser(userId: string, tx?: PrismaLike) {
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

  async accrueWelcomeBonusIfNeeded(userId: string) {
    return this.runInTransaction(async (tx) => {
      const wallet = await this.ensureWalletForUser(userId, tx);
      await this.lockWalletRow(tx, userId);

      const existing = await tx.walletTransaction.findFirst({
        where: {
          userId,
          reason: WalletTransactionReason.WELCOME_BONUS,
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

      const nextBalance = Math.min(
        WALLET_MAX_BALANCE,
        wallet.bonusBalance + WALLET_WELCOME_BONUS,
      );
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
          type: WalletTransactionType.ACCRUAL,
          amount: accruedAmount,
          reason: WalletTransactionReason.WELCOME_BONUS,
          metadata: this.buildTransactionMetadata({
            description: 'Бонус за регистрацию',
            source: 'welcome_bonus',
          }),
        },
      });

      return updatedWallet;
    });
  }

  async checkAndAccrueDailyBonus(userId: string) {
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

      if (
        latestDailyBonus &&
        latestDailyBonus.createdAt >= dayWindow.start &&
        latestDailyBonus.createdAt < dayWindow.end
      ) {
        return tx.wallet.findUniqueOrThrow({
          where: {
            userId,
          },
        });
      }

      if (wallet.bonusBalance >= WALLET_MAX_BALANCE) {
        return tx.wallet.findUniqueOrThrow({
          where: {
            userId,
          },
        });
      }

      const nextBalance = Math.min(
        WALLET_MAX_BALANCE,
        wallet.bonusBalance + WALLET_DAILY_BONUS_AMOUNT,
      );
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
          type: WalletTransactionType.ACCRUAL,
          amount: accruedAmount,
          reason: DAILY_LOGIN_BONUS_REASON,
          metadata: this.buildTransactionMetadata(),
        },
      });

      return updatedWallet;
    });
  }

  async spendBonus(
    userId: string,
    amount: number,
    reason: WalletTransactionReason,
    metadata?: Prisma.InputJsonValue,
    tx?: Prisma.TransactionClient,
  ) {
    if (amount <= 0) {
      throw new BadRequestException('Bonus amount must be positive');
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
        throw new BadRequestException('Недостаточно бонусов');
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
          type: WalletTransactionType.SPEND,
          amount,
          reason,
          metadata: this.buildTransactionMetadata(metadata),
        },
      });

      return updatedWallet;
    }, tx);
  }

  async resolveSpendReason(
    preferred: WalletTransactionReason,
    tx?: PrismaLike,
  ) {
    if (preferred === WalletTransactionReason.RECURRING_BONUS) {
      return preferred;
    }

    const isSupported = await this.supportsWalletTransactionReason(
      preferred,
      tx,
    );
    if (isSupported) {
      return preferred;
    }

    console.warn(
      `[WalletService] WalletTransactionReason ${preferred} is missing in database enum. Falling back to RECURRING_BONUS.`,
    );
    return WalletTransactionReason.RECURRING_BONUS;
  }

  async refundBonus(
    userId: string,
    amount: number,
    reason: WalletTransactionReason,
    metadata?: Prisma.InputJsonValue,
    tx?: Prisma.TransactionClient,
  ) {
    if (amount <= 0) {
      throw new BadRequestException('Bonus amount must be positive');
    }

    return this.runInTransaction(async (transaction) => {
      const wallet = await this.ensureWalletForUser(userId, transaction);
      await this.lockWalletRow(transaction, userId);
      const currentWallet = await transaction.wallet.findUniqueOrThrow({
        where: {
          userId,
        },
      });
      const nextBalance = Math.min(
        WALLET_MAX_BALANCE,
        currentWallet.bonusBalance + amount,
      );
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
          type: WalletTransactionType.REFUND,
          amount: refundAmount,
          reason,
          metadata: this.buildTransactionMetadata(metadata),
        },
      });

      return updatedWallet;
    }, tx);
  }

  async accrueManualBonusIfNeeded(
    userId: string,
    {
      amount,
      reference,
      description,
      source,
      metadata,
    }: {
      amount: number;
      reference: string;
      description: string;
      source?: string;
      metadata?: Prisma.InputJsonValue;
    },
    tx?: Prisma.TransactionClient,
  ) {
    if (amount <= 0) {
      throw new BadRequestException('Bonus amount must be positive');
    }

    const normalizedReference = reference.trim();
    const normalizedDescription = description.trim();
    if (!normalizedReference) {
      throw new BadRequestException('Bonus reference is required');
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
          reason: WalletTransactionReason.RECURRING_BONUS,
        },
      });
      const alreadyApplied = existingTransactions.some((item) => {
        if (!item.metadata || typeof item.metadata !== 'object' || Array.isArray(item.metadata)) {
          return false;
        }
        return (item.metadata as Record<string, unknown>).reference === normalizedReference;
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
          type: WalletTransactionType.ACCRUAL,
          amount,
          reason: WalletTransactionReason.RECURRING_BONUS,
          metadata: this.buildTransactionMetadata({
            reference: normalizedReference,
            description: normalizedDescription,
            source:
              source?.trim().length
                ? source.trim()
                : 'manual_bonus',
            ...(metadata && typeof metadata === 'object' && !Array.isArray(metadata)
              ? (metadata as Record<string, unknown>)
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

  async ensureWalletAndBonuses(userId: string) {
    await this.ensureWalletForUser(userId);
    await this.accrueWelcomeBonusIfNeeded(userId);
    return this.checkAndAccrueDailyBonus(userId);
  }

  async ensureWalletAndBonusesSafely(userId: string) {
    try {
      return await this.ensureWalletAndBonuses(userId);
    } catch {
      return null;
    }
  }

  async buildWalletResponse(
    userId: string,
    wallet: Wallet,
    transactionsPreview?: Awaited<ReturnType<WalletService['listTransactions']>>,
  ) {
    const now = new Date();
    const dayWindow = this.getUtcDayWindow(now);
    const lastDailyBonusAt = wallet.lastBonusAccrualAt;
    const claimedToday =
      lastDailyBonusAt != null &&
      lastDailyBonusAt >= dayWindow.start &&
      lastDailyBonusAt < dayWindow.end;
    const canClaimDailyBonus =
      wallet.bonusBalance < WALLET_MAX_BALANCE && !claimedToday;
    const nextDailyBonusAt = canClaimDailyBonus ? now : dayWindow.end;
    const preview =
      transactionsPreview ?? (await this.listTransactions(userId, 5));

    return {
      balance: wallet.bonusBalance,
      maxBalance: WALLET_MAX_BALANCE,
      welcomeBonus: WALLET_WELCOME_BONUS,
      dailyBonusAmount: WALLET_DAILY_BONUS_AMOUNT,
      lastDailyBonusAt: lastDailyBonusAt?.toISOString() ?? null,
      canClaimDailyBonus,
      nextDailyBonusAt: nextDailyBonusAt.toISOString(),
      lastBonusAccrualAt: lastDailyBonusAt?.toISOString() ?? null,
      nextAccrualAt: nextDailyBonusAt.toISOString(),
      daysUntilNextAccrual: Math.max(
        0,
        Math.ceil((nextDailyBonusAt.getTime() - now.getTime()) / (24 * 60 * 60 * 1000)),
      ),
      secondsUntilNextAccrual: Math.max(
        0,
        Math.ceil((nextDailyBonusAt.getTime() - now.getTime()) / 1000),
      ),
      transactionsPreview: preview.map((transaction) =>
        this.serializeTransaction(transaction),
      ),
    };
  }

  private async findWalletOrThrow(userId: string) {
    const wallet = await this.prisma.wallet.findUnique({
      where: {
        userId,
      },
    });

    if (!wallet) {
      throw new NotFoundException('Wallet not found');
    }

    return wallet;
  }

  private async lockWalletRow(
    tx: Prisma.TransactionClient,
    userId: string,
  ) {
    await tx.$queryRaw`
      SELECT id
      FROM "wallets"
      WHERE "user_id" = ${userId}::uuid
      FOR UPDATE
    `;
  }

  private runInTransaction<T>(
    handler: (tx: Prisma.TransactionClient) => Promise<T>,
    tx?: Prisma.TransactionClient,
  ) {
    if (tx) {
      return handler(tx);
    }

    return this.prisma.$transaction((transaction) => handler(transaction));
  }

  private async supportsWalletTransactionReason(
    reason: WalletTransactionReason,
    tx?: PrismaLike,
  ) {
    const cached = this.walletReasonSupportCache.get(reason);
    if (cached != null) {
      return cached;
    }

    const prisma = tx ?? this.prisma;

    try {
      const result = await prisma.$queryRaw<Array<{ exists: boolean }>>`
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
    } catch {
      return true;
    }
  }

  private buildTransactionMetadata(metadata?: Prisma.InputJsonValue) {
    const base = {
      source: 'bonus',
      futurePaymentId: null,
      futureMoneyAmount: null,
    } as const;

    if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) {
      return base;
    }

    return {
      ...base,
      ...(metadata as Record<string, unknown>),
    } as Prisma.InputJsonValue;
  }

  private listTransactions(userId: string, take?: number) {
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

  private serializeTransaction(transaction: {
    id: string;
    userId: string;
    walletId: string;
    type: WalletTransactionType;
    amount: number;
    reason: WalletTransactionReason;
    metadata: Prisma.JsonValue;
    createdAt: Date;
  }) {
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

  private getUtcDayWindow(date: Date) {
    const start = new Date(
      Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
    );
    const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
    return { start, end };
  }

  private wrapWalletError(error: unknown) {
    if (error instanceof HttpException) {
      return error;
    }
    return new ServiceUnavailableException(
      'Кошелёк временно недоступен. Попробуйте позже.',
    );
  }
}
