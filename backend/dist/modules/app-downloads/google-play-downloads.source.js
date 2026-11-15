"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.GooglePlayDownloadsSource = void 0;
const common_1 = require("@nestjs/common");
const node_fs_1 = require("node:fs");
const env_1 = require("../../config/env");
const jwt_util_1 = require("./jwt.util");
let GooglePlayDownloadsSource = class GooglePlayDownloadsSource {
    constructor() {
        this.platform = 'android';
        this.metric = 'dailyUserInstalls';
        this.metricLabel = 'Установки пользователями';
        this.timeZone = 'America/Los_Angeles';
    }
    isConfigured() {
        return Boolean(env_1.env.GOOGLE_PLAY_SERVICE_ACCOUNT_PATH.trim() &&
            env_1.env.GOOGLE_PLAY_REPORT_BUCKET.trim() &&
            env_1.env.GOOGLE_PLAY_PACKAGE_NAME.trim());
    }
    async fetchDailyDownloads(sinceDate) {
        if (!this.isConfigured())
            return [];
        const account = JSON.parse((0, node_fs_1.readFileSync)(env_1.env.GOOGLE_PLAY_SERVICE_ACCOUNT_PATH, 'utf8'));
        if (!account.client_email || !account.private_key) {
            throw new Error('Google Play service account is invalid');
        }
        const token = await this.getAccessToken(account);
        const bucket = env_1.env.GOOGLE_PLAY_REPORT_BUCKET.trim().replace(/^gs:\/\//, '');
        const packageName = env_1.env.GOOGLE_PLAY_PACKAGE_NAME.trim();
        const prefix = `stats/installs/installs_${packageName}_`;
        const objects = await this.listObjects(bucket, prefix, token);
        const escapedPackage = packageName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const aggregateName = new RegExp(`^stats/installs/installs_${escapedPackage}_\\d{6}(?:_overview)?\\.csv$`);
        const totals = new Map();
        const sinceMonth = sinceDate?.slice(0, 7).replace('-', '') ?? '';
        for (const name of objects.filter((value) => {
            if (!aggregateName.test(value))
                return false;
            const month = value.match(/_(\d{6})(?:_overview)?\.csv$/)?.[1] ?? '';
            return !sinceMonth || month >= sinceMonth;
        })) {
            const response = await fetch(`https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket)}/o/${encodeURIComponent(name)}?alt=media`, { headers: { Authorization: `Bearer ${token}` } });
            if (!response.ok) {
                throw new Error(`Google Play report returned ${response.status}`);
            }
            for (const point of this.parseReport(Buffer.from(await response.arrayBuffer()))) {
                totals.set(point.date, point.downloads);
            }
        }
        return [...totals]
            .map(([date, downloads]) => ({ date, downloads }))
            .sort((left, right) => left.date.localeCompare(right.date));
    }
    parseReport(bytes) {
        const content = this.decodeCsv(bytes);
        const rows = this.parseCsv(content);
        if (rows.length < 2)
            return [];
        const headers = rows[0].map((value) => value.replace(/^\uFEFF/, '').trim());
        const dateIndex = headers.indexOf('Date');
        const installsIndex = headers.indexOf('Daily User Installs');
        if (dateIndex < 0 || installsIndex < 0)
            return [];
        return rows.slice(1).flatMap((row) => {
            const date = row[dateIndex]?.trim();
            const downloads = Number.parseInt((row[installsIndex] ?? '').replace(/,/g, '').trim(), 10);
            return /^\d{4}-\d{2}-\d{2}$/.test(date) && Number.isFinite(downloads)
                ? [{ date, downloads }]
                : [];
        });
    }
    async getAccessToken(account) {
        const tokenUrl = account.token_uri || 'https://oauth2.googleapis.com/token';
        const now = Math.floor(Date.now() / 1000);
        const assertion = (0, jwt_util_1.createJwt)({
            algorithm: 'RSA-SHA256',
            header: { alg: 'RS256', typ: 'JWT' },
            payload: {
                iss: account.client_email,
                scope: 'https://www.googleapis.com/auth/devstorage.read_only',
                aud: tokenUrl,
                iat: now,
                exp: now + 60 * 60,
            },
            privateKey: account.private_key,
        });
        const response = await fetch(tokenUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({
                grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                assertion,
            }),
        });
        if (!response.ok) {
            throw new Error(`Google OAuth returned ${response.status}`);
        }
        const payload = (await response.json());
        if (!payload.access_token)
            throw new Error('Google OAuth token is missing');
        return payload.access_token;
    }
    async listObjects(bucket, prefix, token) {
        const names = [];
        let pageToken = '';
        do {
            const params = new URLSearchParams({ prefix });
            if (pageToken)
                params.set('pageToken', pageToken);
            const response = await fetch(`https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket)}/o?${params}`, { headers: { Authorization: `Bearer ${token}` } });
            if (!response.ok) {
                throw new Error(`Google Cloud Storage returned ${response.status}`);
            }
            const payload = (await response.json());
            names.push(...(payload.items ?? [])
                .map((item) => item.name ?? '')
                .filter((name) => name.length > 0));
            pageToken = payload.nextPageToken ?? '';
        } while (pageToken);
        return names;
    }
    decodeCsv(bytes) {
        if (bytes[0] === 0xff && bytes[1] === 0xfe) {
            return bytes.subarray(2).toString('utf16le');
        }
        if (bytes[0] === 0xfe && bytes[1] === 0xff) {
            const swapped = Buffer.from(bytes.subarray(2));
            swapped.swap16();
            return swapped.toString('utf16le');
        }
        return bytes.toString('utf8');
    }
    parseCsv(content) {
        const rows = [];
        let row = [];
        let value = '';
        let quoted = false;
        for (let index = 0; index < content.length; index += 1) {
            const char = content[index];
            if (quoted) {
                if (char === '"' && content[index + 1] === '"') {
                    value += '"';
                    index += 1;
                }
                else if (char === '"') {
                    quoted = false;
                }
                else {
                    value += char;
                }
            }
            else if (char === '"') {
                quoted = true;
            }
            else if (char === ',') {
                row.push(value);
                value = '';
            }
            else if (char === '\n') {
                row.push(value.replace(/\r$/, ''));
                if (row.some((cell) => cell.length > 0))
                    rows.push(row);
                row = [];
                value = '';
            }
            else {
                value += char;
            }
        }
        row.push(value.replace(/\r$/, ''));
        if (row.some((cell) => cell.length > 0))
            rows.push(row);
        return rows;
    }
};
exports.GooglePlayDownloadsSource = GooglePlayDownloadsSource;
exports.GooglePlayDownloadsSource = GooglePlayDownloadsSource = __decorate([
    (0, common_1.Injectable)()
], GooglePlayDownloadsSource);
//# sourceMappingURL=google-play-downloads.source.js.map