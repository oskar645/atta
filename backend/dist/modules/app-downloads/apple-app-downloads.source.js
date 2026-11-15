"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AppleAppDownloadsSource = void 0;
const common_1 = require("@nestjs/common");
const node_fs_1 = require("node:fs");
const node_zlib_1 = require("node:zlib");
const env_1 = require("../../config/env");
const jwt_util_1 = require("./jwt.util");
let AppleAppDownloadsSource = class AppleAppDownloadsSource {
    constructor() {
        this.platform = 'ios';
        this.metric = 'firstTimeDownload';
        this.metricLabel = 'Первые загрузки';
        this.timeZone = 'UTC';
    }
    isConfigured() {
        return Boolean(env_1.env.APPLE_APP_STORE_CONNECT_ISSUER_ID.trim() &&
            env_1.env.APPLE_APP_STORE_CONNECT_KEY_ID.trim() &&
            env_1.env.APPLE_APP_STORE_CONNECT_PRIVATE_KEY_PATH.trim() &&
            env_1.env.APPLE_APP_STORE_CONNECT_REPORT_REQUEST_ID.trim());
    }
    async fetchDailyDownloads(_sinceDate) {
        if (!this.isConfigured())
            return [];
        const token = this.createToken();
        const requestId = encodeURIComponent(env_1.env.APPLE_APP_STORE_CONNECT_REPORT_REQUEST_ID.trim());
        const reports = await this.getAll(`https://api.appstoreconnect.apple.com/v1/analyticsReportRequests/${requestId}/reports?filter[name]=${encodeURIComponent('App Store Downloads Standard')}&limit=200`, token);
        const report = reports.find((item) => item.attributes?.name === 'App Store Downloads Standard');
        if (!report)
            return [];
        const instances = await this.getAll(`https://api.appstoreconnect.apple.com/v1/analyticsReports/${encodeURIComponent(report.id)}/instances?filter[granularity]=DAILY&limit=200`, token);
        instances.sort((left, right) => String(left.attributes?.processingDate ?? '').localeCompare(String(right.attributes?.processingDate ?? '')));
        // A later processing instance replaces an earlier value for a date. This
        // accepts official corrections without adding the same report twice.
        const latestByDate = new Map();
        for (const instance of instances) {
            const segments = await this.getAll(`https://api.appstoreconnect.apple.com/v1/analyticsReportInstances/${encodeURIComponent(instance.id)}/segments?limit=200`, token);
            const instanceTotals = new Map();
            for (const segment of segments) {
                const url = String(segment.attributes?.url ?? '');
                if (!url)
                    continue;
                const response = await fetch(url);
                if (!response.ok) {
                    throw new Error(`Apple analytics segment returned ${response.status}`);
                }
                const bytes = Buffer.from(await response.arrayBuffer());
                const content = bytes[0] === 0x1f && bytes[1] === 0x8b
                    ? (0, node_zlib_1.gunzipSync)(bytes).toString('utf8')
                    : bytes.toString('utf8');
                for (const point of this.parseReport(content)) {
                    instanceTotals.set(point.date, (instanceTotals.get(point.date) ?? 0) + point.downloads);
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
    parseReport(content) {
        const lines = content.split(/\r?\n/).filter((line) => line.length > 0);
        if (lines.length < 2)
            return [];
        const headers = lines[0].replace(/^\uFEFF/, '').split('\t');
        const dateIndex = headers.indexOf('Date');
        const typeIndex = headers.indexOf('Download Type');
        const countIndex = headers.indexOf('Counts');
        if (dateIndex < 0 || typeIndex < 0 || countIndex < 0)
            return [];
        const points = [];
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
    createToken() {
        const now = Math.floor(Date.now() / 1000);
        const privateKey = (0, node_fs_1.readFileSync)(env_1.env.APPLE_APP_STORE_CONNECT_PRIVATE_KEY_PATH, 'utf8');
        return (0, jwt_util_1.createJwt)({
            algorithm: 'SHA256',
            header: {
                alg: 'ES256',
                kid: env_1.env.APPLE_APP_STORE_CONNECT_KEY_ID,
                typ: 'JWT',
            },
            payload: {
                iss: env_1.env.APPLE_APP_STORE_CONNECT_ISSUER_ID,
                iat: now,
                exp: now + 15 * 60,
                aud: 'appstoreconnect-v1',
            },
            privateKey,
        });
    }
    async getAll(initialUrl, token) {
        const resources = [];
        let url = initialUrl;
        while (url) {
            const response = await fetch(url, {
                headers: { Authorization: `Bearer ${token}` },
            });
            if (!response.ok) {
                throw new Error(`App Store Connect returned ${response.status}`);
            }
            const payload = (await response.json());
            resources.push(...(payload.data ?? []));
            url = payload.links?.next ?? null;
        }
        return resources;
    }
};
exports.AppleAppDownloadsSource = AppleAppDownloadsSource;
exports.AppleAppDownloadsSource = AppleAppDownloadsSource = __decorate([
    (0, common_1.Injectable)()
], AppleAppDownloadsSource);
//# sourceMappingURL=apple-app-downloads.source.js.map