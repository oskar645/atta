import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  buildListingSearchSql,
  buildListingSearchWhere,
  listingSearchDebugVariants,
  normalizeOemPartNumber,
} from './listing-search';

const textVariantsFor = (search: string) =>
  listingSearchDebugVariants(search).tokens.flatMap((token) => token.textVariants);

test('listing search transliterates cyrillic and latin brand-like names', () => {
  const cases = [
    ['Rayban', 'рейбан'],
    ['Рэйбан', 'rayban'],
    ['Toyota', 'тойота'],
    ['Тойота', 'toyota'],
    ['Samsung', 'самсунг'],
    ['Самсунг', 'samsung'],
    ['Mercedes', 'мерседес'],
    ['Camry', 'камри'],
    ['Камри', 'camry'],
    ['Bosch', 'бош'],
    ['Бош', 'bosch'],
    ['Makita', 'макита'],
    ['Макита', 'makita'],
  ];

  for (const [search, expected] of cases) {
    assert.ok(
      textVariantsFor(search).includes(expected),
      `${search} should include ${expected}`,
    );
  }
});

test('listing search transliterates arbitrary names without alias dictionary entries', () => {
  const variants = textVariantsFor('Глобарис');

  assert.ok(variants.includes('globaris'));
});

test('listing search keeps rare human aliases centralized and additive', () => {
  assert.ok(textVariantsFor('Xiaomi').includes('сяоми'));
  assert.ok(textVariantsFor('Huawei').includes('хуавей'));
  assert.ok(textVariantsFor('Айфон').includes('iphone'));
});

test('listing search adds limited typo tolerance for ordinary text tokens', () => {
  const debug = listingSearchDebugVariants('Toyta');
  const token = debug.tokens[0]!;

  assert.deepEqual(token.typoFragments, ['toy', 'ta']);
  assert.ok(token.deletionTypoVariants.includes('toyt'));
});

test('listing search does not apply typo tolerance to OEM-like tokens', () => {
  const debug = listingSearchDebugVariants('81150-06C70');

  assert.deepEqual(
    debug.tokens.flatMap((token) => token.typoFragments),
    [],
  );
  assert.deepEqual(
    debug.tokens.flatMap((token) => token.deletionTypoVariants),
    [],
  );
  assert.equal(normalizeOemPartNumber('81150-06C70'), '8115006C70');
  assert.equal(normalizeOemPartNumber('81150 06C70'), '8115006C70');
  assert.notEqual(
    normalizeOemPartNumber('81150-06C71'),
    normalizeOemPartNumber('81150-06C70'),
  );
});

test('listing search keeps typo tolerance off for very short tokens and pure numbers', () => {
  const shortDebug = listingSearchDebugVariants('ab');
  const numberDebug = listingSearchDebugVariants('1234');

  assert.deepEqual(shortDebug.tokens.flatMap((token) => token.typoFragments), []);
  assert.deepEqual(
    shortDebug.tokens.flatMap((token) => token.deletionTypoVariants),
    [],
  );
  assert.deepEqual(numberDebug.tokens.flatMap((token) => token.typoFragments), []);
  assert.deepEqual(
    numberDebug.tokens.flatMap((token) => token.deletionTypoVariants),
    [],
  );
});

test('listing search where is token-based and reusable by feed, VIP, and showcase', () => {
  const where = buildListingSearchWhere('Рей-Бан 3025') as Record<string, any>;

  assert.equal(where.OR.length, 2);
  assert.ok(where.OR[0].OR.some(
    (condition: Record<string, any>) =>
      condition.title?.contains === 'rayban',
  ));
  assert.ok(where.OR[1].AND[2].OR.some(
    (condition: Record<string, any>) =>
      condition.oemPartNumberNormalized === '3025',
  ));
});

test('listing search sql uses trigram operator for bounded fuzzy text only', () => {
  const fuzzySql = buildListingSearchSql('Toyta')!;
  const oemSql = buildListingSearchSql('81150-06C70')!;

  assert.match(fuzzySql.sql, /l\."title"\s+%/);
  assert.doesNotMatch(oemSql.sql, /l\."title"\s+%/);
});
