import { test } from 'node:test';
import assert from 'node:assert/strict';

import { HttpException } from '@nestjs/common';
import { RestoreCredentialType, UserStatus } from '@prisma/client';
import { RestoreCredentialsService } from './restore-credentials.service';

const baseUser = {
  id: 'user-1',
  email: null,
  phone: '79281234567',
  displayName: 'ATTA User',
  name: 'ATTA User',
  status: UserStatus.ACTIVE,
  deletedAt: null,
  adminProfile: null,
};

test('registration options store a one-time challenge for the authorized user', async () => {
  const context = createContext();
  context.webAuthn.generateRegistrationOptions = async () => ({
    challenge: 'registration-challenge',
    rp: { id: 'attamarket.online', name: 'ATTA' },
  });

  const options = await context.service.createRegistrationOptions({
    userId: 'user-1',
    sessionId: 'session-1',
    email: null,
    role: 'user',
  });

  assert.equal(options.challenge, 'registration-challenge');
  assert.equal(context.redis.values.size, 1);
});

test('valid registration stores a restore credential', async () => {
  const context = createContext();
  context.restoreOrigins('android:apk-key-hash:release');
  context.webAuthn.verifyRegistrationResponse = async () => ({
    verified: true,
    registrationInfo: {
      credential: {
        id: 'credential-1',
        publicKey: new Uint8Array([1, 2, 3]),
        counter: 4,
      },
      credentialDeviceType: 'multiDevice',
      credentialBackedUp: true,
    },
  });
  await context.storeChallenge('registration', 'challenge-1', 'user-1');

  const result = await context.service.verifyRegistration(
    { userId: 'user-1', sessionId: 'session-1', email: null, role: 'user' },
    credentialResponse('credential-1', 'challenge-1'),
  );

  assert.equal(result.registered, true);
  assert.equal(result.credential_id, 'credential-1');
  assert.equal(context.prisma.restoreCredential.records[0].credentialId, 'credential-1');
});

test('registration rejects invalid and replayed challenges', async () => {
  const context = createContext();
  context.restoreOrigins('android:apk-key-hash:release');
  context.webAuthn.verifyRegistrationResponse = async () => ({
    verified: true,
    registrationInfo: {
      credential: {
        id: 'credential-1',
        publicKey: new Uint8Array([1]),
        counter: 0,
      },
      credentialDeviceType: 'multiDevice',
      credentialBackedUp: true,
    },
  });
  await context.storeChallenge('registration', 'challenge-1', 'user-1');

  await assert.rejects(
    context.service.verifyRegistration(
      { userId: 'user-1', sessionId: 'session-1', email: null, role: 'user' },
      credentialResponse('credential-1', 'wrong-challenge'),
    ),
    (error: unknown) => isHttpStatus(error, 401),
  );

  await context.service.verifyRegistration(
    { userId: 'user-1', sessionId: 'session-1', email: null, role: 'user' },
    credentialResponse('credential-1', 'challenge-1'),
  );
  await assert.rejects(
    context.service.verifyRegistration(
      { userId: 'user-1', sessionId: 'session-1', email: null, role: 'user' },
      credentialResponse('credential-1', 'challenge-1'),
    ),
    (error: unknown) => isHttpStatus(error, 401),
  );
});

test('authentication options work without an existing login', async () => {
  const context = createContext();
  context.webAuthn.generateAuthenticationOptions = async () => ({
    challenge: 'authentication-challenge',
    rpId: 'attamarket.online',
  });

  const options = await context.service.createAuthenticationOptions();

  assert.equal(options.challenge, 'authentication-challenge');
  assert.equal(context.redis.values.size, 1);
});

test('valid restore credential maps to the correct user and returns normal session', async () => {
  const context = createContext();
  context.restoreOrigins('android:apk-key-hash:release');
  context.webAuthn.verifyAuthenticationResponse = async () => ({
    verified: true,
    authenticationInfo: {
      newCounter: 8,
      credentialDeviceType: 'multiDevice',
      credentialBackedUp: true,
    },
  });
  context.prisma.restoreCredential.records.push(storedCredential());
  await context.storeChallenge('authentication', 'challenge-1');

  const result = await context.service.verifyAuthentication(
    credentialResponse('credential-1', 'challenge-1'),
  );

  assert.equal(result.auth.access_token, 'access-token-for-user-1');
  assert.equal(context.authService.createdSessionUserIds[0], 'user-1');
  assert.equal(context.prisma.restoreCredential.records[0].counter, 8);
});

test('revoked credential and inactive user are rejected', async () => {
  const context = createContext();
  context.restoreOrigins('android:apk-key-hash:release');
  context.webAuthn.verifyAuthenticationResponse = async () => ({
    verified: true,
    authenticationInfo: {
      newCounter: 8,
      credentialDeviceType: 'multiDevice',
      credentialBackedUp: true,
    },
  });
  context.prisma.restoreCredential.records.push(
    storedCredential({ revokedAt: new Date() }),
  );
  await context.storeChallenge('authentication', 'challenge-1');

  await assert.rejects(
    context.service.verifyAuthentication(
      credentialResponse('credential-1', 'challenge-1'),
    ),
    (error: unknown) => isHttpStatus(error, 401),
  );

  context.prisma.restoreCredential.records = [
    storedCredential({ user: { ...baseUser, status: UserStatus.BLOCKED } }),
  ];
  await context.storeChallenge('authentication', 'challenge-2');
  await assert.rejects(
    context.service.verifyAuthentication(
      credentialResponse('credential-1', 'challenge-2'),
    ),
    (error: unknown) => isHttpStatus(error, 401),
  );
});

test('invalid origin or signature verification failure is rejected', async () => {
  const context = createContext();
  context.restoreOrigins('android:apk-key-hash:release');
  context.webAuthn.verifyAuthenticationResponse = async () => ({
    verified: false,
    authenticationInfo: {
      newCounter: 1,
      credentialDeviceType: 'multiDevice',
      credentialBackedUp: true,
    },
  });
  context.prisma.restoreCredential.records.push(storedCredential());
  await context.storeChallenge('authentication', 'challenge-1');

  await assert.rejects(
    context.service.verifyAuthentication(
      credentialResponse('credential-1', 'challenge-1'),
    ),
    (error: unknown) => isHttpStatus(error, 401),
  );
});

test('thrown restore credential registration errors are controlled 401 responses', async () => {
  const context = createContext();
  context.restoreOrigins('android:apk-key-hash:release');
  context.webAuthn.verifyRegistrationResponse = async () => {
    throw new Error(
      'Unexpected registration response origin "android:apk-key-hash:debug"',
    );
  };
  await context.storeChallenge('registration', 'challenge-1', 'user-1');

  await assert.rejects(
    context.service.verifyRegistration(
      { userId: 'user-1', sessionId: 'session-1', email: null, role: 'user' },
      credentialResponse('credential-1', 'challenge-1'),
    ),
    (error: unknown) => {
      assert.ok(error instanceof HttpException);
      assert.equal(error.getStatus(), 401);
      assert.equal(
        error.message,
        'Restore credential registration rejected',
      );
      return true;
    },
  );
});

test('thrown restore credential verification errors are controlled 401 responses', async () => {
  const context = createContext();
  context.restoreOrigins('android:apk-key-hash:release');
  context.webAuthn.verifyAuthenticationResponse = async () => {
    throw new Error(
      'Unexpected authentication response origin "android:apk-key-hash:debug"',
    );
  };
  context.prisma.restoreCredential.records.push(storedCredential());
  await context.storeChallenge('authentication', 'challenge-1');

  await assert.rejects(
    context.service.verifyAuthentication(
      credentialResponse('credential-1', 'challenge-1'),
    ),
    (error: unknown) => {
      assert.ok(error instanceof HttpException);
      assert.equal(error.getStatus(), 401);
      assert.equal(
        error.message,
        'Restore credential authentication rejected',
      );
      return true;
    },
  );
});

test('revoke prevents future restore for that credential only', async () => {
  const context = createContext();
  context.prisma.restoreCredential.records.push(
    storedCredential({ credentialId: 'credential-1' }),
    storedCredential({ id: 'restore-2', credentialId: 'credential-2' }),
  );

  const result = await context.service.revoke(
    { userId: 'user-1', sessionId: 'session-1', email: null, role: 'user' },
    'credential-1',
  );

  assert.equal(result.revoked, 1);
  assert.ok(context.prisma.restoreCredential.records[0].revokedAt);
  assert.equal(context.prisma.restoreCredential.records[1].revokedAt, null);
});

function createContext() {
  const redis = new FakeRedis();
  const prisma = {
    restoreCredential: {
      records: [] as Array<Record<string, any>>,
      findMany: async () => [],
      upsert: async ({ create, update, where }: any) => {
        const existing = prisma.restoreCredential.records.find(
          (item) => item.credentialId === where.credentialId,
        );
        if (existing) {
          Object.assign(existing, update);
          return existing;
        }
        prisma.restoreCredential.records.push({ ...create, id: 'restore-1' });
        return create;
      },
      findUnique: async ({ where }: any) =>
        prisma.restoreCredential.records.find(
          (item) => item.credentialId === where.credentialId,
        ) ?? null,
      update: async ({ where, data }: any) => {
        const existing = prisma.restoreCredential.records.find(
          (item) => item.id === where.id,
        );
        assert.ok(existing);
        Object.assign(existing, data);
        return existing;
      },
      updateMany: async ({ where, data }: any) => {
        const records = prisma.restoreCredential.records.filter(
          (item) =>
            item.userId === where.userId &&
            item.revokedAt === where.revokedAt &&
            item.type === where.type &&
            (!where.credentialId || item.credentialId === where.credentialId),
        );
        records.forEach((item) => Object.assign(item, data));
        return { count: records.length };
      },
    },
    user: {
      update: async ({ where, data, include }: any) => ({
        ...baseUser,
        id: where.id,
        lastLoginAt: data.lastLoginAt,
        adminProfile: include.adminProfile ? null : undefined,
      }),
    },
  };
  const authService = {
    createdSessionUserIds: [] as string[],
    findActiveUserByIdOrThrow: async () => baseUser,
    createSessionForUser: async (user: typeof baseUser) => {
      authService.createdSessionUserIds.push(user.id);
      return {
        user,
        auth: {
          access_token: `access-token-for-${user.id}`,
          refresh_token: `refresh-token-for-${user.id}`,
        },
      };
    },
  };
  const service = new RestoreCredentialsService(
    prisma as never,
    redis as never,
    { getActiveBlock: async () => null } as never,
    authService as never,
  );
  const webAuthn = (service as any).webAuthn;

  return {
    service,
    webAuthn,
    redis,
    prisma,
    authService,
    restoreOrigins: (...origins: string[]) => {
      (service as any).restoreOrigins = () => origins;
    },
    storeChallenge: (
      purpose: string,
      challenge: string,
      userId?: string,
    ) =>
      redis.setWithTtl(
        `auth:restore-credentials:${purpose}:${challenge}`,
        JSON.stringify({
          purpose,
          challenge,
          userId,
          createdAt: new Date().toISOString(),
        }),
        300,
      ),
  };
}

class FakeRedis {
  values = new Map<string, string>();

  async setWithTtl(key: string, value: string, _ttlSeconds?: number) {
    this.values.set(key, value);
  }

  async get(key: string) {
    return this.values.get(key) ?? null;
  }

  async del(key: string) {
    this.values.delete(key);
  }
}

function storedCredential(overrides: Record<string, any> = {}) {
  return {
    id: 'restore-1',
    userId: 'user-1',
    credentialId: 'credential-1',
    publicKey: new Uint8Array([1, 2, 3]),
    counter: 0,
    transports: ['internal'],
    type: RestoreCredentialType.RESTORE,
    revokedAt: null,
    user: baseUser,
    ...overrides,
  };
}

function credentialResponse(id: string, challenge: string) {
  return {
    id,
    rawId: id,
    type: 'public-key',
    response: {
      clientDataJSON: base64UrlJson({ challenge }),
      transports: ['internal'],
    },
    clientExtensionResults: {},
  };
}

function base64UrlJson(value: Record<string, unknown>) {
  return Buffer.from(JSON.stringify(value))
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function isHttpStatus(error: unknown, status: number) {
  assert.ok(error instanceof HttpException);
  assert.equal(error.getStatus(), status);
  return true;
}
