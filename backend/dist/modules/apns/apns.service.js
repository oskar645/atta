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
var ApnsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.ApnsService = void 0;
const common_1 = require("@nestjs/common");
const crypto = __importStar(require("crypto"));
const fs = __importStar(require("fs"));
const http2 = __importStar(require("http2"));
const env_1 = require("../../config/env");
let ApnsService = ApnsService_1 = class ApnsService {
    constructor() {
        this.logger = new common_1.Logger(ApnsService_1.name);
        this.cachedPrivateKey = null;
        this.cachedJwt = null;
        this.missingPrivateKeyWarningLogged = false;
        this.invalidConfigWarningLogged = false;
        this.rejectedResponseWarningLogged = false;
    }
    sendPlaceholder() {
        return {
            message: 'APNs placeholder created',
            bundleId: env_1.env.APNS_BUNDLE_ID,
            sandbox: env_1.env.APNS_USE_SANDBOX,
            sent: false,
        };
    }
    async send(push) {
        const deviceToken = push.token.trim();
        if (!deviceToken) {
            return { sent: false, status: 0, reason: 'missing_token' };
        }
        let client;
        let jwt;
        try {
            jwt = this.providerToken();
            client = http2.connect(this.apnsOrigin());
        }
        catch (error) {
            return this.skipForConfigurationError(error);
        }
        const body = JSON.stringify({
            aps: {
                alert: {
                    title: push.title,
                    body: push.body,
                },
                sound: 'default',
                ...(push.badge == null ? {} : { badge: push.badge }),
            },
            ...(push.payload ?? {}),
        });
        return await new Promise((resolve) => {
            let settled = false;
            const finish = (result) => {
                if (settled)
                    return;
                settled = true;
                client.close();
                resolve(result);
            };
            client.on('error', (error) => {
                this.logger.warn(`APNs client failed: ${this.safeError(error)}`);
                finish({ sent: false, status: 0, reason: 'client_failed' });
            });
            let request;
            try {
                request = client.request({
                    ':method': 'POST',
                    ':path': `/3/device/${deviceToken}`,
                    authorization: `bearer ${jwt}`,
                    'apns-topic': env_1.env.APNS_BUNDLE_ID,
                    'apns-push-type': 'alert',
                    'apns-priority': '10',
                    'content-type': 'application/json',
                });
            }
            catch (error) {
                this.logger.warn(`APNs request failed: ${this.safeError(error)}`);
                finish({ sent: false, status: 0, reason: 'request_failed' });
                return;
            }
            let status = 0;
            let responseBody = '';
            request.setEncoding('utf8');
            request.on('response', (headers) => {
                status = Number(headers[':status'] ?? 0);
            });
            request.on('data', (chunk) => {
                responseBody += chunk;
            });
            request.on('error', (error) => {
                this.logger.warn(`APNs send failed: ${this.safeError(error)}`);
                finish({ sent: false, status: 0, reason: 'send_failed' });
            });
            request.on('end', () => {
                if (status >= 200 && status < 300) {
                    finish({ sent: true, status });
                    return;
                }
                let reason = responseBody.trim();
                try {
                    const decoded = JSON.parse(responseBody);
                    reason = decoded.reason ?? reason;
                }
                catch {
                    // Keep raw APNs response when it is not JSON.
                }
                this.warnForRejectedResponse(status, reason);
                finish({ sent: false, status, reason });
            });
            try {
                request.end(body);
            }
            catch (error) {
                this.logger.warn(`APNs request end failed: ${this.safeError(error)}`);
                finish({ sent: false, status: 0, reason: 'request_failed' });
            }
        });
    }
    apnsOrigin() {
        return env_1.env.APNS_USE_SANDBOX
            ? 'https://api.sandbox.push.apple.com'
            : 'https://api.push.apple.com';
    }
    providerToken() {
        const now = Math.floor(Date.now() / 1000);
        if (this.cachedJwt && this.cachedJwt.expiresAt > now + 60) {
            return this.cachedJwt.token;
        }
        const header = this.base64Url(JSON.stringify({
            alg: 'ES256',
            kid: env_1.env.APNS_KEY_ID,
        }));
        const claims = this.base64Url(JSON.stringify({
            iss: env_1.env.APNS_TEAM_ID,
            iat: now,
        }));
        const signingInput = `${header}.${claims}`;
        const signature = crypto
            .createSign('SHA256')
            .update(signingInput)
            .sign(this.privateKey());
        const jwt = `${signingInput}.${this.base64Url(signature)}`;
        this.cachedJwt = {
            token: jwt,
            expiresAt: now + 50 * 60,
        };
        return jwt;
    }
    privateKey() {
        if (this.cachedPrivateKey) {
            return this.cachedPrivateKey;
        }
        this.cachedPrivateKey = fs.readFileSync(env_1.env.APNS_PRIVATE_KEY_PATH, 'utf8');
        return this.cachedPrivateKey;
    }
    skipForConfigurationError(error) {
        const nodeError = error;
        if (nodeError?.code === 'ENOENT') {
            if (!this.missingPrivateKeyWarningLogged) {
                this.logger.warn('APNs private key file is missing; push notifications will be skipped until APNs is configured.');
                this.missingPrivateKeyWarningLogged = true;
            }
            return {
                sent: false,
                status: 0,
                reason: 'apns_private_key_missing',
                skipped: true,
            };
        }
        if (!this.invalidConfigWarningLogged) {
            this.logger.warn(`APNs is not configured correctly; push notifications will be skipped. error=${this.safeError(error)}`);
            this.invalidConfigWarningLogged = true;
        }
        return {
            sent: false,
            status: 0,
            reason: 'apns_configuration_invalid',
            skipped: true,
        };
    }
    safeError(error) {
        if (error instanceof Error) {
            return error.name;
        }
        return 'unknown';
    }
    warnForRejectedResponse(status, reason) {
        if (this.rejectedResponseWarningLogged)
            return;
        this.logger.warn(`APNs rejected push request. status=${status} reason=${this.safeReason(reason)}`);
        this.rejectedResponseWarningLogged = true;
    }
    safeReason(reason) {
        const normalized = `${reason ?? ''}`.trim();
        if (!normalized)
            return 'unknown';
        return normalized.replace(/[^a-zA-Z0-9_.-]/g, '_').slice(0, 80);
    }
    base64Url(value) {
        return Buffer.from(value)
            .toString('base64')
            .replace(/\+/g, '-')
            .replace(/\//g, '_')
            .replace(/=+$/g, '');
    }
};
exports.ApnsService = ApnsService;
exports.ApnsService = ApnsService = ApnsService_1 = __decorate([
    (0, common_1.Injectable)()
], ApnsService);
//# sourceMappingURL=apns.service.js.map