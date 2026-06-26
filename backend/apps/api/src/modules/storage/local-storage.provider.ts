import { Injectable } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { promises as fs } from 'fs';
import { basename, join } from 'path';

import { env } from '../../config/env';
import {
  STORAGE_CATEGORY_DIR,
  pickExtension,
} from './storage.constants';
import {
  SaveUploadedFileParams,
  StorageCategory,
  StorageHealthResult,
  StorageProvider,
  StoredMediaFile,
} from './storage.types';

@Injectable()
export class LocalStorageProvider implements StorageProvider {
  getName() {
    return 'local' as const;
  }

  async ensureReady() {
    await Promise.all(
      Object.values(STORAGE_CATEGORY_DIR).map((dir) =>
        fs.mkdir(join(env.LOCAL_UPLOADS_DIR, dir), { recursive: true }),
      ),
    );
  }

  async getHealth(): Promise<StorageHealthResult> {
    try {
      await this.ensureReady();
      return { status: 'local_ok' };
    } catch {
      return {
        status: 'local_error',
        message: 'Локальное хранилище недоступно.',
      };
    }
  }

  async saveFile(params: SaveUploadedFileParams): Promise<StoredMediaFile> {
    await this.ensureReady();
    const mimeType = params.contentType.trim().toLowerCase();
    const extension = pickExtension(mimeType, params.originalName);
    const fileName = `${randomUUID()}${extension}`;
    const absolutePath = join(
      env.LOCAL_UPLOADS_DIR,
      STORAGE_CATEGORY_DIR[params.category],
      fileName,
    );
    await fs.writeFile(absolutePath, params.buffer);
    return {
      bucket: null,
      key: fileName,
      mimeType,
      provider: 'local',
      sizeBytes: params.buffer.byteLength,
      url: this.buildPublicUrl(params.category, fileName),
    };
  }

  buildPublicUrl(category: StorageCategory, key: string) {
    const base = env.MEDIA_PUBLIC_BASE_URL.replace(/\/+$/, '');
    return `${base}/${STORAGE_CATEGORY_DIR[category]}/${basename(key)}`;
  }

  async readFile(category: StorageCategory, key: string) {
    const filePath = join(
      env.LOCAL_UPLOADS_DIR,
      STORAGE_CATEGORY_DIR[category],
      basename(key),
    );
    return fs.readFile(filePath);
  }

  async deleteFile(category: StorageCategory, key: string) {
    const filePath = join(
      env.LOCAL_UPLOADS_DIR,
      STORAGE_CATEGORY_DIR[category],
      basename(key),
    );
    await fs.rm(filePath, { force: true });
  }
}
