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

type ApnsSendResult = {
  sent: boolean;
  status: number;
  reason?: string;
  skipped?: boolean;
};

@Injectable()
export class ApnsService {
  private readonly logger = new Logger(ApnsService.name);
  private cachedPrivateKey: string | null = null;
  private cachedJwt: { token: string; expiresAt: number } | null = null;
  private missingPrivateKeyWarningLogged = false;
  private invalidConfigWarningLogged = false;
  private rejectedResponseWarningLogged = false;

  sendPlaceholder() {
    return {
      message: 'APNs placeholder created',
      bundleId: env.APNS_BUNDLE_ID,
      sandbox: env.APNS_USE_SANDBOX,
      sent: false,
    };
  }

  async send(push: ApnsPush): Promise<ApnsSendResult> {
    const deviceToken = push.token.trim();
    if (!deviceToken) {
      return { sent: false, status: 0, reason: 'missing_token' };
    }

    let client: http2.ClientHttp2Session;
    let jwt: string;
    try {
      jwt = this.providerToken();
      client = http2.connect(this.apnsOrigin());
    } catch (error) {
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

    return await new Promise<ApnsSendResult>(
      (resolve) => {
        let settled = false;
        const finish = (result: ApnsSendResult) => {
          if (settled) return;
          settled = true;
          client.close();
          resolve(result);
        };
        client.on('error', (error) => {
          this.logger.warn(`APNs client failed: ${this.safeError(error)}`);
          finish({ sent: false, status: 0, reason: 'client_failed' });
        });
        let request: http2.ClientHttp2Stream;
        try {
          request = client.request({
            ':method': 'POST',
            ':path': `/3/device/${deviceToken}`,
            authorization: `bearer ${jwt}`,
            'apns-topic': env.APNS_BUNDLE_ID,
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'content-type': 'application/json',
          });
        } catch (error) {
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
            const decoded = JSON.parse(responseBody) as { reason?: string };
            reason = decoded.reason ?? reason;
          } catch {
            // Keep raw APNs response when it is not JSON.
          }
          this.warnForRejectedResponse(status, reason);
          finish({ sent: false, status, reason });
        });
        try {
          request.end(body);
        } catch (error) {
          this.logger.warn(`APNs request end failed: ${this.safeError(error)}`);
          finish({ sent: false, status: 0, reason: 'request_failed' });
        }
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

  private skipForConfigurationError(error: unknown): ApnsSendResult {
    const nodeError = error as NodeJS.ErrnoException;
    if (nodeError?.code === 'ENOENT') {
      if (!this.missingPrivateKeyWarningLogged) {
        this.logger.warn(
          'APNs private key file is missing; push notifications will be skipped until APNs is configured.',
        );
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
      this.logger.warn(
        `APNs is not configured correctly; push notifications will be skipped. error=${this.safeError(error)}`,
      );
      this.invalidConfigWarningLogged = true;
    }
    return {
      sent: false,
      status: 0,
      reason: 'apns_configuration_invalid',
      skipped: true,
    };
  }

  private safeError(error: unknown) {
    if (error instanceof Error) {
      return error.name;
    }
    return 'unknown';
  }

  private warnForRejectedResponse(status: number, reason?: string) {
    if (this.rejectedResponseWarningLogged) return;
    this.logger.warn(
      `APNs rejected push request. status=${status} reason=${this.safeReason(reason)}`,
    );
    this.rejectedResponseWarningLogged = true;
  }

  private safeReason(reason?: string) {
    const normalized = `${reason ?? ''}`.trim();
    if (!normalized) return 'unknown';
    return normalized.replace(/[^a-zA-Z0-9_.-]/g, '_').slice(0, 80);
  }

  private base64Url(value: string | Buffer) {
    return Buffer.from(value)
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/g, '');
  }
}
