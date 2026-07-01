"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.ChatsModule = void 0;
const common_1 = require("@nestjs/common");
const auth_module_1 = require("../auth/auth.module");
const presence_module_1 = require("../presence/presence.module");
const prisma_module_1 = require("../prisma/prisma.module");
const storage_module_1 = require("../storage/storage.module");
const chats_controller_1 = require("./chats.controller");
const chats_gateway_1 = require("./chats.gateway");
const chats_service_1 = require("./chats.service");
let ChatsModule = class ChatsModule {
};
exports.ChatsModule = ChatsModule;
exports.ChatsModule = ChatsModule = __decorate([
    (0, common_1.Module)({
        imports: [
            presence_module_1.PresenceModule,
            prisma_module_1.PrismaModule,
            auth_module_1.AuthModule,
            storage_module_1.StorageModule,
        ],
        controllers: [chats_controller_1.ChatsController, chats_controller_1.MessagesController],
        providers: [chats_service_1.ChatsService, chats_gateway_1.ChatsGateway],
        exports: [chats_service_1.ChatsService, chats_gateway_1.ChatsGateway],
    })
], ChatsModule);
//# sourceMappingURL=chats.module.js.map