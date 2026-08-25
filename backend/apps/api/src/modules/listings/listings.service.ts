import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  ListingStatus,
  Prisma,
  Promotion,
  PromotionType,
  PromotionStatus,
  UserStatus,
} from '@prisma/client';

import {
  buildListingSearchSql,
  buildListingSearchWhere,
  normalizeOemPartNumber,
} from '../../common/listing-search';
import {
  listingStatusFromInput,
  listingStatusToResponse,
  serializeListing,
} from '../../common/serializers';
import { normalizeRussianPhone, validateRussianPhoneOrThrow } from '../../common/phone';
import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import { PromotionsService } from '../promotions/promotions.service';
import { StorageService } from '../storage/storage.service';
import { UserBlocksService } from '../user-blocks/user-blocks.service';
import { UploadedImageFile } from '../storage/uploaded-image-file.type';
import { CreateListingDto } from './dto/create-listing.dto';
import { ArchiveListingDto } from './dto/archive-listing.dto';
import { UpdateListingDto } from './dto/update-listing.dto';

export { normalizeOemPartNumber } from '../../common/listing-search';

export const listingInclude = {
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

export type ListingWithPublicRelations = Prisma.ListingGetPayload<{
  include: typeof listingInclude;
}>;

export const canViewListing = (
  listing: ListingWithPublicRelations,
  authUser?: AuthenticatedUser,
) => {
  const isAdmin = authUser?.role === 'admin';
  const isOwner = authUser?.userId === listing.ownerId;
  const isPublic =
    listing.status === ListingStatus.APPROVED &&
    listing.photos.length > 0 &&
    listing.deletedAt == null &&
    listing.owner?.deletedAt == null &&
    listing.owner?.status === UserStatus.ACTIVE;

  return isPublic || isOwner || isAdmin;
};

export const LISTING_STATUSES = [
  'pending',
  'approved',
  'rejected',
  'sold',
  'deleted',
  'archived',
] as const;

export const LISTING_PHOTO_REQUIRED = 'LISTING_PHOTO_REQUIRED';

const toInputJson = (value: Record<string, unknown> | undefined) =>
  (value ?? {}) as Prisma.InputJsonValue;

const toNullableInputJson = (value: Record<string, unknown> | undefined) =>
  (value ?? Prisma.JsonNull) as Prisma.InputJsonValue | typeof Prisma.JsonNull;

type PromotionLike = Partial<Promotion> | null | undefined;

type FeedListingLike = {
  publishedAt: Date | null;
  createdAt: Date;
  id: string;
  promotions?: PromotionLike[] | null;
};

type PaidFeedRank = {
  tier: 'turbo' | 'vip' | 'bump' | 'none';
  activatedAt: Date | null;
};

type FeedCursorPayload = {
  promotedAt: string | null;
  sortGroup: number | null;
  sortAt: string | null;
  publishedAt: string | null;
  createdAt: string;
  id: string;
};

type VipListingsCursorPayload = {
  createdAt: string;
  id: string;
};

type ListingWithModerationSnapshot = Prisma.ListingGetPayload<{
  include: {
    photos: true;
  };
}>;

const PROTECTED_FEED_HEAD_SIZE = 10;
const VIP_INTERLEAVE_FEED_MODE = 'vip_interleave_v1';
const PUBLIC_ARCHIVE_MODE = 'archive';
const AUTO_PARTS_CATEGORY = 'Запчасти';

const trimOptional = (value: string | null | undefined) => {
  const trimmed = value?.trim() ?? '';
  return trimmed.length > 0 ? trimmed : null;
};

const isAutoPartsCategory = (category: string | null | undefined) =>
  category?.trim() === AUTO_PARTS_CATEGORY;

const parsePromotionDate = (value: Date | string | null | undefined) => {
  const parsed = value instanceof Date ? value : value == null ? null : new Date(value);
  if (!(parsed instanceof Date) || Number.isNaN(parsed.getTime())) {
    return null;
  }
  return parsed;
};

const compareFeedByFreshness = (
  a: Pick<FeedListingLike, 'publishedAt' | 'createdAt' | 'id'>,
  b: Pick<FeedListingLike, 'publishedAt' | 'createdAt' | 'id'>,
) => {
  const aPublished = a.publishedAt?.getTime() ?? 0;
  const bPublished = b.publishedAt?.getTime() ?? 0;
  if (aPublished !== bPublished) {
    return bPublished - aPublished;
  }

  const createdDiff = b.createdAt.getTime() - a.createdAt.getTime();
  if (createdDiff !== 0) {
    return createdDiff;
  }

  return b.id.localeCompare(a.id);
};

const publicFeedOrderBy = [
  {
    publishedAt: {
      sort: 'desc',
      nulls: 'last',
    },
  },
  {
    createdAt: 'desc',
  },
  {
    id: 'desc',
  },
] satisfies Prisma.ListingOrderByWithRelationInput[];

const buildPublicFeedCursorWhere = (
  cursor: FeedCursorPayload | null,
): Prisma.ListingWhereInput | null => {
  if (cursor == null) {
    return null;
  }

  const createdAt = new Date(cursor.createdAt);
  if (Number.isNaN(createdAt.getTime())) {
    return null;
  }

  if (cursor.publishedAt == null) {
    return {
      publishedAt: null,
      OR: [
        {
          createdAt: {
            lt: createdAt,
          },
        },
        {
          createdAt,
          id: {
            lt: cursor.id,
          },
        },
      ],
    };
  }

  const publishedAt = new Date(cursor.publishedAt);
  if (Number.isNaN(publishedAt.getTime())) {
    return null;
  }

  return {
    OR: [
      {
        publishedAt: {
          lt: publishedAt,
        },
      },
      {
        publishedAt,
        createdAt: {
          lt: createdAt,
        },
      },
      {
        publishedAt,
        createdAt,
        id: {
          lt: cursor.id,
        },
      },
      {
        publishedAt: null,
      },
    ],
  };
};

const getPaidFeedRank = (promotions?: PromotionLike[] | null): PaidFeedRank => {
  const latestByTier = new Map<PaidFeedRank['tier'], Date>();
  const now = Date.now();

  for (const promotion of promotions ?? []) {
    if (!promotion || typeof promotion !== 'object') {
      continue;
    }

    if (promotion.status !== PromotionStatus.ACTIVE) {
      continue;
    }

    const endsAt = parsePromotionDate(promotion.endsAt);
    if (endsAt == null || endsAt.getTime() <= now) {
      continue;
    }

    const createdAt = parsePromotionDate(promotion.createdAt);
    if (createdAt == null) {
      continue;
    }

    const tier =
      promotion.type === PromotionType.TURBO
        ? 'turbo'
        : promotion.type === PromotionType.VIP
          ? 'vip'
          : promotion.type === PromotionType.BUMP
            ? 'bump'
            : 'none';

    if (tier === 'none') {
      continue;
    }

    const current = latestByTier.get(tier);
    if (current == null || createdAt.getTime() > current.getTime()) {
      latestByTier.set(tier, createdAt);
    }
  }

  if (latestByTier.has('turbo')) {
    return { tier: 'turbo', activatedAt: latestByTier.get('turbo') ?? null };
  }
  if (latestByTier.has('vip')) {
    return { tier: 'vip', activatedAt: latestByTier.get('vip') ?? null };
  }
  if (latestByTier.has('bump')) {
    return { tier: 'bump', activatedAt: latestByTier.get('bump') ?? null };
  }

  return { tier: 'none', activatedAt: null };
};

const comparePaidFeedListings = (a: FeedListingLike, b: FeedListingLike) => {
  const aRank = getPaidFeedRank(a.promotions);
  const bRank = getPaidFeedRank(b.promotions);

  const activatedDiff =
    (bRank.activatedAt?.getTime() ?? 0) - (aRank.activatedAt?.getTime() ?? 0);
  if (activatedDiff !== 0) {
    return activatedDiff;
  }

  return compareFeedByFreshness(a, b);
};

const buildPublicFeedOrder = <T extends FeedListingLike>(
  listings: T[],
  headSize = PROTECTED_FEED_HEAD_SIZE,
) => {
  const freshnessSorted = [...listings].sort(compareFeedByFreshness);
  const promotionInsertIndex = Math.max(0, headSize - 1);
  const movedPaid = freshnessSorted
    .slice(headSize)
    .filter((listing) => getPaidFeedRank(listing.promotions).tier !== 'none')
    .sort(comparePaidFeedListings);

  if (movedPaid.length === 0) {
    return freshnessSorted;
  }

  const movedIds = new Set(movedPaid.map((listing) => listing.id));
  return [
    ...freshnessSorted.slice(0, promotionInsertIndex),
    ...movedPaid,
    ...freshnessSorted
      .slice(promotionInsertIndex)
      .filter((listing) => !movedIds.has(listing.id)),
  ];
};

const toFeedCursorPayload = (listing: FeedListingLike): FeedCursorPayload => ({
  promotedAt: getPaidFeedRank(listing.promotions).activatedAt?.toISOString() ?? null,
  sortGroup: null,
  sortAt: null,
  publishedAt: listing.publishedAt?.toISOString() ?? null,
  createdAt: listing.createdAt.toISOString(),
  id: listing.id,
});

const toRankedFeedCursorPayload = (row: PublicFeedRankRow): FeedCursorPayload => ({
  promotedAt: row.promotedAt?.toISOString() ?? null,
  sortGroup: row.sortGroup,
  sortAt: row.sortAt.toISOString(),
  publishedAt: row.publishedAt?.toISOString() ?? null,
  createdAt: row.createdAt.toISOString(),
  id: row.id,
});

const encodeFeedCursor = (listing: FeedListingLike) =>
  Buffer.from(JSON.stringify(toFeedCursorPayload(listing))).toString('base64url');

const parseFeedCursor = (rawCursor?: string): FeedCursorPayload | null => {
  const cursor = rawCursor?.trim() ?? '';
  if (!cursor) {
    return null;
  }

  try {
    const parsed = JSON.parse(
      Buffer.from(cursor, 'base64url').toString('utf8'),
    ) as Partial<FeedCursorPayload>;
    if (
      typeof parsed.createdAt !== 'string' ||
      typeof parsed.id !== 'string' ||
      parsed.createdAt.trim().length === 0 ||
      parsed.id.trim().length === 0
    ) {
      return null;
    }

    return {
      promotedAt:
        typeof parsed.promotedAt === 'string' && parsed.promotedAt.trim().length > 0
          ? parsed.promotedAt
          : null,
      sortGroup:
        typeof parsed.sortGroup === 'number' && Number.isFinite(parsed.sortGroup)
          ? parsed.sortGroup
          : null,
      sortAt:
        typeof parsed.sortAt === 'string' && parsed.sortAt.trim().length > 0
          ? parsed.sortAt
          : null,
      publishedAt:
        typeof parsed.publishedAt === 'string' &&
        parsed.publishedAt.trim().length > 0
          ? parsed.publishedAt
          : null,
      createdAt: parsed.createdAt,
      id: parsed.id,
    };
  } catch {
    return null;
  }
};

const encodeVipListingsCursor = (
  promotion: Pick<Promotion, 'createdAt' | 'id'>,
) =>
  Buffer.from(
    JSON.stringify({
      createdAt: promotion.createdAt.toISOString(),
      id: promotion.id,
    } satisfies VipListingsCursorPayload),
  ).toString('base64url');

const parseVipListingsCursor = (
  rawCursor?: string,
): VipListingsCursorPayload | null => {
  const cursor = rawCursor?.trim() ?? '';
  if (!cursor) {
    return null;
  }

  try {
    const parsed = JSON.parse(
      Buffer.from(cursor, 'base64url').toString('utf8'),
    ) as Partial<VipListingsCursorPayload>;
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

type PublicFeedRankRow = {
  id: string;
  promotedAt: Date | null;
  sortGroup: number;
  sortAt: Date;
  publishedAt: Date | null;
  createdAt: Date;
};

const parseRankRowDate = (value: Date | string | null | undefined) =>
  value == null ? null : value instanceof Date ? value : new Date(value);

@Injectable()
export class ListingsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storageService: StorageService,
    private readonly promotionsService: PromotionsService,
    private readonly userBlocksService: UserBlocksService = {
      assertNotBlocked: async () => undefined,
    } as unknown as UserBlocksService,
  ) {}

  async create(authUser: AuthenticatedUser, dto: CreateListingDto) {
    await this.userBlocksService.assertNotBlocked(authUser.userId);

    const owner = await this.prisma.user.findUnique({
      where: {
        id: authUser.userId,
      },
    });

    if (!owner || owner.status === UserStatus.DELETED) {
      throw new NotFoundException('Listing owner was not found');
    }

    const nextPhone = this.pickListingPhone(dto.phone, owner.phone);
    const requestedStatus = listingStatusFromInput(dto.status);
    const nextStatus =
      authUser.role === 'admin' ? requestedStatus : ListingStatus.PENDING;
    const category = dto.category.trim();
    const oemPartNumber = isAutoPartsCategory(category)
      ? trimOptional(dto.oem_part_number)
      : null;

    if (nextStatus === ListingStatus.APPROVED && !dto.photo_urls?.length) {
      throw new BadRequestException(LISTING_PHOTO_REQUIRED);
    }

    const listing = await this.prisma.listing.create({
      data: {
        ownerId: authUser.userId,
        ownerEmail: owner.email ?? dto.owner_email?.trim() ?? null,
        ownerName:
          dto.owner_name?.trim() ||
          owner.displayName ||
          owner.name ||
          owner.email ||
          'Пользователь',
        title: dto.title.trim(),
        description: dto.description.trim(),
        category,
        subcategory: dto.subcategory?.trim() ?? '',
        oemPartNumber,
        oemPartNumberNormalized: normalizeOemPartNumber(oemPartNumber),
        price: dto.price,
        city: dto.city?.trim() ?? '',
        address: dto.address?.trim() ?? '',
        latitude:
          dto.location && typeof dto.location['latitude'] === 'number'
            ? dto.location['latitude']
            : undefined,
        longitude:
          dto.location && typeof dto.location['longitude'] === 'number'
            ? dto.location['longitude']
            : undefined,
        phone: nextPhone,
        phoneHidden: dto.phone_hidden ?? false,
        status: nextStatus,
        delivery: toInputJson(dto.delivery),
        locationJson: toInputJson(dto.location),
        car: dto.car ? toNullableInputJson(dto.car) : undefined,
        dealType: dto.deal_type?.trim() || null,
        realEstateType: dto.real_estate_type?.trim() || null,
        clothesType: dto.clothes_type?.trim() || null,
        clothesSize:
          category === 'Одежда'
            ? dto.clothes_size?.trim() || null
            : null,
        publishedAt: nextStatus === ListingStatus.APPROVED ? new Date() : null,
        photos: dto.photo_urls?.length
          ? {
              create: dto.photo_urls.map((url, index) => ({
                storageKey: `placeholder/${authUser.userId}/${index}`,
                publicUrl: url,
                sortOrder: index,
              })),
            }
          : undefined,
      },
      include: listingInclude,
    });

    return {
      listing: serializeListing(listing),
      allowed_statuses: LISTING_STATUSES,
    };
  }

  async findAll(params?: {
    search?: string;
    category?: string;
    city?: string;
    minPrice?: number;
    maxPrice?: number;
    ownerId?: string;
    ownerMe?: string;
    status?: string;
    publicMode?: string;
    limit?: number;
    cursor?: string;
    feedMode?: string;
    vipRotation?: number;
  }) {
    const search = params?.search?.trim();
    const category = params?.category?.trim();
    const city = params?.city?.trim();
    const ownerId = params?.ownerId?.trim();
    const ownerMe = params?.ownerMe?.trim();
    const status = params?.status?.trim();
    const publicMode = params?.publicMode?.trim();
    const limit = Math.max(1, Math.min(params?.limit ?? 20, 50));
    const cursor = parseFeedCursor(params?.cursor);
    const feedMode = params?.feedMode?.trim();
    const vipRotation = Number.isFinite(params?.vipRotation)
      ? Math.max(0, Math.trunc(params?.vipRotation ?? 0))
      : 0;
    const andConditions: Prisma.ListingWhereInput[] = [];

    const where: Prisma.ListingWhereInput = {
      deletedAt: null,
    };

    if (ownerMe) {
      where.ownerId = ownerMe;
    } else if (ownerId) {
      where.ownerId = ownerId;
    }

    if (!ownerMe && ownerId && publicMode === PUBLIC_ARCHIVE_MODE) {
      where.status = {
        in: [ListingStatus.ARCHIVED, ListingStatus.SOLD],
      };
      where.photos = {
        some: {},
      };
      where.owner = {
        deletedAt: null,
        status: UserStatus.ACTIVE,
      };
    } else if (!ownerMe && ownerId) {
      const requestedStatus = status ? listingStatusFromInput(status) : null;
      if (requestedStatus && requestedStatus !== ListingStatus.APPROVED) {
        return {
          items: [],
          nextCursor: null,
          hasMore: false,
          allowed_statuses: LISTING_STATUSES,
        };
      }
      where.status = ListingStatus.APPROVED;
      where.photos = {
        some: {},
      };
      where.owner = {
        deletedAt: null,
        status: UserStatus.ACTIVE,
      };
    } else if (status) {
      where.status = listingStatusFromInput(status);
    } else if (!ownerMe && !ownerId) {
      where.status = ListingStatus.APPROVED;
      where.photos = {
        some: {},
      };
      where.owner = {
        deletedAt: null,
        status: UserStatus.ACTIVE,
      };
    }

    if (category && category.toLowerCase() != 'все') {
      where.category = category;
    }

    if (city) {
      andConditions.push({
        OR: [
          {
            city: {
              contains: city,
              mode: 'insensitive',
            },
          },
          {
            address: {
              contains: city,
              mode: 'insensitive',
            },
          },
        ],
      });
    }

    if (typeof params?.minPrice === 'number' || typeof params?.maxPrice === 'number') {
      where.price = {
        ...(typeof params?.minPrice === 'number'
          ? { gte: BigInt(params.minPrice) }
          : {}),
        ...(typeof params?.maxPrice === 'number'
          ? { lte: BigInt(params.maxPrice) }
          : {}),
      };
    }

    const searchWhere = buildListingSearchWhere(search);
    if (searchWhere != null) {
      andConditions.push(searchWhere);
    }

    if (andConditions.length > 0) {
      where.AND = andConditions;
    }

    const isPublicFeed = !ownerMe && !ownerId && !status;
    if (isPublicFeed && typeof this.prisma.$queryRaw === 'function') {
      const rankedRows = await this.findPublicFeedRankedRows({
        search,
        category,
        city,
        minPrice: params?.minPrice,
        maxPrice: params?.maxPrice,
        cursor,
        limit,
        feedMode,
        vipRotation,
      });
      const pageRows = rankedRows.slice(0, limit);
      const hasMore = rankedRows.length > limit;
      const ids = pageRows.map((row) => row.id);
      const listings = ids.length === 0
        ? []
        : await this.prisma.listing.findMany({
            where: {
              id: {
                in: ids,
              },
            },
            include: listingInclude,
          });
      const listingsById = new Map(listings.map((listing) => [listing.id, listing]));
      const pageItems = ids
        .map((id) => listingsById.get(id))
        .filter((listing): listing is (typeof listings)[number] => listing != null);
      const nextCursor =
        hasMore && pageRows.length > 0
          ? Buffer.from(
              JSON.stringify(toRankedFeedCursorPayload(pageRows[pageRows.length - 1]!)),
            ).toString('base64url')
          : null;

      return {
        items: pageItems.map((listing) => serializeListing(listing)),
        nextCursor,
        hasMore,
        allowed_statuses: LISTING_STATUSES,
      };
    }

    const cursorWhere = buildPublicFeedCursorWhere(cursor);
    if (cursorWhere != null) {
      if (where.AND == null) {
        where.AND = [cursorWhere];
      } else if (Array.isArray(where.AND)) {
        where.AND.push(cursorWhere);
      }
    }

    const listings = await this.prisma.listing.findMany({
      where,
      include: listingInclude,
      orderBy: publicFeedOrderBy,
      take: limit + 1,
    });

    const orderedListings = isPublicFeed
      ? buildPublicFeedOrder(listings)
      : listings;
    const pageItems = orderedListings.slice(0, limit);
    const hasMore = orderedListings.length > limit;
    const nextCursor =
      hasMore && pageItems.length > 0
        ? encodeFeedCursor(pageItems[pageItems.length - 1]!)
        : null;

    return {
      items: pageItems.map((listing) => serializeListing(listing)),
      nextCursor,
      hasMore,
      allowed_statuses: LISTING_STATUSES,
    };
  }

  async findVipListings(params?: {
    limit?: number;
    cursor?: string;
    category?: string;
    search?: string;
  }) {
    await this.promotionsService.expirePromotionsByTime();

    const limit = Math.max(1, Math.min(params?.limit ?? 20, 50));
    const category = params?.category?.trim();
    const search = params?.search?.trim();
    const cursor = parseVipListingsCursor(params?.cursor);
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
        type: PromotionType.VIP,
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
          include: listingInclude,
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
      take: limit + 1,
    });

    const pageItems = promotions.slice(0, limit);
    const hasMore = promotions.length > limit;
    const nextCursor =
      hasMore && pageItems.length > 0
        ? encodeVipListingsCursor(pageItems[pageItems.length - 1]!)
        : null;

    return {
      items: pageItems.map((promotion) => serializeListing(promotion.listing)),
      nextCursor,
      hasMore,
    };
  }

  private async findPublicFeedRankedRows(params: {
    search?: string;
    category?: string;
    city?: string;
    minPrice?: number;
    maxPrice?: number;
    cursor: FeedCursorPayload | null;
    limit: number;
    feedMode?: string;
    vipRotation: number;
  }): Promise<PublicFeedRankRow[]> {
    const whereParts: Prisma.Sql[] = [
      Prisma.sql`l."deleted_at" IS NULL`,
      Prisma.sql`l."status"::text = 'APPROVED'`,
      Prisma.sql`EXISTS (
        SELECT 1
        FROM "listing_photos" lp
        WHERE lp."listing_id" = l."id"
      )`,
      Prisma.sql`u."deleted_at" IS NULL`,
      Prisma.sql`u."status"::text = 'ACTIVE'`,
    ];

    if (params.category && params.category.toLowerCase() !== 'все') {
      whereParts.push(Prisma.sql`l."category" = ${params.category}`);
    }

    if (params.city) {
      const cityPattern = `%${params.city}%`;
      whereParts.push(Prisma.sql`(
        l."city" ILIKE ${cityPattern}
        OR l."address" ILIKE ${cityPattern}
      )`);
    }

    if (typeof params.minPrice === 'number') {
      whereParts.push(Prisma.sql`l."price" >= ${params.minPrice}`);
    }
    if (typeof params.maxPrice === 'number') {
      whereParts.push(Prisma.sql`l."price" <= ${params.maxPrice}`);
    }

    const searchSql = buildListingSearchSql(params.search);
    if (searchSql != null) {
      whereParts.push(searchSql);
    }

    const cursor = this.buildRankedFeedCursorSql(params.cursor);
    if (params.feedMode === VIP_INTERLEAVE_FEED_MODE) {
      return this.findPublicFeedVipInterleavedRows({
        whereParts,
        cursor,
        limit: params.limit,
        vipRotation: params.vipRotation,
      });
    }

    const rows = await this.prisma.$queryRaw<Array<{
      id: string;
      promoted_at: Date | string | null;
      sort_group: number | bigint;
      sort_at: Date | string;
      published_at: Date | string | null;
      created_at: Date | string;
    }>>`
      WITH base AS (
        SELECT
          l."id",
          l."published_at",
          l."created_at",
          MAX(p."created_at") FILTER (
            WHERE p."status"::text = 'ACTIVE'
              AND p."ends_at" > NOW()
              AND p."type"::text IN ('VIP', 'BUMP', 'TURBO')
          ) AS promoted_at
        FROM "listings" l
        JOIN "users" u ON u."id" = l."owner_id"
        LEFT JOIN "promotions" p ON p."listing_id" = l."id"
        WHERE ${Prisma.join(whereParts, ' AND ')}
        GROUP BY l."id", l."published_at", l."created_at"
      ),
      ranked AS (
        SELECT
          base.*,
          ROW_NUMBER() OVER (
            ORDER BY
              base."published_at" DESC NULLS LAST,
              base."created_at" DESC,
              base."id" DESC
          ) AS natural_rank
        FROM base
      ),
      moved AS (
        SELECT
          ranked.*,
          COUNT(*) FILTER (
            WHERE promoted_at IS NOT NULL
              AND natural_rank > ${PROTECTED_FEED_HEAD_SIZE}
          ) OVER () AS moved_count
        FROM ranked
      ),
      queued AS (
        SELECT
          moved.*,
          CASE
            WHEN promoted_at IS NOT NULL
              AND natural_rank > ${PROTECTED_FEED_HEAD_SIZE}
              THEN ROW_NUMBER() OVER (
                PARTITION BY (
                  promoted_at IS NOT NULL
                    AND natural_rank > ${PROTECTED_FEED_HEAD_SIZE}
                )
                ORDER BY
                  promoted_at DESC,
                  created_at DESC,
                  "id" DESC
              )
            ELSE NULL
          END AS promotion_queue_rank
        FROM moved
      ),
      ordered AS (
        SELECT
          "id",
          promoted_at,
          published_at,
          created_at,
          CASE
            WHEN promoted_at IS NOT NULL
              AND natural_rank > ${PROTECTED_FEED_HEAD_SIZE}
              THEN ${PROTECTED_FEED_HEAD_SIZE} + promotion_queue_rank - 1
            WHEN natural_rank >= ${PROTECTED_FEED_HEAD_SIZE}
              THEN natural_rank + moved_count
            ELSE natural_rank
          END AS sort_group,
          CASE
            WHEN promoted_at IS NOT NULL
              AND natural_rank > ${PROTECTED_FEED_HEAD_SIZE}
              THEN promoted_at
            ELSE COALESCE("published_at", "created_at")
          END AS sort_at
        FROM queued
      )
      SELECT
        "id",
        promoted_at,
        sort_group,
        sort_at,
        published_at,
        created_at
      FROM ordered
      WHERE ${cursor}
      ORDER BY
        sort_group ASC,
        sort_at DESC,
        created_at DESC,
        "id" DESC
      LIMIT ${params.limit + 1}
    `;

    return rows.map((row) => ({
      id: row.id,
      promotedAt: parseRankRowDate(row.promoted_at),
      sortGroup: Number(row.sort_group),
      sortAt: parseRankRowDate(row.sort_at) ?? new Date(0),
      publishedAt: parseRankRowDate(row.published_at),
      createdAt: parseRankRowDate(row.created_at) ?? new Date(0),
    }));
  }

  private async findPublicFeedVipInterleavedRows(params: {
    whereParts: Prisma.Sql[];
    cursor: Prisma.Sql;
    limit: number;
    vipRotation: number;
  }): Promise<PublicFeedRankRow[]> {
    const rows = await this.prisma.$queryRaw<Array<{
      id: string;
      promoted_at: Date | string | null;
      sort_group: number | bigint;
      sort_at: Date | string;
      published_at: Date | string | null;
      created_at: Date | string;
    }>>`
      WITH base AS (
        SELECT
          l."id",
          l."published_at",
          l."created_at",
          MAX(p."created_at") FILTER (
            WHERE p."status"::text = 'ACTIVE'
              AND p."ends_at" > NOW()
              AND p."type"::text = 'VIP'
          ) AS vip_promoted_at
        FROM "listings" l
        JOIN "users" u ON u."id" = l."owner_id"
        LEFT JOIN "promotions" p ON p."listing_id" = l."id"
        WHERE ${Prisma.join(params.whereParts, ' AND ')}
        GROUP BY l."id", l."published_at", l."created_at"
      ),
      ranked AS (
        SELECT
          base.*,
          ROW_NUMBER() OVER (
            PARTITION BY (vip_promoted_at IS NULL)
            ORDER BY
              base."published_at" DESC NULLS LAST,
              base."created_at" DESC,
              base."id" DESC
          ) AS ordinary_rank,
          ROW_NUMBER() OVER (
            PARTITION BY (vip_promoted_at IS NOT NULL)
            ORDER BY
              vip_promoted_at DESC,
              base."created_at" DESC,
              base."id" DESC
          ) AS vip_queue_rank,
          COUNT(*) FILTER (WHERE vip_promoted_at IS NOT NULL) OVER () AS vip_count,
          LEAST(
            COUNT(*) FILTER (WHERE vip_promoted_at IS NULL) OVER (),
            ${PROTECTED_FEED_HEAD_SIZE}
          ) AS ordinary_head_count
        FROM base
      ),
      ordered AS (
        SELECT
          "id",
          vip_promoted_at AS promoted_at,
          published_at,
          created_at,
          CASE
            WHEN vip_promoted_at IS NULL AND ordinary_rank <= ordinary_head_count
              THEN ordinary_rank
            WHEN vip_promoted_at IS NOT NULL
              THEN ordinary_head_count
                + 1
                + (
                  (
                    (
                      vip_queue_rank
                      - 1
                      - (${params.vipRotation} % GREATEST(vip_count, 1))
                    )
                    + vip_count
                  ) % GREATEST(vip_count, 1)
                ) * 3
            ELSE ordinary_head_count
              + (ordinary_rank - ordinary_head_count)
              + CEIL((ordinary_rank - ordinary_head_count)::numeric / 2.0)::int
          END AS sort_group,
          CASE
            WHEN vip_promoted_at IS NOT NULL
              THEN vip_promoted_at
            ELSE COALESCE("published_at", "created_at")
          END AS sort_at
        FROM ranked
      )
      SELECT
        "id",
        promoted_at,
        sort_group,
        sort_at,
        published_at,
        created_at
      FROM ordered
      WHERE ${params.cursor}
      ORDER BY
        sort_group ASC,
        sort_at DESC,
        created_at DESC,
        "id" DESC
      LIMIT ${params.limit + 1}
    `;

    return rows.map((row) => ({
      id: row.id,
      promotedAt: parseRankRowDate(row.promoted_at),
      sortGroup: Number(row.sort_group),
      sortAt: parseRankRowDate(row.sort_at) ?? new Date(0),
      publishedAt: parseRankRowDate(row.published_at),
      createdAt: parseRankRowDate(row.created_at) ?? new Date(0),
    }));
  }

  private buildRankedFeedCursorSql(cursor: FeedCursorPayload | null) {
    if (
      cursor == null ||
      cursor.sortGroup == null ||
      cursor.sortAt == null
    ) {
      return Prisma.sql`TRUE`;
    }

    const sortAt = new Date(cursor.sortAt);
    const createdAt = new Date(cursor.createdAt);
    if (
      Number.isNaN(sortAt.getTime()) ||
      Number.isNaN(createdAt.getTime())
    ) {
      return Prisma.sql`TRUE`;
    }

    return Prisma.sql`(
      sort_group > ${cursor.sortGroup}
      OR (
        sort_group = ${cursor.sortGroup}
        AND (
          sort_at < ${sortAt}
          OR (
            sort_at = ${sortAt}
            AND created_at < ${createdAt}
          )
          OR (
            sort_at = ${sortAt}
            AND created_at = ${createdAt}
            AND "id" < ${cursor.id}::uuid
          )
        )
      )
    )`;
  }

  async findOne(id: string, authUser?: AuthenticatedUser) {
    const listing = await this.prisma.listing.findUnique({
      where: {
        id,
      },
      include: listingInclude,
    });

    if (!listing) {
      throw new NotFoundException('Listing not found');
    }

    if (!canViewListing(listing, authUser)) {
      throw new NotFoundException('Listing not found');
    }

    return {
      listing: serializeListing(listing),
      ...this.promotionsService.enrichListing(listing, authUser),
    };
  }

  async update(id: string, authUser: AuthenticatedUser, dto: UpdateListingDto) {
    await this.userBlocksService.assertNotBlocked(authUser.userId);

    const listing = await this.prisma.listing.findUnique({
      where: {
        id,
      },
      include: listingInclude,
    });

    if (!listing) {
      throw new NotFoundException('Listing not found');
    }

    if (listing.ownerId !== authUser.userId) {
      throw new ForbiddenException('Only owner can update listing');
    }

    if (
      dto.status &&
      dto.status.trim().toLowerCase() !== listing.status.toLowerCase() &&
      authUser.role !== 'admin'
    ) {
      throw new ForbiddenException(
        'Use explicit archive endpoint for sold/archive status changes',
      );
    }

    const requestedStatus = dto.status
      ? listingStatusFromInput(dto.status)
      : undefined;
    const nextStatus =
      requestedStatus != null && requestedStatus !== ListingStatus.APPROVED
        ? requestedStatus
        : this.statusAfterOwnerEdit(listing, authUser);

    const nextPhone = this.pickListingPhone(dto.phone, listing.owner?.phone ?? listing.phone);
    const nextCategory = dto.category?.trim() ?? listing.category;
    const shouldUpdateOem = Object.prototype.hasOwnProperty.call(
      dto,
      'oem_part_number',
    );
    const nextOemPartNumber = isAutoPartsCategory(nextCategory)
      ? trimOptional(dto.oem_part_number)
      : null;

    const updated = await this.prisma.$transaction(async (tx) => {
      await this.createOwnerApprovedSnapshotIfNeeded(tx, listing);

      const savedListing = await tx.listing.update({
        where: {
          id,
        },
        data: {
          title: dto.title?.trim(),
          description: dto.description?.trim(),
          category: dto.category?.trim(),
          subcategory: dto.subcategory?.trim(),
          price: dto.price,
          city: dto.city?.trim(),
          address: dto.address?.trim(),
          latitude:
            dto.location && typeof dto.location['latitude'] === 'number'
              ? dto.location['latitude']
              : undefined,
          longitude:
            dto.location && typeof dto.location['longitude'] === 'number'
              ? dto.location['longitude']
              : undefined,
          phone: nextPhone,
          phoneHidden: dto.phone_hidden,
          delivery: dto.delivery ? toInputJson(dto.delivery) : undefined,
          locationJson: dto.location ? toInputJson(dto.location) : undefined,
          car: dto.car ? toNullableInputJson(dto.car) : undefined,
          oemPartNumber: isAutoPartsCategory(nextCategory)
            ? shouldUpdateOem
              ? nextOemPartNumber
              : undefined
            : null,
          oemPartNumberNormalized: isAutoPartsCategory(nextCategory)
            ? shouldUpdateOem
              ? normalizeOemPartNumber(nextOemPartNumber)
              : undefined
            : null,
          dealType: dto.deal_type?.trim(),
          realEstateType: dto.real_estate_type?.trim(),
          clothesType: dto.clothes_type?.trim(),
          clothesSize:
            dto.category?.trim() === 'Одежда' || listing.category === 'Одежда'
              ? dto.clothes_size?.trim()
              : undefined,
          status: nextStatus,
          ...(nextStatus === ListingStatus.PENDING &&
          listing.status === ListingStatus.APPROVED
            ? this.pendingModerationUpdateData()
            : {}),
          archivedAt:
            nextStatus === ListingStatus.ARCHIVED ? new Date() : listing.archivedAt,
        },
        include: listingInclude,
      });

      if (dto.photo_urls) {
        await tx.listingPhoto.deleteMany({
          where: {
            listingId: id,
          },
        });

        if (dto.photo_urls.length) {
          await tx.listingPhoto.createMany({
            data: dto.photo_urls.map((url, index) => ({
              listingId: id,
              storageKey: `placeholder/${id}/${index}`,
              publicUrl: url,
              sortOrder: index,
            })),
          });
        }
      }

      return tx.listing.findUniqueOrThrow({
        where: { id },
        include: listingInclude,
      });
    });

    return {
      listing: serializeListing(updated),
    };
  }

  async remove(id: string, authUser: AuthenticatedUser) {
    if (authUser.role !== 'admin') {
      await this.userBlocksService.assertNotBlocked(authUser.userId);
    }

    const listing = await this.prisma.listing.findUnique({
      where: {
        id,
      },
    });

    if (!listing) {
      throw new NotFoundException('Listing not found');
    }

    const canDelete =
      listing.ownerId === authUser.userId || authUser.role === 'admin';
    if (!canDelete) {
      throw new ForbiddenException(
        'Удалять объявление может только владелец или администратор',
      );
    }

    const updated = await this.prisma.listing.update({
      where: {
        id,
      },
      data: {
        status: ListingStatus.DELETED,
        deletedAt: new Date(),
      },
      include: listingInclude,
    });

    await this.storageService.deleteListingPhotosForListings([id]);

    return {
      listing: serializeListing(updated),
      status_after_delete: listingStatusToResponse(ListingStatus.DELETED),
    };
  }

  async archive(
    id: string,
    authUser: AuthenticatedUser,
    dto?: ArchiveListingDto,
  ) {
    if (authUser.role !== 'admin') {
      await this.userBlocksService.assertNotBlocked(authUser.userId);
    }

    const listing = await this.prisma.listing.findUnique({
      where: {
        id,
      },
    });

    if (!listing) {
      throw new NotFoundException('Listing not found');
    }

    if (listing.ownerId !== authUser.userId) {
      throw new ForbiddenException('Only owner can archive listing');
    }

    const nextStatus = dto?.status?.trim().toLowerCase() === 'sold'
      ? ListingStatus.SOLD
      : ListingStatus.ARCHIVED;
    const nextNote = dto?.note?.trim();
    const updated = await this.prisma.listing.update({
      where: {
        id,
      },
      data: {
        status: nextStatus,
        rejectionReason:
          nextNote && nextNote.length > 0
            ? nextNote
            : nextStatus === ListingStatus.SOLD
              ? 'Объявление отмечено как проданное.'
              : 'Объявление снято с публикации.',
        archivedAt: new Date(),
      },
      include: listingInclude,
    });

    return {
      listing: serializeListing(updated),
      status_after_archive: listingStatusToResponse(nextStatus),
    };
  }

  async incrementView(
    listingId: string,
    authUser?: AuthenticatedUser,
  ) {
    const listing = await this.prisma.listing.findUnique({
      where: {
        id: listingId,
      },
    });

    if (!listing) {
      throw new NotFoundException('Listing not found');
    }

    const viewerUserId = authUser?.userId;
    if (viewerUserId != null && listing.ownerId === viewerUserId) {
      return {
        listing_id: listingId,
        view_count: listing.viewCount,
      };
    }

    const updated = await this.prisma.$transaction(async (tx) => {
      if (viewerUserId != null && authUser?.role !== 'admin') {
        await tx.$queryRaw`
          SELECT pg_advisory_xact_lock(
            hashtextextended(${`listing-view:${listingId}:${viewerUserId}`}, 0)
          )
        `;

        const existingView = await tx.listingView.findFirst({
          where: {
            listingId,
            viewerUserId,
          },
          select: {
            id: true,
          },
        });

        if (existingView) {
          return listing;
        }
      }

      await tx.listingView.create({
        data: {
          listingId,
          viewerUserId: viewerUserId || null,
          viewerDeviceId: null,
        },
      });

      return tx.listing.update({
        where: {
          id: listingId,
        },
        data: {
          viewCount: {
            increment: 1,
          },
        },
      });
    });

    return {
      listing_id: listingId,
      view_count: updated.viewCount,
    };
  }

  async findMy(
    authUser: AuthenticatedUser,
    params?: { status?: string; limit?: number; cursor?: string },
  ) {
    const status = params?.status?.trim();
    const limit = Math.max(1, Math.min(params?.limit ?? 20, 50));
    const cursor = parseFeedCursor(params?.cursor);
    const cursorWhere = buildPublicFeedCursorWhere(cursor);
    const where: Prisma.ListingWhereInput = {
      deletedAt: null,
      ownerId: authUser.userId,
      ...(status ? { status: listingStatusFromInput(status) } : {}),
    };
    if (cursorWhere != null) {
      where.AND = [cursorWhere];
    }
    const listings = await this.prisma.listing.findMany({
      where,
      include: listingInclude,
      orderBy: publicFeedOrderBy,
      take: limit + 1,
    });

    const orderedListings = listings.sort(compareFeedByFreshness);
    const pageItems = orderedListings.slice(0, limit);
    const hasMore = orderedListings.length > limit;
    const nextCursor =
      hasMore && pageItems.length > 0
        ? encodeFeedCursor(pageItems[pageItems.length - 1]!)
        : null;

    const listingIds = pageItems.map((listing) => listing.id);
    const favorites = listingIds.length === 0
      ? []
      : await this.prisma.favorite.findMany({
          where: {
            listingId: {
              in: listingIds,
            },
            userId: {
              not: authUser.userId,
            },
          },
          select: {
            listingId: true,
          },
        });

    const favoriteCountByListingId = new Map<string, number>();
    for (const favorite of favorites) {
      favoriteCountByListingId.set(
        favorite.listingId,
        (favoriteCountByListingId.get(favorite.listingId) ?? 0) + 1,
      );
    }

    return {
      items: pageItems.map((listing) =>
        serializeListing(listing, {
          favoriteCount: favoriteCountByListingId.get(listing.id) ?? 0,
        }),
      ),
      nextCursor,
      hasMore,
      limit,
      allowed_statuses: LISTING_STATUSES,
    };
  }

  async uploadPhoto(
    authUser: AuthenticatedUser,
    listingId: string,
    file: UploadedImageFile,
    sortOrder?: number,
  ) {
    const listing = await this.prisma.listing.findUnique({
      where: {
        id: listingId,
      },
      include: listingInclude,
    });
    if (!listing) {
      throw new NotFoundException('Listing not found');
    }
    if (listing.ownerId !== authUser.userId && authUser.role !== 'admin') {
      throw new ForbiddenException('Only owner or admin can upload listing photo');
    }
    if (listing.photos.length >= 10) {
      throw new BadRequestException('Listing photo limit is 10');
    }

    const uploaded = await this.storageService.saveUploadedFile({
      buffer: file.buffer,
      category: 'listings',
      contentType: file.mimetype,
      context: {
        listingId,
        userId: authUser.userId,
      },
      originalName: file.originalname,
    });

    const photo = await this.runListingTransaction(async (tx) => {
      await this.createOwnerApprovedSnapshotIfNeeded(tx, listing);
      const created = await tx.listingPhoto.create({
        data: {
          listingId,
          storageBucket: uploaded.bucket ?? 'local',
          storageKey: uploaded.key,
          publicUrl: uploaded.url,
          sortOrder:
            typeof sortOrder === 'number' && Number.isFinite(sortOrder) && sortOrder >= 0
              ? Math.trunc(sortOrder)
              : listing.photos.length,
          sizeBytes: uploaded.sizeBytes,
          mimeType: uploaded.mimeType,
        },
      });
      await this.resubmitPublishedListingAfterOwnerEdit(listing, authUser, tx);
      return created;
    });

    const updated = await this.prisma.listing.findUniqueOrThrow({
      where: { id: listingId },
      include: listingInclude,
    });

    return {
      source: 'timeweb',
      photo: {
        id: photo.id,
        url: photo.publicUrl,
        sort_order: photo.sortOrder,
      },
      listing: serializeListing(updated),
    };
  }

  async deletePhoto(
    authUser: AuthenticatedUser,
    listingId: string,
    photoId: string,
  ) {
    const listing = await this.prisma.listing.findUnique({
      where: {
        id: listingId,
      },
      include: {
        photos: {
          orderBy: {
            sortOrder: 'asc',
          },
        },
      },
    });
    if (!listing) {
      throw new NotFoundException('Listing not found');
    }
    if (listing.ownerId !== authUser.userId && authUser.role !== 'admin') {
      throw new ForbiddenException('Only owner or admin can delete listing photo');
    }

    const photo = listing.photos.find((item) => item.id === photoId);
    if (!photo) {
      throw new NotFoundException('Listing photo not found');
    }
    if (listing.photos.length <= 1 && this.requiresPhotoBeforePublication(listing.status)) {
      throw new BadRequestException(LISTING_PHOTO_REQUIRED);
    }

    await this.storageService.deleteStoredFile('listings', photo.storageKey);
    await this.runListingTransaction(async (tx) => {
      await this.createOwnerApprovedSnapshotIfNeeded(tx, listing);
      await tx.listingPhoto.delete({
        where: {
          id: photoId,
        },
      });

      const remaining = await tx.listingPhoto.findMany({
        where: {
          listingId,
        },
        orderBy: {
          sortOrder: 'asc',
        },
      });
      await Promise.all(
        remaining.map((item, index) =>
          tx.listingPhoto.update({
            where: { id: item.id },
            data: { sortOrder: index },
          }),
        ),
      );

      await this.resubmitPublishedListingAfterOwnerEdit(listing, authUser, tx);
    });

    const updated = await this.prisma.listing.findUniqueOrThrow({
      where: { id: listingId },
      include: listingInclude,
    });

    return {
      source: 'timeweb',
      deleted: true,
      photo_id: photoId,
      listing: serializeListing(updated),
    };
  }

  private pickListingPhone(
    rawPhone: string | undefined,
    fallbackPhone: string | null | undefined,
  ) {
    const candidate = rawPhone?.trim() || fallbackPhone?.trim() || '';
    if (!candidate) {
      return '';
    }

    const normalized = normalizeRussianPhone(candidate);
    if (!normalized) {
      return candidate;
    }
    validateRussianPhoneOrThrow(normalized);
    return normalized;
  }

  private statusAfterOwnerEdit(
    listing: { ownerId: string; status: ListingStatus },
    authUser: AuthenticatedUser,
  ) {
    if (
      listing.ownerId === authUser.userId &&
      listing.status === ListingStatus.APPROVED
    ) {
      return ListingStatus.PENDING;
    }

    return listing.status;
  }

  private pendingModerationUpdateData() {
    return {
      rejectionReason: null,
      moderationNote: null,
      moderatedBy: null,
      moderatedAt: null,
      archivedAt: null,
      deletedAt: null,
    };
  }

  private requiresPhotoBeforePublication(status: ListingStatus) {
    switch (status) {
      case ListingStatus.APPROVED:
      case ListingStatus.PENDING:
      case ListingStatus.REJECTED:
      case ListingStatus.ARCHIVED:
        return true;
      default:
        return false;
    }
  }

  private async resubmitPublishedListingAfterOwnerEdit(
    listing: { id: string; ownerId: string; status: ListingStatus },
    authUser: AuthenticatedUser,
    tx: Prisma.TransactionClient = this.prisma,
  ) {
    if (this.statusAfterOwnerEdit(listing, authUser) !== ListingStatus.PENDING) {
      return;
    }

    await tx.listing.update({
      where: { id: listing.id },
      data: {
        status: ListingStatus.PENDING,
        ...this.pendingModerationUpdateData(),
      },
    });
  }

  private async createOwnerApprovedSnapshotIfNeeded(
    tx: Prisma.TransactionClient,
    listing: ListingWithModerationSnapshot,
  ) {
    if (listing.status !== ListingStatus.APPROVED) {
      return;
    }

    const revisions = tx.listingModerationRevision;
    if (!revisions) {
      return;
    }

    const existing = await revisions.findFirst({
      where: {
        listingId: listing.id,
        resolvedAt: null,
      },
      select: {
        id: true,
      },
    });
    if (existing) {
      return;
    }

    await revisions.create({
      data: {
        listingId: listing.id,
        snapshot: this.buildModerationSnapshot(listing),
      },
    });
  }

  private buildModerationSnapshot(listing: ListingWithModerationSnapshot) {
    return {
      title: listing.title,
      description: listing.description,
      category: listing.category,
      subcategory: listing.subcategory,
      price:
        typeof listing.price === 'bigint'
          ? listing.price.toString()
          : String(listing.price ?? 0),
      phone_hidden: listing.phoneHidden,
      city: listing.city,
      address: listing.address,
      latitude: listing.latitude == null ? null : Number(listing.latitude),
      longitude: listing.longitude == null ? null : Number(listing.longitude),
      location: listing.locationJson ?? {},
      delivery: listing.delivery ?? {},
      car: listing.car ?? null,
      deal_type: listing.dealType,
      real_estate_type: listing.realEstateType,
      clothes_type: listing.clothesType,
      clothes_size: listing.clothesSize,
      oem_part_number: listing.oemPartNumber,
      photos: listing.photos.map((photo) => ({
        id: photo.id,
        storage_key: photo.storageKey,
        url: photo.publicUrl,
        sort_order: photo.sortOrder,
      })),
    };
  }

  private async runListingTransaction<T>(
    handler: (tx: Prisma.TransactionClient) => Promise<T>,
  ) {
    if (typeof this.prisma.$transaction === 'function') {
      return this.prisma.$transaction(handler);
    }
    return handler(this.prisma as unknown as Prisma.TransactionClient);
  }

}
