"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseAdminPhoneNumbers = exports.parseCorsOrigins = exports.env = void 0;
require("dotenv/config");
const zod_1 = require("zod");
const phone_1 = require("../common/phone");
const defaultAdminPhones = ['79288888645', '79306939954'];
const weakSecretValues = new Set([
    'change-me',
    'secret',
    'jwt_secret',
    'refresh_secret',
    'placeholder',
    'dev-secret',
]);
const envSchema = zod_1.z.object({
    NODE_ENV: zod_1.z.enum(['development', 'test', 'production']).default('development'),
    APP_ENV: zod_1.z.string().optional().default(''),
    PORT: zod_1.z.coerce.number().int().positive().default(3000),
    CORS_ORIGIN: zod_1.z.string().default('*'),
    DATABASE_URL: zod_1.z.string().min(1),
    REDIS_URL: zod_1.z.string().min(1),
    JWT_ACCESS_SECRET: zod_1.z.string().min(1),
    JWT_REFRESH_SECRET: zod_1.z.string().min(1),
    JWT_ACCESS_TTL: zod_1.z.string().min(1).default('15m'),
    JWT_REFRESH_TTL: zod_1.z.string().min(1).default('30d'),
    STORAGE_DRIVER: zod_1.z.enum(['local', 's3']).optional(),
    STORAGE_PROVIDER: zod_1.z.enum(['local', 's3']).optional(),
    LOCAL_UPLOADS_DIR: zod_1.z.string().default('/opt/atta-backend/uploads'),
    MEDIA_PUBLIC_BASE_URL: zod_1.z.string().default('http://5.42.125.179/uploads'),
    S3_ENDPOINT: zod_1.z.string().optional().default(''),
    S3_REGION: zod_1.z.string().optional().default(''),
    S3_ACCESS_KEY: zod_1.z.string().optional().default(''),
    S3_SECRET_KEY: zod_1.z.string().optional().default(''),
    S3_ACCESS_KEY_ID: zod_1.z.string().optional().default(''),
    S3_SECRET_ACCESS_KEY: zod_1.z.string().optional().default(''),
    S3_FORCE_PATH_STYLE: zod_1.z
        .string()
        .optional()
        .transform((value) => value === 'true'),
    S3_BUCKET: zod_1.z.string().optional().default(''),
    S3_BUCKET_AVATARS: zod_1.z.string().optional().default(''),
    S3_BUCKET_LISTING_PHOTOS: zod_1.z.string().optional().default(''),
    S3_BUCKET_CHAT_IMAGES: zod_1.z.string().optional().default(''),
    S3_BUCKET_FEED_ADS: zod_1.z.string().optional().default(''),
    S3_BUCKET_SUPPORT: zod_1.z.string().optional().default(''),
    S3_BUCKET_REPORTS: zod_1.z.string().optional().default(''),
    S3_BUCKET_MISC: zod_1.z.string().optional().default(''),
    S3_BUCKET_VIDEOS: zod_1.z.string().optional().default(''),
    S3_PUBLIC_BASE_URL: zod_1.z.string().optional().default(''),
    SMS_RU_API_ID: zod_1.z.string().optional().default(''),
    SMS_RU_CALLCHECK_ENABLED: zod_1.z
        .string()
        .optional()
        .transform((value) => value === 'true'),
    PHONE_VERIFICATION_DEV_MODE: zod_1.z
        .string()
        .optional()
        .transform((value) => value === 'true'),
    APNS_KEY_ID: zod_1.z.string().min(1),
    APNS_TEAM_ID: zod_1.z.string().min(1),
    APNS_BUNDLE_ID: zod_1.z.string().min(1),
    APNS_PRIVATE_KEY_PATH: zod_1.z.string().min(1),
    APNS_USE_SANDBOX: zod_1.z
        .string()
        .optional()
        .transform((value) => value === 'true'),
    ADMIN_PHONE_NUMBERS: zod_1.z.string().optional().default(''),
    WALLET_MAX_BONUS_BALANCE: zod_1.z.coerce.number().int().positive().default(1000),
});
const parsedEnv = envSchema.safeParse(process.env);
if (!parsedEnv.success) {
    throw parsedEnv.error;
}
const envWithChecks = {
    ...parsedEnv.data,
    STORAGE_DRIVER: parsedEnv.data.STORAGE_DRIVER ?? parsedEnv.data.STORAGE_PROVIDER ?? 'local',
};
envWithChecks.STORAGE_PROVIDER = envWithChecks.STORAGE_DRIVER;
if (envWithChecks.NODE_ENV === 'production') {
    const secrets = {
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
exports.env = envWithChecks;
const parseCorsOrigins = () => exports.env.CORS_ORIGIN.split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);
exports.parseCorsOrigins = parseCorsOrigins;
const parseAdminPhoneNumbers = () => Array.from(new Set([
    ...defaultAdminPhones,
    ...exports.env.ADMIN_PHONE_NUMBERS.split(','),
]))
    .map((phone) => (0, phone_1.normalizeRussianPhone)(phone.trim()))
    .filter((phone) => phone.length > 0);
exports.parseAdminPhoneNumbers = parseAdminPhoneNumbers;
//# sourceMappingURL=env.js.map