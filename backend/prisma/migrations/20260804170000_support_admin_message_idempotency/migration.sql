ALTER TABLE "support_messages" ADD COLUMN "idempotency_key" TEXT;

CREATE UNIQUE INDEX "support_messages_idempotency_key_key" ON "support_messages"("idempotency_key");
