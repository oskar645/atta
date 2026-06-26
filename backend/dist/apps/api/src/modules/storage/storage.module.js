"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.StorageModule = void 0;
const common_1 = require("@nestjs/common");
const prisma_module_1 = require("../prisma/prisma.module");
const s3_module_1 = require("../s3/s3.module");
const local_storage_provider_1 = require("./local-storage.provider");
const media_storage_service_1 = require("./media-storage.service");
const s3_storage_provider_1 = require("./s3-storage.provider");
const storage_controller_1 = require("./storage.controller");
const storage_service_1 = require("./storage.service");
let StorageModule = class StorageModule {
};
exports.StorageModule = StorageModule;
exports.StorageModule = StorageModule = __decorate([
    (0, common_1.Module)({
        imports: [s3_module_1.S3Module, prisma_module_1.PrismaModule],
        controllers: [storage_controller_1.StorageController],
        providers: [
            local_storage_provider_1.LocalStorageProvider,
            s3_storage_provider_1.S3StorageProvider,
            media_storage_service_1.MediaStorageService,
            storage_service_1.StorageService,
        ],
        exports: [storage_service_1.StorageService],
    })
], StorageModule);
//# sourceMappingURL=storage.module.js.map