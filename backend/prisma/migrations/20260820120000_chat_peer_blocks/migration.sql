CREATE TABLE "chat_peer_blocks" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "blocker_user_id" UUID NOT NULL,
    "blocked_user_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "chat_peer_blocks_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "chat_peer_blocks_blocker_user_id_blocked_user_id_key"
  ON "chat_peer_blocks"("blocker_user_id", "blocked_user_id");
CREATE INDEX "chat_peer_blocks_blocked_user_id_idx"
  ON "chat_peer_blocks"("blocked_user_id");

ALTER TABLE "chat_peer_blocks"
  ADD CONSTRAINT "chat_peer_blocks_blocker_user_id_fkey"
  FOREIGN KEY ("blocker_user_id") REFERENCES "users"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "chat_peer_blocks"
  ADD CONSTRAINT "chat_peer_blocks_blocked_user_id_fkey"
  FOREIGN KEY ("blocked_user_id") REFERENCES "users"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
