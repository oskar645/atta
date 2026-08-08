import { test } from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';

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
        }),
      },
    } as any,
    {} as any,
    {} as any,
  );

  const html = await controller.getListingLandingPage('listing-1');

  assert.match(html, /Lada Vesta NG/);
  assert.match(html, /Откройте объявление в приложении ATTA/);
  assert.match(html, /https:\/\/apps\.apple\.com\/app\/id6762604298/);
  assert.match(
    html,
    /https:\/\/play\.google\.com\/store\/apps\/details\?id=online\.attomarket\.atta/,
  );
  assert.doesNotMatch(html, /http-equiv="refresh"/);
  assert.match(html, /if \(!\/android\/i\.test\(ua\)\) return;/);
  assert.match(html, /visibilitychange/);
  assert.match(html, /pagehide/);
  assert.match(html, /clearTimeout/);
  assert.match(html, /if \(document\.hidden\) stopFallback\(\)/);
  assert.match(html, /window\.location\.replace/);
  assert.doesNotMatch(html, /appStoreUrl/);
  assert.doesNotMatch(html, /isIos/);
  assert.doesNotMatch(html, /atta:\/\//);
});

test('ios listing page keeps App Store as manual button without timer redirect', async () => {
  const controller = new AppController(
    {
      listing: {
        findFirst: async () => ({
          id: 'listing-1',
          title: 'Lada Vesta NG',
        }),
      },
    } as any,
    {} as any,
    {} as any,
  );

  const html = await controller.getListingLandingPage('listing-1');
  const redirects = runListingScriptRedirects(
    html,
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)',
  );

  assert.deepEqual(redirects, []);
  assert.doesNotMatch(html, /appStoreUrl/);
  assert.doesNotMatch(html, /isIos/);
  assert.match(
    html,
    /<a class="button" href="https:\/\/apps\.apple\.com\/app\/id6762604298">Скачать ATTA в App Store<\/a>/,
  );
});

test('android listing page keeps timed Google Play fallback', async () => {
  const controller = new AppController(
    {
      listing: {
        findFirst: async () => ({
          id: 'listing-1',
          title: 'Lada Vesta NG',
        }),
      },
    } as any,
    {} as any,
    {} as any,
  );

  const html = await controller.getListingLandingPage('listing-1');
  const redirects = runListingScriptRedirects(
    html,
    'Mozilla/5.0 (Linux; Android 14; Pixel 8)',
  );

  assert.deepEqual(redirects, [
    'https://play.google.com/store/apps/details?id=online.attomarket.atta',
  ]);
});

test('missing listing fallback renders unavailable state without auto redirect', async () => {
  const controller = new AppController(
    {
      listing: {
        findFirst: async () => null,
      },
    } as any,
    {} as any,
    {} as any,
  );

  const html = await controller.getListingLandingPage('missing-listing');

  assert.match(html, /Объявление недоступно/);
  assert.match(
    html,
    /https:\/\/play\.google\.com\/store\/apps\/details\?id=online\.attomarket\.atta/,
  );
  assert.doesNotMatch(html, /http-equiv="refresh"/);
  assert.match(html, /visibilitychange/);
  assert.match(html, /pagehide/);
  assert.match(html, /clearTimeout/);
  assert.match(html, /window\.location\.replace/);
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

function runListingScriptRedirects(html: string, userAgent: string) {
  const scriptMatch = html.match(/<script>\s*([\s\S]*?)\s*<\/script>/);
  assert.ok(scriptMatch, 'listing page script is present');
  const redirects: string[] = [];
  const context = {
    navigator: {
      userAgent,
      vendor: '',
    },
    document: {
      hidden: false,
      addEventListener: () => undefined,
    },
    window: {
      addEventListener: () => undefined,
      location: {
        replace: (url: string) => {
          redirects.push(url);
        },
      },
    },
    setTimeout: (callback: () => void) => {
      callback();
      return 1;
    },
    clearTimeout: () => undefined,
  };

  vm.runInNewContext(scriptMatch[1], context);
  return redirects;
}
