import { env } from '../config/env';
import { normalizeRussianPhone } from './phone';

export type ListingContactRolloutStage = 'transitional' | 'final';

export const resolveListingContactRolloutStage = (
  value: string | undefined,
): ListingContactRolloutStage =>
  value?.trim().toLowerCase() === 'final' ? 'final' : 'transitional';

// The safe default deliberately preserves the API contract used by published
// clients. The final stage must only be enabled globally after old clients are
// no longer supported; it must never be selected from an untrusted client
// version header.
export const listingContactRolloutStage = resolveListingContactRolloutStage(
  env.LISTING_CONTACT_ROLLOUT_STAGE,
);

export const isFinalListingContactRollout = () =>
  listingContactRolloutStage === 'final';

export const normalizeListingContactPhone = (
  value: string | null | undefined,
): string => {
  const raw = value?.trim() ?? '';
  const digits = raw.replace(/\D/g, '');
  return normalizeRussianPhone(digits.length === 10 ? `7${digits}` : raw);
};

export const resolveListingContactPhone = (
  listingPhone: string | null | undefined,
  ownerPhone: string | null | undefined,
  stage: ListingContactRolloutStage = listingContactRolloutStage,
): string => {
  const normalizedListingPhone = normalizeListingContactPhone(listingPhone);
  if (normalizedListingPhone || stage === 'final') {
    return normalizedListingPhone;
  }
  return normalizeRussianPhone(ownerPhone?.trim() ?? '');
};
