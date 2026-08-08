CREATE TABLE IF NOT EXISTS "referrals" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "inviter_user_id" UUID NOT NULL,
  "invited_user_id" UUID NOT NULL,
  "referral_code" TEXT NOT NULL,
  "wallet_transaction_id" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "referrals_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "referrals_invited_user_id_key"
  ON "referrals"("invited_user_id");

CREATE UNIQUE INDEX IF NOT EXISTS "referrals_wallet_transaction_id_key"
  ON "referrals"("wallet_transaction_id");

CREATE INDEX IF NOT EXISTS "referrals_inviter_user_id_created_at_idx"
  ON "referrals"("inviter_user_id", "created_at");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'referrals_inviter_user_id_fkey'
  ) THEN
    ALTER TABLE "referrals"
      ADD CONSTRAINT "referrals_inviter_user_id_fkey"
      FOREIGN KEY ("inviter_user_id") REFERENCES "users"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'referrals_invited_user_id_fkey'
  ) THEN
    ALTER TABLE "referrals"
      ADD CONSTRAINT "referrals_invited_user_id_fkey"
      FOREIGN KEY ("invited_user_id") REFERENCES "users"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'referrals_wallet_transaction_id_fkey'
  ) THEN
    ALTER TABLE "referrals"
      ADD CONSTRAINT "referrals_wallet_transaction_id_fkey"
      FOREIGN KEY ("wallet_transaction_id") REFERENCES "wallet_transactions"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;
