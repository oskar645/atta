import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  normalizeListingContactPhone,
  resolveListingContactPhone,
  resolveListingContactRolloutStage,
} from './listing-contact-rollout';

test('listing contact rollout defaults to published-client compatibility', () => {
  assert.equal(resolveListingContactRolloutStage(undefined), 'transitional');
  assert.equal(resolveListingContactRolloutStage(''), 'transitional');
  assert.equal(resolveListingContactRolloutStage('unexpected'), 'transitional');
});

test('final listing contact rollout requires an explicit global setting', () => {
  assert.equal(resolveListingContactRolloutStage('final'), 'final');
  assert.equal(resolveListingContactRolloutStage(' FINAL '), 'final');
});

test('listing contact normalization accepts legacy ten-digit Russian numbers', () => {
  assert.equal(normalizeListingContactPhone('9281234567'), '79281234567');
  assert.equal(normalizeListingContactPhone('8 (928) 123-45-67'), '79281234567');
  assert.equal(normalizeListingContactPhone('+7 928 123-45-67'), '79281234567');
});

test('transitional contact prefers a valid listing phone', () => {
  assert.equal(
    resolveListingContactPhone('9281112233', '79110000000', 'transitional'),
    '79281112233',
  );
});

test('transitional contact falls back after an invalid listing phone', () => {
  assert.equal(
    resolveListingContactPhone('123', '79281234567', 'transitional'),
    '79281234567',
  );
});

test('transitional contact stays unavailable when both numbers are invalid', () => {
  assert.equal(resolveListingContactPhone('123', '456', 'transitional'), '');
  assert.equal(resolveListingContactPhone(null, null, 'transitional'), '');
});

test('final contact never falls back to the owner phone', () => {
  assert.equal(resolveListingContactPhone('', '79281234567', 'final'), '');
  assert.equal(resolveListingContactPhone('123', '79281234567', 'final'), '');
  assert.equal(
    resolveListingContactPhone('9281112233', '79110000000', 'final'),
    '79281112233',
  );
});
