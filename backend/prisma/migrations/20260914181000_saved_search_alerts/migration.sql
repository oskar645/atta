CREATE TABLE "saved_search_alerts" (
  "saved_search_id" UUID NOT NULL,
  "listing_id" UUID NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "saved_search_alerts_pkey" PRIMARY KEY ("saved_search_id", "listing_id"),
  CONSTRAINT "saved_search_alerts_saved_search_id_fkey" FOREIGN KEY ("saved_search_id") REFERENCES "saved_searches"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "saved_search_alerts_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listings"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
