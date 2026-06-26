"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.serializeFavorite = exports.serializeListing = exports.listingStatusFromInput = exports.listingStatusToResponse = exports.serializeAdminProfile = exports.serializeUser = exports.normalizeStoredMediaUrl = exports.normalizeJsonRecord = exports.toIsoString = void 0;
const client_1 = require("@prisma/client");
const env_1 = require("../config/env");
const phone_1 = require("./phone");
const toIsoString = (value) => value ? value.toISOString() : null;
exports.toIsoString = toIsoString;
const normalizeJsonRecord = (value) => {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
        return {};
    }
    return value;
};
exports.normalizeJsonRecord = normalizeJsonRecord;
const cacheBustedMediaUrl = (url, version) => {
    const trimmedUrl = (0, exports.normalizeStoredMediaUrl)(url);
    if (!trimmedUrl) {
        return null;
    }
    if (!version || trimmedUrl.includes('v=')) {
        return trimmedUrl;
    }
    const separator = trimmedUrl.includes('?') ? '&' : '?';
    return `${trimmedUrl}${separator}v=${encodeURIComponent(version.toISOString())}`;
};
const normalizeS3ObjectKey = (value) => {
    let normalized = decodeURIComponent((value ?? '').trim()).replace(/^\/+/, '');
    const bucket = env_1.env.S3_BUCKET.trim();
    while (bucket.length > 0 &&
        normalized.toLowerCase().startsWith(`${bucket.toLowerCase()}/`)) {
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
const inferCategoryFromKey = (key) => {
    const normalized = normalizeS3ObjectKey(key).toLowerCase();
    if (normalized.startsWith('avatars/'))
        return 'avatars';
    if (normalized.startsWith('listings/') ||
        normalized.startsWith('listing-photos/')) {
        return 'listings';
    }
    if (normalized.startsWith('chats/') ||
        normalized.startsWith('chat-images/')) {
        return 'chats';
    }
    if (normalized.startsWith('support/') ||
        normalized.startsWith('support-images/')) {
        return 'support';
    }
    if (normalized.startsWith('reports/'))
        return 'reports';
    if (normalized.startsWith('videos/'))
        return 'videos';
    if (normalized.startsWith('misc/'))
        return 'misc';
    if (normalized.startsWith('feed-ads/'))
        return 'feed-ads';
    return null;
};
const buildProxyMediaUrl = (category, key) => {
    const normalizedKey = normalizeS3ObjectKey(key);
    if (category === 'chats') {
        return `/media/chats/file?key=${encodeURIComponent(normalizedKey)}`;
    }
    return `/media/object?category=${encodeURIComponent(category)}&key=${encodeURIComponent(normalizedKey)}`;
};
const normalizeStoredMediaUrl = (url, options) => {
    const trimmedUrl = url?.trim() ?? '';
    if (!trimmedUrl) {
        return null;
    }
    if (trimmedUrl.startsWith('/media/') ||
        trimmedUrl.startsWith('/uploads/') ||
        trimmedUrl.startsWith(env_1.env.MEDIA_PUBLIC_BASE_URL.replace(/\/+$/, ''))) {
        return trimmedUrl;
    }
    const providerHint = options?.providerHint?.trim().toLowerCase() ?? '';
    const storageKey = normalizeS3ObjectKey(options?.storageKey);
    const preferredCategory = options?.category?.trim().toLowerCase() ??
        inferCategoryFromKey(storageKey) ??
        '';
    const isS3Candidate = providerHint === 's3' ||
        (providerHint !== 'local' &&
            (storageKey.length > 0 ||
                (env_1.env.S3_ENDPOINT.trim().length > 0 &&
                    trimmedUrl.includes(env_1.env.S3_ENDPOINT.replace(/\/+$/, '')))));
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
        }
        catch {
            return trimmedUrl;
        }
    }
    return trimmedUrl;
};
exports.normalizeStoredMediaUrl = normalizeStoredMediaUrl;
const serializeUser = (user, options) => {
    const isAdmin = user.adminProfile?.isAdmin === true;
    const role = isAdmin ? 'admin' : 'user';
    const base = {
        id: user.id,
        display_name: user.displayName,
        name: user.name,
        avatar_url: cacheBustedMediaUrl((0, exports.normalizeStoredMediaUrl)(user.avatarUrl, {
            category: 'avatars',
        }), user.updatedAt),
        avatarUrl: cacheBustedMediaUrl((0, exports.normalizeStoredMediaUrl)(user.avatarUrl, {
            category: 'avatars',
        }), user.updatedAt),
        photo_url: cacheBustedMediaUrl((0, exports.normalizeStoredMediaUrl)(user.photoUrl, {
            category: 'avatars',
        }), user.updatedAt),
        normalized_phone: user.phone,
        normalizedPhone: user.phone,
        phone_verified: user.phoneVerified,
        phoneVerified: user.phoneVerified,
        isPhoneVerified: user.phoneVerified,
        is_admin: isAdmin,
        isAdmin,
        role,
        status: user.status.toLowerCase(),
        last_login_at: (0, exports.toIsoString)(user.lastLoginAt),
        avatar_updated_at: (0, exports.toIsoString)(user.updatedAt),
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
        blocked_at: (0, exports.toIsoString)(user.blockedAt),
        block_reason: user.blockReason,
        deleted_at: (0, exports.toIsoString)(user.deletedAt),
    };
};
exports.serializeUser = serializeUser;
const serializeAdminProfile = (adminProfile) => adminProfile
    ? {
        user_id: adminProfile.userId,
        is_admin: adminProfile.isAdmin,
        role: adminProfile.role,
        permissions: adminProfile.permissions,
        created_at: adminProfile.createdAt.toISOString(),
    }
    : null;
exports.serializeAdminProfile = serializeAdminProfile;
const listingStatusToResponse = (status) => status.toLowerCase();
exports.listingStatusToResponse = listingStatusToResponse;
const listingStatusFromInput = (status) => {
    switch ((status ?? 'pending').trim().toLowerCase()) {
        case 'approved':
            return client_1.ListingStatus.APPROVED;
        case 'rejected':
            return client_1.ListingStatus.REJECTED;
        case 'sold':
            return client_1.ListingStatus.SOLD;
        case 'deleted':
            return client_1.ListingStatus.DELETED;
        case 'archived':
            return client_1.ListingStatus.ARCHIVED;
        case 'pending':
        default:
            return client_1.ListingStatus.PENDING;
    }
};
exports.listingStatusFromInput = listingStatusFromInput;
const serializeListing = (listing) => ({
    ...(() => {
        const fallbackPhone = listing.phone?.trim() || listing.owner?.phone?.trim() || '';
        const normalizedPhone = (0, phone_1.normalizeRussianPhone)(fallbackPhone) || fallbackPhone;
        return {
            phone: normalizedPhone,
        };
    })(),
    ...(() => {
        const activePromotions = new Map();
        for (const promotion of listing.promotions ?? []) {
            if (promotion.status === client_1.PromotionStatus.ACTIVE &&
                promotion.endsAt.getTime() > Date.now() &&
                !activePromotions.has(promotion.type)) {
                activePromotions.set(promotion.type, promotion);
            }
        }
        const serializePromotion = (promotionType, title) => {
            const promotion = activePromotions.get(promotionType);
            if (!promotion) {
                return null;
            }
            return {
                type: promotion.type.toLowerCase(),
                title,
                endsAt: (0, exports.toIsoString)(promotion.endsAt),
                status: promotion.status.toLowerCase(),
                costBonus: promotion.costBonus,
            };
        };
        return {
            promotions: {
                activeShowcase: serializePromotion(client_1.PromotionType.SHOWCASE, 'Витрина ATTA'),
                activeBump: serializePromotion(client_1.PromotionType.BUMP, 'Поднятие'),
                activeVip: serializePromotion(client_1.PromotionType.VIP, 'VIP'),
                activeTurbo: serializePromotion(client_1.PromotionType.TURBO, 'Турбо'),
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
    price: typeof listing.price === 'bigint'
        ? Number(listing.price)
        : Number(listing.price ?? 0),
    phone_hidden: listing.phoneHidden,
    city: listing.city,
    address: listing.address,
    latitude: listing.latitude ? Number(listing.latitude) : null,
    longitude: listing.longitude ? Number(listing.longitude) : null,
    location: (0, exports.normalizeJsonRecord)(listing.locationJson),
    location_json: (0, exports.normalizeJsonRecord)(listing.locationJson),
    delivery: (0, exports.normalizeJsonRecord)(listing.delivery),
    car: listing.car ?? null,
    deal_type: listing.dealType,
    real_estate_type: listing.realEstateType,
    clothes_type: listing.clothesType,
    photo_urls: listing.photos?.map((photo) => (0, exports.normalizeStoredMediaUrl)(photo.publicUrl, {
        category: 'listings',
        providerHint: photo.storageBucket,
        storageKey: photo.storageKey,
    }) ?? photo.publicUrl) ?? [],
    photo_items: listing.photos?.map((photo) => ({
        id: photo.id,
        url: (0, exports.normalizeStoredMediaUrl)(photo.publicUrl, {
            category: 'listings',
            providerHint: photo.storageBucket,
            storageKey: photo.storageKey,
        }) ?? photo.publicUrl,
        sort_order: photo.sortOrder,
    })) ?? [],
    view_count: listing.viewCount,
    status: (0, exports.listingStatusToResponse)(listing.status),
    rejection_reason: listing.rejectionReason ?? '',
    moderation_note: listing.moderationNote,
    moderated_by: listing.moderatedBy,
    moderated_at: (0, exports.toIsoString)(listing.moderatedAt),
    published_at: (0, exports.toIsoString)(listing.publishedAt),
    archived_at: (0, exports.toIsoString)(listing.archivedAt),
    deleted_at: (0, exports.toIsoString)(listing.deletedAt),
    created_at: listing.createdAt.toISOString(),
    updated_at: listing.updatedAt.toISOString(),
    owner: listing.owner
        ? (0, exports.serializeUser)(listing.owner)
        : {
            id: listing.ownerId,
            display_name: listing.ownerName,
            name: listing.ownerName,
        },
});
exports.serializeListing = serializeListing;
const serializeFavorite = (favorite) => ({
    id: favorite.id,
    user_id: favorite.userId,
    listing_id: favorite.listingId,
    created_at: favorite.createdAt.toISOString(),
});
exports.serializeFavorite = serializeFavorite;
//# sourceMappingURL=serializers.js.map