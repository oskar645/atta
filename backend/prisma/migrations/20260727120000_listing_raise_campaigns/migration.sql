CREATE TYPE "ListingRaiseCampaignStatus" AS ENUM ('ACTIVE', 'COMPLETED', 'CANCELLED', 'FAILED');

CREATE TABLE "listing_raise_campaigns" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "purchased_raises" INTEGER NOT NULL,
    "completed_raises" INTEGER NOT NULL DEFAULT 0,
    "price_per_raise" INTEGER NOT NULL,
    "total_price" INTEGER NOT NULL,
    "started_at" TIMESTAMP(3) NOT NULL,
    "last_raise_at" TIMESTAMP(3),
    "next_raise_at" TIMESTAMP(3),
    "status" "ListingRaiseCampaignStatus" NOT NULL DEFAULT 'ACTIVE',
    "cancel_reason" TEXT,
    "idempotency_key" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "listing_raise_campaigns_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "listing_raise_campaigns_idempotency_key_key"
ON "listing_raise_campaigns"("idempotency_key");

CREATE INDEX "listing_raise_campaigns_listing_id_status_next_raise_at_idx"
ON "listing_raise_campaigns"("listing_id", "status", "next_raise_at");

CREATE INDEX "listing_raise_campaigns_user_id_idx"
ON "listing_raise_campaigns"("user_id");

CREATE INDEX "listing_raise_campaigns_status_next_raise_at_idx"
ON "listing_raise_campaigns"("status", "next_raise_at");

ALTER TABLE "listing_raise_campaigns" ADD CONSTRAINT "listing_raise_campaigns_listing_id_fkey"
FOREIGN KEY ("listing_id") REFERENCES "listings"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "listing_raise_campaigns" ADD CONSTRAINT "listing_raise_campaigns_user_id_fkey"
FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
