import {
  Controller,
  Get,
  Header,
  HttpStatus,
  Param,
  Query,
  Res,
} from '@nestjs/common';
import { existsSync } from 'fs';
import { resolve } from 'path';

import { PrismaService } from './modules/prisma/prisma.service';
import { RedisService } from './modules/redis/redis.service';
import { StorageService } from './modules/storage/storage.service';

@Controller()
export class AppController {
  private static readonly appStoreFallbackUrl =
    'https://apps.apple.com/app/id6762604298';
  private static readonly googlePlayFallbackUrl =
    'https://play.google.com/store/apps/details?id=online.attomarket.atta';
  private static readonly appLandingUrl = 'https://attamarket.online/invite';
  private static readonly appOgImageUrl =
    'https://attamarket.online/meta/app-icon.png';
  private static readonly appleTeamId = 'F5F8UG6LWD';
  private static readonly iosBundleId = 'com.mansurdagalaev.atta';
  private static readonly androidPackageName = 'online.attomarket.atta';

  constructor(
    private readonly prisma: PrismaService,
    private readonly redisService: RedisService,
    private readonly storageService: StorageService,
  ) {}

  @Get('health')
  getHealth() {
    return { status: 'ok' };
  }

  @Get('health/dependencies')
  async getDependenciesHealth() {
    const [database, redis, storage] = await Promise.all([
      this.checkDatabaseHealth(),
      this.checkRedisHealth(),
      this.storageService.getHealthStatus(),
    ]);

    return {
      api: 'ok',
      database,
      redis,
      storage: storage.status,
      storage_message: storage.message ?? null,
    };
  }

  @Get('.well-known/apple-app-site-association')
  @Header('Content-Type', 'application/json')
  getAppleAppSiteAssociation() {
    return {
      applinks: {
        apps: [],
        details: [
          {
            appID: `${AppController.appleTeamId}.${AppController.iosBundleId}`,
            paths: ['/listing/*', '/invite*', '/app*', '/payments/yookassa/return*'],
          },
        ],
      },
    };
  }

  @Get('.well-known/assetlinks.json')
  @Header('Content-Type', 'application/json')
  getAndroidAssetLinks() {
    const fingerprints = this.getAndroidSha256Fingerprints();
    return [
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: AppController.androidPackageName,
          sha256_cert_fingerprints: fingerprints,
        },
      },
    ];
  }

  @Get(['app', 'invite'])
  @Header('Content-Type', 'text/html; charset=utf-8')
  getAppLandingPage(@Query('ref') ref?: string) {
    const pageUrl = this.buildInviteLandingUrl(ref);
    return `<!doctype html>
<html lang="ru">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>ATTA</title>
    <meta name="description" content="Приложение для объявлений" />
    <meta property="og:type" content="website" />
    <meta property="og:title" content="ATTA" />
    <meta property="og:description" content="Приложение для объявлений" />
    <meta property="og:image" content="${AppController.appOgImageUrl}" />
    <meta property="og:url" content="${pageUrl}" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="ATTA" />
    <meta name="twitter:description" content="Приложение для объявлений" />
    <meta name="twitter:image" content="${AppController.appOgImageUrl}" />
    <link rel="canonical" href="${pageUrl}" />
    ${this.renderInviteLandingScript(ref)}
    ${this.renderLandingStyles()}
  </head>
  <body>
    <main>
      <section class="card">
        <h1>ATTA</h1>
        <p>Откройте приложение ATTA или установите его из магазина.</p>
        ${this.renderStoreButtons()}
      </section>
    </main>
  </body>
</html>`;
  }

  private buildInviteLandingUrl(ref?: string) {
    const normalizedRef = (ref ?? '').trim();
    if (!normalizedRef) {
      return AppController.appLandingUrl;
    }
    return `${AppController.appLandingUrl}?ref=${encodeURIComponent(normalizedRef)}`;
  }

  @Get('meta/app-icon.png')
  getAppIcon(@Res() res: any) {
    const candidates = [
      resolve(process.cwd(), '../web/icons/Icon-512.png'),
      resolve(process.cwd(), '../assets/branding/icon/app_icon.png'),
    ];
    const iconPath = candidates.find((candidate) => existsSync(candidate));
    if (!iconPath) {
      res.status(404).end();
      return;
    }
    res.sendFile(iconPath, {
      headers: {
        'Cache-Control': 'public, max-age=3600',
      },
    });
  }

  @Get('listing/:listingId')
  @Header('Content-Type', 'text/html; charset=utf-8')
  async getListingLandingPage(
    @Param('listingId') listingId: string,
    @Res({ passthrough: true }) res?: any,
  ) {
    const normalizedListingId = listingId.trim();
    if (!normalizedListingId) {
      res?.status(HttpStatus.NOT_FOUND);
      return this.renderNotFoundPage();
    }

    const listing = await this.prisma.listing.findFirst({
      where: {
        id: normalizedListingId,
        status: 'APPROVED',
        archivedAt: null,
        deletedAt: null,
        owner: {
          status: 'ACTIVE',
          deletedAt: null,
        },
      },
      select: {
        id: true,
        title: true,
        description: true,
        category: true,
        subcategory: true,
        price: true,
        city: true,
        updatedAt: true,
        publishedAt: true,
        photos: {
          orderBy: { sortOrder: 'asc' },
          select: { publicUrl: true },
          take: 1,
        },
      },
    });

    if (!listing) {
      res?.status(HttpStatus.NOT_FOUND);
      return this.renderNotFoundPage();
    }

    return this.renderListingSeoPage(listing);
  }

  @Get('sitemap.xml')
  @Header('Content-Type', 'application/xml; charset=utf-8')
  async getSitemap() {
    const listings = await this.prisma.listing.findMany({
      where: {
        status: 'APPROVED',
        archivedAt: null,
        deletedAt: null,
        owner: {
          status: 'ACTIVE',
          deletedAt: null,
        },
      },
      select: {
        id: true,
        updatedAt: true,
        publishedAt: true,
      },
      orderBy: [
        { publishedAt: 'desc' },
        { updatedAt: 'desc' },
      ],
      take: 45000,
    });
    const urls: Array<{ loc: string; lastmod?: string }> = [
      { loc: 'https://attamarket.online/' },
      { loc: 'https://attamarket.online/privacy' },
      ...listings.map((listing) => ({
        loc: `https://attamarket.online/listing/${encodeURIComponent(listing.id)}`,
        lastmod: (listing.updatedAt ?? listing.publishedAt)?.toISOString(),
      })),
    ];

    return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls
      .map((url) => `  <url>\n    <loc>${this.escapeXml(url.loc)}</loc>${url.lastmod ? `\n    <lastmod>${this.escapeXml(url.lastmod)}</lastmod>` : ''}\n  </url>`)
      .join('\n')}\n</urlset>\n`;
  }

  private renderListingSeoPage(listing: {
    id: string;
    title: string;
    description: string;
    category: string;
    subcategory: string;
    price: bigint | number;
    city: string;
    updatedAt: Date;
    publishedAt: Date | null;
    photos: { publicUrl: string }[];
  }) {
    const pageUrl = `https://attamarket.online/listing/${encodeURIComponent(listing.id)}`;
    const title = this.truncateText(listing.title.trim() || 'Объявление ATTA', 90);
    const description = this.truncateText(
      listing.description.trim() || `${title} на ATTA — Атта Маркет`,
      220,
    );
    const imageUrl = this.safeAbsoluteUrl(listing.photos[0]?.publicUrl);
    const price = this.formatPrice(listing.price);
    const jsonLd = this.safeJsonLd({
      '@context': 'https://schema.org',
      '@type': 'ItemPage',
      '@id': `${pageUrl}#webpage`,
      url: pageUrl,
      name: title,
      description,
      inLanguage: 'ru-RU',
      dateModified: listing.updatedAt.toISOString(),
      datePublished: listing.publishedAt?.toISOString(),
      primaryImageOfPage: imageUrl ? { '@type': 'ImageObject', url: imageUrl } : undefined,
      breadcrumb: {
        '@type': 'BreadcrumbList',
        itemListElement: [
          { '@type': 'ListItem', position: 1, name: 'ATTA', item: 'https://attamarket.online/' },
          { '@type': 'ListItem', position: 2, name: title, item: pageUrl },
        ],
      },
    });
    return `<!doctype html>
<html lang="ru">
  <head>
    <meta charset="utf-8" />
    <base href="/">
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${this.escapeHtml(title)}</title>
    <meta name="description" content="${this.escapeHtml(description)}" />
    <meta property="og:type" content="article" />
    <meta property="og:site_name" content="ATTA — Атта Маркет" />
    <meta property="og:locale" content="ru_RU" />
    <meta property="og:title" content="${this.escapeHtml(title)}" />
    <meta property="og:description" content="${this.escapeHtml(description)}" />
    <meta property="og:url" content="${pageUrl}" />
    ${imageUrl ? `<meta property="og:image" content="${this.escapeHtml(imageUrl)}" />` : ''}
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="${this.escapeHtml(title)}" />
    <meta name="twitter:description" content="${this.escapeHtml(description)}" />
    ${imageUrl ? `<meta name="twitter:image" content="${this.escapeHtml(imageUrl)}" />` : ''}
    <link rel="canonical" href="${pageUrl}" />
    <link rel="manifest" href="manifest.json">
    <link rel="icon" type="image/png" href="favicon.png"/>
    <script type="application/ld+json">${jsonLd}</script>
    <style>
      body {
        margin: 0;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        background: #f5f5f5;
        color: #1f1f1f;
      }
      main {
        min-height: 100vh;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
      }
      .card {
        width: 100%;
        max-width: 420px;
        background: #ffffff;
        border-radius: 18px;
        padding: 24px;
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.08);
        text-align: center;
      }
      h1 {
        margin: 0 0 12px;
        font-size: 28px;
      }
      p {
        margin: 0 0 18px;
        line-height: 1.5;
      }
      .actions {
        display: flex;
        flex-direction: column;
        gap: 12px;
        margin-top: 20px;
      }
      a.button {
        display: inline-block;
        padding: 12px 18px;
        border-radius: 12px;
        background: #1f1f1f;
        color: #ffffff;
        text-decoration: none;
        font-weight: 600;
      }
      a.button.secondary {
        background: #ffffff;
        color: #1f1f1f;
        border: 1px solid rgba(31, 31, 31, 0.14);
      }
    </style>
  </head>
  <body>
    <main>
      <article class="card">
        <h1>${this.escapeHtml(title)}</h1>
        ${imageUrl ? `<img src="${this.escapeHtml(imageUrl)}" alt="${this.escapeHtml(title)}" loading="eager" />` : ''}
        ${price ? `<p class="price">${this.escapeHtml(price)}</p>` : ''}
        ${listing.city.trim() ? `<p>${this.escapeHtml(listing.city.trim())}</p>` : ''}
        <p>${this.escapeHtml(description)}</p>
      </article>
    </main>
    <script src="flutter_bootstrap.js" async></script>
  </body>
</html>`;
  }

  private renderNotFoundPage() {
    return `<!doctype html><html lang="ru"><head><meta charset="utf-8" /><meta name="robots" content="noindex" /><title>Объявление не найдено</title></head><body><h1>Объявление не найдено</h1></body></html>`;
  }

  private renderInviteLandingScript(ref?: string) {
    const normalizedRef = (ref ?? '').trim();
    return `<script>
      (function () {
        var ua = navigator.userAgent || navigator.vendor || '';
        var platform = /android/i.test(ua)
          ? 'android'
          : (/iPad|iPhone|iPod/.test(ua) ? 'ios' : 'unknown');
        document.documentElement.setAttribute('data-platform', platform);
        ${normalizedRef ? `try {
          var ref = '${this.escapeJavaScriptString(normalizedRef)}';
          window.localStorage.setItem('atta.invite.referralCode', ref);
          document.cookie = 'atta_invite_ref=' + encodeURIComponent(ref) + '; Max-Age=2592000; Path=/; SameSite=Lax; Secure';
          try {
            window.fetch('/auth/referrals/open', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ referralCode: ref, appOpened: false }),
              keepalive: true
            });
          } catch (_) {}
        } catch (_) {}` : ''}
      })();
    </script>`;
  }

  private renderLandingStyles() {
    return `<style>
      body {
        margin: 0;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        background: #f5f5f5;
        color: #1f1f1f;
      }
      main {
        min-height: 100vh;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
      }
      .card {
        width: 100%;
        max-width: 420px;
        background: #ffffff;
        border-radius: 18px;
        padding: 24px;
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.08);
        text-align: center;
      }
      h1 {
        margin: 0 0 12px;
        font-size: 28px;
      }
      p {
        margin: 0 0 18px;
        line-height: 1.5;
      }
      .actions {
        display: flex;
        flex-direction: column;
        gap: 12px;
        margin-top: 20px;
      }
      a.button {
        display: inline-block;
        padding: 12px 18px;
        border-radius: 12px;
        background: #1f1f1f;
        color: #ffffff;
        text-decoration: none;
        font-weight: 600;
      }
      a.button.secondary {
        background: #ffffff;
        color: #1f1f1f;
        border: 1px solid rgba(31, 31, 31, 0.14);
      }
    </style>`;
  }

  private renderSmartFallbackScript() {
    return `<script>
      (function () {
        var ua = navigator.userAgent || navigator.vendor || '';
        if (!/android/i.test(ua)) return;

        var googlePlayUrl = '${AppController.googlePlayFallbackUrl}';
        var handled = false;
        var timer = null;

        function stopFallback() {
          handled = true;
          if (timer !== null) {
            clearTimeout(timer);
            timer = null;
          }
        }

        document.addEventListener('visibilitychange', function () {
          if (document.hidden) stopFallback();
        });
        window.addEventListener('pagehide', stopFallback);
        window.addEventListener('blur', function () {
          setTimeout(function () {
            if (document.hidden) stopFallback();
          }, 0);
        });

        timer = setTimeout(function () {
          if (handled) return;
          window.location.replace(googlePlayUrl);
        }, 900);
      })();
    </script>`;
  }

  private renderStoreButtons(options?: { appStoreLabel?: string }) {
    const appStoreLabel = options?.appStoreLabel ?? 'Скачать в App Store';
    return `<div class="actions">
          <a class="button" href="${AppController.appStoreFallbackUrl}">${appStoreLabel}</a>
          <a class="button secondary" href="${AppController.googlePlayFallbackUrl}">Скачать в Google Play</a>
        </div>`;
  }

  private escapeHtml(value: string) {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  private escapeXml(value: string) {
    return this.escapeHtml(value);
  }

  private truncateText(value: string, maxLength: number) {
    const normalized = value.replace(/\s+/g, ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return `${normalized.slice(0, maxLength - 1).trim()}…`;
  }

  private formatPrice(value: bigint | number | null | undefined) {
    const amount = typeof value === 'bigint' ? Number(value) : Number(value ?? 0);
    if (!Number.isFinite(amount) || amount <= 0) {
      return null;
    }
    return `${new Intl.NumberFormat('ru-RU').format(amount)} ₽`;
  }

  private safeAbsoluteUrl(value?: string | null) {
    const raw = value?.trim();
    if (!raw) {
      return null;
    }
    try {
      const url = new URL(raw, 'https://attamarket.online');
      if (url.protocol !== 'https:' && url.protocol !== 'http:') {
        return null;
      }
      return url.toString();
    } catch {
      return null;
    }
  }

  private safeJsonLd(value: unknown) {
    return JSON.stringify(value, (_key, nestedValue) =>
      nestedValue === undefined ? undefined : nestedValue,
    ).replace(/</g, '\\u003c');
  }

  private escapeJavaScriptString(value: string) {
    return value
      .replace(/\\/g, '\\\\')
      .replace(/'/g, "\\'")
      .replace(/\r/g, '\\r')
      .replace(/\n/g, '\\n')
      .replace(/</g, '\\x3c');
  }

  private getAndroidSha256Fingerprints() {
    return (process.env.ANDROID_SHA256_CERT_FINGERPRINTS ?? '')
      .split(',')
      .map((value) => value.trim())
      .filter((value) => value.length > 0);
  }

  private async checkDatabaseHealth() {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
      return 'ok';
    } catch {
      return 'error';
    }
  }

  private async checkRedisHealth() {
    try {
      const result = await this.redisService.ping();
      return result === 'PONG' ? 'ok' : 'error';
    } catch {
      return 'error';
    }
  }
}
