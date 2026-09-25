#!/usr/bin/env ts-node
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const crypto_1 = require("crypto");
const email_service_1 = require("../modules/email/email.service");
function maskEmail(value) {
    const [local, domain] = value.split('@');
    if (!local || !domain)
        return '(invalid)';
    return `${local.slice(0, 1)}***@${domain}`;
}
function safeError(error) {
    const value = error;
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
    const email = new email_service_1.EmailService();
    await email.verify();
    console.log('SMTP verify: OK (TLS/auth accepted)');
    const code = (0, crypto_1.randomInt)(0, 1_000_000).toString().padStart(6, '0');
    const result = await email.sendVerificationCode({ to: recipient, code });
    console.log('Test email accepted:', {
        recipient: maskEmail(recipient),
        messageId: typeof result.messageId === 'string' ? result.messageId : '(not returned)',
        accepted: Array.isArray(result.accepted) && result.accepted.length > 0,
    });
}
main().catch((error) => {
    console.error('SMTP test failed:', safeError(error));
    process.exitCode = 1;
});
//# sourceMappingURL=test-smtp.js.map