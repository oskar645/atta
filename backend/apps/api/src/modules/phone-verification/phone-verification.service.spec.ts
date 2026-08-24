import { afterEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { HttpException } from '@nestjs/common';

import { env } from '../../config/env';
import { PhoneVerificationService } from './phone-verification.service';

type FetchResponseShape = {
  ok: boolean;
  status: number;
  body: Record<string, unknown> | string;
};

function createService(findUniqueResult: { id: string } | null) {
  return new PhoneVerificationService({
    user: {
      findUnique: async () => findUniqueResult,
    },
    phoneVerification: {
      count: async () => 0,
      create: async () => undefined,
    },
  } as never, {
    countUniqueValues: async () => 1,
  } as never);
}

function createStartService(params?: {
  phoneAttemptCount?: number;
  uniqueCounter?: {
    countUniqueValues: (
      key: string,
      value: string,
      windowMs: number,
    ) => Promise<number | null>;
  };
}) {
  return new PhoneVerificationService({
    user: {
      findUnique: async () => null,
    },
    phoneVerification: {
      count: async () => params?.phoneAttemptCount ?? 0,
      create: async () => undefined,
    },
  } as never, (params?.uniqueCounter ?? {
    countUniqueValues: async () => 1,
  }) as never);
}

function createUniqueCounter() {
  const valuesByKey = new Map<string, Set<string>>();
  return {
    async countUniqueValues(key: string, value: string) {
      const values = valuesByKey.get(key) ?? new Set<string>();
      values.add(value);
      valuesByKey.set(key, values);
      return values.size;
    },
  };
}

function enableFakeProvider() {
  (env as { PHONE_VERIFICATION_DEV_MODE: boolean }).PHONE_VERIFICATION_DEV_MODE =
    true;
  (env as { NODE_ENV: 'development' | 'test' | 'production' }).NODE_ENV =
    'test';
  (env as { APP_ENV: string }).APP_ENV = 'local';
}

function setFetchResponse(shape: FetchResponseShape) {
  globalThis.fetch = (async (input: URL | RequestInfo | string) => {
    const url = input instanceof URL ? input : new URL(input.toString());
    return {
      ok: shape.ok,
      status: shape.status,
      text: async () =>
        typeof shape.body === 'string'
          ? shape.body
          : JSON.stringify(shape.body),
      url: url.toString(),
    } as Response;
  }) as typeof fetch;
}

const originalFetch = globalThis.fetch;
const originalSmsEnabled = env.SMS_RU_CALLCHECK_ENABLED;
const originalSmsApiId = env.SMS_RU_API_ID;
const originalDevMode = env.PHONE_VERIFICATION_DEV_MODE;
const originalNodeEnv = env.NODE_ENV;
const originalAppEnv = env.APP_ENV;

afterEach(() => {
  globalThis.fetch = originalFetch;
  (env as { SMS_RU_CALLCHECK_ENABLED: boolean }).SMS_RU_CALLCHECK_ENABLED =
    originalSmsEnabled;
  (env as { SMS_RU_API_ID: string }).SMS_RU_API_ID = originalSmsApiId;
  (env as { PHONE_VERIFICATION_DEV_MODE: boolean }).PHONE_VERIFICATION_DEV_MODE =
    originalDevMode;
  (env as { NODE_ENV: 'development' | 'test' | 'production' }).NODE_ENV =
    originalNodeEnv;
  (env as { APP_ENV: string }).APP_ENV = originalAppEnv;
});

test('checkRegistration returns exists=true for existing phone', async () => {
  const service = createService({ id: 'user-1' });

  const response = await service.checkRegistration('+7 (928) 123-45-67');

  assert.equal(response.exists, true);
  assert.equal(response.phone, '79281234567');
});

test('checkRegistration returns exists=false for unknown phone', async () => {
  const service = createService(null);

  const response = await service.checkRegistration('+7 (928) 123-45-67');

  assert.equal(response.exists, false);
  assert.equal(response.phone, '79281234567');
});

test('phone/start success returns callToPhone and checkId', async () => {
  (env as { SMS_RU_CALLCHECK_ENABLED: boolean }).SMS_RU_CALLCHECK_ENABLED = true;
  (env as { SMS_RU_API_ID: string }).SMS_RU_API_ID = 'present';
  (env as { PHONE_VERIFICATION_DEV_MODE: boolean }).PHONE_VERIFICATION_DEV_MODE =
    false;
  setFetchResponse({
    ok: true,
    status: 200,
    body: {
      status: 'OK',
      status_code: 100,
      check_id: 'check-1',
      call_phone: '78005008275',
      call_phone_pretty: '+7 (800) 500-82-75',
    },
  });
  const service = createService(null);

  const response = await service.startCallVerification(
    '8 (928) 123-45-67',
    'signup',
  );

  assert.equal(response.checkId, 'check-1');
  assert.equal(response.verificationCheckId, 'check-1');
  assert.equal(response.callToPhone, '78005008275');
  assert.equal(response.callPhone, '78005008275');
  assert.equal(response.phoneToCall, '78005008275');
  assert.equal(response.callToPhonePretty, '+7 (800) 500-82-75');
  assert.match(response.expiresAt, /\d{4}-\d{2}-\d{2}T/);
});

test('phone/start missing SMS_RU_API_ID returns safe error', async () => {
  (env as { SMS_RU_CALLCHECK_ENABLED: boolean }).SMS_RU_CALLCHECK_ENABLED = true;
  (env as { SMS_RU_API_ID: string }).SMS_RU_API_ID = '';
  const service = createService(null);

  await assert.rejects(
    service.startCallVerification('79281234567', 'signup'),
    (error: unknown) => {
      assert.ok(error instanceof HttpException);
      assert.equal(error.getStatus(), 503);
      assert.deepEqual(error.getResponse(), {
        message: 'Подтверждение телефона временно недоступно',
        code: 'SMS_RU_API_ID_MISSING',
        details: 'SMS.ru API key missing',
      });
      return true;
    },
  );
});

test('phone/start disabled callcheck returns safe disabled error', async () => {
  (env as { SMS_RU_CALLCHECK_ENABLED: boolean }).SMS_RU_CALLCHECK_ENABLED = false;
  (env as { SMS_RU_API_ID: string }).SMS_RU_API_ID = 'present';
  const service = createService(null);

  await assert.rejects(
    service.startCallVerification('79281234567', 'signup'),
    (error: unknown) => {
      assert.ok(error instanceof HttpException);
      assert.equal(error.getStatus(), 503);
      assert.deepEqual(error.getResponse(), {
        message: 'Подтверждение телефона временно недоступно',
        code: 'SMS_RU_CALLCHECK_DISABLED',
        details: 'SMS.ru callcheck disabled',
      });
      return true;
    },
  );
});

test('phone/start SMS.ru error returns code SMS_RU_CALLCHECK_FAILED', async () => {
  (env as { SMS_RU_CALLCHECK_ENABLED: boolean }).SMS_RU_CALLCHECK_ENABLED = true;
  (env as { SMS_RU_API_ID: string }).SMS_RU_API_ID = 'present';
  setFetchResponse({
    ok: true,
    status: 200,
    body: {
      status: 'ERROR',
      status_code: '209',
      status_text: 'rate limit exceeded',
    },
  });
  const service = createService(null);

  await assert.rejects(
    service.startCallVerification('79281234567', 'signup'),
    (error: unknown) => {
      assert.ok(error instanceof HttpException);
      assert.equal(error.getStatus(), 503);
      assert.deepEqual(error.getResponse(), {
        message: 'Подтверждение телефона временно недоступно',
        code: 'SMS_RU_CALLCHECK_FAILED',
        details:
          'status_code=209; status=ERROR; status_text=rate limit exceeded',
      });
      return true;
    },
  );
});

test('phone/start missing call_phone returns safe error', async () => {
  (env as { SMS_RU_CALLCHECK_ENABLED: boolean }).SMS_RU_CALLCHECK_ENABLED = true;
  (env as { SMS_RU_API_ID: string }).SMS_RU_API_ID = 'present';
  setFetchResponse({
    ok: true,
    status: 200,
    body: {
      status: 'OK',
      status_code: 100,
      check_id: 'check-1',
    },
  });
  const service = createService(null);

  await assert.rejects(
    service.startCallVerification('79281234567', 'signup'),
    (error: unknown) => {
      assert.ok(error instanceof HttpException);
      assert.equal(error.getStatus(), 503);
      assert.deepEqual(error.getResponse(), {
        message: 'Подтверждение телефона временно недоступно',
        code: 'SMS_RU_CALL_PHONE_MISSING',
        details: 'Отсутствует номер для подтверждающего звонка',
      });
      return true;
    },
  );
});

test('phone normalization works for phone/start', async () => {
  (env as { SMS_RU_CALLCHECK_ENABLED: boolean }).SMS_RU_CALLCHECK_ENABLED = true;
  (env as { SMS_RU_API_ID: string }).SMS_RU_API_ID = 'present';
  let requestedPhone = '';
  globalThis.fetch = (async (input: URL | RequestInfo | string) => {
    const url = input instanceof URL ? input : new URL(input.toString());
    requestedPhone = url.searchParams.get('phone') ?? '';
    return {
      ok: true,
      status: 200,
      text: async () =>
        JSON.stringify({
          status: 'OK',
          status_code: 100,
          check_id: 'check-1',
          call_phone: '78005008275',
        }),
      url: url.toString(),
    } as Response;
  }) as typeof fetch;
  const service = createService(null);

  await service.startCallVerification('+7 928 123 45 67', 'signup');

  assert.equal(requestedPhone, '79281234567');
});

test('ordinary repeated phone/start attempts are not blocked before existing phone cooldown', async () => {
  enableFakeProvider();
  const service = createStartService({ phoneAttemptCount: 2 });

  const response = await service.startCallVerification(
    '79281234567',
    'signup',
    { ip: '203.0.113.10', userAgent: 'atta-app/1' },
  );

  assert.equal(response.status, 'ok');
});

test('several users sharing one IP do not break phone registration', async () => {
  enableFakeProvider();
  const uniqueCounter = createUniqueCounter();
  const service = createStartService({ uniqueCounter });

  for (let index = 0; index < 20; index += 1) {
    await service.startCallVerification(
      `79281234${String(index).padStart(3, '0')}`,
      'signup',
      {
        ip: '203.0.113.20',
        userAgent: `atta-app/${index}`,
      },
    );
  }

  assert.ok(true);
});

test('mass phone/start requests to many numbers from one source are limited', async () => {
  enableFakeProvider();
  const uniqueCounter = createUniqueCounter();
  const service = createStartService({ uniqueCounter });

  for (let index = 0; index < 50; index += 1) {
    await service.startCallVerification(
      `79285550${String(index).padStart(3, '0')}`,
      'signup',
      {
        ip: '203.0.113.30',
        userAgent: 'same-script/1',
      },
    );
  }

  await assert.rejects(
    () =>
      service.startCallVerification('79285550999', 'signup', {
        ip: '203.0.113.30',
        userAgent: 'same-script/1',
      }),
    (error: unknown) => {
      assert.ok(error instanceof HttpException);
      assert.equal(error.getStatus(), 429);
      return true;
    },
  );
});

test('production mode does not return fake checkId', async () => {
  (env as { SMS_RU_CALLCHECK_ENABLED: boolean }).SMS_RU_CALLCHECK_ENABLED = true;
  (env as { SMS_RU_API_ID: string }).SMS_RU_API_ID = 'present';
  (env as { PHONE_VERIFICATION_DEV_MODE: boolean }).PHONE_VERIFICATION_DEV_MODE =
    true;
  (env as { NODE_ENV: 'development' | 'test' | 'production' }).NODE_ENV =
    'production';
  setFetchResponse({
    ok: true,
    status: 200,
    body: {
      status: 'OK',
      status_code: 100,
      check_id: 'check-prod',
      call_phone: '78005008275',
    },
  });
  const service = createService(null);

  const response = await service.startCallVerification(
    '79281234567',
    'signup',
  );

  assert.equal(response.checkId, 'check-prod');
  assert.equal(response.checkId.startsWith('fake-'), false);
});

test('phone/check maps SMS.ru 401 to confirmed', async () => {
  (env as { SMS_RU_CALLCHECK_ENABLED: boolean }).SMS_RU_CALLCHECK_ENABLED = true;
  (env as { SMS_RU_API_ID: string }).SMS_RU_API_ID = 'present';
  setFetchResponse({
    ok: true,
    status: 200,
    body: {
      status: 'OK',
      status_code: 100,
      check_status: '401',
      check_status_text: 'Авторизация по звонку: номер подтвержден',
    },
  });

  const service = new PhoneVerificationService({
    user: {
      findUnique: async () => null,
    },
    phoneVerification: {
      count: async () => 0,
      create: async () => undefined,
      findFirst: async () => ({
        id: 'verification-1',
        phone: '79281234567',
        purpose: 'SIGNUP',
        checkId: 'check-1',
        status: 'PENDING',
        expiresAt: new Date(Date.now() + 60_000),
        attempts: 0,
        maxAttempts: 5,
      }),
      update: async () => undefined,
    },
  } as never, {
    countUniqueValues: async () => 1,
  } as never);

  const response = await service.checkCallVerification(
    '79281234567',
    'check-1',
    'signup',
  );

  assert.equal(response.status, 'confirmed');
});

test('phone/check maps SMS.ru 400 to pending', async () => {
  (env as { SMS_RU_CALLCHECK_ENABLED: boolean }).SMS_RU_CALLCHECK_ENABLED = true;
  (env as { SMS_RU_API_ID: string }).SMS_RU_API_ID = 'present';
  setFetchResponse({
    ok: true,
    status: 200,
    body: {
      status: 'OK',
      status_code: 100,
      check_status: '400',
      check_status_text: 'Авторизация по звонку: ожидание звонка',
    },
  });

  const service = new PhoneVerificationService({
    user: {
      findUnique: async () => null,
    },
    phoneVerification: {
      count: async () => 0,
      create: async () => undefined,
      findFirst: async () => ({
        id: 'verification-1',
        phone: '79281234567',
        purpose: 'SIGNUP',
        checkId: 'check-1',
        status: 'PENDING',
        expiresAt: new Date(Date.now() + 60_000),
        attempts: 0,
        maxAttempts: 5,
      }),
      update: async () => undefined,
    },
  } as never, {
    countUniqueValues: async () => 1,
  } as never);

  const response = await service.checkCallVerification(
    '79281234567',
    'check-1',
    'signup',
  );

  assert.equal(response.status, 'pending');
});

test('phone/check maps SMS.ru 402 to expired', async () => {
  (env as { SMS_RU_CALLCHECK_ENABLED: boolean }).SMS_RU_CALLCHECK_ENABLED = true;
  (env as { SMS_RU_API_ID: string }).SMS_RU_API_ID = 'present';
  setFetchResponse({
    ok: true,
    status: 200,
    body: {
      status: 'OK',
      status_code: 100,
      check_status: '402',
      check_status_text: 'Авторизация по звонку: время ожидания истекло',
    },
  });

  const service = new PhoneVerificationService({
    user: {
      findUnique: async () => null,
    },
    phoneVerification: {
      count: async () => 0,
      create: async () => undefined,
      findFirst: async () => ({
        id: 'verification-1',
        phone: '79281234567',
        purpose: 'SIGNUP',
        checkId: 'check-1',
        status: 'PENDING',
        expiresAt: new Date(Date.now() + 60_000),
        attempts: 0,
        maxAttempts: 5,
      }),
      update: async () => undefined,
    },
  } as never, {
    countUniqueValues: async () => 1,
  } as never);

  const response = await service.checkCallVerification(
    '79281234567',
    'check-1',
    'signup',
  );

  assert.equal(response.status, 'expired');
});
