"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveListingVideo = exports.parseListingVideoUrl = void 0;
const common_1 = require("@nestjs/common");
const VIDEO_ERROR = 'Не удалось открыть видео. Проверьте ссылку.';
const VIDEO_PROVIDER_ERROR = 'Видеосервис временно не отвечает. Попробуйте ещё раз.';
const fetchText = async (url) => {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8_000);
    try {
        const response = await fetch(url, {
            signal: controller.signal,
            headers: {
                'user-agent': 'Mozilla/5.0 (compatible; ATTA/1.0)',
                referer: new URL(url).origin,
            },
        });
        if (!response.ok)
            throw new Error(`Video provider returned ${response.status}`);
        return await response.text();
    }
    finally {
        clearTimeout(timeout);
    }
};
const resolveImageRedirect = async (url) => {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8_000);
    try {
        const response = await fetch(url, {
            method: 'HEAD',
            redirect: 'follow',
            signal: controller.signal,
            headers: {
                'user-agent': 'Mozilla/5.0 (compatible; ATTA/1.0)',
                referer: 'https://rutube.ru/',
            },
        });
        if (!response.ok || !(response.headers.get('content-type') ?? '').startsWith('image/')) {
            throw new Error(`Video thumbnail returned ${response.status}`);
        }
        return safeHttpsUrl(response.url);
    }
    finally {
        clearTimeout(timeout);
    }
};
const decodeJsonString = (value) => {
    try {
        return JSON.parse(`"${value.replace(/"/g, '\\"')}"`);
    }
    catch {
        return value.replace(/\\u0026/g, '&').replace(/\\\//g, '/');
    }
};
const safeHttpsUrl = (value) => {
    if (typeof value !== 'string')
        return '';
    try {
        const parsed = new URL(value);
        return parsed.protocol === 'https:' ? parsed.toString() : '';
    }
    catch {
        return '';
    }
};
const parseListingVideoUrl = (rawUrl) => {
    const originalUrl = rawUrl.trim();
    let url;
    try {
        url = new URL(originalUrl);
    }
    catch {
        throw new common_1.BadRequestException(VIDEO_ERROR);
    }
    if (url.protocol !== 'https:')
        throw new common_1.BadRequestException(VIDEO_ERROR);
    const host = url.hostname.toLowerCase().replace(/^www\./, '');
    if (host === 'rutube.ru') {
        const match = url.pathname.match(/^\/(?:video|shorts)\/(?:private\/)?([a-f0-9]{32})(?:\/|$)/i);
        if (!match)
            throw new common_1.BadRequestException(VIDEO_ERROR);
        return { provider: 'rutube', originalUrl, videoId: match[1].toLowerCase() };
    }
    if (host === 'vk.com' || host === 'm.vk.com' || host === 'vk.ru' || host === 'vkvideo.ru') {
        const direct = `${url.pathname}${url.search}`.match(/(?:video|clip)(-?\d+)_(\d+)/i);
        const zValue = url.searchParams.get('z') ?? '';
        const nested = zValue.match(/(?:video|clip)(-?\d+)_(\d+)/i);
        const match = direct ?? nested;
        if (!match)
            throw new common_1.BadRequestException(VIDEO_ERROR);
        return { provider: 'vk', originalUrl, videoId: `${match[1]}_${match[2]}` };
    }
    throw new common_1.BadRequestException(VIDEO_ERROR);
};
exports.parseListingVideoUrl = parseListingVideoUrl;
const resolveListingVideo = async (rawUrl) => {
    const parsed = (0, exports.parseListingVideoUrl)(rawUrl);
    try {
        if (parsed.provider === 'rutube') {
            const playbackUrl = `https://rutube.ru/play/embed/${parsed.videoId}`;
            const thumbnailUrl = await resolveImageRedirect(`https://rutube.ru/api/video/${parsed.videoId}/thumbnail/?redirect=1`);
            if (!thumbnailUrl)
                throw new Error('Rutube thumbnail is missing');
            return { ...parsed, playbackUrl, thumbnailUrl };
        }
        const [ownerId, videoId] = parsed.videoId.split('_');
        const playbackUrl = `https://vk.com/video_ext.php?oid=${ownerId}&id=${videoId}`;
        const html = await fetchText(playbackUrl);
        const candidates = [
            /<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)/i,
            /<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i,
            /["'](?:short_video_cover|jpg|poster)["']\s*:\s*["']((?:\\.|[^"'])+)["']/i,
            /["']url["']\s*:\s*["']((?:\\.|[^"'])+\/getVideoPreview\?(?:\\.|[^"'])+fn=vid_w(?:\\.|[^"'])*)["']/i,
            /["']url["']\s*:\s*["']((?:\\.|[^"'])+\/getVideoPreview\?(?:\\.|[^"'])*)["']/i,
            /["']url["']\s*:\s*["']((?:\\.|[^"'])+size=800x450(?:\\.|[^"'])*)["']/i,
            /["']url["']\s*:\s*["']((?:\\.|[^"'])+type=video_thumb(?:\\.|[^"'])*)["']/i,
        ];
        let thumbnailUrl = '';
        for (const pattern of candidates) {
            const value = html.match(pattern)?.[1];
            if (value) {
                thumbnailUrl = safeHttpsUrl(decodeJsonString(value).replace(/&amp;/g, '&'));
                if (thumbnailUrl)
                    break;
            }
        }
        if (!thumbnailUrl)
            throw new Error('VK thumbnail is missing');
        return { ...parsed, playbackUrl, thumbnailUrl };
    }
    catch (error) {
        if (error instanceof common_1.BadRequestException)
            throw error;
        throw new common_1.ServiceUnavailableException(VIDEO_PROVIDER_ERROR);
    }
};
exports.resolveListingVideo = resolveListingVideo;
//# sourceMappingURL=listing-video.js.map