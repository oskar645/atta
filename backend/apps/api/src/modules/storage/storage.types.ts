export type StorageCategory =
  | 'avatars'
  | 'listings'
  | 'chats'
  | 'feed-ads'
  | 'support'
  | 'reports'
  | 'misc'
  | 'videos';

export type StorageProviderName = 'local' | 's3';

export type StoredMediaFile = {
  bucket: string | null;
  key: string;
  mimeType: string;
  provider: StorageProviderName;
  sizeBytes: number;
  url: string;
};

export type StoragePathContext = {
  chatId?: string;
  feedAdId?: string;
  listingId?: string;
  reportId?: string;
  ticketId?: string;
  userId?: string;
};

export type SaveUploadedFileParams = {
  buffer: Buffer;
  category: StorageCategory;
  contentType: string;
  originalName?: string;
  context?: StoragePathContext;
};

export type StorageHealthResult = {
  message?: string;
  status: 'local_ok' | 'local_error' | 's3_ok' | 's3_error';
};

export type StorageProvider = {
  buildPublicUrl(category: StorageCategory, key: string): string;
  deleteFile(category: StorageCategory, key: string): Promise<void>;
  ensureReady(): Promise<void>;
  getHealth(): Promise<StorageHealthResult>;
  getName(): StorageProviderName;
  readFile(category: StorageCategory, key: string): Promise<Buffer>;
  saveFile(params: SaveUploadedFileParams): Promise<StoredMediaFile>;
};
