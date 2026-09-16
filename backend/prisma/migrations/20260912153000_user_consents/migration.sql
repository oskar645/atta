CREATE TYPE "UserConsentType" AS ENUM (
  'TERMS_ACCEPTANCE',
  'PERSONAL_DATA_PROCESSING',
  'MARKETING_MESSAGES'
);

CREATE TABLE "user_consents" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "user_id" UUID NOT NULL,
  "consent_type" "UserConsentType" NOT NULL,
  "document_version" TEXT NOT NULL,
  "accepted_at" TIMESTAMP(3),
  "withdrawn_at" TIMESTAMP(3),
  "platform" "DevicePlatform",
  "technical_info" JSONB NOT NULL DEFAULT '{}',
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "user_consents_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "user_consents_user_id_consent_type_created_at_idx"
  ON "user_consents"("user_id", "consent_type", "created_at");

ALTER TABLE "user_consents"
  ADD CONSTRAINT "user_consents_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
