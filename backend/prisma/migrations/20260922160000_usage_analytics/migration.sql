-- Additive only. No fabricated history and no changes to public listing views.
CREATE TABLE "analytics_guest_days" (
  "guest_id" UUID NOT NULL,
  "day" DATE NOT NULL,
  CONSTRAINT "analytics_guest_days_pkey" PRIMARY KEY ("guest_id", "day")
);
CREATE INDEX "analytics_guest_days_day_guest_id_idx" ON "analytics_guest_days" ("day", "guest_id");
CREATE TABLE "analytics_listing_opens" (
  "event_id" UUID NOT NULL PRIMARY KEY,
  "listing_id" UUID NOT NULL,
  "registered" BOOLEAN NOT NULL,
  "opened_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "analytics_listing_opens_registered_opened_at_idx" ON "analytics_listing_opens" ("registered", "opened_at");
-- Prisma submits this multi-statement script as one query; PostgreSQL runs it
-- in an implicit transaction, which does not allow CREATE INDEX CONCURRENTLY.
-- A regular index keeps the migration atomic. Unlike the new analytics tables,
-- chat_messages contains existing data: reads continue, but writes wait until
-- the transaction commits. Assess its size and schedule accordingly before deploy.
CREATE INDEX IF NOT EXISTS "chat_messages_created_at_chat_id_idx" ON "chat_messages" ("created_at", "chat_id");
