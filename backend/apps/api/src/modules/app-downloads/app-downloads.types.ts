export const APP_DOWNLOAD_PLATFORMS = ['ios', 'android'] as const;

export type AppDownloadPlatform = (typeof APP_DOWNLOAD_PLATFORMS)[number];

export type AppDownloadPoint = {
  date: string;
  downloads: number;
};

export interface AppDownloadSource {
  readonly platform: AppDownloadPlatform;
  readonly metric: string;
  readonly metricLabel: string;
  readonly timeZone: string;
  isConfigured(): boolean;
  fetchDailyDownloads(sinceDate?: string): Promise<AppDownloadPoint[]>;
}

export type AppDownloadPlatformSnapshot = {
  platform: AppDownloadPlatform;
  configured: boolean;
  status: 'ready' | 'noData' | 'notConfigured';
  metric: string;
  metricLabel: string;
  timeZone: string;
  today: number | null;
  yesterday: number | null;
  last7Days: number | null;
  last30Days: number | null;
  allTime: number | null;
  latestReportDate: string | null;
  lastUpdatedAt: string | null;
};

export type AppDownloadsSnapshot = {
  ios: AppDownloadPlatformSnapshot;
  android: AppDownloadPlatformSnapshot;
};
