import { Controller, Get, Header, Param, Res } from '@nestjs/common';
import { existsSync } from 'fs';
import { resolve } from 'path';

import { PrismaService } from './modules/prisma/prisma.service';
import { RedisService } from './modules/redis/redis.service';
import { StorageService } from './modules/storage/storage.service';

@Controller()
export class AppController {
  private static readonly appStoreFallbackUrl =
    'https://apps.apple.com/us/app/atta/id6762604298?l=ru';
  private static readonly googlePlayFallbackUrl =
    'https://play.google.com/store/apps/details?id=com.example.atta';
  private static readonly appLandingUrl = 'https://attamarket.online/app';
  private static readonly appOgImageUrl =
    'https://attamarket.online/meta/app-icon.png';
  private static readonly appleTeamId = 'F5F8UG6LWD';
  private static readonly iosBundleId = 'com.mansurdagalaev.atta';

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
  getAppleAppSiteAssociation() {
    return {
      applinks: {
        apps: [],
        details: [
          {
            appID: `${AppController.appleTeamId}.${AppController.iosBundleId}`,
            paths: ['/listing/*', '/invite*', '/app*'],
          },
        ],
      },
    };
  }

  @Get(['app', 'invite'])
  @Header('Content-Type', 'text/html; charset=utf-8')
  getAppLandingPage() {
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
    <meta property="og:url" content="${AppController.appLandingUrl}" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="ATTA" />
    <meta name="twitter:description" content="Приложение для объявлений" />
    <meta name="twitter:image" content="${AppController.appOgImageUrl}" />
    <link rel="canonical" href="${AppController.appLandingUrl}" />
    <meta http-equiv="refresh" content="1;url=${AppController.appStoreFallbackUrl}" />
    <script>
      setTimeout(function () {
        window.location.replace('${AppController.appStoreFallbackUrl}');
      }, 120);
    </script>
  </head>
  <body>
    <p>Открываем ATTA…</p>
    <p><a href="${AppController.appStoreFallbackUrl}">Если переход не сработал, нажмите сюда.</a></p>
  </body>
</html>`;
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
    const buttonText = params.available ? 'Открыть в приложении' : 'Установить ATTA';

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
        <p>Если приложение уже установлено, после открытия объявления дополнительные переходы не выполняются.</p>
        <div class="actions">
          <a class="button" href="${pageUrl}">${buttonText}</a>
          <a class="button secondary" href="${AppController.appStoreFallbackUrl}">App Store</a>
          <a class="button secondary" href="${AppController.googlePlayFallbackUrl}">Google Play</a>
        </div>
      </section>
    </main>
  </body>
</html>`;
  }

  private escapeHtml(value: string) {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
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
