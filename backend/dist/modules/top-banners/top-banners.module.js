"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.TopBannersModule = void 0;
const common_1 = require("@nestjs/common");
const auth_module_1 = require("../auth/auth.module");
const prisma_module_1 = require("../prisma/prisma.module");
const storage_module_1 = require("../storage/storage.module");
const user_blocks_module_1 = require("../user-blocks/user-blocks.module");
const top_banners_controller_1 = require("./top-banners.controller");
const top_banners_service_1 = require("./top-banners.service");
let TopBannersModule = class TopBannersModule {
};
exports.TopBannersModule = TopBannersModule;
exports.TopBannersModule = TopBannersModule = __decorate([
    (0, common_1.Module)({
        imports: [auth_module_1.AuthModule, prisma_module_1.PrismaModule, storage_module_1.StorageModule, user_blocks_module_1.UserBlocksModule],
        controllers: [top_banners_controller_1.TopBannersController],
        providers: [top_banners_service_1.TopBannersService],
        exports: [top_banners_service_1.TopBannersService],
    })
], TopBannersModule);
//# sourceMappingURL=top-banners.module.js.map