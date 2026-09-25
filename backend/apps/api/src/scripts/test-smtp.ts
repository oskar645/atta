#!/usr/bin/env ts-node
import { randomInt } from 'crypto';

import { EmailService } from '../modules/email/email.service';

function maskEmail(value: string) {
  const [local, domain] = value.split('@');
  if (!local || !domain) return '(invalid)';
  return `${local.slice(0, 1)}***@${domain}`;
}

function safeError(error: unknown) {
  const value = error as { code?: unknown; command?: unknown; responseCode?: unknown };
  return {
    code: typeof value?.code === 'string' ? value.code : 'SMTP_ERROR',
    command: typeof value?.command === 'string' ? value.command : undefined,
    responseCode: typeof value?.responseCode === 'number' ? value.responseCode : undefined,
  };
}

async function main() {
  const recipient = process.env.SMTP_TEST_TO?.trim() ?? '';
  if (!recipient || !recipient.includes('@')) {
    throw new Error('SMTP_TEST_TO must contain a valid recipient email');
  }

  const email = new EmailService();
  await email.verify();
  console.log('SMTP verify: OK (TLS/auth accepted)');

  const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
  const result = await email.sendVerificationCode({ to: recipient, code });
  console.log('Test email accepted:', {
    recipient: maskEmail(recipient),
    messageId: typeof result.messageId === 'string' ? result.messageId : '(not returned)',
    accepted: Array.isArray(result.accepted) && result.accepted.length > 0,
  });
}

main().catch((error: unknown) => {
  console.error('SMTP test failed:', safeError(error));
  process.exitCode = 1;
});
