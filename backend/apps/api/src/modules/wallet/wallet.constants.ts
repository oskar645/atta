import { env } from '../../config/env';

export const WALLET_WELCOME_BONUS = 200;
export const WALLET_DAILY_BONUS_AMOUNT = 10;
export const WALLET_REFERRAL_INVITER_BONUS = 50;
export const WALLET_TIME_ZONE = env.WALLET_TIME_ZONE;
export const WALLET_NOW_PROVIDER = Symbol('WALLET_NOW_PROVIDER');
