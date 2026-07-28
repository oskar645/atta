ALTER TYPE "WalletTransactionReason" ADD VALUE IF NOT EXISTS 'SIGNUP_BONUS';

ALTER TABLE "wallet_transactions"
ADD COLUMN IF NOT EXISTS "idempotency_key" TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS "wallet_transactions_idempotency_key_key"
ON "wallet_transactions"("idempotency_key");
