CREATE TYPE "TopBannerEventType" AS ENUM ('IMPRESSION', 'CLICK');

CREATE TABLE "top_banners" (
  "id" UUID NOT NULL,
  "title" TEXT NOT NULL,
  "image_url" TEXT NOT NULL,
  "image_bucket" TEXT NOT NULL DEFAULT 'feed-ads',
  "image_key" TEXT,
  "target_url" TEXT NOT NULL DEFAULT '',
  "enabled" BOOLEAN NOT NULL DEFAULT false,
  "start_at" TIMESTAMP(3) NOT NULL,
  "end_at" TIMESTAMP(3) NOT NULL,
  "sort_order" INTEGER NOT NULL DEFAULT 0,
  "impression_count" BIGINT NOT NULL DEFAULT 0,
  "click_count" BIGINT NOT NULL DEFAULT 0,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  "created_by_id" UUID,
  CONSTRAINT "top_banners_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "top_banner_events" (
  "id" UUID NOT NULL,
  "banner_id" UUID NOT NULL,
  "type" "TopBannerEventType" NOT NULL,
  "session_id" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "top_banner_events_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "top_banners_enabled_start_at_end_at_idx" ON "top_banners"("enabled", "start_at", "end_at");
CREATE INDEX "top_banners_sort_order_idx" ON "top_banners"("sort_order");
CREATE UNIQUE INDEX "top_banner_events_banner_id_type_session_id_key" ON "top_banner_events"("banner_id", "type", "session_id");
CREATE INDEX "top_banner_events_banner_id_type_created_at_idx" ON "top_banner_events"("banner_id", "type", "created_at");
ALTER TABLE "top_banners" ADD CONSTRAINT "top_banners_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "top_banner_events" ADD CONSTRAINT "top_banner_events_banner_id_fkey" FOREIGN KEY ("banner_id") REFERENCES "top_banners"("id") ON DELETE CASCADE ON UPDATE CASCADE;
