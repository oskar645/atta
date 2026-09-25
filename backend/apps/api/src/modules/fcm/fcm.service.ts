import { Injectable, Logger } from '@nestjs/common';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

import { env } from '../../config/env';

export type FcmSendResult = {
  sent: boolean;
  reason?: string;
  staleToken?: boolean;
};

@Injectable()
export class FcmService {
  private readonly logger = new Logger(FcmService.name);
  private configurationWarningLogged = false;

  async send(push: {
    token: string;
    title: string;
    body: string;
    data: Record<string, string>;
    notificationCount: number;
  }): Promise<FcmSendResult> {
    const token = push.token.trim();
    if (!token) return { sent: false, reason: 'missing_token' };

    const app = this.firebaseApp();
    if (!app) return { sent: false, reason: 'fcm_not_configured' };

    try {
      await getMessaging(app).send({
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
    } catch (error) {
      const code = this.errorCode(error);
      const staleToken =
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token' ||
        code === 'messaging/invalid-argument';
      this.logger.warn(`FCM send failed. code=${code || 'unknown'}`);
      return { sent: false, reason: code || 'send_failed', staleToken };
    }
  }

  private firebaseApp() {
    const projectId = env.FIREBASE_PROJECT_ID.trim();
    const clientEmail = env.FIREBASE_CLIENT_EMAIL.trim();
    const privateKey = env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n').trim();
    if (!projectId || !clientEmail || !privateKey) {
      if (!this.configurationWarningLogged) {
        this.logger.warn(
          'Firebase credentials are missing; Android push notifications will be skipped.',
        );
        this.configurationWarningLogged = true;
      }
      return null;
    }
    const existing = getApps()[0];
    return (
      existing ??
      initializeApp({
        credential: cert({ projectId, clientEmail, privateKey }),
        projectId,
      })
    );
  }

  private errorCode(error: unknown) {
    if (!error || typeof error !== 'object') return '';
    const code = (error as { code?: unknown }).code;
    return typeof code === 'string' ? code : '';
  }
}
