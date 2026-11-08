CREATE INDEX "wallet_transactions_type_reason_created_at_idx"
ON "wallet_transactions"("type", "reason", "created_at");
