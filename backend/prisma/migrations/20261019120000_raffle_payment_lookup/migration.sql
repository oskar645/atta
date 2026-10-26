CREATE INDEX IF NOT EXISTS "payments_provider_status_credited_at_idx"
  ON "payments"("provider", "status", "credited_at");

CREATE INDEX IF NOT EXISTS "payments_user_id_credited_at_idx"
  ON "payments"("user_id", "credited_at");

CREATE INDEX IF NOT EXISTS "wallet_transactions_payment_id_idx"
  ON "wallet_transactions" (("metadata"->>'paymentId'))
  WHERE "metadata"->>'paymentId' IS NOT NULL;
