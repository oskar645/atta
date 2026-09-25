import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ForbiddenException } from '@nestjs/common';

import { ReviewsService } from './reviews.service';

const storedReview = {
  id: 'review-1', sellerId: 'seller-1', reviewerId: 'reviewer-1',
  reviewerName: 'Reviewer', listingId: null, rating: 5, comment: 'Good',
  replyText: null, replyAt: null, createdAt: new Date('2026-01-01'),
  updatedAt: null, deletedAt: null, reviewer: undefined, seller: undefined,
};

const createService = (reviewerId = storedReview.reviewerId) => {
  let updateCalls = 0;
  const service = new ReviewsService({ review: {
    findUnique: async () => ({ ...storedReview, reviewerId }),
    update: async () => {
      updateCalls += 1;
      return { ...storedReview, reviewerId, deletedAt: new Date(), updatedAt: new Date() };
    },
  } } as never, {} as never);
  return { service, updateCalls: () => updateCalls };
};

test('seller cannot delete another reviewer review about them', async () => {
  const fixture = createService();
  await assert.rejects(() => fixture.service.deleteReview(
    { userId: 'seller-1', role: 'user' } as never, 'review-1'), ForbiddenException);
  assert.equal(fixture.updateCalls(), 0);
});
test('reviewer can delete their own review', async () => {
  const fixture = createService();
  const response = await fixture.service.deleteReview(
    { userId: 'reviewer-1', role: 'user' } as never, 'review-1');
  assert.equal(response.deleted, true);
  assert.equal(fixture.updateCalls(), 1);
});
test('admin can delete any review including their own', async () => {
  const fixture = createService();
  const ownReviewFixture = createService('unrelated-admin');
  await fixture.service.deleteReview(
    { userId: 'unrelated-admin', role: 'admin' } as never, 'review-1');
  await ownReviewFixture.service.deleteReview(
    { userId: 'unrelated-admin', role: 'admin' } as never, 'review-1');
  assert.equal(fixture.updateCalls(), 1);
  assert.equal(ownReviewFixture.updateCalls(), 1);
});
test('unrelated user cannot delete another review', async () => {
  const fixture = createService();
  await assert.rejects(() => fixture.service.deleteReview(
    { userId: 'other-1', role: 'user' } as never, 'review-1'), ForbiddenException);
  assert.equal(fixture.updateCalls(), 0);
});
