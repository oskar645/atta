"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.MediaModule = void 0;
const common_1 = require("@nestjs/common");
const auth_module_1 = require("../auth/auth.module");
const chats_module_1 = require("../chats/chats.module");
const feed_ads_module_1 = require("../feed-ads/feed-ads.module");
const listings_module_1 = require("../listings/listings.module");
const prisma_module_1 = require("../prisma/prisma.module");
const storage_module_1 = require("../storage/storage.module");
const notifications_module_1 = require("../notifications/notifications.module");
const users_module_1 = require("../users/users.module");
const media_controller_1 = require("./media.controller");
let MediaModule = class MediaModule {
};
exports.MediaModule = MediaModule;
exports.MediaModule = MediaModule = __decorate([
    (0, common_1.Module)({
        imports: [
            auth_module_1.AuthModule,
            chats_module_1.ChatsModule,
            feed_ads_module_1.FeedAdsModule,
            listings_module_1.ListingsModule,
            notifications_module_1.NotificationsModule,
            prisma_module_1.PrismaModule,
            storage_module_1.StorageModule,
            users_module_1.UsersModule,
        ],
        controllers: [media_controller_1.MediaController],
    })
], MediaModule);
//# sourceMappingURL=media.module.js.map