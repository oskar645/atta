CREATE TYPE "PaymentProvider" AS ENUM ('YOOKASSA');

CREATE TYPE "PaymentStatus" AS ENUM ('PENDING', 'SUCCEEDED', 'CANCELED');

ALTER TYPE "WalletTransactionReason" ADD VALUE IF NOT EXISTS 'POINTS_PURCHASE';

CREATE TABLE "payments" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "provider" "PaymentProvider" NOT NULL DEFAULT 'YOOKASSA',
    "provider_payment_id" TEXT,
    "idempotency_key" TEXT NOT NULL,
    "amount_rub" DECIMAL(12,2) NOT NULL,
    "points_amount" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'RUB',
    "status" "PaymentStatus" NOT NULL DEFAULT 'PENDING',
    "credited_at" TIMESTAMP(3),
    "metadata" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "payments_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "payments_provider_payment_id_key"
ON "payments"("provider_payment_id");

CREATE UNIQUE INDEX "payments_idempotency_key_key"
ON "payments"("idempotency_key");

CREATE INDEX "payments_user_id_created_at_idx"
ON "payments"("user_id", "created_at");

CREATE INDEX "payments_provider_status_idx"
ON "payments"("provider", "status");

CREATE INDEX "payments_provider_payment_id_status_idx"
ON "payments"("provider_payment_id", "status");

ALTER TABLE "payments" ADD CONSTRAINT "payments_user_id_fkey"
FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
