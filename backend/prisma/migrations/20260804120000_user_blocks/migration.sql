CREATE TYPE "UserBlockType" AS ENUM ('TEMPORARY', 'PERMANENT');
CREATE TYPE "UserBlockStatus" AS ENUM ('ACTIVE', 'EXPIRED', 'LIFTED');

CREATE TABLE "user_blocks" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "listing_id" UUID,
    "admin_id" UUID NOT NULL,
    "type" "UserBlockType" NOT NULL,
    "status" "UserBlockStatus" NOT NULL DEFAULT 'ACTIVE',
    "reason" TEXT NOT NULL,
    "internal_note" TEXT,
    "starts_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "ends_at" TIMESTAMP(3),
    "lifted_at" TIMESTAMP(3),
    "lifted_by_admin_id" UUID,
    "lift_reason" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_blocks_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "blocked_identities" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "normalized_phone" TEXT NOT NULL,
    "user_block_id" UUID NOT NULL,
    "banned_until" TIMESTAMP(3),
    "permanent" BOOLEAN NOT NULL DEFAULT false,
    "reason" TEXT NOT NULL,
    "lifted_at" TIMESTAMP(3),
    "lifted_by_admin_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "blocked_identities_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "support_tickets"
  ADD COLUMN "user_block_id" UUID,
  ADD COLUMN "is_block_appeal" BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX "user_blocks_user_id_status_starts_at_idx" ON "user_blocks"("user_id", "status", "starts_at");
CREATE INDEX "user_blocks_listing_id_idx" ON "user_blocks"("listing_id");
CREATE INDEX "user_blocks_admin_id_created_at_idx" ON "user_blocks"("admin_id", "created_at");
CREATE INDEX "user_blocks_status_ends_at_idx" ON "user_blocks"("status", "ends_at");
CREATE INDEX "blocked_identities_normalized_phone_lifted_at_idx" ON "blocked_identities"("normalized_phone", "lifted_at");
CREATE INDEX "blocked_identities_user_block_id_idx" ON "blocked_identities"("user_block_id");
CREATE INDEX "support_tickets_is_block_appeal_updated_at_idx" ON "support_tickets"("is_block_appeal", "updated_at");
CREATE INDEX "support_tickets_user_block_id_idx" ON "support_tickets"("user_block_id");

ALTER TABLE "user_blocks" ADD CONSTRAINT "user_blocks_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "user_blocks" ADD CONSTRAINT "user_blocks_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listings"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "user_blocks" ADD CONSTRAINT "user_blocks_admin_id_fkey" FOREIGN KEY ("admin_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "user_blocks" ADD CONSTRAINT "user_blocks_lifted_by_admin_id_fkey" FOREIGN KEY ("lifted_by_admin_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "blocked_identities" ADD CONSTRAINT "blocked_identities_user_block_id_fkey" FOREIGN KEY ("user_block_id") REFERENCES "user_blocks"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "blocked_identities" ADD CONSTRAINT "blocked_identities_lifted_by_admin_id_fkey" FOREIGN KEY ("lifted_by_admin_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "support_tickets" ADD CONSTRAINT "support_tickets_user_block_id_fkey" FOREIGN KEY ("user_block_id") REFERENCES "user_blocks"("id") ON DELETE SET NULL ON UPDATE CASCADE;
