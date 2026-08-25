import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import {
  ListingRaiseCampaignStatus,
  ListingStatus,
  Prisma,
  Promotion,
  PromotionStatus,
  PromotionType,
  UserStatus,
} from '@prisma/client';
import { createHash } from 'crypto';

import { buildListingSearchWhere } from '../../common/listing-search';
import { serializeListing, toIsoString } from '../../common/serializers';
import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { WalletService } from '../wallet/wallet.service';
import {
  PROMOTION_PLAN_ORDER,
  PROMOTION_PLANS,
  promotionTypeToResponse,
} from './promotion-plans.constants';

const promotableStatuses = new Set<ListingStatus>([
  ListingStatus.APPROVED,
]);
const MIN_RAISE_DAYS = 1;
const MAX_RAISE_DAYS = 30;
const MIN_PROMOTION_QUANTITY = 1;
const MAX_PROMOTION_QUANTITY = 30;
const RAISE_INTERVAL_MS = 24 * 60 * 60 * 1000;
const RAISE_WORKER_INTERVAL_MS = 60 * 1000;
const RAISE_WORKER_BATCH_SIZE = 10;
const SHOWCASE_IMPRESSION_DEBOUNCE_MS = 30 * 1000;
const SHOWCASE_CLICK_DEBOUNCE_MS = 5 * 1000;

type PromoteListingInput = {
  type: string;
  days?: number;
  idempotencyKey?: string;
};
type CounterSource = { ip?: string; userAgent?: string };
type ShowcaseCursorPayload = {
  createdAt: string;
  id: string;
};

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

const encodeShowcaseCursor = (
  promotion: Pick<Promotion, 'createdAt' | 'id'>,
) =>
  Buffer.from(
    JSON.stringify({
      createdAt: promotion.createdAt.toISOString(),
      id: promotion.id,
    } satisfies ShowcaseCursorPayload),
  ).toString('base64url');

const parseShowcaseCursor = (
  rawCursor?: string,
): ShowcaseCursorPayload | null => {
  const cursor = rawCursor?.trim() ?? '';
  if (!cursor) {
    return null;
  }

  try {
    const parsed = JSON.parse(
      Buffer.from(cursor, 'base64url').toString('utf8'),
    ) as Partial<ShowcaseCursorPayload>;
    if (
      typeof parsed.createdAt !== 'string' ||
      typeof parsed.id !== 'string' ||
      parsed.createdAt.trim().length === 0 ||
      parsed.id.trim().length === 0
    ) {
      return null;
    }
    return {
      createdAt: parsed.createdAt,
      id: parsed.id,
    };
  } catch {
    return null;
  }
};

@Injectable()
export class PromotionsService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PromotionsService.name);
  private workerTimer: NodeJS.Timeout | null = null;
  private workerRunning = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly walletService: WalletService,
    private readonly rateLimitService: RateLimitService,
  ) {}

  onModuleInit() {
    this.workerTimer = setInterval(() => {
      void this.processDueRaiseCampaigns().catch((error) => {
        this.logger.error(
          `Listing raise worker failed: ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
      });
    }, RAISE_WORKER_INTERVAL_MS);
    this.workerTimer.unref?.();
  }

  onModuleDestroy() {
    if (this.workerTimer) {
      clearInterval(this.workerTimer);
      this.workerTimer = null;
    }
  }

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
    input: string | PromoteListingInput,
  ) {
    const inputType = typeof input === 'string' ? input : input.type;
    const type = this.parsePromotionType(inputType);
    const plan = PROMOTION_PLANS[type];
    const quantity = this.parsePromotionQuantity(
      type,
      typeof input === 'string' ? undefined : input.days,
    );
    const requestIdempotencyKey =
      typeof input === 'string' ? undefined : input.idempotencyKey;
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

    if (type === PromotionType.BUMP) {
      return this.purchaseRaiseCampaign({
        listingId,
        authUser,
        days: quantity,
        requestIdempotencyKey,
      });
    }

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
      orderBy: [
        {
          createdAt: 'desc',
        },
        {
          id: 'desc',
        },
      ],
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
    const totalPrice = plan.costBonus * quantity;
    if (wallet.bonusBalance < totalPrice) {
      throw new BadRequestException({
        message: 'Недостаточно бонусов',
        currentBalance: wallet.bonusBalance,
        requiredBalance: totalPrice,
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
          totalPrice,
          walletReason,
          {
            listingId,
            promotionType: promotionTypeToResponse(type),
            quantity,
            pricePerPeriod: plan.costBonus,
            totalPrice,
            requestedWalletReason: plan.walletReason.toLowerCase(),
            walletReasonFallbackApplied: walletReason !== plan.walletReason,
          },
          tx,
        );

        const now = new Date();
        const endsAt = new Date(now.getTime() + plan.durationMs * quantity);
        const promotion = await tx.promotion.create({
          data: {
            listingId,
            userId: authUser.userId,
            type,
            costBonus: totalPrice,
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

  async processDueRaiseCampaigns(now = new Date()) {
    if (this.workerRunning) {
      return { processed: 0 };
    }
    this.workerRunning = true;
    let processed = 0;
    try {
      const dueCampaigns = await this.prisma.listingRaiseCampaign.findMany({
        where: {
          status: ListingRaiseCampaignStatus.ACTIVE,
          nextRaiseAt: {
            lte: now,
          },
        },
        orderBy: {
          nextRaiseAt: 'asc',
        },
        take: RAISE_WORKER_BATCH_SIZE,
      });

      for (const campaign of dueCampaigns) {
        const didProcess = await this.processOneRaiseCampaign(campaign.id, now);
        if (didProcess) {
          processed += 1;
        }
      }
      return { processed };
    } finally {
      this.workerRunning = false;
    }
  }

  async getShowcase(params?: {
    limit?: number;
    cursor?: string;
    category?: string;
    search?: string;
  }) {
    await this.expirePromotionsByTime();

    const limit =
      params?.limit == null ? null : Math.max(1, Math.min(params.limit, 50));
    const category = params?.category?.trim();
    const search = params?.search?.trim();
    const cursor = parseShowcaseCursor(params?.cursor);
    const cursorDate = cursor ? new Date(cursor.createdAt) : null;
    const cursorId = cursor?.id;
    const cursorWhere =
      cursorDate != null &&
      cursorId != null &&
      !Number.isNaN(cursorDate.getTime())
        ? {
            OR: [
              {
                createdAt: {
                  lt: cursorDate,
                },
              },
              {
                createdAt: cursorDate,
                id: {
                  lt: cursorId,
                },
              },
            ],
          }
        : {};
    const listingAndConditions: Prisma.ListingWhereInput[] = [];
    const searchWhere = buildListingSearchWhere(search);
    if (searchWhere != null) {
      listingAndConditions.push(searchWhere);
    }

    const promotions = await this.prisma.promotion.findMany({
      where: {
        type: PromotionType.SHOWCASE,
        status: PromotionStatus.ACTIVE,
        endsAt: {
          gt: new Date(),
        },
        ...cursorWhere,
        listing: {
          status: ListingStatus.APPROVED,
          deletedAt: null,
          archivedAt: null,
          photos: {
            some: {},
          },
          owner: {
            deletedAt: null,
            status: UserStatus.ACTIVE,
          },
          ...(category && category.toLowerCase() !== 'все'
            ? { category }
            : {}),
          ...(listingAndConditions.length > 0
            ? { AND: listingAndConditions }
            : {}),
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
      ...(limit == null ? {} : { take: limit + 1 }),
    });

    const uniquePromotions = promotions.filter((promotion, index, items) =>
      items.findIndex((candidate) => candidate.listingId === promotion.listingId) === index,
    );
    const pageItems = limit == null ? uniquePromotions : uniquePromotions.slice(0, limit);
    const hasMore = limit != null && uniquePromotions.length > limit;
    const nextCursor =
      hasMore && pageItems.length > 0
        ? encodeShowcaseCursor(pageItems[pageItems.length - 1]!)
        : null;
    const sellerIds = [
      ...new Set(pageItems.map((promotion) => promotion.listing.ownerId)),
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
      items: pageItems.map((promotion) => ({
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
      nextCursor,
      hasMore,
    };
  }

  async registerImpression(promotionId: string, source?: CounterSource) {
    const shouldCount = await this.shouldCountCounterEvent(
      'impression',
      promotionId,
      source,
      SHOWCASE_IMPRESSION_DEBOUNCE_MS,
    );
    return shouldCount
      ? this.bumpMetric(promotionId, 'impressionsCount')
      : { ok: true };
  }

  async registerClick(promotionId: string, source?: CounterSource) {
    const shouldCount = await this.shouldCountCounterEvent(
      'click',
      promotionId,
      source,
      SHOWCASE_CLICK_DEBOUNCE_MS,
    );
    return shouldCount ? this.bumpMetric(promotionId, 'clicksCount') : { ok: true };
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

  private async purchaseRaiseCampaign(params: {
    listingId: string;
    authUser: AuthenticatedUser;
    days: number;
    requestIdempotencyKey?: string;
  }) {
    const { listingId, authUser, days } = params;
    const plan = PROMOTION_PLANS[PromotionType.BUMP];
    const totalPrice = plan.costBonus * days;
    const idempotencyKey = this.buildRaisePurchaseIdempotencyKey(
      authUser.userId,
      listingId,
      days,
      params.requestIdempotencyKey,
    );

    const existingCampaign = await this.prisma.listingRaiseCampaign.findUnique({
      where: {
        idempotencyKey,
      },
    });
    if (existingCampaign) {
      const freshListing = await this.prisma.listing.findUniqueOrThrow({
        where: {
          id: listingId,
        },
        include: listingInclude,
      });
      return {
        message: `Поднятие подключено на ${existingCampaign.purchasedRaises} ${this.dayWord(existingCampaign.purchasedRaises)}`,
        listing: serializeListing(freshListing),
        promotion: this.serializePromotion(
          await this.prisma.promotion.findFirst({
            where: {
              listingId,
              userId: authUser.userId,
              type: PromotionType.BUMP,
              status: PromotionStatus.ACTIVE,
            },
            orderBy: {
              createdAt: 'desc',
            },
          }),
        ),
        walletBalance: (await this.walletService.getWallet(authUser)).balance,
        days: existingCampaign.purchasedRaises,
      };
    }

    const wallet = await this.walletService.ensureWalletAndBonuses(authUser.userId);
    if (wallet.bonusBalance < totalPrice) {
      throw new BadRequestException({
        message: 'Недостаточно бонусов',
        currentBalance: wallet.bonusBalance,
        requiredBalance: totalPrice,
      });
    }

    const walletReason = await this.walletService.resolveSpendReason(
      plan.walletReason,
    );

    const { promotion, updatedWallet } = await this.prisma.$transaction(
      async (tx) => {
        await tx.$executeRaw`
          SELECT pg_advisory_xact_lock(
            hashtext(${`raise:${authUser.userId}:${listingId}:${idempotencyKey}`})
          )
        `;

        const existing = await tx.listingRaiseCampaign.findUnique({
          where: {
            idempotencyKey,
          },
        });
        if (existing) {
          return {
            promotion: await tx.promotion.findFirst({
              where: {
                listingId,
                userId: authUser.userId,
                type: PromotionType.BUMP,
                status: PromotionStatus.ACTIVE,
              },
              orderBy: {
                createdAt: 'desc',
              },
            }),
            updatedWallet: await tx.wallet.findUniqueOrThrow({
              where: {
                userId: authUser.userId,
              },
            }),
          };
        }

        const lockedListing = await tx.listing.findUnique({
          where: {
            id: listingId,
          },
          select: {
            id: true,
            ownerId: true,
            status: true,
            deletedAt: true,
            archivedAt: true,
          },
        });
        if (!lockedListing) {
          throw new NotFoundException('Listing not found');
        }
        const cannotPromoteReason = this.getCannotPromoteReason(
          lockedListing,
          authUser,
        );
        if (cannotPromoteReason) {
          throw new BadRequestException(cannotPromoteReason);
        }

        const updatedWallet = await this.walletService.spendBonus(
          authUser.userId,
          totalPrice,
          walletReason,
          {
            listingId,
            promotionType: promotionTypeToResponse(PromotionType.BUMP),
            days,
            pricePerRaise: plan.costBonus,
            totalPrice,
            requestedWalletReason: plan.walletReason.toLowerCase(),
            walletReasonFallbackApplied: walletReason !== plan.walletReason,
          },
          tx,
          `promotion_raise:${idempotencyKey}`,
        );

        const now = new Date();
        const promotion = await this.createBumpPromotion(
          tx,
          listingId,
          authUser.userId,
          plan.costBonus,
          now,
        );

        await tx.listingRaiseCampaign.create({
          data: {
            listingId,
            userId: authUser.userId,
            purchasedRaises: days,
            completedRaises: 1,
            pricePerRaise: plan.costBonus,
            totalPrice,
            startedAt: now,
            lastRaiseAt: now,
            nextRaiseAt:
              days > 1 ? new Date(now.getTime() + RAISE_INTERVAL_MS) : null,
            status:
              days > 1
                ? ListingRaiseCampaignStatus.ACTIVE
                : ListingRaiseCampaignStatus.COMPLETED,
            idempotencyKey,
          },
        });

        return {
          promotion,
          updatedWallet,
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
      message: `Поднятие подключено на ${days} ${this.dayWord(days)}`,
      listing: serializeListing(freshListing),
      promotion: this.serializePromotion(promotion),
      walletBalance: updatedWallet.bonusBalance,
      days,
    };
  }

  private async processOneRaiseCampaign(campaignId: string, now: Date) {
    return this.prisma.$transaction(async (tx) => {
      const locked = await tx.$queryRaw<Array<{ id: string }>>`
        SELECT "id"
        FROM "listing_raise_campaigns"
        WHERE "id" = ${campaignId}::uuid
          AND "status" = 'ACTIVE'::"ListingRaiseCampaignStatus"
          AND "next_raise_at" <= ${now}
        FOR UPDATE SKIP LOCKED
      `;
      if (locked.length === 0) {
        return false;
      }

      const campaign = await tx.listingRaiseCampaign.findUnique({
        where: {
          id: campaignId,
        },
      });
      if (
        !campaign ||
        campaign.status !== ListingRaiseCampaignStatus.ACTIVE ||
        campaign.nextRaiseAt == null ||
        campaign.nextRaiseAt.getTime() > now.getTime()
      ) {
        return false;
      }

      const listing = await tx.listing.findUnique({
        where: {
          id: campaign.listingId,
        },
        select: {
          id: true,
          ownerId: true,
          status: true,
          deletedAt: true,
          archivedAt: true,
        },
      });
      if (
        !listing ||
        listing.ownerId !== campaign.userId ||
        this.getCannotPromoteCode(listing, {
          userId: campaign.userId,
          sessionId: '',
          role: 'user',
        }) != null
      ) {
        await tx.listingRaiseCampaign.update({
          where: {
            id: campaign.id,
          },
          data: {
            status: ListingRaiseCampaignStatus.CANCELLED,
            nextRaiseAt: null,
            cancelReason: 'listing_not_promotable',
          },
        });
        return true;
      }

      await this.createBumpPromotion(
        tx,
        campaign.listingId,
        campaign.userId,
        campaign.pricePerRaise,
        campaign.nextRaiseAt,
      );

      const completedRaises = campaign.completedRaises + 1;
      const hasMore = completedRaises < campaign.purchasedRaises;
      await tx.listingRaiseCampaign.update({
        where: {
          id: campaign.id,
        },
        data: {
          completedRaises,
          lastRaiseAt: campaign.nextRaiseAt,
          nextRaiseAt: hasMore
            ? new Date(campaign.nextRaiseAt.getTime() + RAISE_INTERVAL_MS)
            : null,
          status: hasMore
            ? ListingRaiseCampaignStatus.ACTIVE
            : ListingRaiseCampaignStatus.COMPLETED,
          cancelReason: null,
        },
      });

      return true;
    });
  }

  private async createBumpPromotion(
    tx: Prisma.TransactionClient,
    listingId: string,
    userId: string,
    costBonus: number,
    startsAt: Date,
  ) {
    return tx.promotion.create({
      data: {
        listingId,
        userId,
        type: PromotionType.BUMP,
        costBonus,
        startsAt,
        endsAt: new Date(startsAt.getTime() + RAISE_INTERVAL_MS),
        status: PromotionStatus.ACTIVE,
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

  private parsePromotionQuantity(type: PromotionType, rawQuantity?: number) {
    if (
      type !== PromotionType.BUMP &&
      type !== PromotionType.SHOWCASE &&
      type !== PromotionType.VIP
    ) {
      return 1;
    }
    const quantity = rawQuantity ?? 1;
    const min =
      type === PromotionType.BUMP ? MIN_RAISE_DAYS : MIN_PROMOTION_QUANTITY;
    const max =
      type === PromotionType.BUMP ? MAX_RAISE_DAYS : MAX_PROMOTION_QUANTITY;
    if (!Number.isInteger(quantity) || quantity < min || quantity > max) {
      throw new BadRequestException('days must be an integer from 1 to 30');
    }
    return quantity;
  }

  private buildRaisePurchaseIdempotencyKey(
    userId: string,
    listingId: string,
    days: number,
    requestIdempotencyKey?: string,
  ) {
    const requestKey = requestIdempotencyKey?.trim();
    if (requestKey && requestKey.length <= 120) {
      return `raise_purchase:${userId}:${requestKey}`;
    }
    return `raise_purchase:${userId}:${listingId}:${days}:${Date.now()}`;
  }

  private dayWord(days: number) {
    const mod100 = days % 100;
    const mod10 = days % 10;
    if (mod100 >= 11 && mod100 <= 14) {
      return 'дней';
    }
    if (mod10 === 1) {
      return 'день';
    }
    if (mod10 >= 2 && mod10 <= 4) {
      return 'дня';
    }
    return 'дней';
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

  private shouldCountCounterEvent(
    event: 'impression' | 'click',
    promotionId: string,
    source: CounterSource | undefined,
    windowMs: number,
  ) {
    const sourceKey = this.counterSourceKey(source);
    if (!sourceKey) {
      return Promise.resolve(true);
    }
    return this.rateLimitService.debounce(
      `showcase:${event}:${promotionId}:${sourceKey}`,
      windowMs,
    );
  }

  private counterSourceKey(source?: CounterSource) {
    const ip = source?.ip?.trim();
    const userAgent = source?.userAgent?.trim();
    if (!ip && !userAgent) {
      return '';
    }
    return createHash('sha256')
      .update(`${ip || 'unknown'}:${userAgent || 'unknown'}`)
      .digest('hex');
  }
}
