import { test } from 'node:test';
import assert from 'node:assert/strict';

import { AuthController } from './auth.controller';

test('legacy POST /auth/signup delegates to the compatible signup service', async () => {
  const calls: unknown[] = [];
  const dto = {
    email: ' Legacy@Example.com ',
    password: 'password-123',
    acceptedLegal: true,
    acceptedPersonalData: true,
  };
  const expected = { auth: { access_token: 'token' }, user: { id: 'user-1' } };
  const controller = new AuthController(
    {
      signup: async (payload: unknown) => {
        calls.push(payload);
        return expected;
      },
    } as never,
    {} as never,
    { consumeOrThrow: async () => undefined } as never,
    {} as never,
  );

  const result = await controller.signup({ ip: '127.0.0.1', headers: {} }, dto);

  assert.equal(result, expected);
  assert.deepEqual(calls, [dto]);
});
