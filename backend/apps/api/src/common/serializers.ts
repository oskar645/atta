import {
  AdminUser,
  Favorite,
  Listing,
  ListingPhoto,
  ListingStatus,
  Promotion,
  PromotionStatus,
  PromotionType,
  User,
} from '@prisma/client';
import { env } from '../config/env';
import { normalizeRussianPhone } from './phone';
import { buildReferralCode } from './referral-code';

type SerializedUser = {
  id: string;
  email: string | null;
  phone: string | null;
  normalized_phone: string | null;
  normalizedPhone: string | null;
  phone_verified: boolean;
  phoneVerified: boolean;
  isPhoneVerified: boolean;
  is_admin: boolean;
  isAdmin: boolean;
  role: 'user' | 'admin';
  display_name: string;
  name: string;
  avatar_url: string | null;
  avatarUrl: string | null;
  photo_url: string | null;
  avatar_updated_at: string | null;
  referral_code: string;
  referralCode: string;
  status: string;
  blocked_at: string | null;
  block_reason: string | null;
  last_login_at: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

type JsonRecord = Record<string, unknown>;

export const toIsoString = (value: Date | null | undefined): string | null =>
  value ? value.toISOString() : null;

export const normalizeJsonRecord = (value: unknown): JsonRecord => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return {};
  }

  return value as JsonRecord;
};

const cacheBustedMediaUrl = (
  url: string | null | undefined,
  version: Date | null | undefined,
) => {
  const trimmedUrl = normalizeStoredMediaUrl(url);
  if (!trimmedUrl) {
    return null;
  }
  if (!version || trimmedUrl.includes('v=')) {
    return trimmedUrl;
  }
  const separator = trimmedUrl.includes('?') ? '&' : '?';
  return `${trimmedUrl}${separator}v=${encodeURIComponent(version.toISOString())}`;
};

const normalizeS3ObjectKey = (value: string | null | undefined) => {
  let normalized = decodeURIComponent((value ?? '').trim()).replace(/^\/+/, '');
  const bucket = env.S3_BUCKET.trim();
  while (
    bucket.length > 0 &&
    normalized.toLowerCase().startsWith(`${bucket.toLowerCase()}/`)
  ) {
    normalized = normalized.slice(bucket.length + 1);
  }
  const parts = normalized
    .split('/')
    .map((segment) => segment.trim())
    .filter((segment) => segment.length > 0);
  while (parts.length >= 2 && parts[0] === parts[1]) {
    parts.shift();
  }
  normalized = parts.join('/');
  return normalized;
};

const inferCategoryFromKey = (key: string) => {
  const normalized = normalizeS3ObjectKey(key).toLowerCase();
  if (normalized.startsWith('avatars/')) return 'avatars';
  if (
    normalized.startsWith('listings/') ||
    normalized.startsWith('listing-photos/')
  ) {
    return 'listings';
  }
  if (
    normalized.startsWith('chats/') ||
    normalized.startsWith('chat-images/')
  ) {
    return 'chats';
  }
  if (
    normalized.startsWith('support/') ||
    normalized.startsWith('support-images/')
  ) {
    return 'support';
  }
  if (normalized.startsWith('reports/')) return 'reports';
  if (normalized.startsWith('videos/')) return 'videos';
  if (normalized.startsWith('misc/')) return 'misc';
  if (normalized.startsWith('feed-ads/')) return 'feed-ads';
  return null;
};

const buildProxyMediaUrl = (category: string, key: string) => {
  const normalizedKey = normalizeS3ObjectKey(key);
  if (category === 'chats') {
    return `/media/chats/file?key=${encodeURIComponent(normalizedKey)}`;
  }
  if (category === 'support') {
    return `/media/support/file?key=${encodeURIComponent(normalizedKey)}`;
  }
  return `/media/object?category=${encodeURIComponent(category)}&key=${encodeURIComponent(normalizedKey)}`;
};

export const normalizeStoredMediaUrl = (
  url: string | null | undefined,
  options?: {
    category?: string | null;
    providerHint?: string | null;
    storageKey?: string | null;
  },
) => {
  const trimmedUrl = url?.trim() ?? '';
  if (!trimmedUrl) {
    return null;
  }

  const preferredCategory = options?.category?.trim().toLowerCase() ??
      inferCategoryFromKey(normalizeS3ObjectKey(options?.storageKey)) ??
      '';
  if (preferredCategory === 'support') {
    try {
      const parsed = trimmedUrl.startsWith('/')
        ? new URL(trimmedUrl, 'https://local.invalid')
        : new URL(trimmedUrl);
      if (parsed.pathname === '/media/object') {
        const key = parsed.searchParams.get('key');
        if (key) {
          return buildProxyMediaUrl('support', key);
        }
      }
      const publicBase = env.MEDIA_PUBLIC_BASE_URL.replace(/\/+$/, '');
      const publicBasePath = new URL(publicBase).pathname.replace(/\/+$/, '');
      if (parsed.pathname.startsWith('/uploads/support/')) {
        return buildProxyMediaUrl(
          'support',
          parsed.pathname.replace(/^\/uploads\/+/, ''),
        );
      }
      if (
        publicBasePath &&
        parsed.pathname.startsWith(`${publicBasePath}/support/`)
      ) {
        return buildProxyMediaUrl(
          'support',
          parsed.pathname.slice(publicBasePath.length + 1),
        );
      }
    } catch {
      // Fall through to the generic normalizer.
    }
  }

  if (
    trimmedUrl.startsWith('/media/') ||
    trimmedUrl.startsWith('/uploads/') ||
    trimmedUrl.startsWith(env.MEDIA_PUBLIC_BASE_URL.replace(/\/+$/, ''))
  ) {
    return trimmedUrl;
  }

  const providerHint = options?.providerHint?.trim().toLowerCase() ?? '';
  const storageKey = normalizeS3ObjectKey(options?.storageKey);
  const isS3Candidate =
    providerHint === 's3' ||
    (providerHint !== 'local' &&
      (storageKey.length > 0 ||
        (env.S3_ENDPOINT.trim().length > 0 &&
          trimmedUrl.includes(env.S3_ENDPOINT.replace(/\/+$/, '')))));

  if (isS3Candidate) {
    if (storageKey.length > 0 && preferredCategory.length > 0) {
      return buildProxyMediaUrl(preferredCategory, storageKey);
    }

    try {
      const parsed = new URL(trimmedUrl);
      const segments = parsed.pathname
        .split('/')
        .map((segment) => segment.trim())
        .filter((segment) => segment.length > 0);
      while (segments.length >= 2 && segments[0] === segments[1]) {
        segments.splice(0, 1);
      }
      if (segments.length >= 2) {
        const extractedKey = storageKey.length > 0
          ? storageKey
          : segments.slice(1).join('/');
        const category = preferredCategory.length > 0
          ? preferredCategory
          : inferCategoryFromKey(extractedKey);
        if (category != null && category.length > 0) {
          return buildProxyMediaUrl(category, extractedKey);
        }
      }
    } catch {
      return trimmedUrl;
    }
  }

  return trimmedUrl;
};

export const serializeUser = (
  user: Pick<
    User,
    | 'id'
    | 'email'
    | 'phone'
    | 'phoneVerified'
    | 'displayName'
    | 'name'
    | 'avatarUrl'
    | 'photoUrl'
    | 'status'
    | 'blockedAt'
    | 'blockReason'
    | 'lastLoginAt'
    | 'createdAt'
    | 'updatedAt'
    | 'deletedAt'
  > & {
    adminProfile?: AdminUser | null;
  },
  options?: {
    includePrivate?: boolean;
  },
): SerializedUser | Omit<SerializedUser, 'email' | 'phone' | 'blocked_at' | 'block_reason' | 'deleted_at'> => {
  const isAdmin = user.adminProfile?.isAdmin === true;
  const role: 'user' | 'admin' = isAdmin ? 'admin' : 'user';
  const referralCode = buildReferralCode(user.id);

  const base = {
    id: user.id,
    display_name: user.displayName,
    name: user.name,
    avatar_url: cacheBustedMediaUrl(
      normalizeStoredMediaUrl(user.avatarUrl, {
        category: 'avatars',
      }),
      user.updatedAt,
    ),
    avatarUrl: cacheBustedMediaUrl(
      normalizeStoredMediaUrl(user.avatarUrl, {
        category: 'avatars',
      }),
      user.updatedAt,
    ),
    photo_url: cacheBustedMediaUrl(
      normalizeStoredMediaUrl(user.photoUrl, {
        category: 'avatars',
      }),
      user.updatedAt,
    ),
    normalized_phone: user.phone,
    normalizedPhone: user.phone,
    phone_verified: user.phoneVerified,
    phoneVerified: user.phoneVerified,
    isPhoneVerified: user.phoneVerified,
    is_admin: isAdmin,
    isAdmin,
    role,
    referral_code: referralCode,
    referralCode,
    status: user.status.toLowerCase(),
    last_login_at: toIsoString(user.lastLoginAt),
    avatar_updated_at: toIsoString(user.updatedAt),
    created_at: user.createdAt.toISOString(),
    updated_at: user.updatedAt.toISOString(),
  };

  if (!options?.includePrivate) {
    return base;
  }

  return {
    ...base,
    email: user.email,
    phone: user.phone,
    blocked_at: toIsoString(user.blockedAt),
    block_reason: user.blockReason,
    deleted_at: toIsoString(user.deletedAt),
  };
};

export const serializeAdminProfile = (adminProfile: AdminUser | null | undefined) =>
  adminProfile
    ? {
        user_id: adminProfile.userId,
        is_admin: adminProfile.isAdmin,
        role: adminProfile.role,
        permissions: adminProfile.permissions,
        created_at: adminProfile.createdAt.toISOString(),
      }
    : null;

export const listingStatusToResponse = (status: ListingStatus): string =>
  status.toLowerCase();

export const listingStatusFromInput = (status?: string): ListingStatus => {
  switch ((status ?? 'pending').trim().toLowerCase()) {
    case 'approved':
      return ListingStatus.APPROVED;
    case 'rejected':
      return ListingStatus.REJECTED;
    case 'sold':
      return ListingStatus.SOLD;
    case 'deleted':
      return ListingStatus.DELETED;
    case 'archived':
      return ListingStatus.ARCHIVED;
    case 'pending':
    default:
      return ListingStatus.PENDING;
  }
};

export const serializeListing = (
  listing: Listing & {
    photos?: ListingPhoto[];
    owner?: User | null;
    promotions?: Promotion[];
  },
  options?: {
    favoriteCount?: number | null;
  },
) => {
  const price =
    typeof listing.price === 'bigint'
      ? Number(listing.price)
      : Number(listing.price ?? 0);
  const previousPrice =
    listing.previousPrice == null
      ? null
      : typeof listing.previousPrice === 'bigint'
        ? Number(listing.previousPrice)
        : Number(listing.previousPrice);
  const priceReducedAt = listing.priceReducedAt ?? null;
  const hasActivePriceReduction =
    previousPrice != null &&
    Number.isFinite(previousPrice) &&
    previousPrice > price &&
    priceReducedAt != null &&
    Date.now() - priceReducedAt.getTime() < 48 * 60 * 60 * 1000;

  return {
  ...(() => {
    const fallbackPhone = listing.phone?.trim() || listing.owner?.phone?.trim() || '';
    const normalizedPhone = normalizeRussianPhone(fallbackPhone) || fallbackPhone;
    return {
      phone: normalizedPhone,
    };
  })(),
  ...(() => {
    const activePromotions = new Map<PromotionType, Promotion>();
    for (const promotion of listing.promotions ?? []) {
      if (
        promotion.status === PromotionStatus.ACTIVE &&
        promotion.endsAt.getTime() > Date.now() &&
        !activePromotions.has(promotion.type)
      ) {
        activePromotions.set(promotion.type, promotion);
      }
    }

    const serializePromotion = (promotionType: PromotionType, title: string) => {
      const promotion = activePromotions.get(promotionType);
      if (!promotion) {
        return null;
      }

      return {
        type: promotion.type.toLowerCase(),
        title,
        endsAt: toIsoString(promotion.endsAt),
        status: promotion.status.toLowerCase(),
        costBonus: promotion.costBonus,
      };
    };

    return {
      promotions: {
        activeShowcase: serializePromotion(
          PromotionType.SHOWCASE,
          'Витрина ATTA',
        ),
        activeBump: serializePromotion(PromotionType.BUMP, 'Поднятие'),
        activeVip: serializePromotion(PromotionType.VIP, 'VIP'),
        activeTurbo: serializePromotion(PromotionType.TURBO, 'Турбо'),
      },
    };
  })(),
  id: listing.id,
  owner_id: listing.ownerId,
  owner_email: listing.ownerEmail,
  owner_name: listing.ownerName,
  title: listing.title,
  description: listing.description,
  category: listing.category,
  subcategory: listing.subcategory,
  price,
  previous_price: hasActivePriceReduction ? previousPrice : null,
  price_reduced_at: hasActivePriceReduction ? toIsoString(priceReducedAt) : null,
  phone_hidden: listing.phoneHidden,
  city: listing.city,
  address: listing.address,
  latitude: listing.latitude ? Number(listing.latitude) : null,
  longitude: listing.longitude ? Number(listing.longitude) : null,
  location: normalizeJsonRecord(listing.locationJson),
  location_json: normalizeJsonRecord(listing.locationJson),
  delivery: normalizeJsonRecord(listing.delivery),
  car: listing.car ?? null,
  deal_type: listing.dealType,
  real_estate_type: listing.realEstateType,
  clothes_type: listing.clothesType,
  clothes_size: listing.clothesSize ?? null,
  photo_urls:
    listing.photos?.map((photo) =>
      normalizeStoredMediaUrl(photo.publicUrl, {
        category: 'listings',
        providerHint: photo.storageBucket,
        storageKey: photo.storageKey,
      }) ?? photo.publicUrl,
    ) ?? [],
  photo_items:
    listing.photos?.map((photo) => ({
      id: photo.id,
      url:
        normalizeStoredMediaUrl(photo.publicUrl, {
          category: 'listings',
          providerHint: photo.storageBucket,
          storageKey: photo.storageKey,
        }) ?? photo.publicUrl,
      sort_order: photo.sortOrder,
    })) ?? [],
  view_count: listing.viewCount,
  ...(options?.favoriteCount != null
    ? {
        favorites_count: Math.max(0, Number(options.favoriteCount) || 0),
      }
    : {}),
  status: listingStatusToResponse(listing.status),
  rejection_reason: listing.rejectionReason ?? '',
  moderation_note: listing.moderationNote,
  moderated_by: listing.moderatedBy,
  moderated_at: toIsoString(listing.moderatedAt),
  published_at: toIsoString(listing.publishedAt),
  archived_at: toIsoString(listing.archivedAt),
  deleted_at: toIsoString(listing.deletedAt),
  created_at: listing.createdAt.toISOString(),
  updated_at: listing.updatedAt.toISOString(),
  owner: listing.owner
    ? serializeUser(listing.owner)
    : {
        id: listing.ownerId,
        display_name: listing.ownerName,
        name: listing.ownerName,
      },
  };
};

export const serializeFavorite = (favorite: Favorite) => ({
  id: favorite.id,
  user_id: favorite.userId,
  listing_id: favorite.listingId,
  created_at: favorite.createdAt.toISOString(),
});
