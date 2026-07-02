ALTER TABLE "chat_messages"
ADD COLUMN "client_message_id" TEXT;

CREATE UNIQUE INDEX "chat_messages_chat_id_sender_id_client_message_id_key"
ON "chat_messages"("chat_id", "sender_id", "client_message_id");
