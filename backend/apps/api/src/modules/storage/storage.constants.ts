import { extname } from 'path';

import { BadRequestException } from '@nestjs/common';

import { StorageCategory, StoragePathContext } from './storage.types';

export const STORAGE_CATEGORY_DIR: Record<StorageCategory, string> = {
  avatars: 'avatars',
  chats: 'chats',
  'feed-ads': 'feed-ads',
  listings: 'listings',
  misc: 'misc',
  reports: 'reports',
  support: 'support',
  videos: 'videos',
};

export const STORAGE_BUCKET_ALIAS: Record<StorageCategory, string> = {
  avatars: 'avatars',
  chats: 'chat-images',
  'feed-ads': 'feed-ads',
  listings: 'listing-photos',
  misc: 'misc',
  reports: 'reports',
  support: 'support-images',
  videos: 'videos',
};

export const MIME_EXTENSIONS: Record<string, string> = {
  'image/heic': '.heic',
  'image/heif': '.heif',
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
  'video/mp4': '.mp4',
  'video/quicktime': '.mov',
  'video/webm': '.webm',
};

export const STORAGE_ROUTE_CATEGORY = new Set<StorageCategory>([
  'avatars',
  'listings',
  'feed-ads',
  'support',
  'reports',
  'misc',
  'videos',
]);

export function pickExtension(mimeType: string, originalName?: string) {
  const fromMime = MIME_EXTENSIONS[mimeType];
  if (fromMime) {
    return fromMime;
  }

  const originalExt = extname(originalName?.trim() ?? '').toLowerCase();
  if (Object.values(MIME_EXTENSIONS).includes(originalExt)) {
    return originalExt;
  }

  throw new BadRequestException('Неподдерживаемый формат файла');
}

export function buildScopedStorageKey(
  category: StorageCategory,
  fileName: string,
  context?: StoragePathContext,
) {
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
