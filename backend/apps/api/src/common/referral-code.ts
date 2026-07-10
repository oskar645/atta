import { createCipheriv, createDecipheriv, createHash } from 'crypto';

import { env } from '../config/env';

const REFERRAL_ALGORITHM = 'aes-256-gcm';
const REFERRAL_IV_LENGTH = 12;
const REFERRAL_TAG_LENGTH = 16;

const referralKey = createHash('sha256')
  .update(`atta-referral:${env.JWT_ACCESS_SECRET}`)
  .digest();

const buildReferralIv = (userId: string) =>
  createHash('sha256')
    .update(`atta-referral-iv:${userId}:${env.JWT_ACCESS_SECRET}`)
    .digest()
    .subarray(0, REFERRAL_IV_LENGTH);

const toBase64Url = (value: Buffer) =>
  value
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');

const fromBase64Url = (value: string) => {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const remainder = normalized.length % 4;
  const padded =
    remainder == 0
      ? normalized
      : normalized.padEnd(normalized.length + (4 - remainder), '=');
  return Buffer.from(padded, 'base64');
};

export const buildReferralCode = (userId: string) => {
  const normalizedUserId = userId.trim();
  if (!normalizedUserId) {
    return '';
  }

  const iv = buildReferralIv(normalizedUserId);
  const cipher = createCipheriv(REFERRAL_ALGORITHM, referralKey, iv);
  const encrypted = Buffer.concat([
    cipher.update(normalizedUserId, 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return toBase64Url(Buffer.concat([iv, tag, encrypted]));
};

export const resolveReferralUserId = (referralCode: string) => {
  const normalizedCode = referralCode.trim();
  if (!normalizedCode) {
    return null;
  }

  try {
    const payload = fromBase64Url(normalizedCode);
    if (payload.length <= REFERRAL_IV_LENGTH + REFERRAL_TAG_LENGTH) {
      return null;
    }

    const iv = payload.subarray(0, REFERRAL_IV_LENGTH);
    const tag = payload.subarray(
      REFERRAL_IV_LENGTH,
      REFERRAL_IV_LENGTH + REFERRAL_TAG_LENGTH,
    );
    const encrypted = payload.subarray(REFERRAL_IV_LENGTH + REFERRAL_TAG_LENGTH);
    const decipher = createDecipheriv(REFERRAL_ALGORITHM, referralKey, iv);
    decipher.setAuthTag(tag);
    const decrypted = Buffer.concat([
      decipher.update(encrypted),
      decipher.final(),
    ]);
    const userId = decrypted.toString('utf8').trim();
    return userId || null;
  } catch {
    return null;
  }
};
