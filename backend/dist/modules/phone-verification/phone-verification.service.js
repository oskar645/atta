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
var PhoneVerificationService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.PhoneVerificationService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const crypto_1 = require("crypto");
const phone_1 = require("../../common/phone");
const env_1 = require("../../config/env");
const prisma_service_1 = require("../prisma/prisma.service");
const PHONE_VERIFICATION_TTL_MS = 5 * 60 * 1000;
const MAX_CHECK_ATTEMPTS = 5;
const DEV_CALL_TO_PHONE = '+7 999 000-00-00';
let PhoneVerificationService = PhoneVerificationService_1 = class PhoneVerificationService {
    constructor(prisma) {
        this.prisma = prisma;
        this.logger = new common_1.Logger(PhoneVerificationService_1.name);
    }
    async checkRegistration(phone) {
        const normalizedPhone = this.normalizeRussianPhone(phone);
        this.validatePhoneFormat(normalizedPhone);
        // TODO: replace with Redis-based per-phone and per-IP rate limiting.
        const user = await this.prisma.user.findUnique({
            where: {
                phone: normalizedPhone,
            },
            select: {
                id: true,
            },
        });
        return {
            exists: Boolean(user),
            phone: normalizedPhone,
            message: user
                ? 'Phone is already registered'
                : 'Phone is available',
        };
    }
    async startCallVerification(phone, purpose) {
        const normalizedPhone = this.normalizeRussianPhone(phone);
        this.validatePhoneFormat(normalizedPhone);
        await this.rateLimitPlaceholder(normalizedPhone);
        const now = new Date();
        const expiresAt = new Date(now.getTime() + PHONE_VERIFICATION_TTL_MS);
        if (this.useFakeProvider()) {
            const checkId = `fake-${(0, crypto_1.randomUUID)()}`;
            await this.storeVerificationAttempt({
                phone: normalizedPhone,
                purpose,
                checkId,
                expiresAt,
                status: client_1.PhoneVerificationStatus.PENDING,
                providerStatusCode: '100',
                providerStatusText: 'Fake call verification started',
            });
            return {
                status: 'ok',
                verificationId: checkId,
                checkId,
                callToPhone: DEV_CALL_TO_PHONE,
                call_to_phone: DEV_CALL_TO_PHONE,
                expiresAt: expiresAt.toISOString(),
                message: 'Позвоните на указанный номер для подтверждения',
            };
        }
        this.assertProviderConfigured();
        this.logger.log(`SMS.ru request started for phone=${this.maskPhone(normalizedPhone)}`);
        const response = await this.callSmsRu('/callcheck/add', {
            phone: normalizedPhone.replace(/\D/g, ''),
        });
        this.assertSmsRuSuccess('/callcheck/add', response);
        const checkId = `${response.check_id ?? response.checkId ?? ''}`.trim();
        const callToPhone = this.pickCallPhone(response);
        const callToPhonePretty = this.pickCallPhonePretty(response, callToPhone);
        if (!checkId) {
            this.logger.error('SMS.ru response missing verification id');
            throw this.createSafeCallcheckException(common_1.HttpStatus.SERVICE_UNAVAILABLE, 'SMS_RU_INVALID_RESPONSE', 'Не удалось обработать ответ сервиса подтверждения');
        }
        if (!callToPhone) {
            this.logger.error(`SMS.ru response missing call phone for /callcheck/add: status=${this.pickStatusValue(response)}, status_code=${this.pickStatusCode(response)}, check_id_exists=${checkId.length > 0}, response_keys=${this.pickResponseKeys(response).join(',')}`);
            throw this.createSafeCallcheckException(common_1.HttpStatus.SERVICE_UNAVAILABLE, 'SMS_RU_CALL_PHONE_MISSING', 'Отсутствует номер для подтверждающего звонка');
        }
        await this.storeVerificationAttempt({
            phone: normalizedPhone,
            purpose,
            checkId,
            expiresAt,
            status: client_1.PhoneVerificationStatus.PENDING,
            providerStatusCode: this.pickStatusCode(response),
            providerStatusText: this.pickStatusText(response),
            metadata: response,
        });
        return {
            status: 'ok',
            verificationId: checkId,
            checkId,
            verificationCheckId: checkId,
            callToPhone,
            callPhone: callToPhone,
            phoneToCall: callToPhone,
            call_phone: callToPhone,
            callToPhonePretty,
            callPhonePretty: callToPhonePretty,
            call_phone_pretty: callToPhonePretty,
            call_to_phone: callToPhone,
            expiresAt: expiresAt.toISOString(),
            message: 'Позвоните на указанный номер для подтверждения',
        };
    }
    async checkCallVerification(phone, checkId, purpose) {
        const normalizedPhone = this.normalizeRussianPhone(phone);
        this.validatePhoneFormat(normalizedPhone);
        const verification = await this.prisma.phoneVerification.findFirst({
            where: {
                phone: normalizedPhone,
                purpose: this.mapPurpose(purpose),
                checkId: checkId.trim(),
            },
            orderBy: {
                createdAt: 'desc',
            },
        });
        if (!verification) {
            throw new common_1.BadRequestException('Phone verification session was not found');
        }
        if (verification.status === client_1.PhoneVerificationStatus.CONFIRMED) {
            return {
                status: 'confirmed',
                message: 'Phone verified',
            };
        }
        if (verification.status === client_1.PhoneVerificationStatus.FAILED) {
            return {
                status: 'failed',
                message: 'Не удалось подтвердить звонок. Попробуйте ещё раз позже.',
            };
        }
        if (verification.expiresAt.getTime() <= Date.now()) {
            await this.prisma.phoneVerification.update({
                where: {
                    id: verification.id,
                },
                data: {
                    status: client_1.PhoneVerificationStatus.EXPIRED,
                    providerStatusText: 'Verification expired',
                },
            });
            return {
                status: 'expired',
                message: 'Phone verification has expired',
            };
        }
        if (verification.attempts >= verification.maxAttempts) {
            await this.prisma.phoneVerification.update({
                where: {
                    id: verification.id,
                },
                data: {
                    status: client_1.PhoneVerificationStatus.FAILED,
                    providerStatusText: 'Maximum verification attempts reached',
                },
            });
            return {
                status: 'failed',
                message: 'Не удалось подтвердить звонок. Попробуйте ещё раз позже.',
            };
        }
        const nextAttemptCount = verification.attempts + 1;
        if (this.useFakeProvider()) {
            await this.markVerificationConfirmed(verification.id, {
                attempts: nextAttemptCount,
                providerStatusCode: '100',
                providerStatusText: 'Fake verification confirmed',
            });
            return {
                status: 'confirmed',
                message: 'Номер подтвержден',
            };
        }
        if (this.isDevVerification(verification.checkId ?? '')) {
            this.logger.warn(`Rejected fake phone verification check outside dev mode for ${this.maskPhone(normalizedPhone)}`);
            throw new common_1.BadRequestException('Подтверждение номера недействительно');
        }
        this.assertProviderConfigured();
        const response = await this.callSmsRu('/callcheck/status', {
            check_id: checkId.trim(),
        });
        this.assertSmsRuSuccess('/callcheck/status', response);
        const resolvedStatus = this.resolveSmsRuCheckStatus(response);
        const nextStatus = resolvedStatus === 'confirmed'
            ? client_1.PhoneVerificationStatus.CONFIRMED
            : resolvedStatus === 'expired'
                ? client_1.PhoneVerificationStatus.EXPIRED
                : resolvedStatus === 'failed'
                    ? client_1.PhoneVerificationStatus.FAILED
                    : client_1.PhoneVerificationStatus.PENDING;
        if (resolvedStatus === 'confirmed') {
            await this.markVerificationConfirmed(verification.id, {
                attempts: nextAttemptCount,
                providerStatusCode: this.pickStatusCode(response),
                providerStatusText: this.pickStatusText(response),
                metadata: response,
            });
            return {
                status: 'confirmed',
                message: 'Номер подтвержден',
            };
        }
        if (resolvedStatus === 'expired' || resolvedStatus === 'failed') {
            await this.prisma.phoneVerification.update({
                where: {
                    id: verification.id,
                },
                data: {
                    attempts: nextAttemptCount,
                    status: nextStatus,
                    providerStatusCode: this.pickStatusCode(response),
                    providerStatusText: this.pickStatusText(response),
                    metadata: response,
                },
            });
            return {
                status: resolvedStatus,
                message: resolvedStatus === 'expired'
                    ? 'Время подтверждения истекло. Попробуйте ещё раз позже.'
                    : 'Не удалось подтвердить звонок. Попробуйте ещё раз позже.',
            };
        }
        await this.prisma.phoneVerification.update({
            where: {
                id: verification.id,
            },
            data: {
                attempts: nextAttemptCount,
                status: nextStatus,
                providerStatusCode: this.pickStatusCode(response),
                providerStatusText: this.pickStatusText(response),
                metadata: response,
            },
        });
        return {
            status: 'pending',
            message: 'Звонок пока не найден. Попробуйте ещё раз через несколько секунд.',
        };
    }
    normalizeRussianPhone(phone) {
        return (0, phone_1.normalizeRussianPhone)(phone);
    }
    validatePhoneFormat(phone) {
        (0, phone_1.validateRussianPhoneOrThrow)(phone);
    }
    async rateLimitPlaceholder(phone) {
        const maskedPhone = this.maskPhone(phone);
        const recentAttempts = await this.prisma.phoneVerification.count({
            where: {
                phone,
                createdAt: {
                    gte: new Date(Date.now() - 60 * 1000),
                },
            },
        });
        // TODO: replace with Redis-based per-phone and per-IP rate limiting.
        if (recentAttempts >= 3) {
            throw this.createTooManyRequestsException(`Too many verification attempts for ${maskedPhone}`);
        }
    }
    async storeVerificationAttempt(params) {
        return this.prisma.phoneVerification.create({
            data: {
                phone: params.phone,
                purpose: this.mapPurpose(params.purpose),
                provider: client_1.PhoneVerificationProvider.SMS_RU,
                checkId: params.checkId,
                status: params.status,
                attempts: 0,
                maxAttempts: MAX_CHECK_ATTEMPTS,
                expiresAt: params.expiresAt,
                providerStatusCode: params.providerStatusCode ?? null,
                providerStatusText: params.providerStatusText ?? null,
                metadata: (params.metadata ?? {}),
            },
        });
    }
    async markVerificationConfirmed(verificationId, params) {
        return this.prisma.phoneVerification.update({
            where: {
                id: verificationId,
            },
            data: {
                status: client_1.PhoneVerificationStatus.CONFIRMED,
                confirmedAt: new Date(),
                attempts: params?.attempts,
                providerStatusCode: params?.providerStatusCode ?? undefined,
                providerStatusText: params?.providerStatusText ?? undefined,
                metadata: params?.metadata
                    ? params.metadata
                    : undefined,
            },
        });
    }
    useFakeProvider() {
        return env_1.env.PHONE_VERIFICATION_DEV_MODE === true && !this.isProductionLike();
    }
    isProductionLike() {
        const appEnv = env_1.env.APP_ENV.trim().toLowerCase();
        return (env_1.env.NODE_ENV === 'production' ||
            appEnv === 'production' ||
            appEnv === 'server');
    }
    assertProviderConfigured() {
        const apiId = env_1.env.SMS_RU_API_ID.trim();
        if (env_1.env.SMS_RU_CALLCHECK_ENABLED !== true) {
            this.logger.error('Phone verification is unavailable: SMS_RU_CALLCHECK_ENABLED=false');
            throw this.createSafeCallcheckException(common_1.HttpStatus.SERVICE_UNAVAILABLE, 'SMS_RU_CALLCHECK_DISABLED', 'SMS.ru callcheck disabled');
        }
        if (!apiId || apiId === 'your_sms_ru_api_id_here') {
            this.logger.error('Phone verification is unavailable: SMS_RU_API_ID is missing');
            throw this.createSafeCallcheckException(common_1.HttpStatus.SERVICE_UNAVAILABLE, 'SMS_RU_API_ID_MISSING', 'SMS.ru API key missing');
        }
    }
    isDevVerification(checkId) {
        return checkId.trim().startsWith('fake-');
    }
    createTooManyRequestsException(message) {
        return new common_1.HttpException(message, common_1.HttpStatus.TOO_MANY_REQUESTS);
    }
    mapPurpose(purpose) {
        switch (purpose) {
            case 'signup':
                return client_1.PhoneVerificationPurpose.SIGNUP;
            case 'login':
                return client_1.PhoneVerificationPurpose.LOGIN;
            case 'reset_password':
                return client_1.PhoneVerificationPurpose.RESET_PASSWORD;
        }
    }
    async callSmsRu(path, query) {
        const apiId = env_1.env.SMS_RU_API_ID.trim();
        const url = new URL(`https://sms.ru${path}`);
        url.searchParams.set('api_id', apiId);
        url.searchParams.set('json', '1');
        for (const [key, value] of Object.entries(query)) {
            url.searchParams.set(key, value);
        }
        let response;
        try {
            response = await fetch(url);
        }
        catch (error) {
            this.logger.error(`Unable to reach SMS.ru verification provider for ${path}`, error instanceof Error ? error.stack : undefined);
            throw this.createSafeCallcheckException(common_1.HttpStatus.SERVICE_UNAVAILABLE, 'SMS_RU_UNREACHABLE', 'SMS.ru unavailable');
        }
        const rawBody = await response.text();
        let body = {};
        try {
            body = rawBody.trim() ? JSON.parse(rawBody) : {};
        }
        catch {
            this.logger.error(`SMS.ru returned invalid JSON for ${path}`);
            throw this.createSafeCallcheckException(common_1.HttpStatus.SERVICE_UNAVAILABLE, 'SMS_RU_INVALID_RESPONSE', 'Не удалось обработать ответ сервиса подтверждения');
        }
        if (!response.ok) {
            this.logger.error(`SMS.ru request failed for ${path}: ${this.pickStatusCode(body) ?? response.status}`);
            throw this.createSafeCallcheckException(common_1.HttpStatus.SERVICE_UNAVAILABLE, 'SMS_RU_HTTP_ERROR', this.describeSmsRuFailure(body));
        }
        return body;
    }
    assertSmsRuSuccess(path, response) {
        const status = this.pickStatusValue(response).toUpperCase();
        const statusCode = Number(this.pickStatusCode(response) ?? NaN);
        if (status === 'OK' && statusCode === 100) {
            return;
        }
        const safeStatus = this.pickStatusValue(response) || 'unknown';
        const safeStatusCode = this.pickStatusCode(response) ?? 'unknown';
        const safeStatusText = this.pickStatusText(response) || 'unknown';
        this.logger.warn(`SMS.ru returned business error for ${path}: status=${safeStatus}, status_code=${safeStatusCode}, status_text=${safeStatusText}`);
        throw this.createSafeCallcheckException(common_1.HttpStatus.SERVICE_UNAVAILABLE, 'SMS_RU_CALLCHECK_FAILED', `status_code=${safeStatusCode}; status=${safeStatus}; status_text=${safeStatusText}`);
    }
    pickStatusValue(response) {
        return `${response.status ?? ''}`.trim();
    }
    pickStatusCode(response) {
        return `${response.status_code ?? response.code ?? response.status ?? ''}`.trim() || null;
    }
    pickStatusText(response) {
        return `${response.status_text ?? response.statusText ?? response.error ?? ''}`.trim() || null;
    }
    pickCallPhone(response) {
        return `${response.call_phone ??
            response.callPhone ??
            response.call_number ??
            response.callNumber ??
            response.call_to_phone ??
            response.call_to ??
            response.call ??
            response.phone ??
            ''}`.trim();
    }
    pickCallPhonePretty(response, callPhone) {
        return `${response.call_phone_pretty ??
            response.callPhonePretty ??
            response.call_to_phone_pretty ??
            callPhone}`.trim();
    }
    resolveSmsRuCheckStatus(response) {
        const checkStatus = `${response.check_status ?? response.call_status ?? ''}`.trim();
        switch (checkStatus) {
            case '401':
                return 'confirmed';
            case '400':
                return 'pending';
            case '402':
                return 'expired';
            default:
                return 'failed';
        }
    }
    pickResponseKeys(response) {
        return Object.keys(response).sort();
    }
    maskPhone(phone) {
        return (0, phone_1.maskPhone)(phone);
    }
    createSafeCallcheckException(status, code, details) {
        return new common_1.HttpException({
            message: 'Подтверждение телефона временно недоступно',
            code,
            details,
        }, status);
    }
    describeSmsRuFailure(response) {
        const text = `${response.status_text ?? response.statusText ?? response.error ?? ''}`
            .trim()
            .toLowerCase();
        const code = `${response.status_code ?? response.code ?? ''}`.trim();
        if (text.includes('limit') ||
            text.includes('rate') ||
            code === '209' ||
            code === '210') {
            return 'SMS.ru rate limit';
        }
        if (text.includes('phone') ||
            text.includes('format') ||
            text.includes('номер') ||
            code === '203' ||
            code === '204') {
            return 'SMS.ru invalid phone';
        }
        if (text.includes('balance') ||
            text.includes('insufficient') ||
            text.includes('provider') ||
            code === '206' ||
            code === '208') {
            return 'SMS.ru balance or provider error';
        }
        return 'Unexpected SMS.ru response';
    }
};
exports.PhoneVerificationService = PhoneVerificationService;
exports.PhoneVerificationService = PhoneVerificationService = PhoneVerificationService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], PhoneVerificationService);
//# sourceMappingURL=phone-verification.service.js.map