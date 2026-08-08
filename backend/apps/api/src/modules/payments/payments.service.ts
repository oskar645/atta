import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  PaymentProvider,
  PaymentStatus,
  Prisma,
} from '@prisma/client';
import { randomUUID } from 'crypto';

import { env } from '../../config/env';
import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import { WalletService } from '../wallet/wallet.service';

const YOOKASSA_API_BASE_URL = 'https://api.yookassa.ru/v3';
const YOOKASSA_CURRENCY = 'RUB';

type YooKassaPayment = {
  id?: unknown;
  status?: unknown;
  amount?: {
    value?: unknown;
    currency?: unknown;
  };
  confirmation?: {
    confirmation_url?: unknown;
  };
  metadata?: Record<string, unknown>;
};

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly walletService: WalletService,
  ) {}

  async createYookassaPayment(
    authUser: AuthenticatedUser,
    amountRub: number,
  ) {
    this.assertYookassaConfigured();
    const normalizedAmountRub = this.normalizeAmount(amountRub);
    const pointsAmount = normalizedAmountRub * env.YOOKASSA_POINTS_PER_RUBLE;
    const idempotencyKey = randomUUID();

    const payment = await this.prisma.payment.create({
      data: {
        userId: authUser.userId,
        provider: PaymentProvider.YOOKASSA,
        idempotencyKey,
        amountRub: new Prisma.Decimal(normalizedAmountRub),
        pointsAmount,
        currency: YOOKASSA_CURRENCY,
        status: PaymentStatus.PENDING,
        metadata: {
          source: 'wallet_top_up',
        },
      },
    });

    try {
      const yookassaPayment = await this.requestYooKassaPayment(
        'POST',
        '/payments',
        idempotencyKey,
        {
          amount: {
            value: this.formatRubAmount(normalizedAmountRub),
            currency: YOOKASSA_CURRENCY,
          },
          capture: true,
          confirmation: {
            type: 'redirect',
            return_url: env.YOOKASSA_RETURN_URL,
          },
          description: `Пополнение кошелька ATTA на ${pointsAmount} баллов`,
          metadata: {
            paymentId: payment.id,
            userId: authUser.userId,
          },
        },
      );

      const providerPaymentId = this.getRequiredString(
        yookassaPayment.id,
        'YooKassa payment id is missing',
      );
      const confirmationUrl = this.getRequiredString(
        yookassaPayment.confirmation?.confirmation_url,
        'YooKassa confirmation url is missing',
      );

      await this.prisma.payment.update({
        where: {
          id: payment.id,
        },
        data: {
          providerPaymentId,
        },
      });

      return {
        paymentId: payment.id,
        confirmationUrl,
      };
    } catch (error) {
      await this.prisma.payment.update({
        where: {
          id: payment.id,
        },
        data: {
          status: PaymentStatus.CANCELED,
          metadata: {
            source: 'wallet_top_up',
            failure: this.safeErrorMessage(error),
          },
        },
      });
      this.logger.warn(`YooKassa payment create failed: ${this.safeErrorMessage(error)}`);
      throw new ServiceUnavailableException(
        'Не удалось начать оплату. Попробуйте позже.',
      );
    }
  }

  async getPaymentStatus(authUser: AuthenticatedUser, paymentId: string) {
    let payment = await this.prisma.payment.findFirst({
      where: {
        id: paymentId,
        userId: authUser.userId,
      },
    });

    if (!payment) {
      throw new NotFoundException('Payment not found');
    }

    if (
      payment.status === PaymentStatus.PENDING &&
      payment.providerPaymentId
    ) {
      const actualPayment = await this.fetchYooKassaPayment(
        payment.providerPaymentId,
      );
      const verified = await this.verifyActualPayment(
        payment.providerPaymentId,
        actualPayment,
      );
      this.assertLocalPaymentMatchesVerified(
        payment,
        verified,
        'Payment amount mismatch',
      );
      const actualStatus =
        typeof actualPayment.status === 'string' ? actualPayment.status : '';
      if (actualStatus === 'succeeded') {
        await this.processSucceededYookassaPayment(
          payment.providerPaymentId,
          actualPayment,
        );
      } else if (actualStatus === 'canceled') {
        await this.processCanceledYookassaPayment(
          payment.providerPaymentId,
          actualPayment,
        );
      }

      payment = await this.prisma.payment.findFirst({
        where: {
          id: paymentId,
          userId: authUser.userId,
        },
      });
      if (!payment) {
        throw new NotFoundException('Payment not found');
      }
    }

    const wallet =
      payment.status === PaymentStatus.SUCCEEDED
        ? await this.walletService.ensureWalletForUser(authUser.userId)
        : null;

    return {
      paymentId: payment.id,
      status: this.statusToResponse(payment.status),
      pointsAmount: payment.pointsAmount,
      credited: payment.creditedAt != null,
      balance: wallet?.bonusBalance,
    };
  }

  async handleYookassaWebhook(payload: unknown) {
    const event = this.getPayloadEvent(payload);
    if (event !== 'payment.succeeded' && event !== 'payment.canceled') {
      return { ok: true };
    }

    const providerPaymentId = this.getPayloadPaymentId(payload);
    if (!providerPaymentId) {
      throw new BadRequestException('Payment id is missing');
    }

    const actualPayment = await this.fetchYooKassaPayment(providerPaymentId);
    if (event === 'payment.succeeded') {
      await this.processSucceededYookassaPayment(providerPaymentId, actualPayment);
    } else {
      await this.processCanceledYookassaPayment(providerPaymentId, actualPayment);
    }

    return { ok: true };
  }

  renderYookassaReturnPage() {
    const appUrl = 'https://attamarket.online/app';
    return `<!doctype html>
<html lang="ru">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Возвращаемся в ATTA</title>
    <script>
      window.setTimeout(function () {
        window.location.href = '${appUrl}';
      }, 100);
    </script>
    <style>
      body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f5f5f5; color: #1f1f1f; }
      main { width: 100%; max-width: 420px; padding: 24px; text-align: center; }
      h1 { margin: 0 0 12px; font-size: 28px; }
      p { margin: 0 0 20px; line-height: 1.5; }
      a { display: inline-block; padding: 12px 18px; border-radius: 12px; background: #1f1f1f; color: #ffffff; text-decoration: none; font-weight: 700; }
    </style>
  </head>
  <body>
    <main>
      <h1>Возвращаемся в ATTA</h1>
      <p>Проверим оплату в приложении. Баллы начисляются только после подтверждения ЮKassa.</p>
      <a href="${appUrl}">Открыть ATTA</a>
    </main>
  </body>
</html>`;
  }

  private async processSucceededYookassaPayment(
    providerPaymentId: string,
    actualPayment: YooKassaPayment,
  ) {
    if (actualPayment.status !== 'succeeded') {
      throw new BadRequestException('Payment is not succeeded');
    }
    const verified = await this.verifyActualPayment(providerPaymentId, actualPayment);

    await this.prisma.$transaction(async (tx) => {
      await this.lockPaymentRow(tx, verified.paymentId);
      const payment = await tx.payment.findUnique({
        where: {
          id: verified.paymentId,
        },
      });

      if (!payment || payment.providerPaymentId !== providerPaymentId) {
        throw new BadRequestException('Payment metadata mismatch');
      }
      if (payment.userId !== verified.userId) {
        throw new BadRequestException('Payment user mismatch');
      }
      if (
        payment.status === PaymentStatus.SUCCEEDED &&
        payment.creditedAt != null
      ) {
        return;
      }
      if (
        !this.localPaymentMatchesVerified(payment, verified)
      ) {
        throw new BadRequestException('Payment amount mismatch');
      }

      await this.walletService.accruePurchasedPointsIfNeeded(
        payment.userId,
        {
          amount: payment.pointsAmount,
          paymentId: payment.id,
          providerPaymentId,
        },
        tx,
      );

      await tx.payment.update({
        where: {
          id: payment.id,
        },
        data: {
          status: PaymentStatus.SUCCEEDED,
          creditedAt: new Date(),
          metadata: {
            source: 'wallet_top_up',
            providerPaymentId,
          },
        },
      });
    });
  }

  private async processCanceledYookassaPayment(
    providerPaymentId: string,
    actualPayment: YooKassaPayment,
  ) {
    if (actualPayment.status !== 'canceled') {
      return;
    }

    const verified = await this.verifyActualPayment(providerPaymentId, actualPayment);
    const payment = await this.prisma.payment.findUnique({
      where: {
        providerPaymentId,
      },
    });
    if (!payment || payment.status === PaymentStatus.SUCCEEDED) {
      return;
    }
    if (
      !this.localPaymentMatchesVerified(payment, verified)
    ) {
      throw new BadRequestException('Payment metadata mismatch');
    }

    await this.prisma.payment.update({
      where: {
        id: payment.id,
      },
      data: {
        status: PaymentStatus.CANCELED,
      },
    });
  }

  private async verifyActualPayment(
    providerPaymentId: string,
    actualPayment: YooKassaPayment,
  ) {
    const metadata = actualPayment.metadata ?? {};
    const paymentId = this.getRequiredString(
      metadata.paymentId,
      'Payment metadata is missing',
    );
    const userId = this.getRequiredString(
      metadata.userId,
      'Payment metadata is missing',
    );
    if (actualPayment.id !== providerPaymentId) {
      throw new BadRequestException('Payment id mismatch');
    }
    const amountValue = this.getRequiredString(
      actualPayment.amount?.value,
      'Payment amount is missing',
    );
    const currency = this.getRequiredString(
      actualPayment.amount?.currency,
      'Payment currency is missing',
    );
    if (currency !== YOOKASSA_CURRENCY) {
      throw new BadRequestException('Payment currency mismatch');
    }
    const amountRub = Number(amountValue);
    if (!Number.isFinite(amountRub) || amountRub <= 0) {
      throw new BadRequestException('Payment amount is invalid');
    }

    return {
      paymentId,
      userId,
      amountValue: this.formatRubAmount(amountRub),
      pointsAmount: Math.round(amountRub * env.YOOKASSA_POINTS_PER_RUBLE),
    };
  }

  private assertLocalPaymentMatchesVerified(
    payment: {
      id: string;
      userId: string;
      currency: string;
      amountRub: { toFixed: (fractionDigits?: number) => string };
      pointsAmount: number;
    },
    verified: {
      paymentId: string;
      userId: string;
      amountValue: string;
      pointsAmount: number;
    },
    message = 'Payment metadata mismatch',
  ) {
    if (!this.localPaymentMatchesVerified(payment, verified)) {
      throw new BadRequestException(message);
    }
  }

  private localPaymentMatchesVerified(
    payment: {
      id: string;
      userId: string;
      currency: string;
      amountRub: { toFixed: (fractionDigits?: number) => string };
      pointsAmount: number;
    },
    verified: {
      paymentId: string;
      userId: string;
      amountValue: string;
      pointsAmount: number;
    },
  ) {
    return (
      payment.id === verified.paymentId &&
      payment.userId === verified.userId &&
      payment.currency === YOOKASSA_CURRENCY &&
      payment.amountRub.toFixed(2) === verified.amountValue &&
      payment.pointsAmount === verified.pointsAmount
    );
  }

  private async fetchYooKassaPayment(providerPaymentId: string) {
    this.assertYookassaConfigured();
    return this.requestYooKassaPayment('GET', `/payments/${providerPaymentId}`);
  }

  private async requestYooKassaPayment(
    method: 'GET' | 'POST',
    path: string,
    idempotencyKey?: string,
    body?: unknown,
  ): Promise<YooKassaPayment> {
    const headers: Record<string, string> = {
      Accept: 'application/json',
      Authorization: this.buildAuthorizationHeader(),
    };
    if (idempotencyKey) {
      headers['Idempotence-Key'] = idempotencyKey;
    }
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    let response: Response;
    try {
      response = await fetch(`${YOOKASSA_API_BASE_URL}${path}`, {
        method,
        headers,
        body: body == null ? undefined : JSON.stringify(body),
      });
    } catch {
      throw new ServiceUnavailableException('YooKassa is unavailable');
    }

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new ServiceUnavailableException('YooKassa request failed');
    }
    return data as YooKassaPayment;
  }

  private normalizeAmount(amountRub: number) {
    if (!Number.isInteger(amountRub)) {
      throw new BadRequestException('Сумма должна быть целым числом рублей');
    }
    if (env.YOOKASSA_MAX_AMOUNT_RUB < env.YOOKASSA_MIN_AMOUNT_RUB) {
      throw new ServiceUnavailableException('Payment configuration is invalid');
    }
    if (
      amountRub < env.YOOKASSA_MIN_AMOUNT_RUB ||
      amountRub > env.YOOKASSA_MAX_AMOUNT_RUB
    ) {
      throw new BadRequestException(
        `Сумма должна быть от ${env.YOOKASSA_MIN_AMOUNT_RUB} до ${env.YOOKASSA_MAX_AMOUNT_RUB} ₽`,
      );
    }
    return amountRub;
  }

  private assertYookassaConfigured() {
    if (!env.YOOKASSA_SHOP_ID.trim() || !env.YOOKASSA_SECRET_KEY.trim()) {
      throw new ServiceUnavailableException(
        'Оплата временно недоступна. Попробуйте позже.',
      );
    }
  }

  private buildAuthorizationHeader() {
    const token = Buffer.from(
      `${env.YOOKASSA_SHOP_ID.trim()}:${env.YOOKASSA_SECRET_KEY.trim()}`,
      'utf8',
    ).toString('base64');
    return `Basic ${token}`;
  }

  private lockPaymentRow(tx: Prisma.TransactionClient, paymentId: string) {
    return tx.$queryRaw`
      SELECT id
      FROM "payments"
      WHERE "id" = ${paymentId}::uuid
      FOR UPDATE
    `;
  }

  private getPayloadEvent(payload: unknown) {
    if (!payload || typeof payload !== 'object') return '';
    const event = (payload as Record<string, unknown>).event;
    return typeof event === 'string' ? event : '';
  }

  private getPayloadPaymentId(payload: unknown) {
    if (!payload || typeof payload !== 'object') return '';
    const object = (payload as Record<string, unknown>).object;
    if (!object || typeof object !== 'object') return '';
    const id = (object as Record<string, unknown>).id;
    return typeof id === 'string' ? id.trim() : '';
  }

  private getRequiredString(value: unknown, message: string) {
    if (typeof value !== 'string' || !value.trim()) {
      throw new BadRequestException(message);
    }
    return value.trim();
  }

  private formatRubAmount(amountRub: number) {
    return amountRub.toFixed(2);
  }

  private statusToResponse(status: PaymentStatus) {
    switch (status) {
      case PaymentStatus.SUCCEEDED:
        return 'succeeded';
      case PaymentStatus.CANCELED:
        return 'canceled';
      case PaymentStatus.PENDING:
      default:
        return 'pending';
    }
  }

  private safeErrorMessage(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }
}
