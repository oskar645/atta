"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
var AppController_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.AppController = void 0;
const common_1 = require("@nestjs/common");
const fs_1 = require("fs");
const path_1 = require("path");
const prisma_service_1 = require("./modules/prisma/prisma.service");
const redis_service_1 = require("./modules/redis/redis.service");
const storage_service_1 = require("./modules/storage/storage.service");
let AppController = AppController_1 = class AppController {
    constructor(prisma, redisService, storageService) {
        this.prisma = prisma;
        this.redisService = redisService;
        this.storageService = storageService;
    }
    getHealth() {
        return { status: 'ok' };
    }
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
    getAppleAppSiteAssociation() {
        return {
            applinks: {
                apps: [],
                details: [
                    {
                        appID: `${AppController_1.appleTeamId}.${AppController_1.iosBundleId}`,
                        paths: ['/listing/*', '/invite*', '/app*', '/payments/yookassa/return*'],
                    },
                ],
            },
        };
    }
    getAndroidAssetLinks() {
        const fingerprints = this.getAndroidSha256Fingerprints();
        return [
            {
                relation: ['delegate_permission/common.handle_all_urls'],
                target: {
                    namespace: 'android_app',
                    package_name: AppController_1.androidPackageName,
                    sha256_cert_fingerprints: fingerprints,
                },
            },
        ];
    }
    getAppLandingPage(ref) {
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
    <meta property="og:image" content="${AppController_1.appOgImageUrl}" />
    <meta property="og:url" content="${pageUrl}" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="ATTA" />
    <meta name="twitter:description" content="Приложение для объявлений" />
    <meta name="twitter:image" content="${AppController_1.appOgImageUrl}" />
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
    buildInviteLandingUrl(ref) {
        const normalizedRef = (ref ?? '').trim();
        if (!normalizedRef) {
            return AppController_1.appLandingUrl;
        }
        return `${AppController_1.appLandingUrl}?ref=${encodeURIComponent(normalizedRef)}`;
    }
    getAppIcon(res) {
        const candidates = [
            (0, path_1.resolve)(process.cwd(), '../web/icons/Icon-512.png'),
            (0, path_1.resolve)(process.cwd(), '../assets/branding/icon/app_icon.png'),
        ];
        const iconPath = candidates.find((candidate) => (0, fs_1.existsSync)(candidate));
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
    async getListingLandingPage(listingId) {
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
    renderListingLandingPage(params) {
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
    <meta property="og:image" content="${AppController_1.appOgImageUrl}" />
    <meta property="og:url" content="${pageUrl}" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="${this.escapeHtml(params.title)}" />
    <meta name="twitter:description" content="${this.escapeHtml(params.description)}" />
    <meta name="twitter:image" content="${AppController_1.appOgImageUrl}" />
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
    renderInviteLandingScript(ref) {
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
    renderLandingStyles() {
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
    renderSmartFallbackScript() {
        return `<script>
      (function () {
        var ua = navigator.userAgent || navigator.vendor || '';
        if (!/android/i.test(ua)) return;

        var googlePlayUrl = '${AppController_1.googlePlayFallbackUrl}';
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
    renderStoreButtons(options) {
        const appStoreLabel = options?.appStoreLabel ?? 'Скачать в App Store';
        return `<div class="actions">
          <a class="button" href="${AppController_1.appStoreFallbackUrl}">${appStoreLabel}</a>
          <a class="button secondary" href="${AppController_1.googlePlayFallbackUrl}">Скачать в Google Play</a>
        </div>`;
    }
    escapeHtml(value) {
        return value
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }
    escapeJavaScriptString(value) {
        return value
            .replace(/\\/g, '\\\\')
            .replace(/'/g, "\\'")
            .replace(/\r/g, '\\r')
            .replace(/\n/g, '\\n')
            .replace(/</g, '\\x3c');
    }
    getAndroidSha256Fingerprints() {
        return (process.env.ANDROID_SHA256_CERT_FINGERPRINTS ?? '')
            .split(',')
            .map((value) => value.trim())
            .filter((value) => value.length > 0);
    }
    async checkDatabaseHealth() {
        try {
            await this.prisma.$queryRaw `SELECT 1`;
            return 'ok';
        }
        catch {
            return 'error';
        }
    }
    async checkRedisHealth() {
        try {
            const result = await this.redisService.ping();
            return result === 'PONG' ? 'ok' : 'error';
        }
        catch {
            return 'error';
        }
    }
};
exports.AppController = AppController;
AppController.appStoreFallbackUrl = 'https://apps.apple.com/app/id6762604298';
AppController.googlePlayFallbackUrl = 'https://play.google.com/store/apps/details?id=online.attomarket.atta';
AppController.appLandingUrl = 'https://attamarket.online/invite';
AppController.appOgImageUrl = 'https://attamarket.online/meta/app-icon.png';
AppController.appleTeamId = 'F5F8UG6LWD';
AppController.iosBundleId = 'com.mansurdagalaev.atta';
AppController.androidPackageName = 'online.attomarket.atta';
__decorate([
    (0, common_1.Get)('health'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AppController.prototype, "getHealth", null);
__decorate([
    (0, common_1.Get)('health/dependencies'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], AppController.prototype, "getDependenciesHealth", null);
__decorate([
    (0, common_1.Get)('.well-known/apple-app-site-association'),
    (0, common_1.Header)('Content-Type', 'application/json'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AppController.prototype, "getAppleAppSiteAssociation", null);
__decorate([
    (0, common_1.Get)('.well-known/assetlinks.json'),
    (0, common_1.Header)('Content-Type', 'application/json'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AppController.prototype, "getAndroidAssetLinks", null);
__decorate([
    (0, common_1.Get)(['app', 'invite']),
    (0, common_1.Header)('Content-Type', 'text/html; charset=utf-8'),
    __param(0, (0, common_1.Query)('ref')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], AppController.prototype, "getAppLandingPage", null);
__decorate([
    (0, common_1.Get)('meta/app-icon.png'),
    __param(0, (0, common_1.Res)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], AppController.prototype, "getAppIcon", null);
__decorate([
    (0, common_1.Get)('listing/:listingId'),
    (0, common_1.Header)('Content-Type', 'text/html; charset=utf-8'),
    __param(0, (0, common_1.Param)('listingId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], AppController.prototype, "getListingLandingPage", null);
exports.AppController = AppController = AppController_1 = __decorate([
    (0, common_1.Controller)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        redis_service_1.RedisService,
        storage_service_1.StorageService])
], AppController);
//# sourceMappingURL=app.controller.js.map