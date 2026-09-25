"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.attachSellerLevels = exports.getSellerLevels = exports.sellerLevelFromMetrics = void 0;
const sellerLevelFromMetrics = (activeListingsCount, reviews, sellerId) => {
    const latestByReviewer = new Map();
    for (const review of reviews) {
        if (review.deletedAt || review.reviewerId === sellerId)
            continue;
        const current = latestByReviewer.get(review.reviewerId);
        if (!current ||
            review.createdAt.getTime() > current.createdAt.getTime() ||
            (review.createdAt.getTime() === current.createdAt.getTime() &&
                review.id > current.id)) {
            latestByReviewer.set(review.reviewerId, review);
        }
    }
    const eligibleReviews = [...latestByReviewer.values()];
    const positiveReviewsCount = eligibleReviews.filter(({ rating }) => rating >= 4).length;
    const positiveShare = eligibleReviews.length === 0
        ? 0
        : positiveReviewsCount / eligibleReviews.length;
    if (activeListingsCount >= 50 &&
        positiveReviewsCount >= 25 &&
        positiveShare >= 0.9)
        return 'gold';
    if (activeListingsCount >= 30 &&
        positiveReviewsCount >= 15 &&
        positiveShare >= 0.85)
        return 'silver';
    if (activeListingsCount >= 15 &&
        positiveReviewsCount >= 5 &&
        positiveShare >= 0.8)
        return 'bronze';
    return null;
};
exports.sellerLevelFromMetrics = sellerLevelFromMetrics;
const getSellerLevels = async (prisma, sellerIds) => {
    const ids = [...new Set([...sellerIds].map((id) => id.trim()).filter(Boolean))];
    const levels = new Map(ids.map((id) => [id, null]));
    if (ids.length === 0)
        return levels;
    const [listingCounts, reviews] = await Promise.all([
        prisma.listing.groupBy({
            by: ['ownerId'],
            where: {
                ownerId: { in: ids },
                status: 'APPROVED',
                publishedAt: { not: null },
                deletedAt: null,
            },
            _count: { _all: true },
        }),
        prisma.review.findMany({
            where: {
                sellerId: { in: ids },
                deletedAt: null,
            },
            select: {
                id: true,
                sellerId: true,
                reviewerId: true,
                rating: true,
                createdAt: true,
            },
        }),
    ]);
    const countBySeller = new Map(listingCounts.map((row) => [
        row.ownerId,
        typeof row._count === 'number'
            ? row._count
            : (row._count._all ?? row._count.id ?? 0),
    ]));
    const reviewsBySeller = new Map();
    for (const review of reviews) {
        const sellerReviews = reviewsBySeller.get(review.sellerId) ?? [];
        sellerReviews.push(review);
        reviewsBySeller.set(review.sellerId, sellerReviews);
    }
    for (const sellerId of ids) {
        levels.set(sellerId, (0, exports.sellerLevelFromMetrics)(countBySeller.get(sellerId) ?? 0, reviewsBySeller.get(sellerId) ?? [], sellerId));
    }
    return levels;
};
exports.getSellerLevels = getSellerLevels;
const attachSellerLevels = (listings, levels) => listings.map((listing) => {
    const sellerLevel = levels.get(listing.ownerId) ?? null;
    return {
        ...listing,
        owner: listing.owner
            ? { ...listing.owner, seller_level: sellerLevel, sellerLevel }
            : listing.owner,
    };
});
exports.attachSellerLevels = attachSellerLevels;
//# sourceMappingURL=seller-level.js.map