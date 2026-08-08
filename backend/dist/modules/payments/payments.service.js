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
var PaymentsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.PaymentsService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const crypto_1 = require("crypto");
const env_1 = require("../../config/env");
const prisma_service_1 = require("../prisma/prisma.service");
const wallet_service_1 = require("../wallet/wallet.service");
const YOOKASSA_API_BASE_URL = 'https://api.yookassa.ru/v3';
const YOOKASSA_CURRENCY = 'RUB';
let PaymentsService = PaymentsService_1 = class PaymentsService {
    constructor(prisma, walletService) {
        this.prisma = prisma;
        this.walletService = walletService;
        this.logger = new common_1.Logger(PaymentsService_1.name);
    }
    async createYookassaPayment(authUser, amountRub) {
        this.assertYookassaConfigured();
        const normalizedAmountRub = this.normalizeAmount(amountRub);
        const pointsAmount = normalizedAmountRub * env_1.env.YOOKASSA_POINTS_PER_RUBLE;
        const idempotencyKey = (0, crypto_1.randomUUID)();
        const payment = await this.prisma.payment.create({
            data: {
                userId: authUser.userId,
                provider: client_1.PaymentProvider.YOOKASSA,
                idempotencyKey,
                amountRub: new client_1.Prisma.Decimal(normalizedAmountRub),
                pointsAmount,
                currency: YOOKASSA_CURRENCY,
                status: client_1.PaymentStatus.PENDING,
                metadata: {
                    source: 'wallet_top_up',
                },
            },
        });
        try {
            const yookassaPayment = await this.requestYooKassaPayment('POST', '/payments', idempotencyKey, {
                amount: {
                    value: this.formatRubAmount(normalizedAmountRub),
                    currency: YOOKASSA_CURRENCY,
                },
                capture: true,
                confirmation: {
                    type: 'redirect',
                    return_url: env_1.env.YOOKASSA_RETURN_URL,
                },
                description: `Пополнение кошелька ATTA на ${pointsAmount} баллов`,
                metadata: {
                    paymentId: payment.id,
                    userId: authUser.userId,
                },
            });
            const providerPaymentId = this.getRequiredString(yookassaPayment.id, 'YooKassa payment id is missing');
            const confirmationUrl = this.getRequiredString(yookassaPayment.confirmation?.confirmation_url, 'YooKassa confirmation url is missing');
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
        }
        catch (error) {
            await this.prisma.payment.update({
                where: {
                    id: payment.id,
                },
                data: {
                    status: client_1.PaymentStatus.CANCELED,
                    metadata: {
                        source: 'wallet_top_up',
                        failure: this.safeErrorMessage(error),
                    },
                },
            });
            this.logger.warn(`YooKassa payment create failed: ${this.safeErrorMessage(error)}`);
            throw new common_1.ServiceUnavailableException('Не удалось начать оплату. Попробуйте позже.');
        }
    }
    async getPaymentStatus(authUser, paymentId) {
        let payment = await this.prisma.payment.findFirst({
            where: {
                id: paymentId,
                userId: authUser.userId,
            },
        });
        if (!payment) {
            throw new common_1.NotFoundException('Payment not found');
        }
        if (payment.status === client_1.PaymentStatus.PENDING &&
            payment.providerPaymentId) {
            const actualPayment = await this.fetchYooKassaPayment(payment.providerPaymentId);
            const verified = await this.verifyActualPayment(payment.providerPaymentId, actualPayment);
            this.assertLocalPaymentMatchesVerified(payment, verified, 'Payment amount mismatch');
            const actualStatus = typeof actualPayment.status === 'string' ? actualPayment.status : '';
            if (actualStatus === 'succeeded') {
                await this.processSucceededYookassaPayment(payment.providerPaymentId, actualPayment);
            }
            else if (actualStatus === 'canceled') {
                await this.processCanceledYookassaPayment(payment.providerPaymentId, actualPayment);
            }
            payment = await this.prisma.payment.findFirst({
                where: {
                    id: paymentId,
                    userId: authUser.userId,
                },
            });
            if (!payment) {
                throw new common_1.NotFoundException('Payment not found');
            }
        }
        const wallet = payment.status === client_1.PaymentStatus.SUCCEEDED
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
    async handleYookassaWebhook(payload) {
        const event = this.getPayloadEvent(payload);
        if (event !== 'payment.succeeded' && event !== 'payment.canceled') {
            return { ok: true };
        }
        const providerPaymentId = this.getPayloadPaymentId(payload);
        if (!providerPaymentId) {
            throw new common_1.BadRequestException('Payment id is missing');
        }
        const actualPayment = await this.fetchYooKassaPayment(providerPaymentId);
        if (event === 'payment.succeeded') {
            await this.processSucceededYookassaPayment(providerPaymentId, actualPayment);
        }
        else {
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
    async processSucceededYookassaPayment(providerPaymentId, actualPayment) {
        if (actualPayment.status !== 'succeeded') {
            throw new common_1.BadRequestException('Payment is not succeeded');
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
                throw new common_1.BadRequestException('Payment metadata mismatch');
            }
            if (payment.userId !== verified.userId) {
                throw new common_1.BadRequestException('Payment user mismatch');
            }
            if (payment.status === client_1.PaymentStatus.SUCCEEDED &&
                payment.creditedAt != null) {
                return;
            }
            if (!this.localPaymentMatchesVerified(payment, verified)) {
                throw new common_1.BadRequestException('Payment amount mismatch');
            }
            await this.walletService.accruePurchasedPointsIfNeeded(payment.userId, {
                amount: payment.pointsAmount,
                paymentId: payment.id,
                providerPaymentId,
            }, tx);
            await tx.payment.update({
                where: {
                    id: payment.id,
                },
                data: {
                    status: client_1.PaymentStatus.SUCCEEDED,
                    creditedAt: new Date(),
                    metadata: {
                        source: 'wallet_top_up',
                        providerPaymentId,
                    },
                },
            });
        });
    }
    async processCanceledYookassaPayment(providerPaymentId, actualPayment) {
        if (actualPayment.status !== 'canceled') {
            return;
        }
        const verified = await this.verifyActualPayment(providerPaymentId, actualPayment);
        const payment = await this.prisma.payment.findUnique({
            where: {
                providerPaymentId,
            },
        });
        if (!payment || payment.status === client_1.PaymentStatus.SUCCEEDED) {
            return;
        }
        if (!this.localPaymentMatchesVerified(payment, verified)) {
            throw new common_1.BadRequestException('Payment metadata mismatch');
        }
        await this.prisma.payment.update({
            where: {
                id: payment.id,
            },
            data: {
                status: client_1.PaymentStatus.CANCELED,
            },
        });
    }
    async verifyActualPayment(providerPaymentId, actualPayment) {
        const metadata = actualPayment.metadata ?? {};
        const paymentId = this.getRequiredString(metadata.paymentId, 'Payment metadata is missing');
        const userId = this.getRequiredString(metadata.userId, 'Payment metadata is missing');
        if (actualPayment.id !== providerPaymentId) {
            throw new common_1.BadRequestException('Payment id mismatch');
        }
        const amountValue = this.getRequiredString(actualPayment.amount?.value, 'Payment amount is missing');
        const currency = this.getRequiredString(actualPayment.amount?.currency, 'Payment currency is missing');
        if (currency !== YOOKASSA_CURRENCY) {
            throw new common_1.BadRequestException('Payment currency mismatch');
        }
        const amountRub = Number(amountValue);
        if (!Number.isFinite(amountRub) || amountRub <= 0) {
            throw new common_1.BadRequestException('Payment amount is invalid');
        }
        return {
            paymentId,
            userId,
            amountValue: this.formatRubAmount(amountRub),
            pointsAmount: Math.round(amountRub * env_1.env.YOOKASSA_POINTS_PER_RUBLE),
        };
    }
    assertLocalPaymentMatchesVerified(payment, verified, message = 'Payment metadata mismatch') {
        if (!this.localPaymentMatchesVerified(payment, verified)) {
            throw new common_1.BadRequestException(message);
        }
    }
    localPaymentMatchesVerified(payment, verified) {
        return (payment.id === verified.paymentId &&
            payment.userId === verified.userId &&
            payment.currency === YOOKASSA_CURRENCY &&
            payment.amountRub.toFixed(2) === verified.amountValue &&
            payment.pointsAmount === verified.pointsAmount);
    }
    async fetchYooKassaPayment(providerPaymentId) {
        this.assertYookassaConfigured();
        return this.requestYooKassaPayment('GET', `/payments/${providerPaymentId}`);
    }
    async requestYooKassaPayment(method, path, idempotencyKey, body) {
        const headers = {
            Accept: 'application/json',
            Authorization: this.buildAuthorizationHeader(),
        };
        if (idempotencyKey) {
            headers['Idempotence-Key'] = idempotencyKey;
        }
        if (body != null) {
            headers['Content-Type'] = 'application/json';
        }
        let response;
        try {
            response = await fetch(`${YOOKASSA_API_BASE_URL}${path}`, {
                method,
                headers,
                body: body == null ? undefined : JSON.stringify(body),
            });
        }
        catch {
            throw new common_1.ServiceUnavailableException('YooKassa is unavailable');
        }
        const data = await response.json().catch(() => ({}));
        if (!response.ok) {
            throw new common_1.ServiceUnavailableException('YooKassa request failed');
        }
        return data;
    }
    normalizeAmount(amountRub) {
        if (!Number.isInteger(amountRub)) {
            throw new common_1.BadRequestException('Сумма должна быть целым числом рублей');
        }
        if (env_1.env.YOOKASSA_MAX_AMOUNT_RUB < env_1.env.YOOKASSA_MIN_AMOUNT_RUB) {
            throw new common_1.ServiceUnavailableException('Payment configuration is invalid');
        }
        if (amountRub < env_1.env.YOOKASSA_MIN_AMOUNT_RUB ||
            amountRub > env_1.env.YOOKASSA_MAX_AMOUNT_RUB) {
            throw new common_1.BadRequestException(`Сумма должна быть от ${env_1.env.YOOKASSA_MIN_AMOUNT_RUB} до ${env_1.env.YOOKASSA_MAX_AMOUNT_RUB} ₽`);
        }
        return amountRub;
    }
    assertYookassaConfigured() {
        if (!env_1.env.YOOKASSA_SHOP_ID.trim() || !env_1.env.YOOKASSA_SECRET_KEY.trim()) {
            throw new common_1.ServiceUnavailableException('Оплата временно недоступна. Попробуйте позже.');
        }
    }
    buildAuthorizationHeader() {
        const token = Buffer.from(`${env_1.env.YOOKASSA_SHOP_ID.trim()}:${env_1.env.YOOKASSA_SECRET_KEY.trim()}`, 'utf8').toString('base64');
        return `Basic ${token}`;
    }
    lockPaymentRow(tx, paymentId) {
        return tx.$queryRaw `
      SELECT id
      FROM "payments"
      WHERE "id" = ${paymentId}::uuid
      FOR UPDATE
    `;
    }
    getPayloadEvent(payload) {
        if (!payload || typeof payload !== 'object')
            return '';
        const event = payload.event;
        return typeof event === 'string' ? event : '';
    }
    getPayloadPaymentId(payload) {
        if (!payload || typeof payload !== 'object')
            return '';
        const object = payload.object;
        if (!object || typeof object !== 'object')
            return '';
        const id = object.id;
        return typeof id === 'string' ? id.trim() : '';
    }
    getRequiredString(value, message) {
        if (typeof value !== 'string' || !value.trim()) {
            throw new common_1.BadRequestException(message);
        }
        return value.trim();
    }
    formatRubAmount(amountRub) {
        return amountRub.toFixed(2);
    }
    statusToResponse(status) {
        switch (status) {
            case client_1.PaymentStatus.SUCCEEDED:
                return 'succeeded';
            case client_1.PaymentStatus.CANCELED:
                return 'canceled';
            case client_1.PaymentStatus.PENDING:
            default:
                return 'pending';
        }
    }
    safeErrorMessage(error) {
        return error instanceof Error ? error.message : String(error);
    }
};
exports.PaymentsService = PaymentsService;
exports.PaymentsService = PaymentsService = PaymentsService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        wallet_service_1.WalletService])
], PaymentsService);
//# sourceMappingURL=payments.service.js.map