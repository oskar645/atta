import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ListingStatus, UserStatus } from '@prisma/client';

import { normalizeStoredMediaUrl, serializeListing, serializeUser } from './serializers';

test('private user response exposes recovery-email verification status', () => {
  const verifiedAt = new Date('2026-09-24T10:00:00.000Z');
  const serialized = serializeUser({
    ...listingFixture({}).owner,
    emailVerifiedAt: verifiedAt,
  } as any, { includePrivate: true }) as any;

  assert.equal(serialized.email, 'owner@example.com');
  assert.equal(serialized.emailVerified, true);
  assert.equal(serialized.email_verified, true);
  assert.equal(serialized.emailVerifiedAt, verifiedAt.toISOString());
  assert.equal(serialized.email_verified_at, verifiedAt.toISOString());
});

test('support media urls normalize to protected support proxy', () => {
  assert.equal(
    normalizeStoredMediaUrl('/media/object?category=support&key=support%2Fticket-1%2Fphoto.jpg', {
      category: 'support',
    }),
    '/media/support/file?key=support%2Fticket-1%2Fphoto.jpg',
  );
  assert.equal(
    normalizeStoredMediaUrl('/uploads/support/ticket-1/photo.jpg', {
      category: 'support',
    }),
    '/media/support/file?key=support%2Fticket-1%2Fphoto.jpg',
  );
});

test('listing upload urls remain public-compatible', () => {
  assert.equal(
    normalizeStoredMediaUrl('/uploads/listings/listing-1/photo.jpg', {
      category: 'listings',
    }),
    '/uploads/listings/listing-1/photo.jpg',
  );
});

test('listing serialization exposes active price reduction for 48 hours', () => {
  const listing = listingFixture({
    price: BigInt(9000),
    previousPrice: BigInt(10000),
    priceReducedAt: new Date(Date.now() - 47 * 60 * 60 * 1000),
  });

  const serialized = serializeListing(listing as any);

  assert.equal(serialized.price, 9000);
  assert.equal(serialized.previous_price, 10000);
  assert.equal(typeof serialized.price_reduced_at, 'string');
});

test('listing serialization hides equal, increased and expired price states', () => {
  for (const listing of [
    listingFixture({
      price: BigInt(9000),
      previousPrice: BigInt(9000),
      priceReducedAt: new Date(),
    }),
    listingFixture({
      price: BigInt(11000),
      previousPrice: BigInt(9000),
      priceReducedAt: new Date(),
    }),
    listingFixture({
      price: BigInt(9000),
      previousPrice: BigInt(10000),
      priceReducedAt: new Date(Date.now() - 49 * 60 * 60 * 1000),
    }),
  ]) {
    const serialized = serializeListing(listing as any);

    assert.equal(serialized.previous_price, null);
    assert.equal(serialized.price_reduced_at, null);
  }
});

test('public listing serialization hides owner normalized phone when phone is hidden', () => {
  const serialized = serializeListing(
    listingFixture({
      phone: '79281234567',
      phoneHidden: true,
      owner: {
        ...listingFixture({}).owner,
        phone: '79281234567',
      },
    }) as any,
  );

  assert.equal(serialized.phone, null);
  const owner = serialized.owner as any;
  assert.equal('normalized_phone' in owner, false);
  assert.equal('normalizedPhone' in owner, false);
});

test('public listing serialization keeps owner normalized phone when phone is visible', () => {
  const serialized = serializeListing(
    listingFixture({
      phone: '79281234567',
      phoneHidden: false,
      owner: {
        ...listingFixture({}).owner,
        phone: '79281234567',
      },
    }) as any,
  );

  assert.equal(serialized.phone, '79281234567');
  const owner = serialized.owner as any;
  assert.equal(owner.normalized_phone, '79281234567');
  assert.equal(owner.normalizedPhone, '79281234567');
});

test('private listing serialization keeps owner normalized phone when phone is hidden', () => {
  const serialized = serializeListing(
    listingFixture({
      phone: '79281234567',
      phoneHidden: true,
      owner: {
        ...listingFixture({}).owner,
        phone: '79281234567',
      },
    }) as any,
    { includePrivateContact: true },
  );

  assert.equal(serialized.phone, '79281234567');
  const owner = serialized.owner as any;
  assert.equal(owner.normalized_phone, '79281234567');
  assert.equal(owner.normalizedPhone, '79281234567');
});

function listingFixture(overrides: Record<string, unknown>) {
  const now = new Date();
  return {
    id: 'listing-1',
    ownerId: 'owner-1',
    ownerEmail: 'owner@example.com',
    ownerName: 'Owner',
    title: 'Listing',
    description: '',
    category: 'misc',
    subcategory: '',
    price: BigInt(100),
    previousPrice: null,
    priceReducedAt: null,
    phone: '',
    phoneHidden: false,
    city: '',
    address: '',
    latitude: null,
    longitude: null,
    locationJson: {},
    delivery: {},
    car: null,
    dealType: null,
    realEstateType: null,
    clothesType: null,
    clothesSize: null,
    status: ListingStatus.APPROVED,
    rejectionReason: null,
    moderationNote: null,
    moderatedBy: null,
    moderatedAt: null,
    publishedAt: now,
    archivedAt: null,
    deletedAt: null,
    viewCount: 0,
    createdAt: now,
    updatedAt: now,
    owner: {
      id: 'owner-1',
      email: 'owner@example.com',
      phone: '',
      phoneVerified: true,
      displayName: 'Owner',
      name: 'Owner',
      avatarUrl: null,
      photoUrl: null,
      status: UserStatus.ACTIVE,
      blockedAt: null,
      blockReason: null,
      lastLoginAt: null,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    },
    photos: [],
    promotions: [],
    ...overrides,
  };
}
