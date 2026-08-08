import { Controller, Get, Header, Param, Query, Res } from '@nestjs/common';
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
  ) {
    const normalizedListingId = listingId.trim();
    if (!normalizedListingId) {
      return this.renderListingLandingPage({
        listingId: '',
        title: 'ATTA',
        description: 'Откройте объявление в приложении ATTA',
        available: false,
      });
    }

    const listing = await this.prisma.listing.findFirst({
      where: {
        id: normalizedListingId,
        deletedAt: null,
      },
      select: {
        id: true,
        title: true,
      },
    });

    if (!listing) {
      return this.renderListingLandingPage({
        listingId: normalizedListingId,
        title: 'ATTA',
        description: 'Объявление недоступно',
        available: false,
      });
    }

    return this.renderListingLandingPage({
      listingId: normalizedListingId,
      title: listing.title.trim() || 'ATTA',
      description: 'Откройте объявление в приложении ATTA',
      available: true,
    });
  }

  private renderListingLandingPage(params: {
    listingId: string;
    title: string;
    description: string;
    available: boolean;
  }) {
    const normalizedListingId = params.listingId.trim();
    const pageUrl = normalizedListingId
      ? `https://attamarket.online/listing/${encodeURIComponent(normalizedListingId)}`
      : 'https://attamarket.online/listing';
    return `<!doctype html>
<html lang="ru">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${this.escapeHtml(params.title)}</title>
    <meta name="description" content="${this.escapeHtml(params.description)}" />
    <meta property="og:type" content="website" />
    <meta property="og:title" content="${this.escapeHtml(params.title)}" />
    <meta property="og:description" content="${this.escapeHtml(params.description)}" />
    <meta property="og:image" content="${AppController.appOgImageUrl}" />
    <meta property="og:url" content="${pageUrl}" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="${this.escapeHtml(params.title)}" />
    <meta name="twitter:description" content="${this.escapeHtml(params.description)}" />
    <meta name="twitter:image" content="${AppController.appOgImageUrl}" />
    <link rel="canonical" href="${pageUrl}" />
    ${this.renderSmartFallbackScript()}
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
      <section class="card">
        <h1>ATTA</h1>
        <p>${this.escapeHtml(params.description)}</p>
        <p>${params.available ? 'Если приложение не установлено, скачайте ATTA из магазина.' : 'Если приложение не установлено, выберите магазин вручную.'}</p>
        ${this.renderStoreButtons({ appStoreLabel: 'Скачать ATTA в App Store' })}
      </section>
    </main>
  </body>
</html>`;
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
