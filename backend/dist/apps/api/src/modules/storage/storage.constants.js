"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.STORAGE_ROUTE_CATEGORY = exports.MIME_EXTENSIONS = exports.STORAGE_BUCKET_ALIAS = exports.STORAGE_CATEGORY_DIR = void 0;
exports.pickExtension = pickExtension;
exports.buildScopedStorageKey = buildScopedStorageKey;
const path_1 = require("path");
const common_1 = require("@nestjs/common");
exports.STORAGE_CATEGORY_DIR = {
    avatars: 'avatars',
    chats: 'chats',
    'feed-ads': 'feed-ads',
    listings: 'listings',
    misc: 'misc',
    reports: 'reports',
    support: 'support',
    videos: 'videos',
};
exports.STORAGE_BUCKET_ALIAS = {
    avatars: 'avatars',
    chats: 'chat-images',
    'feed-ads': 'feed-ads',
    listings: 'listing-photos',
    misc: 'misc',
    reports: 'reports',
    support: 'support-images',
    videos: 'videos',
};
exports.MIME_EXTENSIONS = {
    'image/heic': '.heic',
    'image/heif': '.heif',
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/webp': '.webp',
    'video/mp4': '.mp4',
    'video/quicktime': '.mov',
    'video/webm': '.webm',
};
exports.STORAGE_ROUTE_CATEGORY = new Set([
    'avatars',
    'listings',
    'feed-ads',
    'support',
    'reports',
    'misc',
    'videos',
]);
function pickExtension(mimeType, originalName) {
    const fromMime = exports.MIME_EXTENSIONS[mimeType];
    if (fromMime) {
        return fromMime;
    }
    const originalExt = (0, path_1.extname)(originalName?.trim() ?? '').toLowerCase();
    if (Object.values(exports.MIME_EXTENSIONS).includes(originalExt)) {
        return originalExt;
    }
    throw new common_1.BadRequestException('Неподдерживаемый формат файла');
}
function buildScopedStorageKey(category, fileName, context) {
    const safeName = fileName.trim() || 'file.bin';
    switch (category) {
        case 'avatars':
            return `avatars/${context?.userId?.trim() || 'anonymous'}/${safeName}`;
        case 'listings':
            return `listings/${context?.listingId?.trim() || 'draft'}/${safeName}`;
        case 'chats':
            return `chats/${context?.chatId?.trim() || 'draft'}/${safeName}`;
        case 'feed-ads':
            return `misc/${context?.feedAdId?.trim() || 'feed-ads'}/${safeName}`;
        case 'support':
            return `support/${context?.ticketId?.trim() || context?.userId?.trim() || 'draft'}/${safeName}`;
        case 'reports':
            return `reports/${context?.reportId?.trim() || context?.userId?.trim() || 'draft'}/${safeName}`;
        case 'videos':
            return `videos/${context?.listingId?.trim() || context?.chatId?.trim() || context?.userId?.trim() || 'draft'}/${safeName}`;
        case 'misc':
            return `misc/${safeName}`;
    }
}
//# sourceMappingURL=storage.constants.js.map