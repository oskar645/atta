import { test } from 'node:test';
import assert from 'node:assert/strict';

import { AuthController } from '../auth/auth.controller';
import { ChatsController } from '../chats/chats.controller';
import { ListingsController } from '../listings/listings.controller';
import { MediaController } from '../media/media.controller';
import { PromotionsController } from '../promotions/promotions.controller';
import { ReportsController } from '../reports/reports.controller';
import {
  AdminSupportController,
  SupportController,
} from '../support/support.controller';

class StopRateLimitCapture extends Error {}

type CapturedLimit = {
  key: string;
  options: { limit: number; windowMs: number; message?: string };
};

function createRateLimitCapture(calls: CapturedLimit[]) {
  return {
    async consumeOrThrow(
      key: string,
      options: { limit: number; windowMs: number; message?: string },
    ) {
      calls.push({ key, options });
      throw new StopRateLimitCapture();
    },
  };
}

async function captureLimit(
  run: (rateLimit: ReturnType<typeof createRateLimitCapture>) => Promise<unknown>,
) {
  const call = await captureRateLimitCall(run);
  return call.options;
}

async function captureRateLimitCall(
  run: (rateLimit: ReturnType<typeof createRateLimitCapture>) => Promise<unknown>,
) {
  const calls: CapturedLimit[] = [];
  await assert.rejects(
    () => run(createRateLimitCapture(calls)),
    StopRateLimitCapture,
  );
  return calls[0];
}

const request = {
  ip: '203.0.113.1',
  headers: {},
};
const authUser = {
  userId: 'user-1',
  role: 'user' as const,
};

test('existing auth rate limit values are preserved', async () => {
  const cases = [
    ['signup', 6],
    ['login', 8],
    ['signupPhone', 6],
    ['recordReferralOpen', 30],
    ['loginPhone', 8],
    ['resetPasswordPhone', 5],
  ] as const;

  for (const [method, limit] of cases) {
    const options = await captureLimit(async (rateLimit) => {
      const controller = new AuthController({} as never, {} as never, rateLimit as never);
      await (controller[method] as (request: unknown, dto: unknown) => Promise<unknown>)(
        request,
        {},
      );
    });

    assert.equal(options.limit, limit);
    assert.equal(options.windowMs, 60 * 1000);
  }
});

test('signup-phone rate limit source follows trusted request.ip per client', async () => {
  const first = await captureRateLimitCall((rateLimit) => {
    const testedController = new AuthController({} as never, {} as never, rateLimit as never);
    return testedController.signupPhone(
      {
        ip: '198.51.100.10',
        headers: {
          'x-forwarded-for': '203.0.113.200, 198.51.100.10',
        },
      },
      {} as never,
    );
  });
  const second = await captureRateLimitCall((rateLimit) => {
    const testedController = new AuthController({} as never, {} as never, rateLimit as never);
    return testedController.signupPhone(
      {
        ip: '198.51.100.11',
        headers: {
          'x-forwarded-for': '203.0.113.200, 198.51.100.11',
        },
      },
      {} as never,
    );
  });

  assert.equal(first.key, 'auth:signup-phone:198.51.100.10');
  assert.equal(second.key, 'auth:signup-phone:198.51.100.11');
  assert.notEqual(first.key, second.key);
});

test('existing listing, chat, report, support, media and promotion limits are preserved', async () => {
  const checks: Array<{
    expected: { limit: number; windowMs: number };
    run: (rateLimit: ReturnType<typeof createRateLimitCapture>) => Promise<unknown>;
  }> = [
    {
      expected: { limit: 20, windowMs: 60 * 60 * 1000 },
      run: (rateLimit) =>
        new ListingsController({} as never, rateLimit as never).create(
          request,
          authUser as never,
          {} as never,
        ),
    },
    {
      expected: { limit: 30, windowMs: 60 * 1000 },
      run: (rateLimit) =>
        new ChatsController(
          {} as never,
          {} as never,
          rateLimit as never,
          {} as never,
        ).sendMessage(request, authUser as never, 'chat-1', {} as never),
    },
    {
      expected: { limit: 10, windowMs: 60 * 1000 },
      run: (rateLimit) =>
        new ReportsController({} as never, {} as never, rateLimit as never).create(
          request,
          authUser as never,
          {} as never,
        ),
    },
    {
      expected: { limit: 20, windowMs: 60 * 1000 },
      run: (rateLimit) =>
        new SupportController({} as never, rateLimit as never).uploadImage(
          authUser as never,
          request,
          undefined,
        ),
    },
    {
      expected: { limit: 8, windowMs: 60 * 1000 },
      run: (rateLimit) =>
        new SupportController({} as never, rateLimit as never).createTicket(
          request,
          authUser as never,
          {} as never,
        ),
    },
    {
      expected: { limit: 4, windowMs: 60 * 1000 },
      run: (rateLimit) =>
        new SupportController({} as never, rateLimit as never).createBlockAppeal(
          request,
          authUser as never,
          {} as never,
        ),
    },
    {
      expected: { limit: 12, windowMs: 60 * 1000 },
      run: (rateLimit) =>
        new SupportController({} as never, rateLimit as never).sendMessage(
          request,
          authUser as never,
          'ticket-1',
          {} as never,
        ),
    },
    {
      expected: { limit: 20, windowMs: 60 * 1000 },
      run: (rateLimit) =>
        new AdminSupportController({} as never, rateLimit as never).sendMessage(
          'ticket-1',
          {} as never,
        ),
    },
    {
      expected: { limit: 15, windowMs: 60 * 1000 },
      run: (rateLimit) =>
        new MediaController(
          {} as never,
          {} as never,
          rateLimit as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
        ).uploadAvatar(authUser as never, undefined),
    },
    {
      expected: { limit: 20, windowMs: 60 * 1000 },
      run: (rateLimit) =>
        new MediaController(
          {} as never,
          {} as never,
          rateLimit as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
        ).uploadListingPhoto(authUser as never, 'listing-1', request, undefined),
    },
    {
      expected: { limit: 20, windowMs: 60 * 1000 },
      run: (rateLimit) =>
        new MediaController(
          {} as never,
          {} as never,
          rateLimit as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
        ).uploadChatImage(authUser as never, 'chat-1', undefined),
    },
    {
      expected: { limit: 20, windowMs: 60 * 1000 },
      run: (rateLimit) =>
        new MediaController(
          {} as never,
          {} as never,
          rateLimit as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
          {} as never,
        ).uploadNotificationImage(authUser as never, undefined),
    },
    {
      expected: { limit: 20, windowMs: 60 * 60 * 1000 },
      run: (rateLimit) =>
        new PromotionsController({} as never, rateLimit as never).promoteListing(
          request,
          'listing-1',
          authUser as never,
          {} as never,
        ),
    },
    {
      expected: { limit: 20, windowMs: 60 * 60 * 1000 },
      run: (rateLimit) =>
        new PromotionsController({} as never, rateLimit as never).promoteShowcase(
          request,
          'listing-1',
          authUser as never,
        ),
    },
  ];

  for (const check of checks) {
    const options = await captureLimit(check.run);
    assert.deepEqual(options, check.expected);
  }
});
