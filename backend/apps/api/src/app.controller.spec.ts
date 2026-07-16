import { test } from 'node:test';
import assert from 'node:assert/strict';

import { AppController } from './app.controller.ts';

test('app landing page contains open graph metadata and app store redirect', () => {
  const controller = new AppController({} as any, {} as any, {} as any);

  const html = controller.getAppLandingPage();

  assert.match(html, /<meta property="og:title" content="ATTA"/);
  assert.match(
    html,
    /<meta property="og:description" content="Приложение для объявлений"/,
  );
  assert.match(
    html,
    /<meta property="og:url" content="https:\/\/attamarket\.online\/app"/,
  );
  assert.match(
    html,
    /https:\/\/apps\.apple\.com\/us\/app\/atta\/id6762604298\?l=ru/,
  );
});

test('listing fallback renders manual app store button without auto redirect', async () => {
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
  assert.match(html, /href="https:\/\/attamarket\.online\/listing\/listing-1"/);
  assert.match(html, />App Store</);
  assert.match(
    html,
    /https:\/\/apps\.apple\.com\/us\/app\/atta\/id6762604298\?l=ru/,
  );
  assert.match(
    html,
    /https:\/\/play\.google\.com\/store\/apps\/details\?id=com\.example\.atta/,
  );
  assert.doesNotMatch(html, /http-equiv="refresh"/);
  assert.doesNotMatch(html, /setTimeout/);
  assert.doesNotMatch(html, /window\.location\.replace/);
  assert.doesNotMatch(html, /atta:\/\//);
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
    /https:\/\/play\.google\.com\/store\/apps\/details\?id=com\.example\.atta/,
  );
  assert.doesNotMatch(html, /http-equiv="refresh"/);
  assert.doesNotMatch(html, /setTimeout/);
  assert.doesNotMatch(html, /window\.location\.replace/);
});
