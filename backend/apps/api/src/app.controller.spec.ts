import { test } from 'node:test';
import assert from 'node:assert/strict';
import { AppController } from './app.controller';

test('app landing page contains metadata and manual store fallback', () => {
  const controller = new AppController({} as any, {} as any, {} as any);

  const html = controller.getAppLandingPage();

  assert.match(html, /<meta property="og:title" content="ATTA"/);
  assert.match(
    html,
    /<meta property="og:description" content="Приложение для объявлений"/,
  );
  assert.match(
    html,
    /<meta property="og:url" content="https:\/\/attamarket\.online\/invite"/,
  );
  assert.match(html, /https:\/\/apps\.apple\.com\/app\/id6762604298/);
  assert.match(
    html,
    /https:\/\/play\.google\.com\/store\/apps\/details\?id=online\.attomarket\.atta/,
  );
  assert.doesNotMatch(html, /http-equiv="refresh"/);
  assert.doesNotMatch(html, /window\.location\.replace/);
  assert.doesNotMatch(html, /setTimeout/);
  assert.match(html, /data-platform/);
  assert.match(html, /navigator\.userAgent/);
});

test('invite landing page preserves referral code in canonical metadata', () => {
  const controller = new AppController({} as any, {} as any, {} as any);

  const html = controller.getAppLandingPage('REF CODE/42');

  assert.match(
    html,
    /<meta property="og:url" content="https:\/\/attamarket\.online\/invite\?ref=REF%20CODE%2F42"/,
  );
  assert.match(
    html,
    /<link rel="canonical" href="https:\/\/attamarket\.online\/invite\?ref=REF%20CODE%2F42"/,
  );
  assert.match(html, /localStorage\.setItem\('atta\.invite\.referralCode'/);
  assert.match(html, /atta_invite_ref/);
  assert.doesNotMatch(html, /window\.location\.replace/);
});

test('listing fallback renders cancelable store fallback', async () => {
  const controller = new AppController(
    {
      listing: {
        findFirst: async () => ({
          id: 'listing-1',
          title: 'Lada Vesta NG',
          description: 'Семейный седан в отличном состоянии',
          category: 'Авто',
          subcategory: 'Легковые автомобили',
          price: BigInt(1200000),
          city: 'Махачкала',
          updatedAt: new Date('2026-09-01T10:00:00.000Z'),
          publishedAt: new Date('2026-08-20T10:00:00.000Z'),
          photos: [{ publicUrl: '/media/object?category=listings&key=photo.jpg' }],
        }),
      },
    } as any,
    {} as any,
    {} as any,
  );

  const html = await controller.getListingLandingPage('listing-1');

  assert.match(html, /Lada Vesta NG/);
  assert.match(html, /<base href="\/">/);
  assert.match(html, /<link rel="canonical" href="https:\/\/attamarket\.online\/listing\/listing-1"/);
  assert.match(html, /<meta property="og:title" content="Lada Vesta NG"/);
  assert.match(html, /<meta property="og:description" content="Семейный седан/);
  assert.match(html, /<meta property="og:image" content="https:\/\/attamarket\.online\/media\/object\?category=listings&amp;key=photo\.jpg"/);
  assert.match(html, /<h1>Lada Vesta NG<\/h1>/);
  assert.match(html, /1\s200\s000 ₽/);
  assert.match(html, /Махачкала/);
  assert.match(html, /flutter_bootstrap\.js/);
  assert.doesNotMatch(html, /phone/);
});

test('listing SEO escapes title and description', async () => {
  const controller = new AppController(
    {
      listing: {
        findFirst: async () => ({
          id: 'listing-1',
          title: '<script>alert(1)</script>',
          description: 'Описание "опасное" & <b>html</b>',
          category: 'Авто',
          subcategory: 'Легковые автомобили',
          price: BigInt(100),
          city: 'Город',
          updatedAt: new Date('2026-09-01T10:00:00.000Z'),
          publishedAt: null,
          photos: [],
        }),
      },
    } as any,
    {} as any,
    {} as any,
  );

  const html = await controller.getListingLandingPage('listing-1');

  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.match(html, /Описание &quot;опасное&quot; &amp; &lt;b&gt;html&lt;\/b&gt;/);
  assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
});

test('missing listing returns not indexable 404 page', async () => {
  const response = { statusCode: 200, status(code: number) { this.statusCode = code; } };
  const controller = new AppController(
    {
      listing: {
        findFirst: async () => null,
      },
    } as any,
    {} as any,
    {} as any,
  );

  const html = await controller.getListingLandingPage('missing-listing', response);

  assert.equal(response.statusCode, 404);
  assert.match(html, /noindex/);
  assert.doesNotMatch(html, /flutter_bootstrap\.js/);
});

test('sitemap contains public listings and valid xml content', async () => {
  const controller = new AppController(
    {
      listing: {
        findMany: async () => [
          {
            id: 'listing-1',
            updatedAt: new Date('2026-09-01T10:00:00.000Z'),
            publishedAt: new Date('2026-08-20T10:00:00.000Z'),
          },
        ],
      },
    } as any,
    {} as any,
    {} as any,
  );

  const xml = await controller.getSitemap();

  assert.match(xml, /^<\?xml version="1.0" encoding="UTF-8"\?>/);
  assert.match(xml, /<urlset xmlns="http:\/\/www\.sitemaps\.org\/schemas\/sitemap\/0\.9">/);
  assert.match(xml, /<url>\s*<loc>https:\/\/attamarket\.online\/<\/loc>\s*<\/url>/);
  assert.match(xml, /https:\/\/attamarket\.online\/listing\/listing-1/);
  assert.match(xml, /<lastmod>2026-09-01T10:00:00.000Z<\/lastmod>/);
});

test('android asset links uses configured package and fingerprints', () => {
  const previous = process.env.ANDROID_SHA256_CERT_FINGERPRINTS;
  process.env.ANDROID_SHA256_CERT_FINGERPRINTS =
    'AA:BB:CC, 11:22:33 ';
  try {
    const controller = new AppController({} as any, {} as any, {} as any);

    const links = controller.getAndroidAssetLinks();

    assert.deepEqual(links, [
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: 'online.attomarket.atta',
          sha256_cert_fingerprints: ['AA:BB:CC', '11:22:33'],
        },
      },
    ]);
  } finally {
    if (previous === undefined) {
      delete process.env.ANDROID_SHA256_CERT_FINGERPRINTS;
    } else {
      process.env.ANDROID_SHA256_CERT_FINGERPRINTS = previous;
    }
  }
});
