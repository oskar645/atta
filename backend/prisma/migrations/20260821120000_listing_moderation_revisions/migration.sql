CREATE TABLE "listing_moderation_revisions" (
    "id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "snapshot" JSONB NOT NULL,
    "resolved_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "listing_moderation_revisions_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "listing_moderation_revisions_listing_id_resolved_at_created_at_idx"
    ON "listing_moderation_revisions"("listing_id", "resolved_at", "created_at");

ALTER TABLE "listing_moderation_revisions"
    ADD CONSTRAINT "listing_moderation_revisions_listing_id_fkey"
    FOREIGN KEY ("listing_id") REFERENCES "listings"("id") ON DELETE CASCADE ON UPDATE CASCADE;
