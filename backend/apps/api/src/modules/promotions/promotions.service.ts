import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  ListingStatus,
  Prisma,
  Promotion,
  PromotionStatus,
  PromotionType,
} from '@prisma/client';

import { serializeListing, toIsoString } from '../../common/serializers';
import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import { WalletService } from '../wallet/wallet.service';
import {
  PROMOTION_PLAN_ORDER,
  PROMOTION_PLANS,
  promotionTypeToResponse,
} from './promotion-plans.constants';

const promotableStatuses = new Set<ListingStatus>([
  ListingStatus.APPROVED,
]);

const listingInclude = {
  owner: {
    include: {
      adminProfile: true,
    },
  },
  photos: {
    orderBy: {
      sortOrder: 'asc',
    },
  },
  promotions: {
    where: {
      status: PromotionStatus.ACTIVE,
    },
    orderBy: {
      createdAt: 'desc',
    },
  },
} satisfies Prisma.ListingInclude;

@Injectable()
export class PromotionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly walletService: WalletService,
  ) {}

  getPlans() {
    return {
      items: PROMOTION_PLAN_ORDER.map((type) => {
        const plan = PROMOTION_PLANS[type];
        return {
          type: promotionTypeToResponse(plan.type),
          title: plan.title,
          description: plan.description,
          costBonus: plan.costBonus,
          durationHours: Math.floor(plan.durationMs / (60 * 60 * 1000)),
        };
      }),
    };
  }

  async getListingPromotions(listingId: string, authUser: AuthenticatedUser) {
    const listing = await this.prisma.listing.findUnique({
      where: {
        id: listingId,
      },
      include: listingInclude,
    });

    if (!listing) {
      throw new NotFoundException('Listing not found');
    }

    return {
      listing_id: listing.id,
      promotions: this.buildPromotionFlags(listing.promotions),
      canPromote: this.canPromoteListing(listing, authUser),
      cannotPromoteReason: this.getCannotPromoteReason(listing, authUser),
      cannotPromoteCode: this.getCannotPromoteCode(listing, authUser),
    };
  }

  async promoteListing(
    listingId: string,
    authUser: AuthenticatedUser,
    inputType: string,
  ) {
    const type = this.parsePromotionType(inputType);
    const plan = PROMOTION_PLANS[type];
    const listing = await this.prisma.listing.findUnique({
      where: {
        id: listingId,
      },
      include: listingInclude,
    });

    if (!listing) {
      throw new NotFoundException('Listing not found');
    }

    const cannotPromoteReason = this.getCannotPromoteReason(listing, authUser);
    if (cannotPromoteReason) {
      throw new BadRequestException(cannotPromoteReason);
    }

    await this.expireStalePromotionsForListing(listing.id);

    const activePromotion = await this.prisma.promotion.findFirst({
      where: {
        listingId,
        userId: authUser.userId,
        type,
        status: PromotionStatus.ACTIVE,
        endsAt: {
          gt: new Date(),
        },
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    if (activePromotion) {
      const freshListing = await this.prisma.listing.findUniqueOrThrow({
        where: {
          id: listingId,
        },
        include: listingInclude,
      });

      return {
        message:
          type === PromotionType.SHOWCASE
            ? 'Витрина ATTA уже активна'
            : `${plan.title} уже активно`,
        listing: serializeListing(freshListing),
        promotion: this.serializePromotion(activePromotion),
        walletBalance: (await this.walletService.getWallet(authUser)).balance,
      };
    }

    const wallet = await this.walletService.ensureWalletAndBonuses(authUser.userId);
    if (wallet.bonusBalance < plan.costBonus) {
      throw new BadRequestException({
        message: 'Недостаточно бонусов',
        currentBalance: wallet.bonusBalance,
        requiredBalance: plan.costBonus,
      });
    }

    const walletReason = await this.walletService.resolveSpendReason(
      plan.walletReason,
    );

    const { promotion, updatedWallet, alreadyActive } = await this.prisma.$transaction(
      async (tx) => {
        await tx.$executeRaw`
          SELECT pg_advisory_xact_lock(
            hashtext(${`${listingId}:${type}`})
          )
        `;

        await tx.promotion.updateMany({
          where: {
            listingId,
            status: PromotionStatus.ACTIVE,
            endsAt: {
              lte: new Date(),
            },
          },
          data: {
            status: PromotionStatus.EXPIRED,
          },
        });

        const existingPromotion = await tx.promotion.findFirst({
          where: {
            listingId,
            userId: authUser.userId,
            type,
            status: PromotionStatus.ACTIVE,
            endsAt: {
              gt: new Date(),
            },
          },
          orderBy: {
            createdAt: 'desc',
          },
        });

        if (existingPromotion) {
          return {
            promotion: existingPromotion,
            updatedWallet: await tx.wallet.findUniqueOrThrow({
              where: {
                userId: authUser.userId,
              },
            }),
            alreadyActive: true,
          };
        }

        const updatedWallet = await this.walletService.spendBonus(
          authUser.userId,
          plan.costBonus,
          walletReason,
          {
            listingId,
            promotionType: promotionTypeToResponse(type),
            requestedWalletReason: plan.walletReason.toLowerCase(),
            walletReasonFallbackApplied: walletReason !== plan.walletReason,
          },
          tx,
        );

        const now = new Date();
        const endsAt = new Date(now.getTime() + plan.durationMs);
        const promotion = await tx.promotion.create({
          data: {
            listingId,
            userId: authUser.userId,
            type,
            costBonus: plan.costBonus,
            startsAt: now,
            endsAt,
            status: PromotionStatus.ACTIVE,
          },
        });

        return {
          promotion,
          updatedWallet,
          alreadyActive: false,
        };
      },
    );

    const freshListing = await this.prisma.listing.findUniqueOrThrow({
      where: {
        id: listingId,
      },
      include: listingInclude,
    });

    return {
      message:
        alreadyActive
          ? promotion.type === PromotionType.SHOWCASE
            ? 'Витрина ATTA уже активна'
            : `${plan.title} уже активно`
          : promotion.type === PromotionType.SHOWCASE
            ? 'Объявление добавлено в Витрину ATTA'
            : `${plan.title} активировано`,
      listing: serializeListing(freshListing),
      promotion: this.serializePromotion(promotion),
      walletBalance: updatedWallet.bonusBalance,
    };
  }

  async getShowcase() {
    await this.expirePromotionsByTime();

    const promotions = await this.prisma.promotion.findMany({
      where: {
        type: PromotionType.SHOWCASE,
        status: PromotionStatus.ACTIVE,
        endsAt: {
          gt: new Date(),
        },
        listing: {
          status: ListingStatus.APPROVED,
          deletedAt: null,
          archivedAt: null,
        },
      },
      include: {
        listing: {
          include: {
            owner: true,
            photos: {
              orderBy: {
                sortOrder: 'asc',
              },
            },
          },
        },
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    const uniquePromotions = promotions.filter((promotion, index, items) =>
      items.findIndex((candidate) => candidate.listingId === promotion.listingId) === index,
    );
    const sellerIds = [
      ...new Set(uniquePromotions.map((promotion) => promotion.listing.ownerId)),
    ];
    const groupedRatings = sellerIds.length
      ? await this.prisma.review.groupBy({
          by: ['sellerId'],
          where: {
            sellerId: {
              in: sellerIds,
            },
            deletedAt: null,
          },
          _avg: {
            rating: true,
          },
        })
      : [];
    const ratingsBySellerId = new Map(
      groupedRatings.map((entry) => [entry.sellerId, entry._avg.rating]),
    );

    return {
      items: uniquePromotions.map((promotion) => ({
        promotionId: promotion.id,
        listingId: promotion.listingId,
        title: promotion.listing.title,
        price: Number(promotion.listing.price),
        city: promotion.listing.city,
        firstPhotoUrl: promotion.listing.photos[0]?.publicUrl ?? null,
        sellerId: promotion.listing.ownerId,
        sellerName:
          promotion.listing.owner.displayName ||
          promotion.listing.owner.name ||
          promotion.listing.ownerName,
        sellerAvatarUrl:
          promotion.listing.owner.avatarUrl ??
          promotion.listing.owner.photoUrl ??
          null,
        sellerRating:
          ratingsBySellerId.get(promotion.listing.ownerId) == null
            ? null
            : Number(ratingsBySellerId.get(promotion.listing.ownerId)?.toFixed(2)),
        category: promotion.listing.category,
        startsAt: promotion.startsAt.toISOString(),
        endsAt: promotion.endsAt.toISOString(),
        impressionsCount: promotion.impressionsCount,
        clicksCount: promotion.clicksCount,
      })),
    };
  }

  async registerImpression(promotionId: string) {
    return this.bumpMetric(promotionId, 'impressionsCount');
  }

  async registerClick(promotionId: string) {
    return this.bumpMetric(promotionId, 'clicksCount');
  }

  async expirePromotionsByTime() {
    await this.prisma.promotion.updateMany({
      where: {
        status: PromotionStatus.ACTIVE,
        endsAt: {
          lte: new Date(),
        },
      },
      data: {
        status: PromotionStatus.EXPIRED,
      },
    });
  }

  enrichListing<T extends { id: string; ownerId: string; status: ListingStatus; deletedAt: Date | null; archivedAt: Date | null; promotions?: Promotion[] }>(
    listing: T,
    authUser?: AuthenticatedUser,
  ) {
    return {
      promotions: this.buildPromotionFlags(listing.promotions ?? []),
      canPromote: authUser ? this.canPromoteListing(listing, authUser) : false,
      cannotPromoteReason: authUser
        ? this.getCannotPromoteReason(listing, authUser)
        : 'Требуется авторизация',
      cannotPromoteCode: authUser
        ? this.getCannotPromoteCode(listing, authUser)
        : 'not_authenticated',
    };
  }

  private async expireStalePromotionsForListing(listingId: string) {
    await this.prisma.promotion.updateMany({
      where: {
        listingId,
        status: PromotionStatus.ACTIVE,
        endsAt: {
          lte: new Date(),
        },
      },
      data: {
        status: PromotionStatus.EXPIRED,
      },
    });
  }

  private canPromoteListing(
    listing: Pick<Prisma.ListingGetPayload<{ include: typeof listingInclude }>, 'ownerId' | 'status' | 'deletedAt' | 'archivedAt'>,
    authUser: AuthenticatedUser,
  ) {
    return this.getCannotPromoteCode(listing, authUser) == null;
  }

  private getCannotPromoteCode(
    listing: Pick<Prisma.ListingGetPayload<{ include: typeof listingInclude }>, 'ownerId' | 'status' | 'deletedAt' | 'archivedAt'>,
    authUser: AuthenticatedUser,
  ) {
    if (listing.ownerId !== authUser.userId) {
      return 'not_owner';
    }

    if (listing.deletedAt || listing.status === ListingStatus.DELETED) {
      return 'deleted';
    }

    if (listing.archivedAt || listing.status === ListingStatus.ARCHIVED) {
      return 'archived';
    }

    switch (listing.status) {
      case ListingStatus.PENDING:
        return 'pending';
      case ListingStatus.REJECTED:
        return 'rejected';
      case ListingStatus.SOLD:
        return 'sold';
      default:
        break;
    }

    if (!promotableStatuses.has(listing.status)) {
      return 'unpublished';
    }

    return null;
  }

  private getCannotPromoteReason(
    listing: Pick<Prisma.ListingGetPayload<{ include: typeof listingInclude }>, 'ownerId' | 'status' | 'deletedAt' | 'archivedAt'>,
    authUser: AuthenticatedUser,
  ) {
    switch (this.getCannotPromoteCode(listing, authUser)) {
      case 'not_owner':
        return 'Продвижение доступно только владельцу объявления.';
      case 'deleted':
        return 'Удалённые объявления нельзя продвигать.';
      case 'archived':
        return 'Архивные объявления нельзя продвигать.';
      case 'pending':
        return 'Объявление пока на модерации.';
      case 'rejected':
        return 'Отклонённые объявления нельзя продвигать.';
      case 'sold':
        return 'Проданное объявление нельзя продвигать.';
      case 'unpublished':
        return 'Это объявление сейчас нельзя продвигать.';
      default:
        return null;
    }
  }

  private buildPromotionFlags(promotions: Promotion[]) {
    const activeByType = new Map<PromotionType, Promotion>();

    for (const promotion of promotions) {
      if (
        promotion.status === PromotionStatus.ACTIVE &&
        promotion.endsAt.getTime() > Date.now() &&
        !activeByType.has(promotion.type)
      ) {
        activeByType.set(promotion.type, promotion);
      }
    }

    return {
      activeShowcase: this.serializePromotion(
        activeByType.get(PromotionType.SHOWCASE),
      ),
      activeBump: this.serializePromotion(activeByType.get(PromotionType.BUMP)),
      activeVip: this.serializePromotion(activeByType.get(PromotionType.VIP)),
      activeTurbo: this.serializePromotion(activeByType.get(PromotionType.TURBO)),
    };
  }

  private serializePromotion(promotion?: Promotion | null) {
    if (!promotion) {
      return null;
    }

    const plan = PROMOTION_PLANS[promotion.type];
    return {
      id: promotion.id,
      type: promotionTypeToResponse(promotion.type),
      title: plan.title,
      endsAt: toIsoString(promotion.endsAt),
      startsAt: toIsoString(promotion.startsAt),
      status: promotion.status.toLowerCase(),
      costBonus: promotion.costBonus,
      impressionsCount: promotion.impressionsCount,
      clicksCount: promotion.clicksCount,
    };
  }

  private parsePromotionType(inputType: string) {
    switch (inputType.trim().toLowerCase()) {
      case 'showcase':
        return PromotionType.SHOWCASE;
      case 'bump':
        return PromotionType.BUMP;
      case 'vip':
        return PromotionType.VIP;
      case 'turbo':
        return PromotionType.TURBO;
      default:
        throw new BadRequestException('Unsupported promotion type');
    }
  }

  private async bumpMetric(
    promotionId: string,
    field: 'impressionsCount' | 'clicksCount',
  ) {
    const promotion = await this.prisma.promotion.findUnique({
      where: {
        id: promotionId,
      },
    });

    if (!promotion) {
      return { ok: true };
    }

    if (
      promotion.status !== PromotionStatus.ACTIVE ||
      promotion.endsAt.getTime() <= Date.now()
    ) {
      if (
        promotion.status === PromotionStatus.ACTIVE &&
        promotion.endsAt.getTime() <= Date.now()
      ) {
        await this.prisma.promotion.update({
          where: {
            id: promotionId,
          },
          data: {
            status: PromotionStatus.EXPIRED,
          },
        });
      }

      return { ok: true };
    }

    const updated = await this.prisma.promotion.update({
      where: {
        id: promotionId,
      },
      data: {
        [field]: {
          increment: 1,
        },
      },
    });

    return {
      ok: true,
      promotionId: updated.id,
      impressionsCount: updated.impressionsCount,
      clicksCount: updated.clicksCount,
    };
  }
}
