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
  listingStatusFromInput,
  listingStatusToResponse,
  serializeListing,
} from '../../common/serializers';
import { normalizeRussianPhone, validateRussianPhoneOrThrow } from '../../common/phone';
import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import { PromotionsService } from '../promotions/promotions.service';
import { StorageService } from '../storage/storage.service';
import { UploadedImageFile } from '../storage/uploaded-image-file.type';
import { CreateListingDto } from './dto/create-listing.dto';
import { ArchiveListingDto } from './dto/archive-listing.dto';
import { UpdateListingDto } from './dto/update-listing.dto';

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

export const LISTING_STATUSES = [
  'pending',
  'approved',
  'rejected',
  'sold',
  'deleted',
  'archived',
] as const;

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
  bumpAt: string | null;
  publishedAt: string | null;
  createdAt: string;
  id: string;
};

const DEFAULT_FEED_HEAD_SIZE = 8;

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
  const tierWeight = {
    turbo: 0,
    vip: 1,
    bump: 2,
    none: 3,
  } satisfies Record<PaidFeedRank['tier'], number>;

  const tierDiff = tierWeight[aRank.tier] - tierWeight[bRank.tier];
  if (tierDiff !== 0) {
    return tierDiff;
  }

  const activatedDiff =
    (bRank.activatedAt?.getTime() ?? 0) - (aRank.activatedAt?.getTime() ?? 0);
  if (activatedDiff !== 0) {
    return activatedDiff;
  }

  return compareFeedByFreshness(a, b);
};

const buildPublicFeedOrder = <T extends FeedListingLike>(
  listings: T[],
  headSize = DEFAULT_FEED_HEAD_SIZE,
) => {
  const freshnessSorted = [...listings].sort(compareFeedByFreshness);
  const regular: T[] = [];
  const paid: T[] = [];

  for (const listing of freshnessSorted) {
    const rank = getPaidFeedRank(listing.promotions);
    if (rank.tier === 'none') {
      regular.push(listing);
    } else {
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

const toFeedCursorPayload = (listing: FeedListingLike): FeedCursorPayload => ({
  bumpAt: getPaidFeedRank(listing.promotions).activatedAt?.toISOString() ?? null,
  publishedAt: listing.publishedAt?.toISOString() ?? null,
  createdAt: listing.createdAt.toISOString(),
  id: listing.id,
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
      bumpAt:
        typeof parsed.bumpAt === 'string' && parsed.bumpAt.trim().length > 0
          ? parsed.bumpAt
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

@Injectable()
export class ListingsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storageService: StorageService,
    private readonly promotionsService: PromotionsService,
  ) {}

  async create(authUser: AuthenticatedUser, dto: CreateListingDto) {
    const owner = await this.prisma.user.findUnique({
      where: {
        id: authUser.userId,
      },
    });

    if (!owner || owner.status === UserStatus.DELETED) {
      throw new NotFoundException('Listing owner was not found');
    }

    const nextPhone = this.pickListingPhone(dto.phone, owner.phone);

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
        category: dto.category.trim(),
        subcategory: dto.subcategory?.trim() ?? '',
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
        status: listingStatusFromInput(dto.status),
        delivery: toInputJson(dto.delivery),
        locationJson: toInputJson(dto.location),
        car: dto.car ? toNullableInputJson(dto.car) : undefined,
        dealType: dto.deal_type?.trim() || null,
        realEstateType: dto.real_estate_type?.trim() || null,
        clothesType: dto.clothes_type?.trim() || null,
        publishedAt:
          listingStatusFromInput(dto.status) === ListingStatus.APPROVED
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
    limit?: number;
    cursor?: string;
  }) {
    const search = params?.search?.trim();
    const category = params?.category?.trim();
    const city = params?.city?.trim();
    const ownerId = params?.ownerId?.trim();
    const ownerMe = params?.ownerMe?.trim();
    const status = params?.status?.trim();
    const limit = Math.max(1, Math.min(params?.limit ?? 20, 50));
    const cursor = parseFeedCursor(params?.cursor);
    const andConditions: Prisma.ListingWhereInput[] = [];

    const where: Prisma.ListingWhereInput = {
      deletedAt: null,
    };

    if (ownerMe) {
      where.ownerId = ownerMe;
    } else if (ownerId) {
      where.ownerId = ownerId;
    }

    if (status) {
      where.status = listingStatusFromInput(status);
    } else if (!ownerMe && !ownerId) {
      where.status = ListingStatus.APPROVED;
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

    const startIndex =
      cursor == null
        ? 0
        : orderedListings.findIndex((listing) => listing.id === cursor.id) + 1;
    const safeStartIndex = startIndex < 0 ? 0 : startIndex;
    const pageItems = orderedListings.slice(safeStartIndex, safeStartIndex + limit);
    const hasMore = safeStartIndex + limit < orderedListings.length;
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

    const isAdmin = authUser?.role === 'admin';
    const isOwner = authUser?.userId === listing.ownerId;
    const isPublic =
      listing.status === ListingStatus.APPROVED &&
      listing.deletedAt == null &&
      listing.owner?.deletedAt == null &&
      listing.owner?.status === UserStatus.ACTIVE;

    if (!isPublic && !isOwner && !isAdmin) {
      throw new NotFoundException('Listing not found');
    }

    return {
      listing: serializeListing(listing),
      ...this.promotionsService.enrichListing(listing, authUser),
    };
  }

  async update(id: string, authUser: AuthenticatedUser, dto: UpdateListingDto) {
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
          dealType: dto.deal_type?.trim(),
          realEstateType: dto.real_estate_type?.trim(),
          clothesType: dto.clothes_type?.trim(),
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
    viewerUserId?: string,
    viewerDeviceId?: string,
  ) {
    const listing = await this.prisma.listing.findUnique({
      where: {
        id: listingId,
      },
    });

    if (!listing) {
      throw new NotFoundException('Listing not found');
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

  async findMy(authUser: AuthenticatedUser) {
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

    const favoriteCountByListingId = new Map<string, number>();
    for (const favorite of favorites) {
      favoriteCountByListingId.set(
        favorite.listingId,
        (favoriteCountByListingId.get(favorite.listingId) ?? 0) + 1,
      );
    }

    return {
      items: listings.map((listing) =>
        serializeListing(listing, {
          favoriteCount: favoriteCountByListingId.get(listing.id) ?? 0,
        }),
      ),
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

    const photo = await this.prisma.listingPhoto.create({
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
    await Promise.all(
      remaining.map((item, index) =>
        this.prisma.listingPhoto.update({
          where: { id: item.id },
          data: { sortOrder: index },
        }),
      ),
    );

    await this.resubmitPublishedListingAfterOwnerEdit(listing, authUser);

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

  private async resubmitPublishedListingAfterOwnerEdit(
    listing: { id: string; ownerId: string; status: ListingStatus },
    authUser: AuthenticatedUser,
  ) {
    if (this.statusAfterOwnerEdit(listing, authUser) !== ListingStatus.PENDING) {
      return;
    }

    await this.prisma.listing.update({
      where: { id: listing.id },
      data: {
        status: ListingStatus.PENDING,
        ...this.pendingModerationUpdateData(),
      },
    });
  }

}
