"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AppModule = void 0;
const common_1 = require("@nestjs/common");
const app_controller_1 = require("./app.controller");
const admin_module_1 = require("./modules/admin/admin.module");
const apns_module_1 = require("./modules/apns/apns.module");
const auth_module_1 = require("./modules/auth/auth.module");
const chats_module_1 = require("./modules/chats/chats.module");
const favorites_module_1 = require("./modules/favorites/favorites.module");
const listings_module_1 = require("./modules/listings/listings.module");
const media_module_1 = require("./modules/media/media.module");
const notifications_module_1 = require("./modules/notifications/notifications.module");
const feed_ads_module_1 = require("./modules/feed-ads/feed-ads.module");
const phone_verification_module_1 = require("./modules/phone-verification/phone-verification.module");
const presence_module_1 = require("./modules/presence/presence.module");
const prisma_module_1 = require("./modules/prisma/prisma.module");
const promotions_module_1 = require("./modules/promotions/promotions.module");
const redis_module_1 = require("./modules/redis/redis.module");
const rate_limit_module_1 = require("./modules/rate-limit/rate-limit.module");
const reports_module_1 = require("./modules/reports/reports.module");
const reviews_module_1 = require("./modules/reviews/reviews.module");
const s3_module_1 = require("./modules/s3/s3.module");
const storage_module_1 = require("./modules/storage/storage.module");
const support_module_1 = require("./modules/support/support.module");
const users_module_1 = require("./modules/users/users.module");
const user_follows_module_1 = require("./modules/user-follows/user-follows.module");
const saved_searches_module_1 = require("./modules/saved-searches/saved-searches.module");
const viewed_listings_module_1 = require("./modules/viewed-listings/viewed-listings.module");
const wallet_module_1 = require("./modules/wallet/wallet.module");
let AppModule = class AppModule {
};
exports.AppModule = AppModule;
exports.AppModule = AppModule = __decorate([
    (0, common_1.Module)({
        imports: [
            prisma_module_1.PrismaModule,
            rate_limit_module_1.RateLimitModule,
            redis_module_1.RedisModule,
            s3_module_1.S3Module,
            apns_module_1.ApnsModule,
            auth_module_1.AuthModule,
            users_module_1.UsersModule,
            wallet_module_1.WalletModule,
            user_follows_module_1.UserFollowsModule,
            saved_searches_module_1.SavedSearchesModule,
            viewed_listings_module_1.ViewedListingsModule,
            phone_verification_module_1.PhoneVerificationModule,
            listings_module_1.ListingsModule,
            promotions_module_1.PromotionsModule,
            media_module_1.MediaModule,
            storage_module_1.StorageModule,
            favorites_module_1.FavoritesModule,
            chats_module_1.ChatsModule,
            presence_module_1.PresenceModule,
            notifications_module_1.NotificationsModule,
            feed_ads_module_1.FeedAdsModule,
            admin_module_1.AdminModule,
            reports_module_1.ReportsModule,
            reviews_module_1.ReviewsModule,
            support_module_1.SupportModule,
        ],
        controllers: [app_controller_1.AppController],
    })
], AppModule);
//# sourceMappingURL=app.module.js.map