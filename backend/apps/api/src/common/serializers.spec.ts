import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ListingStatus, UserStatus } from '@prisma/client';

import { normalizeStoredMediaUrl, serializeListing, serializeUser } from './serializers';

// Mirrors the call-contact lookup used by the published Flutter clients
// 1.0.24+28 and 1.0.26+30: prefer listing.phone, then fall back to the
// separately loaded public seller profile aliases.
function resolvePublishedClientPhone(
  listing: Record<string, any>,
  publicSeller: Record<string, any>,
) {
  for (const candidate of [
    listing.phone,
    publicSeller.phone,
    publicSeller.normalized_phone,
    publicSeller.normalizedPhone,
  ]) {
    const value = candidate?.toString().trim() ?? '';
    if (value) return value;
  }
  return '';
}

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
  assert.equal(serialized.has_call_contact, true);
  assert.equal(serialized.hasCallContact, true);
});

test('public listing exposes contact availability without exposing hidden phone', () => {
  const serialized = serializeListing(
    listingFixture({
      phone: '79281234567',
      phoneHidden: true,
    }) as any,
  ) as any;

  assert.equal(serialized.phone, null);
  assert.equal(serialized.has_call_contact, true);
  assert.equal(serialized.hasCallContact, true);
});

test('transitional legacy listing reports owner contact as callable', () => {
  const serialized = serializeListing(
    listingFixture({
      phone: '',
      phoneHidden: false,
      owner: {
        ...listingFixture({}).owner,
        phone: '79281234567',
      },
    }) as any,
  ) as any;

  assert.equal(serialized.has_call_contact, true);
  assert.equal(serialized.hasCallContact, true);
});

test('legacy ten-digit listing contact is callable and normalized publicly', () => {
  const serialized = serializeListing(
    listingFixture({
      phone: '9281234567',
      phoneHidden: false,
      owner: {
        ...listingFixture({}).owner,
        phone: '79110000000',
      },
    }) as any,
  ) as any;

  assert.equal(serialized.phone, '79281234567');
  assert.equal(serialized.has_call_contact, true);
  assert.equal(serialized.hasCallContact, true);
});

test('invalid listing contact falls back to owner without exposing a hidden phone', () => {
  const serialized = serializeListing(
    listingFixture({
      phone: '123',
      phoneHidden: true,
      owner: {
        ...listingFixture({}).owner,
        phone: '79281234567',
      },
    }) as any,
  ) as any;

  assert.equal(serialized.phone, null);
  assert.equal(serialized.has_call_contact, true);
  assert.equal(serialized.hasCallContact, true);
});

test('transitional public listing serialization preserves published-client phone aliases', () => {
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

test('transitional public user serialization preserves published-client phone aliases', () => {
  const serialized = serializeUser({
    ...listingFixture({}).owner,
    phone: '79281234567',
  } as any) as any;

  assert.equal('phone' in serialized, false);
  assert.equal(serialized.normalized_phone, '79281234567');
  assert.equal(serialized.normalizedPhone, '79281234567');
});

test('transitional listing serialization preserves owner-phone fallback for old clients', () => {
  const serialized = serializeListing(
    listingFixture({
      phone: '',
      phoneHidden: false,
      owner: {
        ...listingFixture({}).owner,
        phone: '79281234567',
      },
    }) as any,
  );

  assert.equal(serialized.phone, '79281234567');
  assert.equal(serialized.has_call_contact, true);
  assert.equal(serialized.hasCallContact, true);
});

test('published clients resolve an open listing contact from the listing itself', () => {
  const listing = serializeListing(
    listingFixture({
      phone: '79281112233',
      phoneHidden: false,
      owner: {
        ...listingFixture({}).owner,
        phone: '79110000000',
      },
    }) as any,
  ) as any;
  const publicSeller = serializeUser({
    ...listingFixture({}).owner,
    phone: '79110000000',
  } as any) as any;

  assert.equal(
    resolvePublishedClientPhone(listing, publicSeller),
    '79281112233',
  );
});

test('published clients keep their legacy account-phone fallback for a hidden listing', () => {
  const listing = serializeListing(
    listingFixture({
      phone: '79281112233',
      phoneHidden: true,
      owner: {
        ...listingFixture({}).owner,
        phone: '79110000000',
      },
    }) as any,
  ) as any;
  const publicSeller = serializeUser({
    ...listingFixture({}).owner,
    phone: '79110000000',
  } as any) as any;

  assert.equal(listing.phone, null);
  assert.equal(
    resolvePublishedClientPhone(listing, publicSeller),
    '79110000000',
  );
  assert.notEqual(
    resolvePublishedClientPhone(listing, publicSeller),
    '79281112233',
  );
});

test('published clients cannot resolve a hidden listing contact for an email-only seller', () => {
  const listing = serializeListing(
    listingFixture({
      phone: '79281112233',
      phoneHidden: true,
      owner: {
        ...listingFixture({}).owner,
        phone: null,
        phoneVerified: false,
      },
    }) as any,
  ) as any;
  const publicSeller = serializeUser({
    ...listingFixture({}).owner,
    phone: null,
    phoneVerified: false,
  } as any) as any;

  assert.equal(listing.phone, null);
  assert.equal(resolvePublishedClientPhone(listing, publicSeller), '');
  assert.equal(listing.has_call_contact, true);
});

test('published public seller profile preserves transitional phone aliases', () => {
  const publicSeller = serializeUser({
    ...listingFixture({}).owner,
    phone: '79110000000',
  } as any) as any;

  assert.equal('phone' in publicSeller, false);
  assert.equal(publicSeller.normalized_phone, '79110000000');
  assert.equal(publicSeller.normalizedPhone, '79110000000');
});

test('published clients resolve no contact when listing and account phones are absent', () => {
  const listing = serializeListing(
    listingFixture({
      phone: '',
      phoneHidden: false,
      owner: {
        ...listingFixture({}).owner,
        phone: null,
        phoneVerified: false,
      },
    }) as any,
  ) as any;
  const publicSeller = serializeUser({
    ...listingFixture({}).owner,
    phone: null,
    phoneVerified: false,
  } as any) as any;

  assert.equal(resolvePublishedClientPhone(listing, publicSeller), '');
  assert.equal(listing.has_call_contact, false);
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
