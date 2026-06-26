"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
require("dotenv/config");
const client_s3_1 = require("@aws-sdk/client-s3");
const client_1 = require("@prisma/client");
const crypto_1 = require("crypto");
const promises_1 = require("fs/promises");
const path_1 = require("path");
const env_1 = require("../apps/api/src/config/env");
const prisma = new client_1.PrismaClient();
const dryRun = process.argv.includes('--dry-run');
const contentPrefix = '__atta_support_payload__:';
const s3 = new client_s3_1.S3Client({
    credentials: {
        accessKeyId: env_1.env.S3_ACCESS_KEY_ID || env_1.env.S3_ACCESS_KEY,
        secretAccessKey: env_1.env.S3_SECRET_ACCESS_KEY || env_1.env.S3_SECRET_KEY,
    },
    endpoint: env_1.env.S3_ENDPOINT,
    forcePathStyle: env_1.env.S3_FORCE_PATH_STYLE ?? true,
    region: env_1.env.S3_REGION,
});
function localUrlPath(category, urlOrKey) {
    const key = (0, path_1.basename)(urlOrKey);
    return (0, path_1.join)(env_1.env.LOCAL_UPLOADS_DIR, category, key);
}
function buildS3Url(key) {
    const base = env_1.env.S3_PUBLIC_BASE_URL.trim() ||
        `${env_1.env.S3_ENDPOINT.replace(/\/+$/, '')}/${env_1.env.S3_BUCKET}`;
    return `${base.replace(/\/+$/, '')}/${key}`;
}
async function uploadLocalFile(params) {
    const buffer = await (0, promises_1.readFile)(params.localPath);
    if (dryRun) {
        return;
    }
    await s3.send(new client_s3_1.PutObjectCommand({
        Body: buffer,
        Bucket: params.bucket,
        ContentType: params.contentType,
        Key: params.key,
    }));
}
async function migrateUsers() {
    const users = await prisma.user.findMany({
        where: {
            avatarUrl: {
                contains: '/uploads/avatars/',
            },
        },
        select: {
            id: true,
            avatarUrl: true,
            photoUrl: true,
        },
    });
    for (const user of users) {
        const extension = (0, path_1.extname)(user.avatarUrl || user.photoUrl || '') || '.jpg';
        const key = `avatars/${user.id}/${(0, crypto_1.randomUUID)()}${extension}`;
        await uploadLocalFile({
            bucket: env_1.env.S3_BUCKET_AVATARS || env_1.env.S3_BUCKET,
            contentType: extension === '.png' ? 'image/png' : 'image/jpeg',
            key,
            localPath: localUrlPath('avatars', user.avatarUrl || user.photoUrl || ''),
        });
        const nextUrl = buildS3Url(key);
        console.log(`[users] ${dryRun ? 'dry-run' : 'migrated'} ${user.id} -> ${key}`);
        if (!dryRun) {
            await prisma.user.update({
                where: { id: user.id },
                data: {
                    avatarUrl: nextUrl,
                    photoUrl: nextUrl,
                },
            });
        }
    }
}
async function migrateListingPhotos() {
    const photos = await prisma.listingPhoto.findMany({
        where: {
            OR: [
                { storageBucket: 'local' },
                { publicUrl: { contains: '/uploads/listings/' } },
            ],
        },
        select: {
            id: true,
            listingId: true,
            publicUrl: true,
            storageKey: true,
        },
    });
    for (const photo of photos) {
        const extension = (0, path_1.extname)(photo.publicUrl || photo.storageKey || '') || '.jpg';
        const key = `listings/${photo.listingId}/${(0, crypto_1.randomUUID)()}${extension}`;
        await uploadLocalFile({
            bucket: env_1.env.S3_BUCKET_LISTING_PHOTOS || env_1.env.S3_BUCKET,
            contentType: extension === '.png' ? 'image/png' : 'image/jpeg',
            key,
            localPath: localUrlPath('listings', photo.storageKey || photo.publicUrl || ''),
        });
        const nextUrl = buildS3Url(key);
        console.log(`[listing_photos] ${dryRun ? 'dry-run' : 'migrated'} ${photo.id} -> ${key}`);
        if (!dryRun) {
            await prisma.listingPhoto.update({
                where: { id: photo.id },
                data: {
                    publicUrl: nextUrl,
                    storageBucket: env_1.env.S3_BUCKET_LISTING_PHOTOS || env_1.env.S3_BUCKET,
                    storageKey: key,
                },
            });
        }
    }
}
async function migrateChatImages() {
    const messages = await prisma.chatMessage.findMany({
        where: {
            imageKey: { not: null },
            OR: [
                { imageBucket: 'local' },
                { imageUrl: { contains: '/uploads/chats/' } },
            ],
        },
        select: {
            id: true,
            chatId: true,
            imageKey: true,
            imageUrl: true,
        },
    });
    for (const message of messages) {
        const extension = (0, path_1.extname)(message.imageKey || message.imageUrl || '') || '.jpg';
        const key = `chats/${message.chatId}/${(0, crypto_1.randomUUID)()}${extension}`;
        await uploadLocalFile({
            bucket: env_1.env.S3_BUCKET_CHAT_IMAGES || env_1.env.S3_BUCKET,
            contentType: extension === '.png' ? 'image/png' : 'image/jpeg',
            key,
            localPath: localUrlPath('chats', message.imageKey || message.imageUrl || ''),
        });
        const nextUrl = buildS3Url(key);
        console.log(`[chat_images] ${dryRun ? 'dry-run' : 'migrated'} ${message.id} -> ${key}`);
        if (!dryRun) {
            await prisma.chatMessage.update({
                where: { id: message.id },
                data: {
                    imageBucket: env_1.env.S3_BUCKET_CHAT_IMAGES || env_1.env.S3_BUCKET,
                    imageKey: key,
                    imageUrl: nextUrl,
                },
            });
        }
    }
}
async function migrateFeedAds() {
    const items = await prisma.feedAd.findMany({
        where: {
            imageKey: { not: null },
            OR: [
                { imageBucket: 'local' },
                { imageUrl: { contains: '/uploads/feed-ads/' } },
            ],
        },
        select: {
            id: true,
            imageKey: true,
            imageUrl: true,
        },
    });
    for (const item of items) {
        const extension = (0, path_1.extname)(item.imageKey || item.imageUrl || '') || '.jpg';
        const key = `misc/${item.id}/${(0, crypto_1.randomUUID)()}${extension}`;
        await uploadLocalFile({
            bucket: env_1.env.S3_BUCKET_FEED_ADS || env_1.env.S3_BUCKET,
            contentType: extension === '.png' ? 'image/png' : 'image/jpeg',
            key,
            localPath: localUrlPath('feed-ads', item.imageKey || item.imageUrl || ''),
        });
        const nextUrl = buildS3Url(key);
        console.log(`[feed_ads] ${dryRun ? 'dry-run' : 'migrated'} ${item.id} -> ${key}`);
        if (!dryRun) {
            await prisma.feedAd.update({
                where: { id: item.id },
                data: {
                    imageBucket: env_1.env.S3_BUCKET_FEED_ADS || env_1.env.S3_BUCKET,
                    imageKey: key,
                    imageUrl: nextUrl,
                },
            });
        }
    }
}
async function migrateSupportImages() {
    const messages = await prisma.supportMessage.findMany({
        where: {
            text: {
                contains: '/uploads/support/',
            },
        },
        select: {
            id: true,
            ticketId: true,
            text: true,
        },
    });
    for (const message of messages) {
        if (!message.text.startsWith(contentPrefix)) {
            continue;
        }
        const payload = JSON.parse(message.text.slice(contentPrefix.length));
        const localUrl = payload.image_url?.trim() ?? '';
        if (!localUrl) {
            continue;
        }
        const extension = (0, path_1.extname)(localUrl) || '.jpg';
        const key = `support/${message.ticketId}/${(0, crypto_1.randomUUID)()}${extension}`;
        await uploadLocalFile({
            bucket: env_1.env.S3_BUCKET_SUPPORT || env_1.env.S3_BUCKET,
            contentType: extension === '.png' ? 'image/png' : 'image/jpeg',
            key,
            localPath: localUrlPath('support', localUrl),
        });
        const nextUrl = buildS3Url(key);
        console.log(`[support] ${dryRun ? 'dry-run' : 'migrated'} ${message.id} -> ${key}`);
        if (!dryRun) {
            await prisma.supportMessage.update({
                where: { id: message.id },
                data: {
                    text: `${contentPrefix}${JSON.stringify({
                        ...payload,
                        image_url: nextUrl,
                    })}`,
                },
            });
        }
    }
}
async function main() {
    if (!env_1.env.S3_BUCKET || !env_1.env.S3_ENDPOINT || !env_1.env.S3_REGION) {
        throw new Error('S3 не настроен. Проверьте переменные окружения.');
    }
    console.log(`[media:migrate-local-to-s3] mode=${dryRun ? 'dry-run' : 'apply'} bucket=${env_1.env.S3_BUCKET}`);
    await migrateUsers();
    await migrateListingPhotos();
    await migrateChatImages();
    await migrateFeedAds();
    await migrateSupportImages();
}
main()
    .catch((error) => {
    console.error('[media:migrate-local-to-s3] failed:', error instanceof Error ? error.message : error);
    process.exitCode = 1;
})
    .finally(async () => {
    await prisma.$disconnect();
});
//# sourceMappingURL=media-migrate-local-to-s3.js.map