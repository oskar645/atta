ALTER TYPE "EmailChallengePurpose" ADD VALUE IF NOT EXISTS 'EMAIL_AUTH';

ALTER TABLE "blocked_identities"
  ALTER COLUMN "normalized_phone" DROP NOT NULL,
  ADD COLUMN "normalized_email" TEXT;

ALTER TABLE "blocked_identities"
  ADD CONSTRAINT "blocked_identities_contact_check"
  CHECK ("normalized_phone" IS NOT NULL OR "normalized_email" IS NOT NULL);

CREATE INDEX "blocked_identities_normalized_email_lifted_at_idx"
  ON "blocked_identities"("normalized_email", "lifted_at");

ALTER TABLE "deleted_user_identities"
  ADD COLUMN "email" TEXT;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "users"
    WHERE "email" IS NOT NULL
    GROUP BY LOWER(BTRIM("email"))
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Cannot enable email authentication: case-insensitive duplicate user emails exist';
  END IF;
END $$;

CREATE UNIQUE INDEX "users_email_lower_unique"
  ON "users" (LOWER(BTRIM("email")))
  WHERE "email" IS NOT NULL;
