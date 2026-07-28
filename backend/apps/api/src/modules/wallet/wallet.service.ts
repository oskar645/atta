import {
  BadRequestException,
  HttpException,
  Inject,
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
  WALLET_NOW_PROVIDER,
  WALLET_TIME_ZONE,
  WALLET_WELCOME_BONUS,
} from './wallet.constants';

type PrismaLike = PrismaService | Prisma.TransactionClient;
type WalletNowProvider = () => Date;
const DAILY_LOGIN_BONUS_REASON = WalletTransactionReason.DAILY_LOGIN_BONUS;
const SIGNUP_BONUS_REASON = WalletTransactionReason.SIGNUP_BONUS;
type DailyBonusResult = {
  wallet: Wallet;
  awarded: boolean;
  amount: number;
  claimedDate: string;
  alreadyClaimed?: boolean;
  reason?: 'registration_day';
};

const reasonToResponse = (reason: WalletTransactionReason) =>
  reason.toLowerCase();

const typeToResponse = (type: WalletTransactionType) =>
  type.toLowerCase();

@Injectable()
export class WalletService {
  private readonly walletReasonSupportCache =
    new Map<WalletTransactionReason, boolean>();

  constructor(
    private readonly prisma: PrismaService,
    @Inject(WALLET_NOW_PROVIDER)
    private readonly nowProvider: WalletNowProvider = () => new Date(),
  ) {}

  async getWallet(authUser: AuthenticatedUser) {
    try {
      await this.ensureWalletAndSignupBonus(authUser.userId);
      const wallet = await this.findWalletOrThrow(authUser.userId);
      const transactionsPreview = await this.listTransactions(authUser.userId, 5);

      return this.buildWalletResponse(authUser.userId, wallet, transactionsPreview);
    } catch (error) {
      throw this.wrapWalletError(error);
    }
  }

  async getTransactions(authUser: AuthenticatedUser) {
    try {
      await this.ensureWalletAndSignupBonus(authUser.userId);
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
      await this.ensureWalletAndSignupBonus(authUser.userId);
      const result = await this.checkDailyBonus(authUser.userId);
      return {
        awarded: result.awarded,
        amount: result.amount,
        balance: result.wallet.bonusBalance,
        alreadyClaimed: result.alreadyClaimed ?? false,
        reason: result.reason,
        claimedDate: result.claimedDate,
        wallet: await this.buildWalletResponse(authUser.userId, result.wallet),
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
          reason: {
            in: [SIGNUP_BONUS_REASON, WalletTransactionReason.WELCOME_BONUS],
          },
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

      const idempotencyKey = `signup_bonus:${userId}`;
      const existingByKey = await tx.walletTransaction.findUnique({
        where: {
          idempotencyKey,
        },
        select: {
          id: true,
        },
      });
      if (existingByKey) {
        return tx.wallet.findUniqueOrThrow({
          where: {
            userId,
          },
        });
      }

      const updatedWallet = await tx.wallet.update({
        where: {
          id: wallet.id,
        },
        data: {
          bonusBalance: {
            increment: WALLET_WELCOME_BONUS,
          },
        },
      });

      await tx.walletTransaction.create({
        data: {
          userId,
          walletId: wallet.id,
          type: WalletTransactionType.ACCRUAL,
          amount: WALLET_WELCOME_BONUS,
          reason: SIGNUP_BONUS_REASON,
          idempotencyKey,
          metadata: this.buildTransactionMetadata({
            description: 'Бонус за регистрацию',
            source: 'signup_bonus',
          }),
        },
      });

      return updatedWallet;
    });
  }

  async checkAndAccrueDailyBonus(userId: string) {
    const result = await this.checkDailyBonus(userId);
    return result.wallet;
  }

  private async checkDailyBonus(userId: string): Promise<DailyBonusResult> {
    const now = this.nowProvider();
    const claimDate = this.getZonedDateStamp(now);
    try {
      return await this.runInTransaction(async (tx) => {
      const wallet = await this.ensureWalletForUser(userId, tx);
      await this.lockWalletRow(tx, userId);

      const user = await tx.user.findUniqueOrThrow({
        where: {
          id: userId,
        },
        select: {
          createdAt: true,
        },
      });
      if (this.getZonedDateStamp(user.createdAt) === claimDate) {
        const currentWallet = await tx.wallet.findUniqueOrThrow({
          where: {
            userId,
          },
        });
        return {
          wallet: currentWallet,
          awarded: false,
          amount: 0,
          reason: 'registration_day',
          claimedDate: claimDate,
        };
      }

      const idempotencyKey = `daily_login_bonus:${userId}:${claimDate}`;
      if (
        wallet.lastBonusAccrualAt != null &&
        this.getZonedDateStamp(wallet.lastBonusAccrualAt) === claimDate
      ) {
        const currentWallet = await tx.wallet.findUniqueOrThrow({
          where: {
            userId,
          },
        });
        return {
          wallet: currentWallet,
          awarded: false,
          amount: 0,
          alreadyClaimed: true,
          claimedDate: claimDate,
        };
      }

      const existingDailyBonus = await tx.walletTransaction.findUnique({
        where: {
          idempotencyKey,
        },
        select: {
          id: true,
          createdAt: true,
        },
      });

      if (existingDailyBonus) {
        const currentWallet = await tx.wallet.findUniqueOrThrow({
          where: {
            userId,
          },
        });
        return {
          wallet: currentWallet,
          awarded: false,
          amount: 0,
          alreadyClaimed: true,
          claimedDate: claimDate,
        };
      }

      const accrualAt = now;
      const updatedWallet = await tx.wallet.update({
        where: {
          id: wallet.id,
        },
        data: {
          bonusBalance: {
            increment: WALLET_DAILY_BONUS_AMOUNT,
          },
          lastBonusAccrualAt: accrualAt,
        },
      });

      await tx.walletTransaction.create({
        data: {
          userId,
          walletId: wallet.id,
          type: WalletTransactionType.ACCRUAL,
          amount: WALLET_DAILY_BONUS_AMOUNT,
          reason: DAILY_LOGIN_BONUS_REASON,
          idempotencyKey,
          metadata: this.buildTransactionMetadata(),
        },
      });

      return {
        wallet: updatedWallet,
        awarded: true,
        amount: WALLET_DAILY_BONUS_AMOUNT,
        claimedDate: claimDate,
      };
      });
    } catch (error) {
      if (!this.isUniqueConstraintError(error)) {
        throw error;
      }
      const wallet = await this.findWalletOrThrow(userId);
      return {
        wallet,
        awarded: false,
        amount: 0,
        alreadyClaimed: true,
        claimedDate: claimDate,
      };
    }
  }

  async spendBonus(
    userId: string,
    amount: number,
    reason: WalletTransactionReason,
    metadata?: Prisma.InputJsonValue,
    tx?: Prisma.TransactionClient,
    idempotencyKey?: string,
  ) {
    if (amount <= 0) {
      throw new BadRequestException('Bonus amount must be positive');
    }

    return this.runInTransaction(async (transaction) => {
      const wallet = await this.ensureWalletForUser(userId, transaction);
      await this.lockWalletRow(transaction, userId);
      if (idempotencyKey) {
        const existingTransaction = await transaction.walletTransaction.findUnique({
          where: {
            idempotencyKey,
          },
          select: {
            id: true,
          },
        });
        if (existingTransaction) {
          return transaction.wallet.findUniqueOrThrow({
            where: {
              userId,
            },
          });
        }
      }

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
          idempotencyKey,
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
          type: WalletTransactionType.REFUND,
          amount,
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
    return this.ensureWalletAndSignupBonus(userId);
  }

  async ensureWalletAndSignupBonus(userId: string) {
    await this.ensureWalletForUser(userId);
    return this.accrueWelcomeBonusIfNeeded(userId);
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
    const now = this.nowProvider();
    const claimDate = this.getZonedDateStamp(now);
    const lastDailyBonusAt = wallet.lastBonusAccrualAt;
    const claimedToday =
      lastDailyBonusAt != null &&
      this.getZonedDateStamp(lastDailyBonusAt) === claimDate;
    const canClaimDailyBonus = !claimedToday;
    const nextDailyBonusAt = canClaimDailyBonus
      ? now
      : this.getNextZonedMidnight(now);
    const preview =
      transactionsPreview ?? (await this.listTransactions(userId, 5));

    return {
      balance: wallet.bonusBalance,
      maxBalance: null,
      welcomeBonus: WALLET_WELCOME_BONUS,
      dailyBonusAmount: WALLET_DAILY_BONUS_AMOUNT,
      lastDailyBonusAt: lastDailyBonusAt?.toISOString() ?? null,
      claimedDate: claimDate,
      timeZone: WALLET_TIME_ZONE,
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
    idempotencyKey?: string | null;
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
      idempotency_key: transaction.idempotencyKey ?? null,
      metadata: transaction.metadata,
      created_at: transaction.createdAt.toISOString(),
    };
  }

  private getZonedDateStamp(date: Date) {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: WALLET_TIME_ZONE,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(date);
    const values = Object.fromEntries(
      parts
        .filter((part) => part.type !== 'literal')
        .map((part) => [part.type, part.value]),
    );
    return `${values.year}-${values.month}-${values.day}`;
  }

  private getNextZonedMidnight(date: Date) {
    const [year, month, day] = this.getZonedDateStamp(date)
      .split('-')
      .map((value) => Number(value));
    const nextUtcApproximation = new Date(
      Date.UTC(year, month - 1, day + 1, 0, 0, 0),
    );
    if (WALLET_TIME_ZONE === 'Europe/Moscow') {
      return new Date(nextUtcApproximation.getTime() - 3 * 60 * 60 * 1000);
    }
    return nextUtcApproximation;
  }

  private isUniqueConstraintError(error: unknown) {
    return (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === 'P2002'
    );
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
