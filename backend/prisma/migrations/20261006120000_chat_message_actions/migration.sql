ALTER TABLE "chat_messages"
  ADD COLUMN "edited_at" TIMESTAMPTZ(3),
  ADD COLUMN "reply_to_message_id" UUID,
  ADD COLUMN "hidden_for_user_ids" UUID[] NOT NULL DEFAULT ARRAY[]::UUID[];

ALTER TABLE "chat_messages"
  ADD CONSTRAINT "chat_messages_reply_to_message_id_fkey"
  FOREIGN KEY ("reply_to_message_id") REFERENCES "chat_messages"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX "chat_messages_reply_to_message_id_idx"
  ON "chat_messages"("reply_to_message_id");
