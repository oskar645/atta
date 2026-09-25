import 'reflect-metadata';
import assert from 'node:assert/strict';
import { test } from 'node:test';

import nodemailer from 'nodemailer';

test('verification email uses the ATTA sender and formats a six-digit code', async () => {
  const originalCreateTransport = nodemailer.createTransport;
  let message: Record<string, unknown> | undefined;
  nodemailer.createTransport = (() => ({
    verify: async () => true,
    sendMail: async (value: Record<string, unknown>) => {
      message = value;
      return { messageId: 'test-message', accepted: [value.to] };
    },
  })) as typeof nodemailer.createTransport;

  try {
    process.env.SMTP_PASS = 'test-only-password';
    const { EmailService } = await import('./email.service');
    const email = new EmailService();
    await email.verify();
    await email.sendVerificationCode({ to: 'recipient@example.com', code: '123456' });

    assert.equal(message?.from, 'ATTA <atta@attamarket.online>');
    assert.equal(message?.subject, 'Код подтверждения ATTA');
    assert.match(String(message?.text), /123 456/);
    assert.match(String(message?.html), /123 456/);
    assert.doesNotMatch(String(message?.text), /test-only-password/);
  } finally {
    nodemailer.createTransport = originalCreateTransport;
    delete process.env.SMTP_PASS;
  }
});
