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
exports.ListingsService = exports.LISTING_STATUSES = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const serializers_1 = require("../../common/serializers");
const phone_1 = require("../../common/phone");
const prisma_service_1 = require("../prisma/prisma.service");
const promotions_service_1 = require("../promotions/promotions.service");
const storage_service_1 = require("../storage/storage.service");
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
const toInputJson = (value) => (value ?? {});
const toNullableInputJson = (value) => (value ?? client_1.Prisma.JsonNull);
const DEFAULT_FEED_HEAD_SIZE = 8;
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
const buildPublicFeedOrder = (listings, headSize = DEFAULT_FEED_HEAD_SIZE) => {
    const freshnessSorted = [...listings].sort(compareFeedByFreshness);
    const regular = [];
    const paid = [];
    for (const listing of freshnessSorted) {
        const rank = getPaidFeedRank(listing.promotions);
        if (rank.tier === 'none') {
            regular.push(listing);
        }
        else {
            paid.push(listing);
        }
    }
    paid.sort(comparePaidFeedListings);
    return [
        ...regular.slice(0, headSize),
        ...paid,
        ...regular.slice(headSize),
    ];
};
const toFeedCursorPayload = (listing) => ({
    bumpAt: getPaidFeedRank(listing.promotions).activatedAt?.toISOString() ?? null,
    publishedAt: listing.publishedAt?.toISOString() ?? null,
    createdAt: listing.createdAt.toISOString(),
    id: listing.id,
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
            bumpAt: typeof parsed.bumpAt === 'string' && parsed.bumpAt.trim().length > 0
                ? parsed.bumpAt
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
let ListingsService = class ListingsService {
    constructor(prisma, storageService, promotionsService) {
        this.prisma = prisma;
        this.storageService = storageService;
        this.promotionsService = promotionsService;
    }
    async create(authUser, dto) {
        const owner = await this.prisma.user.findUnique({
            where: {
                id: authUser.userId,
            },
        });
        if (!owner || owner.status === client_1.UserStatus.DELETED) {
            throw new common_1.NotFoundException('Listing owner was not found');
        }
        const nextPhone = this.pickListingPhone(dto.phone, owner.phone);
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
                status: (0, serializers_1.listingStatusFromInput)(dto.status),
                delivery: toInputJson(dto.delivery),
                locationJson: toInputJson(dto.location),
                car: dto.car ? toNullableInputJson(dto.car) : undefined,
                dealType: dto.deal_type?.trim() || null,
                realEstateType: dto.real_estate_type?.trim() || null,
                clothesType: dto.clothes_type?.trim() || null,
                publishedAt: (0, serializers_1.listingStatusFromInput)(dto.status) === client_1.ListingStatus.APPROVED
                    ? new Date()
                    : null,
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
        const listings = await this.prisma.listing.findMany({
            where,
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
        const orderedListings = buildPublicFeedOrder(listings);
        const startIndex = cursor == null
            ? 0
            : orderedListings.findIndex((listing) => listing.id === cursor.id) + 1;
        const safeStartIndex = startIndex < 0 ? 0 : startIndex;
        const pageItems = orderedListings.slice(safeStartIndex, safeStartIndex + limit);
        const hasMore = safeStartIndex + limit < orderedListings.length;
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
        const nextStatus = dto.status
            ? (0, serializers_1.listingStatusFromInput)(dto.status)
            : listing.status;
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
                    status: nextStatus,
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
};
exports.ListingsService = ListingsService;
exports.ListingsService = ListingsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        storage_service_1.StorageService,
        promotions_service_1.PromotionsService])
], ListingsService);
//# sourceMappingURL=listings.service.js.map