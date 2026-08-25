import { Prisma } from '@prisma/client';

const TEXT_FIELDS = [
  { prisma: 'title', sql: 'title' },
  { prisma: 'description', sql: 'description' },
  { prisma: 'category', sql: 'category' },
  { prisma: 'subcategory', sql: 'subcategory' },
  { prisma: 'city', sql: 'city' },
  { prisma: 'address', sql: 'address' },
  { prisma: 'ownerName', sql: 'owner_name' },
] as const;

const SEARCH_ALIASES = [
  ['xiaomi', 'сяоми'],
  ['huawei', 'хуавей'],
  ['iphone', 'айфон'],
  ['rayban', 'ray-ban', 'ray ban', 'рейбан', 'рэйбан'],
  ['nike', 'найк'],
] as const;

const CYRILLIC_TO_LATIN: Record<string, string> = {
  а: 'a',
  б: 'b',
  в: 'v',
  г: 'g',
  д: 'd',
  е: 'e',
  ё: 'e',
  ж: 'zh',
  з: 'z',
  и: 'i',
  й: 'y',
  к: 'k',
  л: 'l',
  м: 'm',
  н: 'n',
  о: 'o',
  п: 'p',
  р: 'r',
  с: 's',
  т: 't',
  у: 'u',
  ф: 'f',
  х: 'h',
  ц: 'ts',
  ч: 'ch',
  ш: 'sh',
  щ: 'sch',
  ы: 'y',
  э: 'e',
  ю: 'yu',
  я: 'ya',
};

const LATIN_TO_CYRILLIC_PAIRS: Array<[string, string]> = [
  ['sch', 'ш'],
  ['sh', 'ш'],
  ['ch', 'ч'],
  ['yo', 'ё'],
  ['yu', 'ю'],
  ['ya', 'я'],
  ['zh', 'ж'],
  ['ts', 'ц'],
  ['kh', 'х'],
  ['ph', 'ф'],
  ['oo', 'у'],
  ['oy', 'ой'],
  ['ai', 'ай'],
  ['ay', 'ай'],
  ['ei', 'ей'],
  ['ey', 'ей'],
];

const LATIN_TO_CYRILLIC: Record<string, string> = {
  a: 'а',
  b: 'б',
  d: 'д',
  e: 'е',
  f: 'ф',
  g: 'г',
  h: 'х',
  i: 'и',
  j: 'дж',
  k: 'к',
  l: 'л',
  m: 'м',
  n: 'н',
  o: 'о',
  p: 'п',
  q: 'к',
  r: 'р',
  s: 'с',
  t: 'т',
  u: 'у',
  v: 'в',
  w: 'в',
  x: 'кс',
  y: 'й',
  z: 'з',
};

const LIKE_ESCAPE_PATTERN = /[%_\\]/g;

const escapeLikePattern = (value: string) =>
  value.replace(LIKE_ESCAPE_PATTERN, (char) => `\\${char}`);

export const normalizeOemPartNumber = (value: string | null | undefined) => {
  const normalized = (value ?? '')
    .normalize('NFKC')
    .replace(/[\s\-–—_/\\.]+/g, '')
    .toUpperCase();
  return normalized.length > 0 ? normalized : null;
};

const normalizeSearchText = (value: string | null | undefined) => {
  const normalized = (value ?? '')
    .normalize('NFKC')
    .replace(/[‐‑‒–—―]+/g, '-')
    .replace(/[_/\\.]+/g, ' ')
    .replace(/\s+/g, ' ')
    .toLocaleLowerCase('ru-RU')
    .trim();
  return normalized.length > 0 ? normalized : null;
};

const compactSearchText = (value: string) =>
  normalizeSearchText(value)?.replace(/[^\p{L}\p{N}]+/gu, '') ?? '';

const tokenizeSearchText = (value: string) =>
  normalizeSearchText(value)
    ?.split(/[^\p{L}\p{N}]+/u)
    .map((token) => token.trim())
    .filter((token) => token.length > 0) ?? [];

const hasCyrillic = (value: string) => /[а-яё]/i.test(value);

const hasLatin = (value: string) => /[a-z]/i.test(value);

const transliterateLatinCharToCyrillic = (char: string, rest: string) => {
  if (char === 'c') {
    return /^[aou]/.test(rest) ? 'к' : 'с';
  }
  if (char === 'y' && rest.length === 0) {
    return 'и';
  }
  return LATIN_TO_CYRILLIC[char] ?? char;
};

const transliterateCyrillicToLatin = (value: string) => {
  let result = '';
  for (const char of value) {
    result += CYRILLIC_TO_LATIN[char] ?? char;
  }
  return result
    .replace(/oi/g, 'oy')
    .replace(/ai/g, 'ay')
    .replace(/ei/g, 'ey')
    .replace(/sh/g, 'sch');
};

const transliterateLatinToCyrillic = (value: string) => {
  let rest = value;
  let result = '';
  while (rest.length > 0) {
    const pair = LATIN_TO_CYRILLIC_PAIRS.find(([latin]) =>
      rest.startsWith(latin),
    );
    if (pair) {
      result += pair[1];
      rest = rest.slice(pair[0].length);
      continue;
    }
    const char = rest[0]!;
    result += transliterateLatinCharToCyrillic(char, rest.slice(1));
    rest = rest.slice(1);
  }
  return result;
};

const addAliasVariants = (variants: Set<string>, value: string) => {
  const compactValue = compactSearchText(value);
  if (!compactValue) return;

  for (const group of SEARCH_ALIASES) {
    const compactGroup = group.map(compactSearchText);
    if (compactGroup.includes(compactValue)) {
      for (const alias of group) {
        variants.add(alias);
      }
    }
    for (let index = 0; index < compactGroup.length; index += 1) {
      const source = compactGroup[index];
      if (!source || !compactValue.includes(source)) continue;
      for (const target of compactGroup) {
        variants.add(compactValue.replace(source, target));
        if (/^\p{L}+$/u.test(source)) {
          variants.add(target);
        }
      }
    }
  }
};

const addLatinOrthographicVariants = (variants: Set<string>, value: string) => {
  if (!/^[a-z]+$/.test(value)) return;

  const add = (variant: string) => {
    if (variant !== value) variants.add(variant);
  };

  add(value.replace(/s(?=[eiye])/g, 'c'));
  add(value.replace(/c(?=[eiye])/g, 's'));
  add(value.replace(/c(?=[aou])/g, 'k'));
  add(value.replace(/k(?=[aou])/g, 'c'));
  add(value.replace(/y$/g, 'i'));
  add(value.replace(/i$/g, 'y'));
  add(value.replace(/sh/g, 'sch'));
  add(value.replace(/sch/g, 'sh'));
};

const expandLatinOrthographicVariants = (variants: Set<string>) => {
  for (let pass = 0; pass < 3; pass += 1) {
    const before = variants.size;
    for (const variant of [...variants]) {
      addLatinOrthographicVariants(variants, compactSearchText(variant));
    }
    if (variants.size === before || variants.size > 64) break;
  }
};

const searchTextVariants = (value: string) => {
  const variants = new Set<string>([value]);
  const yoVariant = value.replace(/ё/g, 'е').replace(/Ё/g, 'Е');
  variants.add(yoVariant);

  const normalized = normalizeSearchText(value);
  if (normalized != null) {
    variants.add(normalized);
    variants.add(normalized.replace(/-/g, ' '));
    variants.add(normalized.replace(/\s+/g, '-'));

    const compact = compactSearchText(normalized);
    if (compact) {
      variants.add(compact);
    }

    if (hasCyrillic(normalized)) {
      variants.add(transliterateCyrillicToLatin(normalized));
    }
    if (hasLatin(normalized)) {
      variants.add(transliterateLatinToCyrillic(normalized));
      addLatinOrthographicVariants(variants, normalized);
    }
    addAliasVariants(variants, normalized);
  }

  expandLatinOrthographicVariants(variants);

  for (const variant of [...variants]) {
    if (hasLatin(variant)) {
      variants.add(transliterateLatinToCyrillic(compactSearchText(variant)));
    }
    addAliasVariants(variants, variant);
  }

  return [...variants].map((item) => item.trim()).filter((item) => item.length > 0);
};

const extractOemSearchCandidates = (value: string) => {
  const candidates = new Set<string>();
  const hasCodeLikePart = /\d/.test(value);
  const normalizedFull = hasCodeLikePart ? normalizeOemPartNumber(value) : null;
  if (normalizedFull != null) {
    candidates.add(normalizedFull);
  }

  const codeLikeParts = value
    .split(/\s+/)
    .map((part) => part.trim())
    .filter((part) => /\d/.test(part));

  for (const part of codeLikeParts) {
    const normalizedPart = normalizeOemPartNumber(part);
    if (normalizedPart != null) {
      candidates.add(normalizedPart);
    }
  }

  return [...candidates];
};

const isCodeLikeToken = (value: string) => /\d/.test(value);

const typoFragments = (value: string) => {
  const compact = compactSearchText(value);
  if (compact.length < 5 || isCodeLikeToken(compact)) {
    return [];
  }
  const headLength = compact.length <= 6 ? 3 : 4;
  const tailLength = compact.length <= 6 ? 2 : 3;
  return [
    compact.slice(0, headLength),
    compact.slice(-tailLength),
  ].filter((fragment, index, fragments) =>
    fragment.length > 0 && fragments.indexOf(fragment) === index,
  );
};

const deletionTypoVariants = (value: string) => {
  const compact = compactSearchText(value);
  if (compact.length < 5 || isCodeLikeToken(compact)) {
    return [];
  }
  const variants = new Set<string>();
  for (let index = 0; index < compact.length; index += 1) {
    variants.add(`${compact.slice(0, index)}${compact.slice(index + 1)}`);
  }
  return [...variants].filter((variant) => variant.length >= 4);
};

const textFieldContains = (
  field: (typeof TEXT_FIELDS)[number]['prisma'],
  variant: string,
) =>
  ({
    [field]: {
      contains: variant,
      mode: 'insensitive' as const,
    },
  }) satisfies Prisma.ListingWhereInput;

const buildTokenSearchWhere = (token: string): Prisma.ListingWhereInput | null => {
  const variants = new Set(searchTextVariants(token));
  for (const variant of [...variants]) {
    for (const deletion of deletionTypoVariants(variant)) {
      variants.add(deletion);
    }
  }

  const textConditions: Prisma.ListingWhereInput[] = [...variants].flatMap((variant) =>
    TEXT_FIELDS.map((field) => textFieldContains(field.prisma, variant)),
  );
  const compactVariants = [...variants].map(compactSearchText).filter(Boolean);
  for (const compact of compactVariants) {
    textConditions.push(
      ...TEXT_FIELDS.map((field) => textFieldContains(field.prisma, compact)),
    );
  }

  const fragments = typoFragments(token);
  if (fragments.length > 1) {
    textConditions.push(
      ...TEXT_FIELDS.map((field) => ({
        AND: fragments.map((fragment) => textFieldContains(field.prisma, fragment)),
      })),
    );
  }

  const oemConditions = extractOemSearchCandidates(token).map(
    (candidate) =>
      ({
        oemPartNumberNormalized: candidate,
      }) as unknown as Prisma.ListingWhereInput,
  );

  const OR = [...textConditions, ...oemConditions];
  return OR.length > 0 ? { OR } : null;
};

const buildPhraseSearchWhere = (value: string): Prisma.ListingWhereInput | null => {
  const variants = new Set(searchTextVariants(value));
  const textConditions: Prisma.ListingWhereInput[] = [...variants].flatMap((variant) =>
    TEXT_FIELDS.map((field) => textFieldContains(field.prisma, variant)),
  );
  const oemConditions = extractOemSearchCandidates(value).map(
    (candidate) =>
      ({
        oemPartNumberNormalized: candidate,
      }) as unknown as Prisma.ListingWhereInput,
  );
  const OR = [...textConditions, ...oemConditions];
  return OR.length > 0 ? { OR } : null;
};

export const buildListingSearchWhere = (
  search: string | null | undefined,
): Prisma.ListingWhereInput | null => {
  const value = normalizeSearchText(search);
  if (!value) return null;

  const tokenConditions = tokenizeSearchText(value)
    .map(buildTokenSearchWhere)
    .filter((condition): condition is Prisma.ListingWhereInput => condition != null);
  const phraseCondition = buildPhraseSearchWhere(value);

  return {
    OR: [
      ...(phraseCondition == null ? [] : [phraseCondition]),
      ...(tokenConditions.length === 0 ? [] : [{ AND: tokenConditions }]),
    ],
  };
};

const sqlTextContains = (
  alias: string,
  field: (typeof TEXT_FIELDS)[number]['sql'],
  variant: string,
) => {
  const table = Prisma.raw(alias);
  const searchPattern = `%${escapeLikePattern(variant)}%`;
  return Prisma.sql`${table}.${Prisma.raw(`"${field}"`)} ILIKE ${searchPattern} ESCAPE '\\'`;
};

const sqlTextCompactContains = (
  alias: string,
  field: (typeof TEXT_FIELDS)[number]['sql'],
  variant: string,
) => {
  const table = Prisma.raw(alias);
  const compactPattern = `%${escapeLikePattern(compactSearchText(variant))}%`;
  return Prisma.sql`regexp_replace(lower(coalesce(${table}.${Prisma.raw(`"${field}"`)}, '')), '[^[:alnum:]]+', '', 'g') LIKE ${compactPattern} ESCAPE '\\'`;
};

const sqlTextFuzzyContains = (
  alias: string,
  field: (typeof TEXT_FIELDS)[number]['sql'],
  token: string,
) => {
  const compact = compactSearchText(token);
  const table = Prisma.raw(alias);
  return Prisma.sql`${table}.${Prisma.raw(`"${field}"`)} % ${compact}`;
};

export const buildListingSearchSql = (
  search: string | null | undefined,
  alias = 'l',
): Prisma.Sql | null => {
  const value = normalizeSearchText(search);
  if (!value) return null;

  const phraseVariants = new Set(searchTextVariants(value));
  const phraseConditions = [...phraseVariants].flatMap((variant) =>
    TEXT_FIELDS.flatMap((field) => [
      sqlTextContains(alias, field.sql, variant),
      sqlTextCompactContains(alias, field.sql, variant),
    ]),
  );
  const phraseOemConditions = extractOemSearchCandidates(value).map((candidate) => {
    const table = Prisma.raw(alias);
    return Prisma.sql`${table}."oem_part_number_normalized" = ${candidate}`;
  });
  const phraseSql = Prisma.sql`(${Prisma.join(
    [...phraseConditions, ...phraseOemConditions],
    ' OR ',
  )})`;

  const tokenConditions = tokenizeSearchText(value).map((token) => {
    const variants = new Set(searchTextVariants(token));
    for (const variant of [...variants]) {
      for (const deletion of deletionTypoVariants(variant)) {
        variants.add(deletion);
      }
    }
    const textConditions = [...variants].flatMap((variant) =>
      TEXT_FIELDS.flatMap((field) => [
        sqlTextContains(alias, field.sql, variant),
        sqlTextCompactContains(alias, field.sql, variant),
      ]),
    );
    if (typoFragments(token).length > 1) {
      textConditions.push(
        ...TEXT_FIELDS.map((field) => sqlTextFuzzyContains(alias, field.sql, token)),
      );
    }
    const oemConditions = extractOemSearchCandidates(token).map((candidate) => {
      const table = Prisma.raw(alias);
      return Prisma.sql`${table}."oem_part_number_normalized" = ${candidate}`;
    });
    return Prisma.sql`(${Prisma.join([...textConditions, ...oemConditions], ' OR ')})`;
  });

  if (tokenConditions.length === 0) return null;

  return Prisma.sql`(
    ${phraseSql}
    OR (${Prisma.join(tokenConditions, ' AND ')})
  )`;
};

export const listingSearchDebugVariants = (search: string) => ({
  tokens: tokenizeSearchText(search).map((token) => ({
    token,
    textVariants: searchTextVariants(token),
    typoFragments: typoFragments(token),
    deletionTypoVariants: deletionTypoVariants(token),
    oemCandidates: extractOemSearchCandidates(token),
  })),
});
