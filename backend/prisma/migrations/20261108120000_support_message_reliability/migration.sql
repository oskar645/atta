ALTER TABLE "support_tickets"
ADD COLUMN "create_idempotency_key" TEXT;

CREATE UNIQUE INDEX "support_tickets_create_idempotency_key_key"
ON "support_tickets"("create_idempotency_key");

ALTER TABLE "support_messages"
ADD COLUMN "read_at" TIMESTAMP(3),
ADD COLUMN "edited_at" TIMESTAMP(3),
ADD COLUMN "edited_by_user_id" UUID,
ADD COLUMN "deleted_at" TIMESTAMP(3),
ADD COLUMN "deleted_by_user_id" UUID;

CREATE TABLE "support_message_revisions" (
  "id" UUID NOT NULL,
  "message_id" UUID NOT NULL,
  "editor_user_id" UUID NOT NULL,
  "previous_text" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "support_message_revisions_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "support_message_revisions_message_id_fkey"
    FOREIGN KEY ("message_id") REFERENCES "support_messages"("id")
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "support_message_revisions_message_id_created_at_idx"
ON "support_message_revisions"("message_id", "created_at");
