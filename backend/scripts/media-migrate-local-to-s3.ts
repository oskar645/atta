import 'dotenv/config';

import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { PrismaClient } from '@prisma/client';
import { randomUUID } from 'crypto';
import { readFile } from 'fs/promises';
import { basename, extname, join } from 'path';

import { env } from '../apps/api/src/config/env';

const prisma = new PrismaClient();
const dryRun = process.argv.includes('--dry-run');
const contentPrefix = '__atta_support_payload__:';

const s3 = new S3Client({
  credentials: {
    accessKeyId: env.S3_ACCESS_KEY_ID || env.S3_ACCESS_KEY,
    secretAccessKey: env.S3_SECRET_ACCESS_KEY || env.S3_SECRET_KEY,
  },
  endpoint: env.S3_ENDPOINT,
  forcePathStyle: env.S3_FORCE_PATH_STYLE ?? true,
  region: env.S3_REGION,
});

function localUrlPath(category: string, urlOrKey: string) {
  const key = basename(urlOrKey);
  return join(env.LOCAL_UPLOADS_DIR, category, key);
}

function buildS3Url(key: string) {
  const base =
    env.S3_PUBLIC_BASE_URL.trim() ||
    `${env.S3_ENDPOINT.replace(/\/+$/, '')}/${env.S3_BUCKET}`;
  return `${base.replace(/\/+$/, '')}/${key}`;
}

async function uploadLocalFile(params: {
  bucket: string;
  contentType: string;
  key: string;
  localPath: string;
}) {
  const buffer = await readFile(params.localPath);
  if (dryRun) {
    return;
  }
  await s3.send(
    new PutObjectCommand({
      Body: buffer,
      Bucket: params.bucket,
      ContentType: params.contentType,
      Key: params.key,
    }),
  );
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
    const extension = extname(user.avatarUrl || user.photoUrl || '') || '.jpg';
    const key = `avatars/${user.id}/${randomUUID()}${extension}`;
    await uploadLocalFile({
      bucket: env.S3_BUCKET_AVATARS || env.S3_BUCKET,
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
    const extension = extname(photo.publicUrl || photo.storageKey || '') || '.jpg';
    const key = `listings/${photo.listingId}/${randomUUID()}${extension}`;
    await uploadLocalFile({
      bucket: env.S3_BUCKET_LISTING_PHOTOS || env.S3_BUCKET,
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
          storageBucket: env.S3_BUCKET_LISTING_PHOTOS || env.S3_BUCKET,
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
    const extension = extname(message.imageKey || message.imageUrl || '') || '.jpg';
    const key = `chats/${message.chatId}/${randomUUID()}${extension}`;
    await uploadLocalFile({
      bucket: env.S3_BUCKET_CHAT_IMAGES || env.S3_BUCKET,
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
          imageBucket: env.S3_BUCKET_CHAT_IMAGES || env.S3_BUCKET,
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
    const extension = extname(item.imageKey || item.imageUrl || '') || '.jpg';
    const key = `misc/${item.id}/${randomUUID()}${extension}`;
    await uploadLocalFile({
      bucket: env.S3_BUCKET_FEED_ADS || env.S3_BUCKET,
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
          imageBucket: env.S3_BUCKET_FEED_ADS || env.S3_BUCKET,
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
    const payload = JSON.parse(message.text.slice(contentPrefix.length)) as {
      image_url?: string;
      text?: string;
    };
    const localUrl = payload.image_url?.trim() ?? '';
    if (!localUrl) {
      continue;
    }
    const extension = extname(localUrl) || '.jpg';
    const key = `support/${message.ticketId}/${randomUUID()}${extension}`;
    await uploadLocalFile({
      bucket: env.S3_BUCKET_SUPPORT || env.S3_BUCKET,
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
  if (!env.S3_BUCKET || !env.S3_ENDPOINT || !env.S3_REGION) {
    throw new Error('S3 не настроен. Проверьте переменные окружения.');
  }

  console.log(
    `[media:migrate-local-to-s3] mode=${dryRun ? 'dry-run' : 'apply'} bucket=${env.S3_BUCKET}`,
  );

  await migrateUsers();
  await migrateListingPhotos();
  await migrateChatImages();
  await migrateFeedAds();
  await migrateSupportImages();
}

main()
  .catch((error) => {
    console.error(
      '[media:migrate-local-to-s3] failed:',
      error instanceof Error ? error.message : error,
    );
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
