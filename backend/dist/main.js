"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
require("reflect-metadata");
const common_1 = require("@nestjs/common");
const core_1 = require("@nestjs/core");
const path_1 = require("path");
const app_module_1 = require("./app.module");
const trust_proxy_1 = require("./common/trust-proxy");
const env_1 = require("./config/env");
const storage_service_1 = require("./modules/storage/storage.service");
const express = require('express');
async function bootstrap() {
    const app = await core_1.NestFactory.create(app_module_1.AppModule, {
        cors: {
            origin: (0, env_1.parseCorsOrigins)(),
            credentials: true,
        },
    });
    (0, trust_proxy_1.configureTrustProxy)(app.getHttpAdapter().getInstance());
    app.useGlobalPipes(new common_1.ValidationPipe({
        whitelist: true,
        transform: true,
        forbidNonWhitelisted: true,
    }));
    app.use((req, res, next) => {
        res.setHeader('X-Frame-Options', 'DENY');
        res.setHeader('X-Content-Type-Options', 'nosniff');
        res.setHeader('Referrer-Policy', 'no-referrer');
        res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
        next();
    });
    const storageService = app.get(storage_service_1.StorageService);
    await storageService.ensureUploadsDirs();
    const uploadsRoot = storageService.getUploadsRoot();
    app.use('/uploads/avatars', express.static((0, path_1.join)(uploadsRoot, 'avatars')));
    app.use('/uploads/listings', express.static((0, path_1.join)(uploadsRoot, 'listings')));
    app.use('/uploads/feed-ads', express.static((0, path_1.join)(uploadsRoot, 'feed-ads')));
    await app.listen(env_1.env.PORT);
    const logger = new common_1.Logger('Bootstrap');
    logger.log(`ATTA backend skeleton is running on port ${env_1.env.PORT}`);
}
void bootstrap();
//# sourceMappingURL=main.js.map