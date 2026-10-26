"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var FcmService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.FcmService = void 0;
const common_1 = require("@nestjs/common");
const crypto = __importStar(require("crypto"));
const fs = __importStar(require("fs"));
const env_1 = require("../../config/env");
let FcmService = FcmService_1 = class FcmService {
    constructor() {
        this.logger = new common_1.Logger(FcmService_1.name);
        this.accountCache = null;
        this.accessTokenCache = null;
        this.configurationWarningLogged = false;
    }
    async send(push) {
        const token = push.token.trim();
        if (!token)
            return { sent: false, status: 0, reason: 'missing_token' };
        try {
            const account = this.serviceAccount();
            const accessToken = await this.accessToken(account);
            const response = await fetch(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`, {
                method: 'POST',
                headers: {
                    authorization: `Bearer ${accessToken}`,
                    'content-type': 'application/json',
                },
                body: JSON.stringify({
                    message: {
                        token,
                        notification: { title: push.title, body: push.body },
                        data: {
                            notification: JSON.stringify(push.notification),
                            recipientId: push.recipientId,
                            actionType: push.actionType,
                            title: push.title,
                            body: push.body,
                        },
                        android: {
                            priority: 'HIGH',
                            notification: {
                                channel_id: 'atta_messages',
                                sound: 'default',
                            },
                        },
                    },
                }),
            });
            if (response.ok)
                return { sent: true, status: response.status };
            const responseBody = await response.text();
            let reason = `fcm_http_${response.status}`;
            try {
                const decoded = JSON.parse(responseBody);
                reason =
                    decoded.error?.details?.find((item) => item.errorCode)?.errorCode ??
                        decoded.error?.status ??
                        reason;
            }
            catch {
                // Never log the provider response because it can contain identifiers.
            }
            this.logger.warn(`FCM rejected push request. status=${response.status} reason=${reason}`);
            return { sent: false, status: response.status, reason };
        }
        catch (error) {
            if (!this.configurationWarningLogged) {
                this.logger.warn(`FCM push skipped. error=${error instanceof Error ? error.name : 'unknown'}`);
                this.configurationWarningLogged = true;
            }
            return {
                sent: false,
                status: 0,
                reason: 'fcm_configuration_invalid',
                skipped: true,
            };
        }
    }
    serviceAccount() {
        if (this.accountCache)
            return this.accountCache;
        const path = env_1.env.FCM_SERVICE_ACCOUNT_PATH.trim();
        if (!path)
            throw new Error('FCM service account path is missing');
        const parsed = JSON.parse(fs.readFileSync(path, 'utf8'));
        if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
            throw new Error('FCM service account is incomplete');
        }
        this.accountCache = parsed;
        return this.accountCache;
    }
    async accessToken(account) {
        const now = Math.floor(Date.now() / 1000);
        if (this.accessTokenCache && this.accessTokenCache.expiresAt > now + 60) {
            return this.accessTokenCache.value;
        }
        const header = this.base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
        const claims = this.base64Url(JSON.stringify({
            iss: account.client_email,
            scope: 'https://www.googleapis.com/auth/firebase.messaging',
            aud: account.token_uri ?? 'https://oauth2.googleapis.com/token',
            iat: now,
            exp: now + 3600,
        }));
        const signingInput = `${header}.${claims}`;
        const signature = crypto.createSign('RSA-SHA256').update(signingInput).sign(account.private_key);
        const assertion = `${signingInput}.${this.base64Url(signature)}`;
        const response = await fetch(account.token_uri ?? 'https://oauth2.googleapis.com/token', {
            method: 'POST',
            headers: { 'content-type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({
                grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                assertion,
            }),
        });
        if (!response.ok)
            throw new Error(`FCM OAuth failed with ${response.status}`);
        const payload = (await response.json());
        if (!payload.access_token)
            throw new Error('FCM OAuth token is missing');
        this.accessTokenCache = {
            value: payload.access_token,
            expiresAt: now + Math.max(60, Number(payload.expires_in ?? 3600)),
        };
        return payload.access_token;
    }
    base64Url(value) {
        return Buffer.from(value)
            .toString('base64')
            .replace(/\+/g, '-')
            .replace(/\//g, '_')
            .replace(/=+$/g, '');
    }
};
exports.FcmService = FcmService;
exports.FcmService = FcmService = FcmService_1 = __decorate([
    (0, common_1.Injectable)()
], FcmService);
//# sourceMappingURL=fcm.service.js.map