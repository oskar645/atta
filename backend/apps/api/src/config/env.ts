import 'dotenv/config';

import { z } from 'zod';

import { normalizeRussianPhone } from '../common/phone';

const defaultAdminPhones = ['79288888645', '79306939954'] as const;

const weakSecretValues = new Set([
  'change-me',
  'secret',
  'jwt_secret',
  'refresh_secret',
  'placeholder',
  'dev-secret',
]);

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  APP_ENV: z.string().optional().default(''),
  PORT: z.coerce.number().int().positive().default(3000),
  CORS_ORIGIN: z.string().default('*'),
  DATABASE_URL: z.string().min(1),
  REDIS_URL: z.string().min(1),
  JWT_ACCESS_SECRET: z.string().min(1),
  JWT_REFRESH_SECRET: z.string().min(1),
  JWT_ACCESS_TTL: z.string().min(1).default('15m'),
  JWT_REFRESH_TTL: z.string().min(1).default('30d'),
  STORAGE_DRIVER: z.enum(['local', 's3']).optional(),
  STORAGE_PROVIDER: z.enum(['local', 's3']).optional(),
  LOCAL_UPLOADS_DIR: z.string().default('/opt/atta-backend/uploads'),
  MEDIA_PUBLIC_BASE_URL: z.string().default('https://attamarket.online/uploads'),
  S3_ENDPOINT: z.string().optional().default(''),
  S3_REGION: z.string().optional().default(''),
  S3_ACCESS_KEY: z.string().optional().default(''),
  S3_SECRET_KEY: z.string().optional().default(''),
  S3_ACCESS_KEY_ID: z.string().optional().default(''),
  S3_SECRET_ACCESS_KEY: z.string().optional().default(''),
  S3_FORCE_PATH_STYLE: z
    .string()
    .optional()
    .transform((value) => value === 'true'),
  S3_BUCKET: z.string().optional().default(''),
  S3_BUCKET_AVATARS: z.string().optional().default(''),
  S3_BUCKET_LISTING_PHOTOS: z.string().optional().default(''),
  S3_BUCKET_CHAT_IMAGES: z.string().optional().default(''),
  S3_BUCKET_FEED_ADS: z.string().optional().default(''),
  S3_BUCKET_SUPPORT: z.string().optional().default(''),
  S3_BUCKET_REPORTS: z.string().optional().default(''),
  S3_BUCKET_MISC: z.string().optional().default(''),
  S3_BUCKET_VIDEOS: z.string().optional().default(''),
  S3_PUBLIC_BASE_URL: z.string().optional().default(''),
  SMS_RU_API_ID: z.string().optional().default(''),
  SMS_RU_CALLCHECK_ENABLED: z
    .string()
    .optional()
    .transform((value) => value === 'true'),
  PHONE_VERIFICATION_DEV_MODE: z
    .string()
    .optional()
    .transform((value) => value === 'true'),
  APNS_KEY_ID: z.string().min(1),
  APNS_TEAM_ID: z.string().min(1),
  APNS_BUNDLE_ID: z.string().min(1),
  APNS_PRIVATE_KEY_PATH: z.string().min(1),
  APNS_USE_SANDBOX: z
    .string()
    .optional()
    .transform((value) => value === 'true'),
  ADMIN_PHONE_NUMBERS: z.string().optional().default(''),
  WALLET_TIME_ZONE: z.string().min(1).default('Europe/Moscow'),
});

const parsedEnv = envSchema.safeParse(process.env);
if (!parsedEnv.success) {
  throw parsedEnv.error;
}

const envWithChecks = {
  ...parsedEnv.data,
  STORAGE_DRIVER:
    parsedEnv.data.STORAGE_DRIVER ?? parsedEnv.data.STORAGE_PROVIDER ?? 'local',
};
envWithChecks.STORAGE_PROVIDER = envWithChecks.STORAGE_DRIVER;
if (envWithChecks.NODE_ENV === 'production') {
  const secrets: Record<string, string> = {
    'JWT_ACCESS_SECRET': envWithChecks.JWT_ACCESS_SECRET,
    'JWT_REFRESH_SECRET': envWithChecks.JWT_REFRESH_SECRET,
  };

  for (const entry of Object.entries(secrets)) {
    const name = entry[0];
    const secret = entry[1].trim().toLowerCase();
    if (secret.length < 16 || weakSecretValues.has(secret)) {
      throw new Error(`${name} is missing or too weak for production`);
    }
  }
}

export const env = envWithChecks;

export const parseCorsOrigins = () =>
  env.CORS_ORIGIN.split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);

export const parseAdminPhoneNumbers = () =>
  Array.from(
    new Set<string>([
      ...defaultAdminPhones,
      ...env.ADMIN_PHONE_NUMBERS.split(','),
    ]),
  )
    .map((phone) => normalizeRussianPhone(phone.trim()))
    .filter((phone) => phone.length > 0);
