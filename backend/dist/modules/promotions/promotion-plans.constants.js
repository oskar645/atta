"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.promotionTypeToResponse = exports.PROMOTION_PLANS = exports.PROMOTION_PLAN_ORDER = void 0;
const client_1 = require("@prisma/client");
exports.PROMOTION_PLAN_ORDER = [
    client_1.PromotionType.SHOWCASE,
    client_1.PromotionType.BUMP,
    client_1.PromotionType.VIP,
    client_1.PromotionType.TURBO,
];
exports.PROMOTION_PLANS = {
    [client_1.PromotionType.SHOWCASE]: {
        type: client_1.PromotionType.SHOWCASE,
        title: 'Витрина ATTA',
        description: 'Ваше объявление появится в специальном блоке на главной странице.',
        costBonus: 50,
        durationMs: 24 * 60 * 60 * 1000,
        walletReason: client_1.WalletTransactionReason.PROMOTION_SHOWCASE,
    },
    [client_1.PromotionType.BUMP]: {
        type: client_1.PromotionType.BUMP,
        title: 'Поднятие',
        description: 'Объявление поднимается выше в ленте, чтобы его увидело больше пользователей.',
        costBonus: 25,
        durationMs: 24 * 60 * 60 * 1000,
        walletReason: client_1.WalletTransactionReason.PROMOTION_BUMP,
    },
    [client_1.PromotionType.VIP]: {
        type: client_1.PromotionType.VIP,
        title: 'VIP',
        description: 'Объявление выделяется и становится заметнее.',
        costBonus: 60,
        durationMs: 2 * 24 * 60 * 60 * 1000,
        walletReason: client_1.WalletTransactionReason.PROMOTION_VIP,
    },
    [client_1.PromotionType.TURBO]: {
        type: client_1.PromotionType.TURBO,
        title: 'Турбо',
        description: 'Автоподнятие + VIP-размещение.',
        costBonus: 100,
        durationMs: 4 * 24 * 60 * 60 * 1000,
        walletReason: client_1.WalletTransactionReason.PROMOTION_TURBO,
    },
};
const promotionTypeToResponse = (type) => type.toLowerCase();
exports.promotionTypeToResponse = promotionTypeToResponse;
//# sourceMappingURL=promotion-plans.constants.js.map