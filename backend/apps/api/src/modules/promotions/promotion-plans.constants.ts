import {
  PromotionType,
  WalletTransactionReason,
} from '@prisma/client';

export const PROMOTION_PLAN_ORDER = [
  PromotionType.SHOWCASE,
  PromotionType.BUMP,
  PromotionType.VIP,
  PromotionType.TURBO,
] as const;

export const PROMOTION_PLANS = {
  [PromotionType.SHOWCASE]: {
    type: PromotionType.SHOWCASE,
    title: 'Витрина ATTA',
    description:
      'Ваше объявление появится в специальном блоке на главной странице.',
    costBonus: 230,
    durationMs: 24 * 60 * 60 * 1000,
    walletReason: WalletTransactionReason.PROMOTION_SHOWCASE,
  },
  [PromotionType.BUMP]: {
    type: PromotionType.BUMP,
    title: 'Поднятие',
    description:
      'Объявление поднимается выше в ленте, чтобы его увидело больше пользователей.',
    costBonus: 35,
    durationMs: 24 * 60 * 60 * 1000,
    walletReason: WalletTransactionReason.PROMOTION_BUMP,
  },
  [PromotionType.VIP]: {
    type: PromotionType.VIP,
    title: 'VIP',
    description: 'Объявление выделяется и становится заметнее.',
    costBonus: 150,
    durationMs: 2 * 24 * 60 * 60 * 1000,
    walletReason: WalletTransactionReason.PROMOTION_VIP,
  },
  [PromotionType.TURBO]: {
    type: PromotionType.TURBO,
    title: 'Турбо',
    description: 'Автоподнятие + VIP-размещение.',
    costBonus: 100,
    durationMs: 4 * 24 * 60 * 60 * 1000,
    walletReason: WalletTransactionReason.PROMOTION_TURBO,
  },
} as const;

export const promotionTypeToResponse = (type: PromotionType) =>
  type.toLowerCase();
