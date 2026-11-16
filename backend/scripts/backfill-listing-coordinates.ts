import 'dotenv/config';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { PrismaClient, ListingStatus } from '@prisma/client';

type CachedResult =
  | { status: 'resolved'; latitude: number; longitude: number; label: string }
  | { status: 'ambiguous' | 'not_found' | 'error'; reason: string };

type NominatimRow = Record<string, unknown> & {
  address?: Record<string, unknown>;
  namedetails?: Record<string, unknown>;
};

const prisma = new PrismaClient();
const apply = process.argv.includes('--apply');
const auditOnly = process.argv.includes('--audit');
const endpoint = (process.env.GEOCODING_BASE_URL ?? '').trim();
const cachePath = path.resolve(process.cwd(), 'reports/map-coordinate-cache.json');
const reportPath = path.resolve(
  process.cwd(),
  `reports/map-coordinate-${apply ? 'apply' : 'dry-run'}-${new Date().toISOString().replaceAll(':', '-')}.json`,
);

const normalize = (value: string) =>
  value.normalize('NFKC').toLocaleLowerCase('ru-RU').replace(/ё/g, 'е')
    .replace(/[^\p{L}\p{N}]+/gu, ' ').trim().replace(/\s+/g, ' ');

const localityKinds = new Set(['city', 'town', 'village', 'hamlet', 'municipality']);

function localityName(address: string) {
  const part = address.split(',').map((value) => value.trim()).filter(Boolean).at(-1) ?? '';
  return part.replace(/^(?:город|г\.?|село|с\.?|пос[её]лок|пгт)\s+/iu, '').trim();
}

function expectedRegionCode(address: string) {
  const value = normalize(address);
  if (value.includes('чечен')) return 'RU-CE';
  if (value.includes('дагестан')) return 'RU-DA';
  return null;
}

function exactLocalityCandidate(row: NominatimRow, locality: string, regionCode: string | null) {
  const address = row.address ?? {};
  const names = [
    row.name,
    row.namedetails?.['name:ru'],
    address.city,
    address.town,
    address.village,
    address.hamlet,
  ].filter((value): value is string => typeof value === 'string');
  const exactName = names.some((value) => normalize(value) === normalize(locality));
  const kind = String(row.addresstype ?? row.type ?? '');
  const rowRegionCode = String(address['ISO3166-2-lvl4'] ?? '');
  return exactName && localityKinds.has(kind) && (!regionCode || rowRegionCode === regionCode);
}

async function search(query: string): Promise<NominatimRow[]> {
  const url = new URL(endpoint);
  url.searchParams.set('q', query);
  url.searchParams.set('format', 'jsonv2');
  url.searchParams.set('addressdetails', '1');
  url.searchParams.set('namedetails', '1');
  url.searchParams.set('limit', '10');
  url.searchParams.set('countrycodes', 'ru');
  const response = await fetch(url, {
    headers: { 'user-agent': 'ATTA-Market-coordinate-backfill/1.1 (admin batch)' },
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json() as Promise<NominatimRow[]>;
}

async function loadCache(): Promise<Record<string, CachedResult>> {
  try {
    return JSON.parse(await readFile(cachePath, 'utf8')) as Record<string, CachedResult>;
  } catch {
    return {};
  }
}

export async function geocode(address: string): Promise<CachedResult> {
  if (!endpoint) return { status: 'error', reason: 'GEOCODING_BASE_URL is not configured' };
  const locality = localityName(address);
  const regionCode = expectedRegionCode(address);
  let rows: NominatimRow[];
  try {
    rows = await search(address);
    let exactRows = rows.filter((row) => exactLocalityCandidate(row, locality, regionCode));
    if (exactRows.length === 0 && locality) {
      const region = regionCode === 'RU-CE' ? 'Чечня' : regionCode === 'RU-DA' ? 'Дагестан' : 'Россия';
      await new Promise((resolve) => setTimeout(resolve, 1100));
      rows = await search(`${locality}, ${region}, Россия`);
      exactRows = rows.filter((row) => exactLocalityCandidate(row, locality, regionCode));
    }
    if (exactRows.length > 0) {
      const best = exactRows.sort(
        (a, b) => Number(b.importance ?? 0) - Number(a.importance ?? 0),
      )[0];
      const latitude = Number(best.lat);
      const longitude = Number(best.lon);
      if (!Number.isFinite(latitude) || !Number.isFinite(longitude)
          || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
        return { status: 'error', reason: 'Provider returned invalid coordinates' };
      }
      return {
        status: 'resolved',
        latitude,
        longitude,
        label: String(best.display_name ?? locality),
      };
    }
  } catch (error) {
    return { status: 'error', reason: error instanceof Error ? error.message : 'Geocoder request failed' };
  }
  if (rows.length === 0) return { status: 'not_found', reason: 'No result' };
  const addressTokens = new Set(normalize(address).split(' ').filter((part) => part.length > 2));
  const candidates = rows.map((row) => {
    const label = String(row.display_name ?? '');
    const labelTokens = new Set(normalize(label).split(' '));
    const matches = [...addressTokens].filter((token) => labelTokens.has(token)).length;
    return { row, label, score: addressTokens.size === 0 ? 0 : matches / addressTokens.size };
  }).sort((a, b) => b.score - a.score);
  const best = candidates[0];
  if (!best || best.score < 0.5 || (candidates[1] && candidates[1].score === best.score)) {
    return { status: 'ambiguous', reason: 'No unique high-confidence result' };
  }
  const latitude = Number(best.row.lat);
  const longitude = Number(best.row.lon);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)
      || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return { status: 'error', reason: 'Provider returned invalid coordinates' };
  }
  return { status: 'resolved', latitude, longitude, label: best.label };
}

async function main() {
  if (apply && process.env.ALLOW_LISTING_COORDINATE_BACKFILL !== 'true') {
    throw new Error('Apply is blocked. Set ALLOW_LISTING_COORDINATE_BACKFILL=true explicitly.');
  }
  const publicWhere = {
    category: 'Недвижимость',
    status: ListingStatus.APPROVED,
    deletedAt: null,
    photos: { some: {} },
    owner: { deletedAt: null, status: 'ACTIVE' as const },
  };
  const [withCoordinates, withoutCoordinates, listings] = await Promise.all([
    prisma.listing.count({ where: { ...publicWhere, latitude: { not: null }, longitude: { not: null } } }),
    prisma.listing.count({ where: { ...publicWhere, OR: [{ latitude: null }, { longitude: null }] } }),
    prisma.listing.findMany({
      where: { ...publicWhere, OR: [{ latitude: null }, { longitude: null }] },
      select: { id: true, city: true, address: true, latitude: true, longitude: true },
      orderBy: { id: 'asc' },
    }),
  ]);
  if (auditOnly) {
    console.log(JSON.stringify({ withCoordinates, withoutCoordinates }, null, 2));
    return;
  }

  const cache = await loadCache();
  const entries: Array<Record<string, unknown>> = [];
  let updated = 0;
  for (const listing of listings) {
    const address = (listing.address || listing.city).trim();
    if (!address) {
      entries.push({ id: listing.id, address, status: 'not_found', reason: 'Empty address' });
      continue;
    }
    const key = normalize(address);
    let result = cache[key];
    if (!result || result.status !== 'resolved') {
      result = await geocode(address);
      cache[key] = result;
      await new Promise((resolve) => setTimeout(resolve, 1100));
    }
    entries.push({ id: listing.id, address, ...result });
    if (apply && result.status === 'resolved') {
      const changed = await prisma.listing.updateMany({
        where: { id: listing.id, latitude: null, longitude: null },
        data: {
          latitude: result.latitude,
          longitude: result.longitude,
          locationJson: { latitude: result.latitude, longitude: result.longitude, geocoded_from: address },
        },
      });
      updated += changed.count;
    }
  }
  await mkdir(path.dirname(reportPath), { recursive: true });
  await writeFile(cachePath, JSON.stringify(cache, null, 2));
  await writeFile(reportPath, JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    withCoordinates,
    withoutCoordinates,
    uniqueAddresses: Object.keys(cache).length,
    updated,
    entries,
  }, null, 2));
  console.log(JSON.stringify({ withCoordinates, withoutCoordinates, updated, reportPath }, null, 2));
}

if (require.main === module) {
  main().finally(() => prisma.$disconnect());
}
