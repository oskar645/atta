"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveListingContactPhone = exports.normalizeListingContactPhone = exports.isFinalListingContactRollout = exports.listingContactRolloutStage = exports.resolveListingContactRolloutStage = void 0;
const env_1 = require("../config/env");
const phone_1 = require("./phone");
const resolveListingContactRolloutStage = (value) => value?.trim().toLowerCase() === 'final' ? 'final' : 'transitional';
exports.resolveListingContactRolloutStage = resolveListingContactRolloutStage;
// The safe default deliberately preserves the API contract used by published
// clients. The final stage must only be enabled globally after old clients are
// no longer supported; it must never be selected from an untrusted client
// version header.
exports.listingContactRolloutStage = (0, exports.resolveListingContactRolloutStage)(env_1.env.LISTING_CONTACT_ROLLOUT_STAGE);
const isFinalListingContactRollout = () => exports.listingContactRolloutStage === 'final';
exports.isFinalListingContactRollout = isFinalListingContactRollout;
const normalizeListingContactPhone = (value) => {
    const raw = value?.trim() ?? '';
    const digits = raw.replace(/\D/g, '');
    return (0, phone_1.normalizeRussianPhone)(digits.length === 10 ? `7${digits}` : raw);
};
exports.normalizeListingContactPhone = normalizeListingContactPhone;
const resolveListingContactPhone = (listingPhone, ownerPhone, stage = exports.listingContactRolloutStage) => {
    const normalizedListingPhone = (0, exports.normalizeListingContactPhone)(listingPhone);
    if (normalizedListingPhone || stage === 'final') {
        return normalizedListingPhone;
    }
    return (0, phone_1.normalizeRussianPhone)(ownerPhone?.trim() ?? '');
};
exports.resolveListingContactPhone = resolveListingContactPhone;
//# sourceMappingURL=listing-contact-rollout.js.map