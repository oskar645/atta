CREATE TYPE "RestoreCredentialType" AS ENUM ('RESTORE');

CREATE TABLE "restore_credentials" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "credential_id" TEXT NOT NULL,
    "public_key" BYTEA NOT NULL,
    "counter" INTEGER NOT NULL DEFAULT 0,
    "transports" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "type" "RestoreCredentialType" NOT NULL DEFAULT 'RESTORE',
    "device_type" TEXT,
    "backed_up" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_used_at" TIMESTAMP(3),
    "revoked_at" TIMESTAMP(3),

    CONSTRAINT "restore_credentials_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "restore_credentials_credential_id_key" ON "restore_credentials"("credential_id");
CREATE INDEX "restore_credentials_user_id_revoked_at_idx" ON "restore_credentials"("user_id", "revoked_at");

ALTER TABLE "restore_credentials"
ADD CONSTRAINT "restore_credentials_user_id_fkey"
FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
