"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.UserFollowsModule = void 0;
const common_1 = require("@nestjs/common");
const auth_module_1 = require("../auth/auth.module");
const prisma_module_1 = require("../prisma/prisma.module");
const user_follows_controller_1 = require("./user-follows.controller");
const user_follows_service_1 = require("./user-follows.service");
let UserFollowsModule = class UserFollowsModule {
};
exports.UserFollowsModule = UserFollowsModule;
exports.UserFollowsModule = UserFollowsModule = __decorate([
    (0, common_1.Module)({
        imports: [auth_module_1.AuthModule, prisma_module_1.PrismaModule],
        controllers: [user_follows_controller_1.UserFollowsController],
        providers: [user_follows_service_1.UserFollowsService],
        exports: [user_follows_service_1.UserFollowsService],
    })
], UserFollowsModule);
//# sourceMappingURL=user-follows.module.js.map