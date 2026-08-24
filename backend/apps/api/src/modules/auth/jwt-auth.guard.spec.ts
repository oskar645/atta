import { test } from 'node:test';
import assert from 'node:assert/strict';

import { UnauthorizedException } from '@nestjs/common';

import { JwtAuthGuard } from './jwt-auth.guard';

function createContext(request: Record<string, unknown>) {
  return {
    switchToHttp: () => ({
      getRequest: () => request,
    }),
  };
}

test('JwtAuthGuard rejects revoked session access', async () => {
  const guard = new JwtAuthGuard(
    {
      verifyAsync: async () => ({
        sub: 'user-1',
        sessionId: 'session-1',
        type: 'access',
        role: 'user',
        email: null,
      }),
    } as never,
    {
      userSession: {
        findFirst: async () => null,
      },
    } as never,
    {
      getActiveBlock: async () => null,
    } as never,
  );

  await assert.rejects(
    guard.canActivate(
      createContext({
        method: 'GET',
        path: '/auth/me',
        headers: {
          authorization: 'Bearer access-token',
        },
      }) as never,
    ),
    (error: unknown) => {
      assert.ok(error instanceof UnauthorizedException);
      assert.equal(error.message, 'Session is not active');
      return true;
    },
  );
});
