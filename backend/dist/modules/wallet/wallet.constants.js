"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.WALLET_NOW_PROVIDER = exports.WALLET_TIME_ZONE = exports.WALLET_REFERRAL_INVITER_BONUS = exports.WALLET_DAILY_BONUS_AMOUNT = exports.WALLET_WELCOME_BONUS = void 0;
const env_1 = require("../../config/env");
exports.WALLET_WELCOME_BONUS = 500;
exports.WALLET_DAILY_BONUS_AMOUNT = 25;
exports.WALLET_REFERRAL_INVITER_BONUS = 100;
exports.WALLET_TIME_ZONE = env_1.env.WALLET_TIME_ZONE;
exports.WALLET_NOW_PROVIDER = Symbol('WALLET_NOW_PROVIDER');
//# sourceMappingURL=wallet.constants.js.map