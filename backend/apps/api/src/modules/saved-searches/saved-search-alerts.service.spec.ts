import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Listing, ListingStatus, SavedSearch, UserStatus } from '@prisma/client';
import { SavedSearchAlertsService } from './saved-search-alerts.service';
import { matchesSavedSearchFilters } from './saved-search-matching';

const saved = (): SavedSearch => ({ id: 'search', userId: 'buyer', title: 'Toyota', queryKey: '',
  search: 'Toyota', category: 'Авто', subcategory: 'Все', location: 'Москва', radiusKm: 10,
  preferLocationFirst: false, autoBrand: 'Toyota', autoModel: '', autoCondition: '',
  autoMileageTo: 50000, onlyUncrashed: false, alertsEnabled: true,
  createdAt: new Date('2026-01-01'), updatedAt: new Date('2026-01-01') });
const listing = () => ({ id: 'listing', ownerId: 'seller', title: 'Toyota Corolla', description: '',
  category: 'Авто', subcategory: 'Седан', city: 'Москва', price: 1000000n,
  status: ListingStatus.APPROVED, publishedAt: new Date('2026-09-14'), deletedAt: null,
  car: { brand: 'Toyota', model: 'Corolla', mileageKm: 10000, year: 2020 }, locationJson: {},
}) as unknown as Listing;

function harness() {
  let search: SavedSearch | null = saved();
  let row = listing();
  let textMatches = true;
  const alerts = new Set<string>();
  const records: any[] = [], emitted: any[] = [];
  const prisma: any = {
    listing: { findFirst: async ({ where }: any) => {
      assert.equal(where.status, ListingStatus.APPROVED);
      assert.deepEqual(where.owner, { status: UserStatus.ACTIVE, deletedAt: null });
      assert.deepEqual(where.photos, { some: {} });
      if (where.AND) assert.notDeepEqual(where.AND, [{}], 'existing text search predicate is used');
      return row.status === ListingStatus.APPROVED && !row.deletedAt && (!where.AND || textMatches) ? row : null;
    } },
    savedSearch: { findMany: async () => search ? [search] : [], findUnique: async () => search },
    $queryRaw: async () => [],
    savedSearchAlert: { createMany: async ({ data }: any) => {
      const key = data[0].savedSearchId + data[0].listingId;
      if (alerts.has(key)) return { count: 0 };
      alerts.add(key); return { count: 1 };
    } },
    userNotification: { create: async ({ data }: any) => {
      const record = { ...data, id: `n${records.length}`, createdAt: new Date(), isRead: false };
      records.push(record); return record;
    } },
    $transaction: async (fn: any) => fn(prisma),
  };
  const service = new SavedSearchAlertsService(prisma, { publishNotification: async (n: any) => emitted.push(n) } as never);
  return { service, records, emitted, setSearch: (s: SavedSearch | null) => search = s,
    setListing: (l: Listing) => row = l, mismatchText: () => textMatches = false };
}

test('approved match creates exactly one persistent alert and navigable notification', async () => {
  const h = harness();
  await h.service.notifyApprovedListing('listing');
  await h.service.notifyApprovedListing('listing');
  assert.equal(h.records.length, 1);
  assert.equal(h.emitted.length, 1);
  assert.equal(h.records[0].userId, 'buyer');
  assert.equal(h.records[0].type, 'SAVED_SEARCH');
  assert.equal(h.records[0].isRead, false);
  assert.deepEqual(h.records[0].payload, { actionType: 'saved_search', listingId: 'listing', savedSearchId: 'search' });
});
for (const status of [ListingStatus.PENDING, ListingStatus.REJECTED, ListingStatus.ARCHIVED, ListingStatus.DELETED, ListingStatus.SOLD]) {
  test(`${status} does not alert`, async () => {
    const h = harness(); h.setListing({ ...listing(), status });
    await h.service.notifyApprovedListing('listing'); assert.equal(h.records.length, 0);
  });
}
for (const search of [null, { ...saved(), alertsEnabled: false }, { ...saved(), userId: 'seller' }, { ...saved(), createdAt: new Date('2027-01-01') }]) {
  test(`deleted/disabled/owner/future saved search is excluded: ${search?.userId ?? 'deleted'} ${search?.alertsEnabled}`, async () => {
    const h = harness(); h.setSearch(search);
    await h.service.notifyApprovedListing('listing'); assert.equal(h.records.length, 0);
  });
}
test('text mismatch creates no notification', async () => {
  const h = harness(); h.mismatchText(); await h.service.notifyApprovedListing('listing');
  assert.equal(h.records.length, 0);
});
test('stored category, subcategory, location and vehicle limits are respected', () => {
  assert.equal(matchesSavedSearchFilters(listing(), saved()), true);
  for (const mismatch of [{ category: 'Одежда' }, { subcategory: 'Внедорожник' }, { location: 'Казань' },
    { autoBrand: 'Ford' }, { autoModel: 'Camry' }, { autoCondition: 'новый' }, { autoMileageTo: 9000 }]) {
    assert.equal(matchesSavedSearchFilters(listing(), { ...saved(), ...mismatch }), false);
  }
  assert.equal(matchesSavedSearchFilters(listing(), { ...saved(), location: 'Казань', radiusKm: null }), true);
});
test('extended persisted queryKey price and year are honored', () => {
  const parts = Array(26).fill(''); parts[4] = '900000';
  assert.equal(matchesSavedSearchFilters(listing(), { ...saved(), queryKey: parts.join('|') }), false);
  parts[4] = ''; parts[11] = '2022';
  assert.equal(matchesSavedSearchFilters(listing(), { ...saved(), queryKey: parts.join('|') }), false);
});
