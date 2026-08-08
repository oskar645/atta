"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.ViewedListingsModule = void 0;
const common_1 = require("@nestjs/common");
const auth_module_1 = require("../auth/auth.module");
const prisma_module_1 = require("../prisma/prisma.module");
const user_blocks_module_1 = require("../user-blocks/user-blocks.module");
const viewed_listings_controller_1 = require("./viewed-listings.controller");
const viewed_listings_service_1 = require("./viewed-listings.service");
let ViewedListingsModule = class ViewedListingsModule {
};
exports.ViewedListingsModule = ViewedListingsModule;
exports.ViewedListingsModule = ViewedListingsModule = __decorate([
    (0, common_1.Module)({
        imports: [auth_module_1.AuthModule, prisma_module_1.PrismaModule, user_blocks_module_1.UserBlocksModule],
        controllers: [viewed_listings_controller_1.ViewedListingsController],
        providers: [viewed_listings_service_1.ViewedListingsService],
        exports: [viewed_listings_service_1.ViewedListingsService],
    })
], ViewedListingsModule);
//# sourceMappingURL=viewed-listings.module.js.map