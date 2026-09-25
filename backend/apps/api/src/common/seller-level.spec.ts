import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  SellerLevelReview,
  getSellerLevels,
  sellerLevelFromMetrics,
} from './seller-level';

const sellerId = 'seller-1';
const review = (reviewerId: string, rating: number, options: Partial<SellerLevelReview> = {}): SellerLevelReview => ({
  id: options.id ?? `review-${reviewerId}`,
  reviewerId,
  rating,
  createdAt: options.createdAt ?? new Date('2026-01-01T00:00:00.000Z'),
  deletedAt: options.deletedAt ?? null,
});
const reviews = (positive: number, other = 0, otherRating = 1) => [
  ...Array.from({ length: positive }, (_, i) => review(`positive-${i}`, i % 2 ? 5 : 4)),
  ...Array.from({ length: other }, (_, i) => review(`other-${i}`, otherRating)),
];

test('15 active and 5/5 positive -> bronze', () => {
  assert.equal(sellerLevelFromMetrics(15, reviews(5), sellerId), 'bronze');
});
test('15 active and 5 positive below 80% -> none', () => {
  assert.equal(sellerLevelFromMetrics(15, reviews(5, 2), sellerId), null);
});
test('30 active, 15 positive and at least 85% -> silver', () => {
  assert.equal(sellerLevelFromMetrics(30, reviews(15, 2), sellerId), 'silver');
});
test('50 active, 25 positive and at least 90% -> gold', () => {
  assert.equal(sellerLevelFromMetrics(50, reviews(25, 2), sellerId), 'gold');
});
test('many negative reviews prevent gold', () => {
  assert.equal(sellerLevelFromMetrics(50, reviews(25, 5), sellerId), 'bronze');
});
test('ratings 3, 1 and 2 are not positive and remain in denominator', () => {
  assert.equal(sellerLevelFromMetrics(15, reviews(5, 1, 3), sellerId), 'bronze');
  assert.equal(sellerLevelFromMetrics(15, reviews(5, 2, 3), sellerId), null);
  assert.equal(sellerLevelFromMetrics(15, reviews(5, 2, 1), sellerId), null);
  assert.equal(sellerLevelFromMetrics(15, reviews(5, 2, 2), sellerId), null);
});
test('deleted and self reviews are ignored', () => {
  assert.equal(sellerLevelFromMetrics(15, [
    ...reviews(5),
    review('deleted', 1, { deletedAt: new Date() }),
    review(sellerId, 1),
  ], sellerId), 'bronze');
});
test('one reviewer contributes only the latest review', () => {
  assert.equal(sellerLevelFromMetrics(15, [
    ...reviews(5),
    review('duplicate', 5, { id: 'older' }),
    review('duplicate', 1, { id: 'newer', createdAt: new Date('2026-01-02') }),
  ], sellerId), 'bronze');
});
test('id deterministically breaks equal-createdAt ties', () => {
  const createdAt = new Date('2026-01-01');
  assert.equal(sellerLevelFromMetrics(15, [
    ...reviews(5),
    review('duplicate', 5, { id: 'a', createdAt }),
    review('duplicate', 1, { id: 'b', createdAt }),
  ], sellerId), 'bronze');
});
test('lower quality or fewer active listings lowers or removes medal', () => {
  assert.equal(sellerLevelFromMetrics(50, reviews(25, 2), sellerId), 'gold');
  assert.equal(sellerLevelFromMetrics(49, reviews(25, 2), sellerId), 'silver');
  assert.equal(sellerLevelFromMetrics(50, reviews(25, 7), sellerId), null);
  assert.equal(sellerLevelFromMetrics(14, reviews(25), sellerId), null);
});

test('seller levels for a page are loaded in two batch queries', async () => {
  let groupByCalls = 0;
  let reviewCalls = 0;
  const levels = await getSellerLevels({
    listing: {
      groupBy: async () => {
        groupByCalls += 1;
        return [
          { ownerId: 'seller-1', _count: { _all: 15 } },
          { ownerId: 'seller-2', _count: { _all: 30 } },
        ];
      },
    },
    review: {
      findMany: async () => {
        reviewCalls += 1;
        return [
          ...reviews(5).map((item) => ({ ...item, sellerId: 'seller-1' })),
          ...reviews(15).map((item, index) => ({
            ...item,
            id: `seller-2-${index}`,
            sellerId: 'seller-2',
          })),
        ];
      },
    },
  }, ['seller-1', 'seller-2', 'seller-1']);

  assert.equal(levels.get('seller-1'), 'bronze');
  assert.equal(levels.get('seller-2'), 'silver');
  assert.equal(groupByCalls, 1);
  assert.equal(reviewCalls, 1);
});
