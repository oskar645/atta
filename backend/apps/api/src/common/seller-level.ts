export type SellerLevel = 'bronze' | 'silver' | 'gold';

export type SellerLevelReview = {
  id: string;
  reviewerId: string;
  rating: number;
  createdAt: Date;
  deletedAt?: Date | null;
};

type SellerLevelPrisma = {
  listing: {
    groupBy(args: unknown): Promise<Array<{
      ownerId: string;
      _count: { _all?: number; id?: number } | number;
    }>>;
  };
  review: {
    findMany(args: unknown): Promise<Array<SellerLevelReview & { sellerId: string }>>;
  };
};

export const sellerLevelFromMetrics = (
  activeListingsCount: number,
  reviews: SellerLevelReview[],
  sellerId: string,
): SellerLevel | null => {
  const latestByReviewer = new Map<string, SellerLevelReview>();

  for (const review of reviews) {
    if (review.deletedAt || review.reviewerId === sellerId) continue;

    const current = latestByReviewer.get(review.reviewerId);
    if (
      !current ||
      review.createdAt.getTime() > current.createdAt.getTime() ||
      (review.createdAt.getTime() === current.createdAt.getTime() &&
        review.id > current.id)
    ) {
      latestByReviewer.set(review.reviewerId, review);
    }
  }

  const eligibleReviews = [...latestByReviewer.values()];
  const positiveReviewsCount = eligibleReviews.filter(
    ({ rating }) => rating >= 4,
  ).length;
  const positiveShare = eligibleReviews.length === 0
    ? 0
    : positiveReviewsCount / eligibleReviews.length;

  if (
    activeListingsCount >= 50 &&
    positiveReviewsCount >= 25 &&
    positiveShare >= 0.9
  ) return 'gold';
  if (
    activeListingsCount >= 30 &&
    positiveReviewsCount >= 15 &&
    positiveShare >= 0.85
  ) return 'silver';
  if (
    activeListingsCount >= 15 &&
    positiveReviewsCount >= 5 &&
    positiveShare >= 0.8
  ) return 'bronze';
  return null;
};

export const getSellerLevels = async (
  prisma: SellerLevelPrisma,
  sellerIds: Iterable<string>,
): Promise<Map<string, SellerLevel | null>> => {
  const ids = [...new Set([...sellerIds].map((id) => id.trim()).filter(Boolean))];
  const levels = new Map<string, SellerLevel | null>(
    ids.map((id) => [id, null]),
  );
  if (ids.length === 0) return levels;

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

  const countBySeller = new Map(
    listingCounts.map((row) => [
      row.ownerId,
      typeof row._count === 'number'
        ? row._count
        : (row._count._all ?? row._count.id ?? 0),
    ]),
  );
  const reviewsBySeller = new Map<string, SellerLevelReview[]>();
  for (const review of reviews) {
    const sellerReviews = reviewsBySeller.get(review.sellerId) ?? [];
    sellerReviews.push(review);
    reviewsBySeller.set(review.sellerId, sellerReviews);
  }

  for (const sellerId of ids) {
    levels.set(
      sellerId,
      sellerLevelFromMetrics(
        countBySeller.get(sellerId) ?? 0,
        reviewsBySeller.get(sellerId) ?? [],
        sellerId,
      ),
    );
  }
  return levels;
};

export const attachSellerLevels = <T extends {
  ownerId: string;
  owner?: Record<string, unknown> | null;
}>(
  listings: T[],
  levels: ReadonlyMap<string, SellerLevel | null>,
): T[] => listings.map((listing) => {
  const sellerLevel = levels.get(listing.ownerId) ?? null;
  return {
    ...listing,
    owner: listing.owner
      ? { ...listing.owner, seller_level: sellerLevel, sellerLevel }
      : listing.owner,
  };
});
