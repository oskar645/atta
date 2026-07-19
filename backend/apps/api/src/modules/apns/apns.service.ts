import { Injectable, Logger } from '@nestjs/common';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as http2 from 'http2';

import { env } from '../../config/env';

type ApnsPush = {
  token: string;
  title: string;
  body: string;
  payload?: Record<string, unknown>;
  badge?: number;
};

@Injectable()
export class ApnsService {
  private readonly logger = new Logger(ApnsService.name);
  private cachedPrivateKey: string | null = null;
  private cachedJwt: { token: string; expiresAt: number } | null = null;

  sendPlaceholder() {
    return {
      message: 'APNs placeholder created',
      bundleId: env.APNS_BUNDLE_ID,
      sandbox: env.APNS_USE_SANDBOX,
      sent: false,
    };
  }

  async send(push: ApnsPush) {
    const deviceToken = push.token.trim();
    if (!deviceToken) {
      return { sent: false, status: 0, reason: 'missing_token' };
    }

    const client = http2.connect(this.apnsOrigin());
    const jwt = this.providerToken();
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

    return await new Promise<{ sent: boolean; status: number; reason?: string }>(
      (resolve) => {
        const request = client.request({
          ':method': 'POST',
          ':path': `/3/device/${deviceToken}`,
          authorization: `bearer ${jwt}`,
          'apns-topic': env.APNS_BUNDLE_ID,
          'apns-push-type': 'alert',
          'apns-priority': '10',
          'content-type': 'application/json',
        });
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
          this.logger.warn(`APNs send failed: ${error.message}`);
          client.close();
          resolve({ sent: false, status: 0, reason: error.message });
        });
        request.on('end', () => {
          client.close();
          if (status >= 200 && status < 300) {
            resolve({ sent: true, status });
            return;
          }
          let reason = responseBody.trim();
          try {
            const decoded = JSON.parse(responseBody) as { reason?: string };
            reason = decoded.reason ?? reason;
          } catch {
            // Keep raw APNs response when it is not JSON.
          }
          resolve({ sent: false, status, reason });
        });
        request.end(body);
      },
    );
  }

  private apnsOrigin() {
    return env.APNS_USE_SANDBOX
      ? 'https://api.sandbox.push.apple.com'
      : 'https://api.push.apple.com';
  }

  private providerToken() {
    const now = Math.floor(Date.now() / 1000);
    if (this.cachedJwt && this.cachedJwt.expiresAt > now + 60) {
      return this.cachedJwt.token;
    }

    const header = this.base64Url(
      JSON.stringify({
        alg: 'ES256',
        kid: env.APNS_KEY_ID,
      }),
    );
    const claims = this.base64Url(
      JSON.stringify({
        iss: env.APNS_TEAM_ID,
        iat: now,
      }),
    );
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

  private privateKey() {
    if (this.cachedPrivateKey) {
      return this.cachedPrivateKey;
    }
    this.cachedPrivateKey = fs.readFileSync(
      env.APNS_PRIVATE_KEY_PATH,
      'utf8',
    );
    return this.cachedPrivateKey;
  }

  private base64Url(value: string | Buffer) {
    return Buffer.from(value)
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/g, '');
  }
}
