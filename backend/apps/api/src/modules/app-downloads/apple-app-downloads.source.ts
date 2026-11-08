import { Injectable } from '@nestjs/common';
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';

import { env } from '../../config/env';
import { AppDownloadPoint, AppDownloadSource } from './app-downloads.types';
import { createJwt } from './jwt.util';

type JsonApiResource = {
  id: string;
  attributes?: Record<string, unknown>;
};

@Injectable()
export class AppleAppDownloadsSource implements AppDownloadSource {
  readonly platform = 'ios' as const;
  readonly metric = 'firstTimeDownload';
  readonly metricLabel = 'Первые загрузки';
  readonly timeZone = 'UTC';

  isConfigured() {
    return Boolean(
      env.APPLE_APP_STORE_CONNECT_ISSUER_ID.trim() &&
        env.APPLE_APP_STORE_CONNECT_KEY_ID.trim() &&
        env.APPLE_APP_STORE_CONNECT_PRIVATE_KEY_PATH.trim() &&
        env.APPLE_APP_STORE_CONNECT_REPORT_REQUEST_ID.trim(),
    );
  }

  async fetchDailyDownloads(_sinceDate?: string): Promise<AppDownloadPoint[]> {
    if (!this.isConfigured()) return [];

    const token = this.createToken();
    const requestId = encodeURIComponent(
      env.APPLE_APP_STORE_CONNECT_REPORT_REQUEST_ID.trim(),
    );
    const reports = await this.getAll(
      `https://api.appstoreconnect.apple.com/v1/analyticsReportRequests/${requestId}/reports?filter[name]=${encodeURIComponent(
        'App Store Downloads Standard',
      )}&limit=200`,
      token,
    );
    const report = reports.find(
      (item) => item.attributes?.name === 'App Store Downloads Standard',
    );
    if (!report) return [];

    const instances = await this.getAll(
      `https://api.appstoreconnect.apple.com/v1/analyticsReports/${encodeURIComponent(
        report.id,
      )}/instances?filter[granularity]=DAILY&limit=200`,
      token,
    );
    instances.sort((left, right) =>
      String(left.attributes?.processingDate ?? '').localeCompare(
        String(right.attributes?.processingDate ?? ''),
      ),
    );

    // A later processing instance replaces an earlier value for a date. This
    // accepts official corrections without adding the same report twice.
    const latestByDate = new Map<string, number>();
    for (const instance of instances) {
      const segments = await this.getAll(
        `https://api.appstoreconnect.apple.com/v1/analyticsReportInstances/${encodeURIComponent(
          instance.id,
        )}/segments?limit=200`,
        token,
      );
      const instanceTotals = new Map<string, number>();
      for (const segment of segments) {
        const url = String(segment.attributes?.url ?? '');
        if (!url) continue;
        const response = await fetch(url);
        if (!response.ok) {
          throw new Error(`Apple analytics segment returned ${response.status}`);
        }
        const bytes = Buffer.from(await response.arrayBuffer());
        const content =
          bytes[0] === 0x1f && bytes[1] === 0x8b
            ? gunzipSync(bytes).toString('utf8')
            : bytes.toString('utf8');
        for (const point of this.parseReport(content)) {
          instanceTotals.set(
            point.date,
            (instanceTotals.get(point.date) ?? 0) + point.downloads,
          );
        }
      }
      for (const [date, downloads] of instanceTotals) {
        latestByDate.set(date, downloads);
      }
    }

    return [...latestByDate]
      .map(([date, downloads]) => ({ date, downloads }))
      .sort((left, right) => left.date.localeCompare(right.date));
  }

  parseReport(content: string): AppDownloadPoint[] {
    const lines = content.split(/\r?\n/).filter((line) => line.length > 0);
    if (lines.length < 2) return [];
    const headers = lines[0].replace(/^\uFEFF/, '').split('\t');
    const dateIndex = headers.indexOf('Date');
    const typeIndex = headers.indexOf('Download Type');
    const countIndex = headers.indexOf('Counts');
    if (dateIndex < 0 || typeIndex < 0 || countIndex < 0) return [];

    const points: AppDownloadPoint[] = [];
    for (const line of lines.slice(1)) {
      const columns = line.split('\t');
      if (columns[typeIndex]?.trim().toLowerCase() !== 'first-time download') {
        continue;
      }
      const date = columns[dateIndex]?.trim();
      const downloads = Number.parseInt(columns[countIndex]?.trim() ?? '', 10);
      if (/^\d{4}-\d{2}-\d{2}$/.test(date) && Number.isFinite(downloads)) {
        points.push({ date, downloads });
      }
    }
    return points;
  }

  private createToken() {
    const now = Math.floor(Date.now() / 1000);
    const privateKey = readFileSync(
      env.APPLE_APP_STORE_CONNECT_PRIVATE_KEY_PATH,
      'utf8',
    );
    return createJwt({
      algorithm: 'SHA256',
      header: {
        alg: 'ES256',
        kid: env.APPLE_APP_STORE_CONNECT_KEY_ID,
        typ: 'JWT',
      },
      payload: {
        iss: env.APPLE_APP_STORE_CONNECT_ISSUER_ID,
        iat: now,
        exp: now + 15 * 60,
        aud: 'appstoreconnect-v1',
      },
      privateKey,
    });
  }

  private async getAll(initialUrl: string, token: string) {
    const resources: JsonApiResource[] = [];
    let url: string | null = initialUrl;
    while (url) {
      const response = await fetch(url, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!response.ok) {
        throw new Error(`App Store Connect returned ${response.status}`);
      }
      const payload = (await response.json()) as {
        data?: JsonApiResource[];
        links?: { next?: string | null };
      };
      resources.push(...(payload.data ?? []));
      url = payload.links?.next ?? null;
    }
    return resources;
  }
}
