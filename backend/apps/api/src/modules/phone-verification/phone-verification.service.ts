import {
  BadRequestException,
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
} from '@nestjs/common';
import {
  PhoneVerificationProvider,
  PhoneVerificationPurpose,
  PhoneVerificationStatus,
  Prisma,
} from '@prisma/client';
import { createHash } from 'crypto';
import { randomUUID } from 'crypto';

import {
  maskPhone,
  normalizeRussianPhone,
  validateRussianPhoneOrThrow,
} from '../../common/phone';
import { env } from '../../config/env';
import { PrismaService } from '../prisma/prisma.service';
import { RateLimitService } from '../rate-limit/rate-limit.service';

type VerificationPurpose = 'signup' | 'login' | 'reset_password';

type SmsRuResponse = Record<string, unknown>;
type VerificationSource = {
  deviceId?: string;
  ip?: string;
  userAgent?: string;
};

const PHONE_VERIFICATION_TTL_MS = 5 * 60 * 1000;
const MAX_CHECK_ATTEMPTS = 5;
const DEV_CALL_TO_PHONE = '+7 999 000-00-00';
const SMS_SOURCE_UNIQUE_WINDOW_MS = 15 * 60 * 1000;
const SMS_DEVICE_UNIQUE_PHONE_LIMIT = 50;
const SMS_IP_UNIQUE_PHONE_LIMIT = 100;

@Injectable()
export class PhoneVerificationService {
  private readonly logger = new Logger(PhoneVerificationService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly rateLimitService: RateLimitService,
  ) {}

  async checkRegistration(phone: string) {
    const normalizedPhone = this.normalizeRussianPhone(phone);
    this.validatePhoneFormat(normalizedPhone);

    // Keep the existing per-phone cooldown stable; Redis only adds mass source detection.
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

  async startCallVerification(
    phone: string,
    purpose: VerificationPurpose,
    source?: VerificationSource,
  ) {
    const normalizedPhone = this.normalizeRussianPhone(phone);
    this.validatePhoneFormat(normalizedPhone);
    await this.rateLimitPlaceholder(normalizedPhone);
    await this.enforceSmsCostAbuseLimit(normalizedPhone, source);

    const now = new Date();
    const expiresAt = new Date(now.getTime() + PHONE_VERIFICATION_TTL_MS);

    if (this.useFakeProvider()) {
      const checkId = `fake-${randomUUID()}`;
      await this.storeVerificationAttempt({
        phone: normalizedPhone,
        purpose,
        checkId,
        expiresAt,
        status: PhoneVerificationStatus.PENDING,
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
    this.logger.log(
      `SMS.ru request started for phone=${this.maskPhone(normalizedPhone)}`,
    );

    const response = await this.callSmsRu('/callcheck/add', {
      phone: normalizedPhone.replace(/\D/g, ''),
    });

    this.assertSmsRuSuccess('/callcheck/add', response);

    const checkId = `${response.check_id ?? response.checkId ?? ''}`.trim();
    const callToPhone = this.pickCallPhone(response);
    const callToPhonePretty = this.pickCallPhonePretty(response, callToPhone);
    if (!checkId) {
      this.logger.error('SMS.ru response missing verification id');
      throw this.createSafeCallcheckException(
        HttpStatus.SERVICE_UNAVAILABLE,
        'SMS_RU_INVALID_RESPONSE',
        'Не удалось обработать ответ сервиса подтверждения',
      );
    }
    if (!callToPhone) {
      this.logger.error(
        `SMS.ru response missing call phone for /callcheck/add: status=${this.pickStatusValue(response)}, status_code=${this.pickStatusCode(response)}, check_id_exists=${checkId.length > 0}, response_keys=${this.pickResponseKeys(response).join(',')}`,
      );
      throw this.createSafeCallcheckException(
        HttpStatus.SERVICE_UNAVAILABLE,
        'SMS_RU_CALL_PHONE_MISSING',
        'Отсутствует номер для подтверждающего звонка',
      );
    }

    await this.storeVerificationAttempt({
      phone: normalizedPhone,
      purpose,
      checkId,
      expiresAt,
      status: PhoneVerificationStatus.PENDING,
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

  async checkCallVerification(
    phone: string,
    checkId: string,
    purpose: VerificationPurpose,
  ) {
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
      throw new BadRequestException('Phone verification session was not found');
    }

    if (verification.status === PhoneVerificationStatus.CONFIRMED) {
      return {
        status: 'confirmed',
        message: 'Phone verified',
      };
    }

    if (verification.status === PhoneVerificationStatus.FAILED) {
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
          status: PhoneVerificationStatus.EXPIRED,
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
          status: PhoneVerificationStatus.FAILED,
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
      this.logger.warn(
        `Rejected fake phone verification check outside dev mode for ${this.maskPhone(normalizedPhone)}`,
      );
      throw new BadRequestException('Подтверждение номера недействительно');
    }

    this.assertProviderConfigured();

    const response = await this.callSmsRu('/callcheck/status', {
      check_id: checkId.trim(),
    });

    this.assertSmsRuSuccess('/callcheck/status', response);

    const resolvedStatus = this.resolveSmsRuCheckStatus(response);
    const nextStatus =
      resolvedStatus === 'confirmed'
        ? PhoneVerificationStatus.CONFIRMED
        : resolvedStatus === 'expired'
          ? PhoneVerificationStatus.EXPIRED
          : resolvedStatus === 'failed'
            ? PhoneVerificationStatus.FAILED
            : PhoneVerificationStatus.PENDING;

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
          metadata: response as Prisma.InputJsonValue,
        },
      });

      return {
        status: resolvedStatus,
        message:
          resolvedStatus === 'expired'
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
        metadata: response as Prisma.InputJsonValue,
      },
    });

    return {
      status: 'pending',
      message: 'Звонок пока не найден. Попробуйте ещё раз через несколько секунд.',
    };
  }

  normalizeRussianPhone(phone: string) {
    return normalizeRussianPhone(phone);
  }

  validatePhoneFormat(phone: string) {
    validateRussianPhoneOrThrow(phone);
  }

  async rateLimitPlaceholder(phone: string) {
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
      throw this.createTooManyRequestsException(
        `Too many verification attempts for ${maskedPhone}`,
      );
    }
  }

  async enforceSmsCostAbuseLimit(phone: string, source?: VerificationSource) {
    const signals = this.smsSourceSignals(source);
    if (signals.length === 0) {
      return;
    }

    const phoneHash = this.sha256(phone);
    for (const signal of signals) {
      const count = await this.rateLimitService.countUniqueValues(
        `phone:start:unique:${signal.kind}:${signal.key}`,
        phoneHash,
        SMS_SOURCE_UNIQUE_WINDOW_MS,
      );
      if (count != null && count > signal.limit) {
        this.logger.warn(
          `Blocked SMS.ru mass verification source=${signal.kind} count=${count} limit=${signal.limit}`,
        );
        throw this.createTooManyRequestsException(
          'Too many verification attempts. Попробуйте позже.',
        );
      }
    }
  }

  async storeVerificationAttempt(params: {
    phone: string;
    purpose: VerificationPurpose;
    checkId: string;
    expiresAt: Date;
    status: PhoneVerificationStatus;
    providerStatusCode?: string | null;
    providerStatusText?: string | null;
    metadata?: SmsRuResponse;
  }) {
    return this.prisma.phoneVerification.create({
      data: {
        phone: params.phone,
        purpose: this.mapPurpose(params.purpose),
        provider: PhoneVerificationProvider.SMS_RU,
        checkId: params.checkId,
        status: params.status,
        attempts: 0,
        maxAttempts: MAX_CHECK_ATTEMPTS,
        expiresAt: params.expiresAt,
        providerStatusCode: params.providerStatusCode ?? null,
        providerStatusText: params.providerStatusText ?? null,
        metadata: (params.metadata ?? {}) as Prisma.InputJsonValue,
      },
    });
  }

  async markVerificationConfirmed(
    verificationId: string,
    params?: {
      attempts?: number;
      providerStatusCode?: string | null;
      providerStatusText?: string | null;
      metadata?: SmsRuResponse;
    },
  ) {
    return this.prisma.phoneVerification.update({
      where: {
        id: verificationId,
      },
      data: {
        status: PhoneVerificationStatus.CONFIRMED,
        confirmedAt: new Date(),
        attempts: params?.attempts,
        providerStatusCode: params?.providerStatusCode ?? undefined,
        providerStatusText: params?.providerStatusText ?? undefined,
        metadata: params?.metadata
          ? (params.metadata as Prisma.InputJsonValue)
          : undefined,
      },
    });
  }

  private useFakeProvider() {
    return env.PHONE_VERIFICATION_DEV_MODE === true && !this.isProductionLike();
  }

  private isProductionLike() {
    const appEnv = env.APP_ENV.trim().toLowerCase();
    return (
      env.NODE_ENV === 'production' ||
      appEnv === 'production' ||
      appEnv === 'server'
    );
  }

  private assertProviderConfigured() {
    const apiId = env.SMS_RU_API_ID.trim();
    if (env.SMS_RU_CALLCHECK_ENABLED !== true) {
      this.logger.error('Phone verification is unavailable: SMS_RU_CALLCHECK_ENABLED=false');
      throw this.createSafeCallcheckException(
        HttpStatus.SERVICE_UNAVAILABLE,
        'SMS_RU_CALLCHECK_DISABLED',
        'SMS.ru callcheck disabled',
      );
    }
    if (!apiId || apiId === 'your_sms_ru_api_id_here') {
      this.logger.error('Phone verification is unavailable: SMS_RU_API_ID is missing');
      throw this.createSafeCallcheckException(
        HttpStatus.SERVICE_UNAVAILABLE,
        'SMS_RU_API_ID_MISSING',
        'SMS.ru API key missing',
      );
    }
  }

  private isDevVerification(checkId: string) {
    return checkId.trim().startsWith('fake-');
  }

  private smsSourceSignals(source?: VerificationSource) {
    const deviceId = source?.deviceId?.trim();
    const ip = source?.ip?.trim();
    const userAgent = source?.userAgent?.trim();
    const signals: Array<{ kind: string; key: string; limit: number }> = [];

    if (deviceId) {
      signals.push({
        kind: 'device',
        key: this.sha256(deviceId),
        limit: SMS_DEVICE_UNIQUE_PHONE_LIMIT,
      });
    } else if (ip || userAgent) {
      signals.push({
        kind: 'client',
        key: this.sha256(`${ip || 'unknown'}:${userAgent || 'unknown'}`),
        limit: SMS_DEVICE_UNIQUE_PHONE_LIMIT,
      });
    }

    if (ip && ip !== 'unknown') {
      signals.push({
        kind: 'ip',
        key: this.sha256(ip),
        limit: SMS_IP_UNIQUE_PHONE_LIMIT,
      });
    }

    return signals;
  }

  private sha256(value: string) {
    return createHash('sha256').update(value).digest('hex');
  }

  private createTooManyRequestsException(message: string) {
    return new HttpException(message, HttpStatus.TOO_MANY_REQUESTS);
  }

  private mapPurpose(purpose: VerificationPurpose): PhoneVerificationPurpose {
    switch (purpose) {
      case 'signup':
        return PhoneVerificationPurpose.SIGNUP;
      case 'login':
        return PhoneVerificationPurpose.LOGIN;
      case 'reset_password':
        return PhoneVerificationPurpose.RESET_PASSWORD;
    }
  }

  private async callSmsRu(
    path: '/callcheck/add' | '/callcheck/status',
    query: Record<string, string>,
  ) {
    const apiId = env.SMS_RU_API_ID.trim();

    const url = new URL(`https://sms.ru${path}`);
    url.searchParams.set('api_id', apiId);
    url.searchParams.set('json', '1');

    for (const [key, value] of Object.entries(query)) {
      url.searchParams.set(key, value);
    }

    let response: Response;
    try {
      response = await fetch(url);
    } catch (error) {
      this.logger.error(
        `Unable to reach SMS.ru verification provider for ${path}`,
        error instanceof Error ? error.stack : undefined,
      );
      throw this.createSafeCallcheckException(
        HttpStatus.SERVICE_UNAVAILABLE,
        'SMS_RU_UNREACHABLE',
        'SMS.ru unavailable',
      );
    }

    const rawBody = await response.text();
    let body: SmsRuResponse = {};
    try {
      body = rawBody.trim() ? (JSON.parse(rawBody) as SmsRuResponse) : {};
    } catch {
      this.logger.error(`SMS.ru returned invalid JSON for ${path}`);
      throw this.createSafeCallcheckException(
        HttpStatus.SERVICE_UNAVAILABLE,
        'SMS_RU_INVALID_RESPONSE',
        'Не удалось обработать ответ сервиса подтверждения',
      );
    }

    if (!response.ok) {
      this.logger.error(
        `SMS.ru request failed for ${path}: ${this.pickStatusCode(body) ?? response.status}`,
      );
      throw this.createSafeCallcheckException(
        HttpStatus.SERVICE_UNAVAILABLE,
        'SMS_RU_HTTP_ERROR',
        this.describeSmsRuFailure(body),
      );
    }

    return body;
  }

  private assertSmsRuSuccess(
    path: '/callcheck/add' | '/callcheck/status',
    response: SmsRuResponse,
  ) {
    const status = this.pickStatusValue(response).toUpperCase();
    const statusCode = Number(this.pickStatusCode(response) ?? NaN);

    if (status === 'OK' && statusCode === 100) {
      return;
    }

    const safeStatus = this.pickStatusValue(response) || 'unknown';
    const safeStatusCode = this.pickStatusCode(response) ?? 'unknown';
    const safeStatusText = this.pickStatusText(response) || 'unknown';
    this.logger.warn(
      `SMS.ru returned business error for ${path}: status=${safeStatus}, status_code=${safeStatusCode}, status_text=${safeStatusText}`,
    );
    throw this.createSafeCallcheckException(
      HttpStatus.SERVICE_UNAVAILABLE,
      'SMS_RU_CALLCHECK_FAILED',
      `status_code=${safeStatusCode}; status=${safeStatus}; status_text=${safeStatusText}`,
    );
  }

  private pickStatusValue(response: SmsRuResponse) {
    return `${response.status ?? ''}`.trim();
  }

  private pickStatusCode(response: SmsRuResponse) {
    return `${response.status_code ?? response.code ?? response.status ?? ''}`.trim() || null;
  }

  private pickStatusText(response: SmsRuResponse) {
    return `${response.status_text ?? response.statusText ?? response.error ?? ''}`.trim() || null;
  }

  private pickCallPhone(response: SmsRuResponse) {
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

  private pickCallPhonePretty(response: SmsRuResponse, callPhone: string) {
    return `${response.call_phone_pretty ??
      response.callPhonePretty ??
      response.call_to_phone_pretty ??
      callPhone}`.trim();
  }

  private resolveSmsRuCheckStatus(response: SmsRuResponse) {
    const checkStatus = `${response.check_status ?? response.call_status ?? ''}`.trim();

    switch (checkStatus) {
      case '401':
        return 'confirmed' as const;
      case '400':
        return 'pending' as const;
      case '402':
        return 'expired' as const;
      default:
        return 'failed' as const;
    }
  }

  private pickResponseKeys(response: SmsRuResponse) {
    return Object.keys(response).sort();
  }

  private maskPhone(phone: string) {
    return maskPhone(phone);
  }

  private createSafeCallcheckException(
    status: HttpStatus,
    code: string,
    details: string,
  ) {
    return new HttpException(
      {
        message: 'Подтверждение телефона временно недоступно',
        code,
        details,
      },
      status,
    );
  }

  private describeSmsRuFailure(response: SmsRuResponse) {
    const text = `${response.status_text ?? response.statusText ?? response.error ?? ''}`
      .trim()
      .toLowerCase();
    const code = `${response.status_code ?? response.code ?? ''}`.trim();

    if (
      text.includes('limit') ||
      text.includes('rate') ||
      code === '209' ||
      code === '210'
    ) {
      return 'SMS.ru rate limit';
    }
    if (
      text.includes('phone') ||
      text.includes('format') ||
      text.includes('номер') ||
      code === '203' ||
      code === '204'
    ) {
      return 'SMS.ru invalid phone';
    }
    if (
      text.includes('balance') ||
      text.includes('insufficient') ||
      text.includes('provider') ||
      code === '206' ||
      code === '208'
    ) {
      return 'SMS.ru balance or provider error';
    }
    return 'Unexpected SMS.ru response';
  }
}
