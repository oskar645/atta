import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildReferralCode, resolveReferralUserId } from './referral-code';

test('buildReferralCode returns stable non-empty code for same user', () => {
  const first = buildReferralCode('user-42');
  const second = buildReferralCode('user-42');

  assert.notEqual(first, '');
  assert.equal(first, second);
});

test('buildReferralCode returns different codes for different users', () => {
  const first = buildReferralCode('user-42');
  const second = buildReferralCode('user-43');

  assert.notEqual(first, second);
});

test('resolveReferralUserId decodes valid referral code and rejects invalid', () => {
  const referralCode = buildReferralCode('user-99');

  assert.equal(resolveReferralUserId(referralCode), 'user-99');
  assert.equal(resolveReferralUserId('broken-referral-code'), null);
});
