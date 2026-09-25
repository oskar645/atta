"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var FcmService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.FcmService = void 0;
const common_1 = require("@nestjs/common");
const app_1 = require("firebase-admin/app");
const messaging_1 = require("firebase-admin/messaging");
const env_1 = require("../../config/env");
let FcmService = FcmService_1 = class FcmService {
    constructor() {
        this.logger = new common_1.Logger(FcmService_1.name);
        this.configurationWarningLogged = false;
    }
    async send(push) {
        const token = push.token.trim();
        if (!token)
            return { sent: false, reason: 'missing_token' };
        const app = this.firebaseApp();
        if (!app)
            return { sent: false, reason: 'fcm_not_configured' };
        try {
            await (0, messaging_1.getMessaging)(app).send({
                token,
                notification: { title: push.title, body: push.body },
                data: push.data,
                android: {
                    priority: 'high',
                    notification: {
                        channelId: 'atta_notifications',
                        sound: 'default',
                        notificationCount: Math.max(0, Math.trunc(push.notificationCount)),
                    },
                },
            });
            return { sent: true };
        }
        catch (error) {
            const code = this.errorCode(error);
            const staleToken = code === 'messaging/registration-token-not-registered' ||
                code === 'messaging/invalid-registration-token' ||
                code === 'messaging/invalid-argument';
            this.logger.warn(`FCM send failed. code=${code || 'unknown'}`);
            return { sent: false, reason: code || 'send_failed', staleToken };
        }
    }
    firebaseApp() {
        const projectId = env_1.env.FIREBASE_PROJECT_ID.trim();
        const clientEmail = env_1.env.FIREBASE_CLIENT_EMAIL.trim();
        const privateKey = env_1.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n').trim();
        if (!projectId || !clientEmail || !privateKey) {
            if (!this.configurationWarningLogged) {
                this.logger.warn('Firebase credentials are missing; Android push notifications will be skipped.');
                this.configurationWarningLogged = true;
            }
            return null;
        }
        const existing = (0, app_1.getApps)()[0];
        return (existing ??
            (0, app_1.initializeApp)({
                credential: (0, app_1.cert)({ projectId, clientEmail, privateKey }),
                projectId,
            }));
    }
    errorCode(error) {
        if (!error || typeof error !== 'object')
            return '';
        const code = error.code;
        return typeof code === 'string' ? code : '';
    }
};
exports.FcmService = FcmService;
exports.FcmService = FcmService = FcmService_1 = __decorate([
    (0, common_1.Injectable)()
], FcmService);
//# sourceMappingURL=fcm.service.js.map