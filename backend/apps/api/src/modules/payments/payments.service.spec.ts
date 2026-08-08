import { test } from 'node:test';
import assert from 'node:assert/strict';

import { PaymentStatus } from '@prisma/client';

import { env } from '../../config/env';
import { PaymentsService } from './payments.service';

const originalFetch = global.fetch;
const originalConfig = {
  shopId: env.YOOKASSA_SHOP_ID,
  secretKey: env.YOOKASSA_SECRET_KEY,
  minAmountRub: env.YOOKASSA_MIN_AMOUNT_RUB,
  maxAmountRub: env.YOOKASSA_MAX_AMOUNT_RUB,
  pointsPerRuble: env.YOOKASSA_POINTS_PER_RUBLE,
};

function restoreGlobals() {
  global.fetch = originalFetch;
  (env as { YOOKASSA_SHOP_ID: string }).YOOKASSA_SHOP_ID =
    originalConfig.shopId;
  (env as { YOOKASSA_SECRET_KEY: string }).YOOKASSA_SECRET_KEY =
    originalConfig.secretKey;
  (env as { YOOKASSA_MIN_AMOUNT_RUB: number }).YOOKASSA_MIN_AMOUNT_RUB =
    originalConfig.minAmountRub;
  (env as { YOOKASSA_MAX_AMOUNT_RUB: number }).YOOKASSA_MAX_AMOUNT_RUB =
    originalConfig.maxAmountRub;
  (env as { YOOKASSA_POINTS_PER_RUBLE: number }).YOOKASSA_POINTS_PER_RUBLE =
    originalConfig.pointsPerRuble;
}

test.afterEach(restoreGlobals);

test('createYookassaPayment creates local payment and returns only safe fields', async () => {
  (env as { YOOKASSA_SHOP_ID: string }).YOOKASSA_SHOP_ID = '1425242';
  (env as { YOOKASSA_SECRET_KEY: string }).YOOKASSA_SECRET_KEY = 'secret';
  (env as { YOOKASSA_MIN_AMOUNT_RUB: number }).YOOKASSA_MIN_AMOUNT_RUB = 100;
  (env as { YOOKASSA_MAX_AMOUNT_RUB: number }).YOOKASSA_MAX_AMOUNT_RUB = 1500;
  (env as { YOOKASSA_POINTS_PER_RUBLE: number }).YOOKASSA_POINTS_PER_RUBLE = 1;

  let createdPayment: Record<string, unknown> | undefined;
  let updateData: Record<string, unknown> | undefined;
  let sentBody: Record<string, any> | undefined;
  let sentAuthHeader = '';

  global.fetch = (async (_url: string | URL | Request, init?: RequestInit) => {
    sentAuthHeader = String(init?.headers?.['Authorization' as keyof HeadersInit] ?? '');
    sentBody = JSON.parse(String(init?.body));
    return {
      ok: true,
      json: async () => ({
        id: 'yk-payment-1',
        confirmation: {
          confirmation_url: 'https://yookassa.ru/checkout/payments/v2/contract',
        },
      }),
    } as Response;
  }) as typeof fetch;

  const service = new PaymentsService(
    {
      payment: {
        create: async (args: Record<string, any>) => {
          createdPayment = args.data;
          return {
            id: 'local-payment-1',
            userId: args.data.userId,
          };
        },
        update: async (args: Record<string, any>) => {
          updateData = args.data;
          return args.data;
        },
      },
    } as any,
    {} as any,
  );

  const result = await service.createYookassaPayment(
    { userId: 'user-1' } as any,
    300,
  );

  assert.deepEqual(result, {
    paymentId: 'local-payment-1',
    confirmationUrl: 'https://yookassa.ru/checkout/payments/v2/contract',
  });
  assert.equal(createdPayment?.['pointsAmount'], 300);
  assert.equal(updateData?.['providerPaymentId'], 'yk-payment-1');
  assert.equal(sentBody?.['capture'], true);
  assert.equal(sentBody?.['amount']?.['value'], '300.00');
  assert.deepEqual(sentBody?.['metadata'], {
    paymentId: 'local-payment-1',
    userId: 'user-1',
  });
  assert.equal(Object.keys(result).includes('secretKey'), false);
  assert.equal(sentAuthHeader.startsWith('Basic '), true);
});

test('createYookassaPayment rejects amount outside configured limits', async () => {
  (env as { YOOKASSA_SECRET_KEY: string }).YOOKASSA_SECRET_KEY = 'secret';
  (env as { YOOKASSA_MIN_AMOUNT_RUB: number }).YOOKASSA_MIN_AMOUNT_RUB = 100;
  (env as { YOOKASSA_MAX_AMOUNT_RUB: number }).YOOKASSA_MAX_AMOUNT_RUB = 1500;

  const service = new PaymentsService({} as any, {} as any);

  await assert.rejects(
    () => service.createYookassaPayment({ userId: 'user-1' } as any, 99),
    /Сумма должна быть от 100 до 1500/,
  );
});

test('repeated succeeded webhook does not accrue points again', async () => {
  (env as { YOOKASSA_SHOP_ID: string }).YOOKASSA_SHOP_ID = '1425242';
  (env as { YOOKASSA_SECRET_KEY: string }).YOOKASSA_SECRET_KEY = 'secret';

  global.fetch = (async () =>
    ({
      ok: true,
      json: async () => ({
        id: 'yk-payment-1',
        status: 'succeeded',
        amount: {
          value: '100.00',
          currency: 'RUB',
        },
        metadata: {
          paymentId: 'local-payment-1',
          userId: 'user-1',
        },
      }),
    }) as Response) as typeof fetch;

  let accrueCalls = 0;
  const service = new PaymentsService(
    {
      $transaction: async (handler: (tx: unknown) => Promise<void>) =>
        handler({
          $queryRaw: async () => [],
          payment: {
            findUnique: async () => ({
              id: 'local-payment-1',
              userId: 'user-1',
              providerPaymentId: 'yk-payment-1',
              status: PaymentStatus.SUCCEEDED,
              creditedAt: new Date(),
              amountRub: { toFixed: () => '100.00' },
              pointsAmount: 100,
              currency: 'RUB',
            }),
            update: async () => {
              throw new Error('payment should not be updated');
            },
          },
        }),
    } as any,
    {
      accruePurchasedPointsIfNeeded: async () => {
        accrueCalls += 1;
      },
    } as any,
  );

  await service.handleYookassaWebhook({
    event: 'payment.succeeded',
    object: {
      id: 'yk-payment-1',
    },
  });

  assert.equal(accrueCalls, 0);
});

test('status endpoint syncs succeeded YooKassa payment and accrues once', async () => {
  (env as { YOOKASSA_SHOP_ID: string }).YOOKASSA_SHOP_ID = '1425242';
  (env as { YOOKASSA_SECRET_KEY: string }).YOOKASSA_SECRET_KEY = 'secret';

  global.fetch = yookassaFetch({
    id: 'yk-payment-1',
    status: 'succeeded',
    amount: {
      value: '100.00',
      currency: 'RUB',
    },
    metadata: {
      paymentId: 'local-payment-1',
      userId: 'user-1',
    },
  });

  const payment = paymentFixture();
  let accrueCalls = 0;
  const service = new PaymentsService(
    {
      payment: {
        findFirst: async () => payment,
      },
      $transaction: async (handler: (tx: unknown) => Promise<void>) =>
        handler({
          $queryRaw: async () => [],
          payment: {
            findUnique: async () => payment,
            update: async (args: Record<string, any>) => {
              Object.assign(payment, args.data);
              return payment;
            },
          },
        }),
    } as any,
    {
      accruePurchasedPointsIfNeeded: async () => {
        accrueCalls += 1;
      },
      ensureWalletForUser: async () => ({
        bonusBalance: 325,
      }),
    } as any,
  );

  const result = await service.getPaymentStatus(
    { userId: 'user-1' } as any,
    'local-payment-1',
  );

  assert.equal(result.status, 'succeeded');
  assert.equal(result.credited, true);
  assert.equal(result.balance, 325);
  assert.equal(accrueCalls, 1);
});

test('concurrent webhook and status sync accrue purchased points once', async () => {
  (env as { YOOKASSA_SHOP_ID: string }).YOOKASSA_SHOP_ID = '1425242';
  (env as { YOOKASSA_SECRET_KEY: string }).YOOKASSA_SECRET_KEY = 'secret';

  global.fetch = yookassaFetch({
    id: 'yk-payment-1',
    status: 'succeeded',
    amount: {
      value: '100.00',
      currency: 'RUB',
    },
    metadata: {
      paymentId: 'local-payment-1',
      userId: 'user-1',
    },
  });

  const payment = paymentFixture();
  let accrueCalls = 0;
  let transactionQueue = Promise.resolve();
  const service = new PaymentsService(
    {
      payment: {
        findFirst: async () => payment,
      },
      $transaction: async (handler: (tx: unknown) => Promise<void>) => {
        const run = transactionQueue.then(() =>
          handler({
            $queryRaw: async () => [],
            payment: {
              findUnique: async () => payment,
              update: async (args: Record<string, any>) => {
                Object.assign(payment, args.data);
                return payment;
              },
            },
          }),
        );
        transactionQueue = run.catch(() => undefined);
        return run;
      },
    } as any,
    {
      accruePurchasedPointsIfNeeded: async () => {
        accrueCalls += 1;
      },
      ensureWalletForUser: async () => ({
        bonusBalance: 325,
      }),
    } as any,
  );

  await Promise.all([
    service.handleYookassaWebhook({
      event: 'payment.succeeded',
      object: {
        id: 'yk-payment-1',
      },
    }),
    service.getPaymentStatus({ userId: 'user-1' } as any, 'local-payment-1'),
  ]);

  assert.equal(payment.status, PaymentStatus.SUCCEEDED);
  assert.equal(payment.creditedAt != null, true);
  assert.equal(accrueCalls, 1);
});

test('status endpoint keeps pending payment pending without accrual', async () => {
  (env as { YOOKASSA_SHOP_ID: string }).YOOKASSA_SHOP_ID = '1425242';
  (env as { YOOKASSA_SECRET_KEY: string }).YOOKASSA_SECRET_KEY = 'secret';

  global.fetch = yookassaFetch({
    id: 'yk-payment-1',
    status: 'pending',
    amount: {
      value: '100.00',
      currency: 'RUB',
    },
    metadata: {
      paymentId: 'local-payment-1',
      userId: 'user-1',
    },
  });

  let accrueCalls = 0;
  const payment = paymentFixture();
  const service = new PaymentsService(
    {
      payment: {
        findFirst: async () => payment,
      },
    } as any,
    {
      accruePurchasedPointsIfNeeded: async () => {
        accrueCalls += 1;
      },
    } as any,
  );

  const result = await service.getPaymentStatus(
    { userId: 'user-1' } as any,
    'local-payment-1',
  );

  assert.equal(result.status, 'pending');
  assert.equal(accrueCalls, 0);
});

test('status endpoint syncs canceled payment without accrual', async () => {
  (env as { YOOKASSA_SHOP_ID: string }).YOOKASSA_SHOP_ID = '1425242';
  (env as { YOOKASSA_SECRET_KEY: string }).YOOKASSA_SECRET_KEY = 'secret';

  global.fetch = yookassaFetch({
    id: 'yk-payment-1',
    status: 'canceled',
    amount: {
      value: '100.00',
      currency: 'RUB',
    },
    metadata: {
      paymentId: 'local-payment-1',
      userId: 'user-1',
    },
  });

  const payment = paymentFixture();
  let accrueCalls = 0;
  const service = new PaymentsService(
    {
      payment: {
        findFirst: async () => payment,
        findUnique: async () => payment,
        update: async (args: Record<string, any>) => {
          Object.assign(payment, args.data);
          return payment;
        },
      },
    } as any,
    {
      accruePurchasedPointsIfNeeded: async () => {
        accrueCalls += 1;
      },
    } as any,
  );

  const result = await service.getPaymentStatus(
    { userId: 'user-1' } as any,
    'local-payment-1',
  );

  assert.equal(result.status, 'canceled');
  assert.equal(accrueCalls, 0);
});

test('status endpoint rejects succeeded payment with amount mismatch', async () => {
  (env as { YOOKASSA_SHOP_ID: string }).YOOKASSA_SHOP_ID = '1425242';
  (env as { YOOKASSA_SECRET_KEY: string }).YOOKASSA_SECRET_KEY = 'secret';

  global.fetch = yookassaFetch({
    id: 'yk-payment-1',
    status: 'succeeded',
    amount: {
      value: '90.00',
      currency: 'RUB',
    },
    metadata: {
      paymentId: 'local-payment-1',
      userId: 'user-1',
    },
  });

  const service = new PaymentsService(
    {
      payment: {
        findFirst: async () => paymentFixture(),
      },
      $transaction: async (handler: (tx: unknown) => Promise<void>) =>
        handler({
          $queryRaw: async () => [],
          payment: {
            findUnique: async () => paymentFixture(),
          },
        }),
    } as any,
    {
      accruePurchasedPointsIfNeeded: async () => {
        throw new Error('payment should not be accrued');
      },
    } as any,
  );

  await assert.rejects(
    () => service.getPaymentStatus({ userId: 'user-1' } as any, 'local-payment-1'),
    /Payment amount mismatch/,
  );
});

function paymentFixture() {
  return {
    id: 'local-payment-1',
    userId: 'user-1',
    providerPaymentId: 'yk-payment-1',
    status: PaymentStatus.PENDING,
    creditedAt: null,
    amountRub: { toFixed: () => '100.00' },
    pointsAmount: 100,
    currency: 'RUB',
  };
}

function yookassaFetch(payment: Record<string, unknown>) {
  return (async () =>
    ({
      ok: true,
      json: async () => payment,
    }) as Response) as typeof fetch;
}
