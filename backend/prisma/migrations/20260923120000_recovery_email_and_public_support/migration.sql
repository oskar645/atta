-- Additive account recovery and public support primitives. Existing emails remain unverified.
CREATE TYPE "EmailChallengePurpose" AS ENUM ('RECOVERY_EMAIL', 'ACCOUNT_RECOVERY');
CREATE TYPE "SupportTicketCategory" AS ENUM ('GENERAL', 'ACCESS_RECOVERY');

ALTER TABLE "users" ADD COLUMN "email_verified_at" TIMESTAMPTZ(3);

CREATE TABLE "email_challenges" (
  "id" UUID NOT NULL,
  "user_id" UUID,
  "purpose" "EmailChallengePurpose" NOT NULL,
  "target_email" TEXT NOT NULL,
  "code_hash" TEXT NOT NULL,
  "attempts" INTEGER NOT NULL DEFAULT 0,
  "max_attempts" INTEGER NOT NULL DEFAULT 5,
  "expires_at" TIMESTAMPTZ(3) NOT NULL,
  "resend_available_at" TIMESTAMPTZ(3) NOT NULL,
  "consumed_at" TIMESTAMPTZ(3),
  "requested_by_ip" TEXT,
  "requested_by_device" TEXT,
  "metadata" JSONB NOT NULL DEFAULT '{}',
  "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(3) NOT NULL,
  CONSTRAINT "email_challenges_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "account_recovery_grants" (
  "id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "token_hash" TEXT NOT NULL,
  "expires_at" TIMESTAMPTZ(3) NOT NULL,
  "consumed_at" TIMESTAMPTZ(3),
  "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "account_recovery_grants_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "support_tickets" ALTER COLUMN "user_id" DROP NOT NULL;
ALTER TABLE "support_tickets"
  ADD COLUMN "category" "SupportTicketCategory" NOT NULL DEFAULT 'GENERAL',
  ADD COLUMN "public_token_hash" TEXT,
  ADD COLUMN "contact_phone" TEXT,
  ADD COLUMN "contact_email" TEXT;

CREATE UNIQUE INDEX "account_recovery_grants_token_hash_key" ON "account_recovery_grants"("token_hash");
CREATE INDEX "account_recovery_grants_user_id_expires_at_idx" ON "account_recovery_grants"("user_id", "expires_at");
CREATE INDEX "email_challenges_user_id_purpose_created_at_idx" ON "email_challenges"("user_id", "purpose", "created_at");
CREATE INDEX "email_challenges_target_email_purpose_created_at_idx" ON "email_challenges"("target_email", "purpose", "created_at");
CREATE INDEX "email_challenges_expires_at_idx" ON "email_challenges"("expires_at");
CREATE UNIQUE INDEX "support_tickets_public_token_hash_key" ON "support_tickets"("public_token_hash");
CREATE INDEX "support_tickets_category_status_updated_at_idx" ON "support_tickets"("category", "status", "updated_at");

ALTER TABLE "email_challenges" ADD CONSTRAINT "email_challenges_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "account_recovery_grants" ADD CONSTRAINT "account_recovery_grants_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
