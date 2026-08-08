DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ReferralRewardStatus') THEN
    CREATE TYPE "ReferralRewardStatus" AS ENUM (
      'PENDING',
      'REWARDED',
      'NOT_REWARDED',
      'FAILED_RETRYABLE'
    );
  END IF;
END $$;

ALTER TABLE "referrals"
  ALTER COLUMN "invited_user_id" DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS "opened_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "app_opened_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "signup_started_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "registered_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "is_new_user" BOOLEAN,
  ADD COLUMN IF NOT EXISTS "reward_status" "ReferralRewardStatus" NOT NULL DEFAULT 'PENDING',
  ADD COLUMN IF NOT EXISTS "reward_amount" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "rewarded_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "failure_reason" TEXT,
  ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

UPDATE "referrals"
SET
  "reward_status" = CASE
    WHEN "wallet_transaction_id" IS NOT NULL THEN 'REWARDED'::"ReferralRewardStatus"
    ELSE "reward_status"
  END,
  "reward_amount" = CASE
    WHEN "wallet_transaction_id" IS NOT NULL AND "reward_amount" = 0 THEN 100
    ELSE "reward_amount"
  END,
  "rewarded_at" = CASE
    WHEN "wallet_transaction_id" IS NOT NULL AND "rewarded_at" IS NULL THEN "created_at"
    ELSE "rewarded_at"
  END,
  "registered_at" = CASE
    WHEN "invited_user_id" IS NOT NULL AND "registered_at" IS NULL THEN "created_at"
    ELSE "registered_at"
  END,
  "is_new_user" = CASE
    WHEN "invited_user_id" IS NOT NULL AND "is_new_user" IS NULL THEN TRUE
    ELSE "is_new_user"
  END;

CREATE INDEX IF NOT EXISTS "referrals_referral_code_created_at_idx"
  ON "referrals"("referral_code", "created_at");

CREATE INDEX IF NOT EXISTS "referrals_reward_status_created_at_idx"
  ON "referrals"("reward_status", "created_at");
