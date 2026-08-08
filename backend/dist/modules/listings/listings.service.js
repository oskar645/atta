"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.ListingsService = exports.LISTING_PHOTO_REQUIRED = exports.LISTING_STATUSES = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const serializers_1 = require("../../common/serializers");
const phone_1 = require("../../common/phone");
const prisma_service_1 = require("../prisma/prisma.service");
const promotions_service_1 = require("../promotions/promotions.service");
const storage_service_1 = require("../storage/storage.service");
const user_blocks_service_1 = require("../user-blocks/user-blocks.service");
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
            status: client_1.PromotionStatus.ACTIVE,
        },
        orderBy: {
            createdAt: 'desc',
        },
    },
};
exports.LISTING_STATUSES = [
    'pending',
    'approved',
    'rejected',
    'sold',
    'deleted',
    'archived',
];
exports.LISTING_PHOTO_REQUIRED = 'LISTING_PHOTO_REQUIRED';
const toInputJson = (value) => (value ?? {});
const toNullableInputJson = (value) => (value ?? client_1.Prisma.JsonNull);
const PROTECTED_FEED_HEAD_SIZE = 10;
const parsePromotionDate = (value) => {
    const parsed = value instanceof Date ? value : value == null ? null : new Date(value);
    if (!(parsed instanceof Date) || Number.isNaN(parsed.getTime())) {
        return null;
    }
    return parsed;
};
const compareFeedByFreshness = (a, b) => {
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
];
const buildPublicFeedCursorWhere = (cursor) => {
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
const getPaidFeedRank = (promotions) => {
    const latestByTier = new Map();
    const now = Date.now();
    for (const promotion of promotions ?? []) {
        if (!promotion || typeof promotion !== 'object') {
            continue;
        }
        if (promotion.status !== client_1.PromotionStatus.ACTIVE) {
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
        const tier = promotion.type === client_1.PromotionType.TURBO
            ? 'turbo'
            : promotion.type === client_1.PromotionType.VIP
                ? 'vip'
                : promotion.type === client_1.PromotionType.BUMP
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
const comparePaidFeedListings = (a, b) => {
    const aRank = getPaidFeedRank(a.promotions);
    const bRank = getPaidFeedRank(b.promotions);
    const tierWeight = {
        turbo: 0,
        vip: 1,
        bump: 2,
        none: 3,
    };
    const tierDiff = tierWeight[aRank.tier] - tierWeight[bRank.tier];
    if (tierDiff !== 0) {
        return tierDiff;
    }
    const activatedDiff = (bRank.activatedAt?.getTime() ?? 0) - (aRank.activatedAt?.getTime() ?? 0);
    if (activatedDiff !== 0) {
        return activatedDiff;
    }
    return compareFeedByFreshness(a, b);
};
const buildPublicFeedOrder = (listings, headSize = PROTECTED_FEED_HEAD_SIZE) => {
    const freshnessSorted = [...listings].sort(compareFeedByFreshness);
    const naturalTop = freshnessSorted.slice(0, headSize);
    const movedPaid = freshnessSorted
        .slice(headSize)
        .filter((listing) => getPaidFeedRank(listing.promotions).tier !== 'none');
    if (movedPaid.length === 0) {
        return freshnessSorted;
    }
    const movedIds = new Set(movedPaid.map((listing) => listing.id));
    const placedIds = new Set();
    const protectedHead = Array.from({ length: headSize }, () => null);
    for (const [index, listing] of naturalTop.entries()) {
        if (getPaidFeedRank(listing.promotions).tier !== 'none') {
            protectedHead[index] = listing;
            placedIds.add(listing.id);
        }
    }
    const availableSlots = protectedHead
        .map((listing, index) => (listing == null ? index : -1))
        .filter((index) => index >= 0)
        .slice(-Math.min(movedPaid.length, protectedHead.filter((listing) => listing == null).length));
    for (const [index, slot] of availableSlots.entries()) {
        const listing = movedPaid[index];
        if (listing == null) {
            break;
        }
        protectedHead[slot] = listing;
        placedIds.add(listing.id);
    }
    const naturalRest = freshnessSorted.filter((listing) => !movedIds.has(listing.id) && !placedIds.has(listing.id));
    let regularIndex = 0;
    for (let index = 0; index < protectedHead.length; index += 1) {
        if (protectedHead[index] == null) {
            protectedHead[index] = naturalRest[regularIndex] ?? null;
            if (naturalRest[regularIndex] != null) {
                placedIds.add(naturalRest[regularIndex].id);
            }
            regularIndex += 1;
        }
    }
    return [
        ...protectedHead.filter((listing) => listing != null),
        ...movedPaid.slice(availableSlots.length),
        ...freshnessSorted.filter((listing) => !placedIds.has(listing.id)),
    ].filter((listing, index, items) => items.findIndex((candidate) => candidate.id === listing.id) === index);
};
const toFeedCursorPayload = (listing) => ({
    promotedAt: getPaidFeedRank(listing.promotions).activatedAt?.toISOString() ?? null,
    sortGroup: null,
    sortAt: null,
    publishedAt: listing.publishedAt?.toISOString() ?? null,
    createdAt: listing.createdAt.toISOString(),
    id: listing.id,
});
const toRankedFeedCursorPayload = (row) => ({
    promotedAt: row.promotedAt?.toISOString() ?? null,
    sortGroup: row.sortGroup,
    sortAt: row.sortAt.toISOString(),
    publishedAt: row.publishedAt?.toISOString() ?? null,
    createdAt: row.createdAt.toISOString(),
    id: row.id,
});
const encodeFeedCursor = (listing) => Buffer.from(JSON.stringify(toFeedCursorPayload(listing))).toString('base64url');
const parseFeedCursor = (rawCursor) => {
    const cursor = rawCursor?.trim() ?? '';
    if (!cursor) {
        return null;
    }
    try {
        const parsed = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
        if (typeof parsed.createdAt !== 'string' ||
            typeof parsed.id !== 'string' ||
            parsed.createdAt.trim().length === 0 ||
            parsed.id.trim().length === 0) {
            return null;
        }
        return {
            promotedAt: typeof parsed.promotedAt === 'string' && parsed.promotedAt.trim().length > 0
                ? parsed.promotedAt
                : null,
            sortGroup: typeof parsed.sortGroup === 'number' && Number.isFinite(parsed.sortGroup)
                ? parsed.sortGroup
                : null,
            sortAt: typeof parsed.sortAt === 'string' && parsed.sortAt.trim().length > 0
                ? parsed.sortAt
                : null,
            publishedAt: typeof parsed.publishedAt === 'string' &&
                parsed.publishedAt.trim().length > 0
                ? parsed.publishedAt
                : null,
            createdAt: parsed.createdAt,
            id: parsed.id,
        };
    }
    catch {
        return null;
    }
};
const parseRankRowDate = (value) => value == null ? null : value instanceof Date ? value : new Date(value);
let ListingsService = class ListingsService {
    constructor(prisma, storageService, promotionsService, userBlocksService = {
        assertNotBlocked: async () => undefined,
    }) {
        this.prisma = prisma;
        this.storageService = storageService;
        this.promotionsService = promotionsService;
        this.userBlocksService = userBlocksService;
    }
    async create(authUser, dto) {
        await this.userBlocksService.assertNotBlocked(authUser.userId);
        const owner = await this.prisma.user.findUnique({
            where: {
                id: authUser.userId,
            },
        });
        if (!owner || owner.status === client_1.UserStatus.DELETED) {
            throw new common_1.NotFoundException('Listing owner was not found');
        }
        const nextPhone = this.pickListingPhone(dto.phone, owner.phone);
        const requestedStatus = (0, serializers_1.listingStatusFromInput)(dto.status);
        const nextStatus = authUser.role === 'admin' ? requestedStatus : client_1.ListingStatus.PENDING;
        if (nextStatus === client_1.ListingStatus.APPROVED && !dto.photo_urls?.length) {
            throw new common_1.BadRequestException(exports.LISTING_PHOTO_REQUIRED);
        }
        const listing = await this.prisma.listing.create({
            data: {
                ownerId: authUser.userId,
                ownerEmail: owner.email ?? dto.owner_email?.trim() ?? null,
                ownerName: dto.owner_name?.trim() ||
                    owner.displayName ||
                    owner.name ||
                    owner.email ||
                    'Пользователь',
                title: dto.title.trim(),
                description: dto.description.trim(),
                category: dto.category.trim(),
                subcategory: dto.subcategory?.trim() ?? '',
                price: dto.price,
                city: dto.city?.trim() ?? '',
                address: dto.address?.trim() ?? '',
                latitude: dto.location && typeof dto.location['latitude'] === 'number'
                    ? dto.location['latitude']
                    : undefined,
                longitude: dto.location && typeof dto.location['longitude'] === 'number'
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
                clothesSize: dto.category.trim() === 'Одежда'
                    ? dto.clothes_size?.trim() || null
                    : null,
                publishedAt: nextStatus === client_1.ListingStatus.APPROVED ? new Date() : null,
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
            listing: (0, serializers_1.serializeListing)(listing),
            allowed_statuses: exports.LISTING_STATUSES,
        };
    }
    async findAll(params) {
        const search = params?.search?.trim();
        const category = params?.category?.trim();
        const city = params?.city?.trim();
        const ownerId = params?.ownerId?.trim();
        const ownerMe = params?.ownerMe?.trim();
        const status = params?.status?.trim();
        const limit = Math.max(1, Math.min(params?.limit ?? 20, 50));
        const cursor = parseFeedCursor(params?.cursor);
        const andConditions = [];
        const where = {
            deletedAt: null,
        };
        if (ownerMe) {
            where.ownerId = ownerMe;
        }
        else if (ownerId) {
            where.ownerId = ownerId;
        }
        if (status) {
            where.status = (0, serializers_1.listingStatusFromInput)(status);
        }
        else if (!ownerMe && !ownerId) {
            where.status = client_1.ListingStatus.APPROVED;
            where.photos = {
                some: {},
            };
            where.owner = {
                deletedAt: null,
                status: client_1.UserStatus.ACTIVE,
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
        if (search) {
            andConditions.push({
                OR: [
                    {
                        title: {
                            contains: search,
                            mode: 'insensitive',
                        },
                    },
                    {
                        description: {
                            contains: search,
                            mode: 'insensitive',
                        },
                    },
                    {
                        category: {
                            contains: search,
                            mode: 'insensitive',
                        },
                    },
                    {
                        subcategory: {
                            contains: search,
                            mode: 'insensitive',
                        },
                    },
                    {
                        city: {
                            contains: search,
                            mode: 'insensitive',
                        },
                    },
                    {
                        address: {
                            contains: search,
                            mode: 'insensitive',
                        },
                    },
                    {
                        ownerName: {
                            contains: search,
                            mode: 'insensitive',
                        },
                    },
                ],
            });
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
                .filter((listing) => listing != null);
            const nextCursor = hasMore && pageRows.length > 0
                ? Buffer.from(JSON.stringify(toRankedFeedCursorPayload(pageRows[pageRows.length - 1]))).toString('base64url')
                : null;
            return {
                items: pageItems.map((listing) => (0, serializers_1.serializeListing)(listing)),
                nextCursor,
                hasMore,
                allowed_statuses: exports.LISTING_STATUSES,
            };
        }
        const cursorWhere = buildPublicFeedCursorWhere(cursor);
        if (cursorWhere != null) {
            if (where.AND == null) {
                where.AND = [cursorWhere];
            }
            else if (Array.isArray(where.AND)) {
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
        const nextCursor = hasMore && pageItems.length > 0
            ? encodeFeedCursor(pageItems[pageItems.length - 1])
            : null;
        return {
            items: pageItems.map((listing) => (0, serializers_1.serializeListing)(listing)),
            nextCursor,
            hasMore,
            allowed_statuses: exports.LISTING_STATUSES,
        };
    }
    async findPublicFeedRankedRows(params) {
        const whereParts = [
            client_1.Prisma.sql `l."deleted_at" IS NULL`,
            client_1.Prisma.sql `l."status"::text = 'APPROVED'`,
            client_1.Prisma.sql `EXISTS (
        SELECT 1
        FROM "listing_photos" lp
        WHERE lp."listing_id" = l."id"
      )`,
            client_1.Prisma.sql `u."deleted_at" IS NULL`,
            client_1.Prisma.sql `u."status"::text = 'ACTIVE'`,
        ];
        if (params.category && params.category.toLowerCase() !== 'все') {
            whereParts.push(client_1.Prisma.sql `l."category" = ${params.category}`);
        }
        if (params.city) {
            const cityPattern = `%${params.city}%`;
            whereParts.push(client_1.Prisma.sql `(
        l."city" ILIKE ${cityPattern}
        OR l."address" ILIKE ${cityPattern}
      )`);
        }
        if (typeof params.minPrice === 'number') {
            whereParts.push(client_1.Prisma.sql `l."price" >= ${params.minPrice}`);
        }
        if (typeof params.maxPrice === 'number') {
            whereParts.push(client_1.Prisma.sql `l."price" <= ${params.maxPrice}`);
        }
        if (params.search) {
            const searchPattern = `%${params.search}%`;
            whereParts.push(client_1.Prisma.sql `(
        l."title" ILIKE ${searchPattern}
        OR l."description" ILIKE ${searchPattern}
        OR l."category" ILIKE ${searchPattern}
        OR l."subcategory" ILIKE ${searchPattern}
        OR l."city" ILIKE ${searchPattern}
        OR l."address" ILIKE ${searchPattern}
        OR l."owner_name" ILIKE ${searchPattern}
      )`);
        }
        const cursor = this.buildRankedFeedCursorSql(params.cursor);
        const rows = await this.prisma.$queryRaw `
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
        WHERE ${client_1.Prisma.join(whereParts, ' AND ')}
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
          SUM(
            CASE
              WHEN promoted_at IS NOT NULL
                AND natural_rank > ${PROTECTED_FEED_HEAD_SIZE}
                THEN 1
              ELSE 0
            END
          ) OVER (
            ORDER BY natural_rank ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
          ) AS moved_rank,
          COUNT(*) FILTER (
            WHERE promoted_at IS NOT NULL
              AND natural_rank > ${PROTECTED_FEED_HEAD_SIZE}
          ) OVER () AS moved_count
        FROM ranked
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
              THEN ${PROTECTED_FEED_HEAD_SIZE}
                - LEAST(moved_count, ${PROTECTED_FEED_HEAD_SIZE})
                + moved_rank
            WHEN natural_rank >= (
              ${PROTECTED_FEED_HEAD_SIZE}
                - LEAST(moved_count, ${PROTECTED_FEED_HEAD_SIZE})
                + 1
            ) THEN natural_rank + LEAST(moved_count, ${PROTECTED_FEED_HEAD_SIZE})
            ELSE natural_rank
          END AS sort_group,
          COALESCE("published_at", "created_at") AS sort_at
        FROM moved
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
    buildRankedFeedCursorSql(cursor) {
        if (cursor == null ||
            cursor.sortGroup == null ||
            cursor.sortAt == null) {
            return client_1.Prisma.sql `TRUE`;
        }
        const sortAt = new Date(cursor.sortAt);
        const createdAt = new Date(cursor.createdAt);
        if (Number.isNaN(sortAt.getTime()) ||
            Number.isNaN(createdAt.getTime())) {
            return client_1.Prisma.sql `TRUE`;
        }
        return client_1.Prisma.sql `(
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
    async findOne(id, authUser) {
        const listing = await this.prisma.listing.findUnique({
            where: {
                id,
            },
            include: listingInclude,
        });
        if (!listing) {
            throw new common_1.NotFoundException('Listing not found');
        }
        const isAdmin = authUser?.role === 'admin';
        const isOwner = authUser?.userId === listing.ownerId;
        const isPublic = listing.status === client_1.ListingStatus.APPROVED &&
            listing.photos.length > 0 &&
            listing.deletedAt == null &&
            listing.owner?.deletedAt == null &&
            listing.owner?.status === client_1.UserStatus.ACTIVE;
        if (!isPublic && !isOwner && !isAdmin) {
            throw new common_1.NotFoundException('Listing not found');
        }
        return {
            listing: (0, serializers_1.serializeListing)(listing),
            ...this.promotionsService.enrichListing(listing, authUser),
        };
    }
    async update(id, authUser, dto) {
        await this.userBlocksService.assertNotBlocked(authUser.userId);
        const listing = await this.prisma.listing.findUnique({
            where: {
                id,
            },
            include: listingInclude,
        });
        if (!listing) {
            throw new common_1.NotFoundException('Listing not found');
        }
        if (listing.ownerId !== authUser.userId) {
            throw new common_1.ForbiddenException('Only owner can update listing');
        }
        if (dto.status &&
            dto.status.trim().toLowerCase() !== listing.status.toLowerCase() &&
            authUser.role !== 'admin') {
            throw new common_1.ForbiddenException('Use explicit archive endpoint for sold/archive status changes');
        }
        const requestedStatus = dto.status
            ? (0, serializers_1.listingStatusFromInput)(dto.status)
            : undefined;
        const nextStatus = requestedStatus != null && requestedStatus !== client_1.ListingStatus.APPROVED
            ? requestedStatus
            : this.statusAfterOwnerEdit(listing, authUser);
        const nextPhone = this.pickListingPhone(dto.phone, listing.owner?.phone ?? listing.phone);
        const updated = await this.prisma.$transaction(async (tx) => {
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
                    latitude: dto.location && typeof dto.location['latitude'] === 'number'
                        ? dto.location['latitude']
                        : undefined,
                    longitude: dto.location && typeof dto.location['longitude'] === 'number'
                        ? dto.location['longitude']
                        : undefined,
                    phone: nextPhone,
                    phoneHidden: dto.phone_hidden,
                    delivery: dto.delivery ? toInputJson(dto.delivery) : undefined,
                    locationJson: dto.location ? toInputJson(dto.location) : undefined,
                    car: dto.car ? toNullableInputJson(dto.car) : undefined,
                    dealType: dto.deal_type?.trim(),
                    realEstateType: dto.real_estate_type?.trim(),
                    clothesType: dto.clothes_type?.trim(),
                    clothesSize: dto.category?.trim() === 'Одежда' || listing.category === 'Одежда'
                        ? dto.clothes_size?.trim()
                        : undefined,
                    status: nextStatus,
                    ...(nextStatus === client_1.ListingStatus.PENDING &&
                        listing.status === client_1.ListingStatus.APPROVED
                        ? this.pendingModerationUpdateData()
                        : {}),
                    archivedAt: nextStatus === client_1.ListingStatus.ARCHIVED ? new Date() : listing.archivedAt,
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
            listing: (0, serializers_1.serializeListing)(updated),
        };
    }
    async remove(id, authUser) {
        if (authUser.role !== 'admin') {
            await this.userBlocksService.assertNotBlocked(authUser.userId);
        }
        const listing = await this.prisma.listing.findUnique({
            where: {
                id,
            },
        });
        if (!listing) {
            throw new common_1.NotFoundException('Listing not found');
        }
        const canDelete = listing.ownerId === authUser.userId || authUser.role === 'admin';
        if (!canDelete) {
            throw new common_1.ForbiddenException('Удалять объявление может только владелец или администратор');
        }
        const updated = await this.prisma.listing.update({
            where: {
                id,
            },
            data: {
                status: client_1.ListingStatus.DELETED,
                deletedAt: new Date(),
            },
            include: listingInclude,
        });
        await this.storageService.deleteListingPhotosForListings([id]);
        return {
            listing: (0, serializers_1.serializeListing)(updated),
            status_after_delete: (0, serializers_1.listingStatusToResponse)(client_1.ListingStatus.DELETED),
        };
    }
    async archive(id, authUser, dto) {
        if (authUser.role !== 'admin') {
            await this.userBlocksService.assertNotBlocked(authUser.userId);
        }
        const listing = await this.prisma.listing.findUnique({
            where: {
                id,
            },
        });
        if (!listing) {
            throw new common_1.NotFoundException('Listing not found');
        }
        if (listing.ownerId !== authUser.userId) {
            throw new common_1.ForbiddenException('Only owner can archive listing');
        }
        const nextStatus = dto?.status?.trim().toLowerCase() === 'sold'
            ? client_1.ListingStatus.SOLD
            : client_1.ListingStatus.ARCHIVED;
        const nextNote = dto?.note?.trim();
        const updated = await this.prisma.listing.update({
            where: {
                id,
            },
            data: {
                status: nextStatus,
                rejectionReason: nextNote && nextNote.length > 0
                    ? nextNote
                    : nextStatus === client_1.ListingStatus.SOLD
                        ? 'Объявление отмечено как проданное.'
                        : 'Объявление снято с публикации.',
                archivedAt: new Date(),
            },
            include: listingInclude,
        });
        return {
            listing: (0, serializers_1.serializeListing)(updated),
            status_after_archive: (0, serializers_1.listingStatusToResponse)(nextStatus),
        };
    }
    async incrementView(listingId, viewerUserId, viewerDeviceId) {
        const listing = await this.prisma.listing.findUnique({
            where: {
                id: listingId,
            },
        });
        if (!listing) {
            throw new common_1.NotFoundException('Listing not found');
        }
        const updated = await this.prisma.$transaction(async (tx) => {
            await tx.listingView.create({
                data: {
                    listingId,
                    viewerUserId: viewerUserId || null,
                    viewerDeviceId: viewerDeviceId || null,
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
    async findMy(authUser) {
        const listings = await this.prisma.listing.findMany({
            where: {
                deletedAt: null,
                ownerId: authUser.userId,
            },
            include: listingInclude,
            orderBy: [
                {
                    publishedAt: 'desc',
                },
                {
                    createdAt: 'desc',
                },
                {
                    id: 'desc',
                },
            ],
        });
        listings.sort(compareFeedByFreshness);
        const listingIds = listings.map((listing) => listing.id);
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
        const favoriteCountByListingId = new Map();
        for (const favorite of favorites) {
            favoriteCountByListingId.set(favorite.listingId, (favoriteCountByListingId.get(favorite.listingId) ?? 0) + 1);
        }
        return {
            items: listings.map((listing) => (0, serializers_1.serializeListing)(listing, {
                favoriteCount: favoriteCountByListingId.get(listing.id) ?? 0,
            })),
            allowed_statuses: exports.LISTING_STATUSES,
        };
    }
    async uploadPhoto(authUser, listingId, file, sortOrder) {
        const listing = await this.prisma.listing.findUnique({
            where: {
                id: listingId,
            },
            include: listingInclude,
        });
        if (!listing) {
            throw new common_1.NotFoundException('Listing not found');
        }
        if (listing.ownerId !== authUser.userId && authUser.role !== 'admin') {
            throw new common_1.ForbiddenException('Only owner or admin can upload listing photo');
        }
        if (listing.photos.length >= 10) {
            throw new common_1.BadRequestException('Listing photo limit is 10');
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
        const photo = await this.prisma.listingPhoto.create({
            data: {
                listingId,
                storageBucket: uploaded.bucket ?? 'local',
                storageKey: uploaded.key,
                publicUrl: uploaded.url,
                sortOrder: typeof sortOrder === 'number' && Number.isFinite(sortOrder) && sortOrder >= 0
                    ? Math.trunc(sortOrder)
                    : listing.photos.length,
                sizeBytes: uploaded.sizeBytes,
                mimeType: uploaded.mimeType,
            },
        });
        await this.resubmitPublishedListingAfterOwnerEdit(listing, authUser);
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
            listing: (0, serializers_1.serializeListing)(updated),
        };
    }
    async deletePhoto(authUser, listingId, photoId) {
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
            throw new common_1.NotFoundException('Listing not found');
        }
        if (listing.ownerId !== authUser.userId && authUser.role !== 'admin') {
            throw new common_1.ForbiddenException('Only owner or admin can delete listing photo');
        }
        const photo = listing.photos.find((item) => item.id === photoId);
        if (!photo) {
            throw new common_1.NotFoundException('Listing photo not found');
        }
        if (listing.photos.length <= 1 && this.requiresPhotoBeforePublication(listing.status)) {
            throw new common_1.BadRequestException(exports.LISTING_PHOTO_REQUIRED);
        }
        await this.storageService.deleteStoredFile('listings', photo.storageKey);
        await this.prisma.listingPhoto.delete({
            where: {
                id: photoId,
            },
        });
        const remaining = await this.prisma.listingPhoto.findMany({
            where: {
                listingId,
            },
            orderBy: {
                sortOrder: 'asc',
            },
        });
        await Promise.all(remaining.map((item, index) => this.prisma.listingPhoto.update({
            where: { id: item.id },
            data: { sortOrder: index },
        })));
        await this.resubmitPublishedListingAfterOwnerEdit(listing, authUser);
        const updated = await this.prisma.listing.findUniqueOrThrow({
            where: { id: listingId },
            include: listingInclude,
        });
        return {
            source: 'timeweb',
            deleted: true,
            photo_id: photoId,
            listing: (0, serializers_1.serializeListing)(updated),
        };
    }
    pickListingPhone(rawPhone, fallbackPhone) {
        const candidate = rawPhone?.trim() || fallbackPhone?.trim() || '';
        if (!candidate) {
            return '';
        }
        const normalized = (0, phone_1.normalizeRussianPhone)(candidate);
        if (!normalized) {
            return candidate;
        }
        (0, phone_1.validateRussianPhoneOrThrow)(normalized);
        return normalized;
    }
    statusAfterOwnerEdit(listing, authUser) {
        if (listing.ownerId === authUser.userId &&
            listing.status === client_1.ListingStatus.APPROVED) {
            return client_1.ListingStatus.PENDING;
        }
        return listing.status;
    }
    pendingModerationUpdateData() {
        return {
            rejectionReason: null,
            moderationNote: null,
            moderatedBy: null,
            moderatedAt: null,
            archivedAt: null,
            deletedAt: null,
        };
    }
    requiresPhotoBeforePublication(status) {
        switch (status) {
            case client_1.ListingStatus.APPROVED:
            case client_1.ListingStatus.PENDING:
            case client_1.ListingStatus.REJECTED:
            case client_1.ListingStatus.ARCHIVED:
                return true;
            default:
                return false;
        }
    }
    async resubmitPublishedListingAfterOwnerEdit(listing, authUser) {
        if (this.statusAfterOwnerEdit(listing, authUser) !== client_1.ListingStatus.PENDING) {
            return;
        }
        await this.prisma.listing.update({
            where: { id: listing.id },
            data: {
                status: client_1.ListingStatus.PENDING,
                ...this.pendingModerationUpdateData(),
            },
        });
    }
};
exports.ListingsService = ListingsService;
exports.ListingsService = ListingsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        storage_service_1.StorageService,
        promotions_service_1.PromotionsService,
        user_blocks_service_1.UserBlocksService])
], ListingsService);
//# sourceMappingURL=listings.service.js.map