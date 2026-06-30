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
var MediaController_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.MediaController = void 0;
const common_1 = require("@nestjs/common");
const platform_express_1 = require("@nestjs/platform-express");
const jwt_1 = require("@nestjs/jwt");
const env_1 = require("../../config/env");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const admin_guard_1 = require("../auth/admin.guard");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const chats_gateway_1 = require("../chats/chats.gateway");
const chats_service_1 = require("../chats/chats.service");
const feed_ads_service_1 = require("../feed-ads/feed-ads.service");
const listings_service_1 = require("../listings/listings.service");
const prisma_service_1 = require("../prisma/prisma.service");
const rate_limit_service_1 = require("../rate-limit/rate-limit.service");
const storage_service_1 = require("../storage/storage.service");
const users_service_1 = require("../users/users.service");
const memoryImageUpload = (0, platform_express_1.FileInterceptor)('file', {
    storage: require('multer').memoryStorage(),
});
// TODO: Video upload / 30 sec limit will be migrated later.
let MediaController = MediaController_1 = class MediaController {
    constructor(jwtService, prisma, rateLimitService, chatsGateway, chatsService, feedAdsService, listingsService, storageService, usersService) {
        this.jwtService = jwtService;
        this.prisma = prisma;
        this.rateLimitService = rateLimitService;
        this.chatsGateway = chatsGateway;
        this.chatsService = chatsService;
        this.feedAdsService = feedAdsService;
        this.listingsService = listingsService;
        this.storageService = storageService;
        this.usersService = usersService;
        this.logger = new common_1.Logger(MediaController_1.name);
    }
    uploadAvatar(authUser, file) {
        this.rateLimitService.consumeOrThrow(`media:avatar:${authUser.userId}`, {
            limit: 15,
            windowMs: 60 * 1000,
        });
        return this.usersService.uploadAvatar(authUser, this.requireImage(file, 2 * 1024 * 1024));
    }
    uploadListingPhoto(authUser, listingId, request, file) {
        this.rateLimitService.consumeOrThrow(`media:listing:${authUser.userId}`, {
            limit: 20,
            windowMs: 60 * 1000,
        });
        const rawSortOrder = request?.body?.sort_order ?? request?.body?.sortOrder;
        const parsedSortOrder = typeof rawSortOrder === 'string' && rawSortOrder.trim().length > 0
            ? Number(rawSortOrder)
            : typeof rawSortOrder === 'number'
                ? rawSortOrder
                : undefined;
        return this.listingsService.uploadPhoto(authUser, listingId, this.requireImage(file, 8 * 1024 * 1024), Number.isFinite(parsedSortOrder) ? parsedSortOrder : undefined);
    }
    deleteListingPhoto(authUser, listingId, photoId) {
        return this.listingsService.deletePhoto(authUser, listingId, photoId);
    }
    uploadChatImage(authUser, chatId, file) {
        this.rateLimitService.consumeOrThrow(`media:chat:${authUser.userId}`, {
            limit: 20,
            windowMs: 60 * 1000,
        });
        return this.chatsService.uploadImage(authUser, chatId, this.requireImage(file, 2 * 1024 * 1024)).then((result) => {
            this.chatsGateway.emitOutgoingMessage(result.chat, result.recipientChat, result.message, result.recipientId, result.notification);
            return result;
        });
    }
    async getChatImage(mediaId, token, request, response) {
        const authUser = await this.authenticateRequest(request, token);
        const access = await this.chatsService.getChatImageAccess(authUser, mediaId);
        const bytes = await this.storageService.readChatFile(access.key, access.bucket);
        this.debugProxyHit('chats', access.key, access.bucket ?? 's3', 200);
        response.setHeader('Content-Type', access.mimeType);
        response.setHeader('Cache-Control', 'private, max-age=300');
        response.send(bytes);
    }
    async getChatImageByKey(key, token, request, response) {
        const authUser = await this.authenticateRequest(request, token);
        const access = await this.chatsService.getChatImageAccessByKey(authUser, key);
        const bytes = await this.storageService.readChatFile(access.key, access.bucket);
        this.debugProxyHit('chats', access.key, access.bucket ?? 's3', 200);
        response.setHeader('Content-Type', access.mimeType);
        response.setHeader('Cache-Control', 'private, max-age=300');
        response.send(bytes);
    }
    async getPublicObject(category, key, response) {
        const allowed = new Set([
            'avatars',
            'listings',
            'feed-ads',
            'support',
            'reports',
            'misc',
            'videos',
        ]);
        if (!allowed.has(category) || !key?.trim()) {
            throw new common_1.BadRequestException('Файл не найден');
        }
        const bytes = await this.storageService.readStoredFile(category, key, 's3');
        this.debugProxyHit(category, key, 's3', 200);
        const lowerKey = key.toLowerCase();
        const mimeType = lowerKey.endsWith('.png')
            ? 'image/png'
            : lowerKey.endsWith('.webp')
                ? 'image/webp'
                : lowerKey.endsWith('.heic')
                    ? 'image/heic'
                    : lowerKey.endsWith('.heif')
                        ? 'image/heif'
                        : lowerKey.endsWith('.mp4')
                            ? 'video/mp4'
                            : lowerKey.endsWith('.mov')
                                ? 'video/quicktime'
                                : lowerKey.endsWith('.webm')
                                    ? 'video/webm'
                                    : 'image/jpeg';
        response.setHeader('Content-Type', mimeType);
        response.setHeader('Cache-Control', 'public, max-age=300');
        response.send(bytes);
    }
    uploadFeedAdImage(authUser, feedAdId, file) {
        return this.feedAdsService.attachImage(authUser, feedAdId, this.requireImage(file, 5 * 1024 * 1024));
    }
    deleteMedia(authUser, id) {
        if (authUser.role !== 'admin') {
            throw new common_1.ForbiddenException('Generic media delete is admin-only for now');
        }
        return this.storageService.deleteMediaByEntityId(id);
    }
    requireImage(file, maxSizeBytes) {
        if (!file || !file.buffer || file.size === 0) {
            throw new common_1.BadRequestException('Изображение обязательно');
        }
        const mime = file.mimetype.trim().toLowerCase();
        const allowed = new Set([
            'image/jpeg',
            'image/png',
            'image/webp',
            'image/heic',
            'image/heif',
        ]);
        if (!allowed.has(mime)) {
            throw new common_1.BadRequestException('Поддерживаются JPG, PNG, WEBP и HEIC/HEIF');
        }
        const detectedMime = this.detectImageMime(file.buffer);
        if (!detectedMime || detectedMime !== mime) {
            throw new common_1.BadRequestException('Файл не является корректным изображением');
        }
        if (file.size > maxSizeBytes) {
            throw new common_1.BadRequestException('Файл слишком большой');
        }
        return file;
    }
    debugProxyHit(category, key, provider, status) {
        if (env_1.env.NODE_ENV === 'production') {
            return;
        }
        this.logger.debug(`Media proxy status=${status} category=${category} provider=${provider} key=${key}`);
    }
    detectImageMime(buffer) {
        if (buffer.length >= 3 &&
            buffer[0] === 0xff &&
            buffer[1] === 0xd8 &&
            buffer[2] === 0xff) {
            return 'image/jpeg';
        }
        if (buffer.length >= 8 &&
            buffer[0] === 0x89 &&
            buffer[1] === 0x50 &&
            buffer[2] === 0x4e &&
            buffer[3] === 0x47 &&
            buffer[4] === 0x0d &&
            buffer[5] === 0x0a &&
            buffer[6] === 0x1a &&
            buffer[7] === 0x0a) {
            return 'image/png';
        }
        if (buffer.length >= 12 &&
            buffer[0] === 0x52 &&
            buffer[1] === 0x49 &&
            buffer[2] === 0x46 &&
            buffer[3] === 0x46 &&
            buffer[8] === 0x57 &&
            buffer[9] === 0x45 &&
            buffer[10] === 0x42 &&
            buffer[11] === 0x50) {
            return 'image/webp';
        }
        if (buffer.length >= 12 &&
            buffer[4] === 0x66 &&
            buffer[5] === 0x74 &&
            buffer[6] === 0x79 &&
            buffer[7] === 0x70) {
            const brand = Buffer.from(buffer.subarray(8, 12)).toString('ascii').toLowerCase();
            if (brand.includes('heic') || brand.includes('heix')) {
                return 'image/heic';
            }
            if (brand.includes('heif') || brand.includes('hevx')) {
                return 'image/heif';
            }
        }
        return null;
    }
    async authenticateRequest(request, queryToken) {
        const header = request?.headers?.authorization;
        const bearerHeader = typeof header === 'string' && header.startsWith('Bearer ')
            ? header.slice('Bearer '.length).trim()
            : '';
        const token = queryToken?.trim() || bearerHeader;
        if (!token) {
            throw new common_1.ForbiddenException('Access token is required');
        }
        let payload;
        try {
            payload = await this.jwtService.verifyAsync(token, {
                secret: env_1.env.JWT_ACCESS_SECRET,
            });
        }
        catch {
            throw new common_1.ForbiddenException('Access token is invalid or expired');
        }
        const session = await this.prisma.userSession.findFirst({
            where: {
                id: payload.sessionId,
                userId: payload.sub,
                revokedAt: null,
            },
            select: {
                id: true,
                userId: true,
                expiresAt: true,
            },
        });
        if (!session || session.expiresAt.getTime() <= Date.now()) {
            throw new common_1.ForbiddenException('Session is not active');
        }
        return {
            userId: session.userId,
            sessionId: session.id,
            role: payload.role,
            email: payload.email,
        };
    }
};
exports.MediaController = MediaController;
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)('avatar'),
    (0, common_1.UseInterceptors)(memoryImageUpload),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.UploadedFile)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", void 0)
], MediaController.prototype, "uploadAvatar", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)('listings/:listingId/photos'),
    (0, common_1.UseInterceptors)(memoryImageUpload),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('listingId', new common_1.ParseUUIDPipe())),
    __param(2, (0, common_1.Req)()),
    __param(3, (0, common_1.UploadedFile)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, Object, Object]),
    __metadata("design:returntype", void 0)
], MediaController.prototype, "uploadListingPhoto", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Delete)('listings/:listingId/photos/:photoId'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('listingId', new common_1.ParseUUIDPipe())),
    __param(2, (0, common_1.Param)('photoId', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, String]),
    __metadata("design:returntype", void 0)
], MediaController.prototype, "deleteListingPhoto", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)('chats/:chatId/images'),
    (0, common_1.UseInterceptors)(memoryImageUpload),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('chatId', new common_1.ParseUUIDPipe())),
    __param(2, (0, common_1.UploadedFile)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, Object]),
    __metadata("design:returntype", void 0)
], MediaController.prototype, "uploadChatImage", null);
__decorate([
    (0, common_1.Get)('chats/:mediaId'),
    __param(0, (0, common_1.Param)('mediaId')),
    __param(1, (0, common_1.Query)('token')),
    __param(2, (0, common_1.Req)()),
    __param(3, (0, common_1.Res)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, Object, Object]),
    __metadata("design:returntype", Promise)
], MediaController.prototype, "getChatImage", null);
__decorate([
    (0, common_1.Get)('chats/file'),
    __param(0, (0, common_1.Query)('key')),
    __param(1, (0, common_1.Query)('token')),
    __param(2, (0, common_1.Req)()),
    __param(3, (0, common_1.Res)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, Object, Object]),
    __metadata("design:returntype", Promise)
], MediaController.prototype, "getChatImageByKey", null);
__decorate([
    (0, common_1.Get)('object'),
    __param(0, (0, common_1.Query)('category')),
    __param(1, (0, common_1.Query)('key')),
    __param(2, (0, common_1.Res)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, Object]),
    __metadata("design:returntype", Promise)
], MediaController.prototype, "getPublicObject", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, admin_guard_1.AdminGuard),
    (0, common_1.Post)('feed-ads/:feedAdId/image'),
    (0, common_1.UseInterceptors)(memoryImageUpload),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('feedAdId', new common_1.ParseUUIDPipe())),
    __param(2, (0, common_1.UploadedFile)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, Object]),
    __metadata("design:returntype", void 0)
], MediaController.prototype, "uploadFeedAdImage", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Delete)(':id'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], MediaController.prototype, "deleteMedia", null);
exports.MediaController = MediaController = MediaController_1 = __decorate([
    (0, common_1.Controller)('media'),
    __metadata("design:paramtypes", [jwt_1.JwtService,
        prisma_service_1.PrismaService,
        rate_limit_service_1.RateLimitService,
        chats_gateway_1.ChatsGateway,
        chats_service_1.ChatsService,
        feed_ads_service_1.FeedAdsService,
        listings_service_1.ListingsService,
        storage_service_1.StorageService,
        users_service_1.UsersService])
], MediaController);
//# sourceMappingURL=media.controller.js.map