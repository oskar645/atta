"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const strict_1 = __importDefault(require("node:assert/strict"));
const common_1 = require("@nestjs/common");
const env_1 = require("../../config/env");
const phone_verification_service_1 = require("./phone-verification.service");
function createService(findUniqueResult) {
    return new phone_verification_service_1.PhoneVerificationService({
        user: {
            findUnique: async () => findUniqueResult,
        },
        phoneVerification: {
            count: async () => 0,
            create: async () => undefined,
        },
    });
}
function setFetchResponse(shape) {
    globalThis.fetch = (async (input) => {
        const url = input instanceof URL ? input : new URL(input.toString());
        return {
            ok: shape.ok,
            status: shape.status,
            text: async () => typeof shape.body === 'string'
                ? shape.body
                : JSON.stringify(shape.body),
            url: url.toString(),
        };
    });
}
const originalFetch = globalThis.fetch;
const originalSmsEnabled = env_1.env.SMS_RU_CALLCHECK_ENABLED;
const originalSmsApiId = env_1.env.SMS_RU_API_ID;
const originalDevMode = env_1.env.PHONE_VERIFICATION_DEV_MODE;
const originalNodeEnv = env_1.env.NODE_ENV;
const originalAppEnv = env_1.env.APP_ENV;
(0, node_test_1.afterEach)(() => {
    globalThis.fetch = originalFetch;
    env_1.env.SMS_RU_CALLCHECK_ENABLED =
        originalSmsEnabled;
    env_1.env.SMS_RU_API_ID = originalSmsApiId;
    env_1.env.PHONE_VERIFICATION_DEV_MODE =
        originalDevMode;
    env_1.env.NODE_ENV =
        originalNodeEnv;
    env_1.env.APP_ENV = originalAppEnv;
});
(0, node_test_1.test)('checkRegistration returns exists=true for existing phone', async () => {
    const service = createService({ id: 'user-1' });
    const response = await service.checkRegistration('+7 (928) 123-45-67');
    strict_1.default.equal(response.exists, true);
    strict_1.default.equal(response.phone, '79281234567');
});
(0, node_test_1.test)('checkRegistration returns exists=false for unknown phone', async () => {
    const service = createService(null);
    const response = await service.checkRegistration('+7 (928) 123-45-67');
    strict_1.default.equal(response.exists, false);
    strict_1.default.equal(response.phone, '79281234567');
});
(0, node_test_1.test)('phone/start success returns callToPhone and checkId', async () => {
    env_1.env.SMS_RU_CALLCHECK_ENABLED = true;
    env_1.env.SMS_RU_API_ID = 'present';
    env_1.env.PHONE_VERIFICATION_DEV_MODE =
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
    const response = await service.startCallVerification('8 (928) 123-45-67', 'signup');
    strict_1.default.equal(response.checkId, 'check-1');
    strict_1.default.equal(response.verificationCheckId, 'check-1');
    strict_1.default.equal(response.callToPhone, '78005008275');
    strict_1.default.equal(response.callPhone, '78005008275');
    strict_1.default.equal(response.phoneToCall, '78005008275');
    strict_1.default.equal(response.callToPhonePretty, '+7 (800) 500-82-75');
    strict_1.default.match(response.expiresAt, /\d{4}-\d{2}-\d{2}T/);
});
(0, node_test_1.test)('phone/start missing SMS_RU_API_ID returns safe error', async () => {
    env_1.env.SMS_RU_CALLCHECK_ENABLED = true;
    env_1.env.SMS_RU_API_ID = '';
    const service = createService(null);
    await strict_1.default.rejects(service.startCallVerification('79281234567', 'signup'), (error) => {
        strict_1.default.ok(error instanceof common_1.HttpException);
        strict_1.default.equal(error.getStatus(), 503);
        strict_1.default.deepEqual(error.getResponse(), {
            message: 'Подтверждение телефона временно недоступно',
            code: 'SMS_RU_API_ID_MISSING',
            details: 'SMS.ru API key missing',
        });
        return true;
    });
});
(0, node_test_1.test)('phone/start disabled callcheck returns safe disabled error', async () => {
    env_1.env.SMS_RU_CALLCHECK_ENABLED = false;
    env_1.env.SMS_RU_API_ID = 'present';
    const service = createService(null);
    await strict_1.default.rejects(service.startCallVerification('79281234567', 'signup'), (error) => {
        strict_1.default.ok(error instanceof common_1.HttpException);
        strict_1.default.equal(error.getStatus(), 503);
        strict_1.default.deepEqual(error.getResponse(), {
            message: 'Подтверждение телефона временно недоступно',
            code: 'SMS_RU_CALLCHECK_DISABLED',
            details: 'SMS.ru callcheck disabled',
        });
        return true;
    });
});
(0, node_test_1.test)('phone/start SMS.ru error returns code SMS_RU_CALLCHECK_FAILED', async () => {
    env_1.env.SMS_RU_CALLCHECK_ENABLED = true;
    env_1.env.SMS_RU_API_ID = 'present';
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
    await strict_1.default.rejects(service.startCallVerification('79281234567', 'signup'), (error) => {
        strict_1.default.ok(error instanceof common_1.HttpException);
        strict_1.default.equal(error.getStatus(), 503);
        strict_1.default.deepEqual(error.getResponse(), {
            message: 'Подтверждение телефона временно недоступно',
            code: 'SMS_RU_CALLCHECK_FAILED',
            details: 'status_code=209; status=ERROR; status_text=rate limit exceeded',
        });
        return true;
    });
});
(0, node_test_1.test)('phone/start missing call_phone returns safe error', async () => {
    env_1.env.SMS_RU_CALLCHECK_ENABLED = true;
    env_1.env.SMS_RU_API_ID = 'present';
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
    await strict_1.default.rejects(service.startCallVerification('79281234567', 'signup'), (error) => {
        strict_1.default.ok(error instanceof common_1.HttpException);
        strict_1.default.equal(error.getStatus(), 503);
        strict_1.default.deepEqual(error.getResponse(), {
            message: 'Подтверждение телефона временно недоступно',
            code: 'SMS_RU_CALL_PHONE_MISSING',
            details: 'Отсутствует номер для подтверждающего звонка',
        });
        return true;
    });
});
(0, node_test_1.test)('phone normalization works for phone/start', async () => {
    env_1.env.SMS_RU_CALLCHECK_ENABLED = true;
    env_1.env.SMS_RU_API_ID = 'present';
    let requestedPhone = '';
    globalThis.fetch = (async (input) => {
        const url = input instanceof URL ? input : new URL(input.toString());
        requestedPhone = url.searchParams.get('phone') ?? '';
        return {
            ok: true,
            status: 200,
            text: async () => JSON.stringify({
                status: 'OK',
                status_code: 100,
                check_id: 'check-1',
                call_phone: '78005008275',
            }),
            url: url.toString(),
        };
    });
    const service = createService(null);
    await service.startCallVerification('+7 928 123 45 67', 'signup');
    strict_1.default.equal(requestedPhone, '79281234567');
});
(0, node_test_1.test)('production mode does not return fake checkId', async () => {
    env_1.env.SMS_RU_CALLCHECK_ENABLED = true;
    env_1.env.SMS_RU_API_ID = 'present';
    env_1.env.PHONE_VERIFICATION_DEV_MODE =
        true;
    env_1.env.NODE_ENV =
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
    const response = await service.startCallVerification('79281234567', 'signup');
    strict_1.default.equal(response.checkId, 'check-prod');
    strict_1.default.equal(response.checkId.startsWith('fake-'), false);
});
(0, node_test_1.test)('phone/check maps SMS.ru 401 to confirmed', async () => {
    env_1.env.SMS_RU_CALLCHECK_ENABLED = true;
    env_1.env.SMS_RU_API_ID = 'present';
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
    const service = new phone_verification_service_1.PhoneVerificationService({
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
    });
    const response = await service.checkCallVerification('79281234567', 'check-1', 'signup');
    strict_1.default.equal(response.status, 'confirmed');
});
(0, node_test_1.test)('phone/check maps SMS.ru 400 to pending', async () => {
    env_1.env.SMS_RU_CALLCHECK_ENABLED = true;
    env_1.env.SMS_RU_API_ID = 'present';
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
    const service = new phone_verification_service_1.PhoneVerificationService({
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
    });
    const response = await service.checkCallVerification('79281234567', 'check-1', 'signup');
    strict_1.default.equal(response.status, 'pending');
});
(0, node_test_1.test)('phone/check maps SMS.ru 402 to expired', async () => {
    env_1.env.SMS_RU_CALLCHECK_ENABLED = true;
    env_1.env.SMS_RU_API_ID = 'present';
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
    const service = new phone_verification_service_1.PhoneVerificationService({
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
    });
    const response = await service.checkCallVerification('79281234567', 'check-1', 'signup');
    strict_1.default.equal(response.status, 'expired');
});
//# sourceMappingURL=phone-verification.service.spec.js.map