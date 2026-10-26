import { Injectable, Logger } from '@nestjs/common';
import * as crypto from 'crypto';
import * as fs from 'fs';

import { env } from '../../config/env';

type FcmPush = {
  token: string;
  title: string;
  body: string;
  notification: Record<string, unknown>;
  recipientId: string;
  actionType: string;
};

export type FcmSendResult = {
  sent: boolean;
  status: number;
  reason?: string;
  skipped?: boolean;
};

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

@Injectable()
export class FcmService {
  private readonly logger = new Logger(FcmService.name);
  private accountCache: ServiceAccount | null = null;
  private accessTokenCache: { value: string; expiresAt: number } | null = null;
  private configurationWarningLogged = false;

  async send(push: FcmPush): Promise<FcmSendResult> {
    const token = push.token.trim();
    if (!token) return { sent: false, status: 0, reason: 'missing_token' };
    try {
      const account = this.serviceAccount();
      const accessToken = await this.accessToken(account);
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`,
        {
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
        },
      );
      if (response.ok) return { sent: true, status: response.status };
      const responseBody = await response.text();
      let reason = `fcm_http_${response.status}`;
      try {
        const decoded = JSON.parse(responseBody) as {
          error?: { status?: string; details?: Array<{ errorCode?: string }> };
        };
        reason =
          decoded.error?.details?.find((item) => item.errorCode)?.errorCode ??
          decoded.error?.status ??
          reason;
      } catch {
        // Never log the provider response because it can contain identifiers.
      }
      this.logger.warn(`FCM rejected push request. status=${response.status} reason=${reason}`);
      return { sent: false, status: response.status, reason };
    } catch (error) {
      if (!this.configurationWarningLogged) {
        this.logger.warn(
          `FCM push skipped. error=${error instanceof Error ? error.name : 'unknown'}`,
        );
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

  private serviceAccount() {
    if (this.accountCache) return this.accountCache;
    const path = env.FCM_SERVICE_ACCOUNT_PATH.trim();
    if (!path) throw new Error('FCM service account path is missing');
    const parsed = JSON.parse(fs.readFileSync(path, 'utf8')) as Partial<ServiceAccount>;
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
      throw new Error('FCM service account is incomplete');
    }
    this.accountCache = parsed as ServiceAccount;
    return this.accountCache;
  }

  private async accessToken(account: ServiceAccount) {
    const now = Math.floor(Date.now() / 1000);
    if (this.accessTokenCache && this.accessTokenCache.expiresAt > now + 60) {
      return this.accessTokenCache.value;
    }
    const header = this.base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claims = this.base64Url(
      JSON.stringify({
        iss: account.client_email,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: account.token_uri ?? 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600,
      }),
    );
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
    if (!response.ok) throw new Error(`FCM OAuth failed with ${response.status}`);
    const payload = (await response.json()) as { access_token?: string; expires_in?: number };
    if (!payload.access_token) throw new Error('FCM OAuth token is missing');
    this.accessTokenCache = {
      value: payload.access_token,
      expiresAt: now + Math.max(60, Number(payload.expires_in ?? 3600)),
    };
    return payload.access_token;
  }

  private base64Url(value: string | Buffer) {
    return Buffer.from(value)
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/g, '');
  }
}
