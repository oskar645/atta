-- Commit the metadata change before backfill: ADD COLUMN's ACCESS EXCLUSIVE
-- lock must not block readers for the duration of historical matching.
BEGIN;
ALTER TABLE "promotions" ADD COLUMN "raise_campaign_id" UUID;
ALTER TABLE "promotions" ADD CONSTRAINT "promotions_raise_campaign_id_fkey"
FOREIGN KEY ("raise_campaign_id") REFERENCES "listing_raise_campaigns"("id")
ON DELETE SET NULL ON UPDATE CASCADE NOT VALID;
COMMIT;

-- One statement / snapshot: count ALL candidates before filtering either side.
-- A slot is (campaign_id, slot_number), not just campaign_id: a campaign may
-- legitimately have multiple executed raises. Ambiguous legacy rows stay NULL.
-- Failure rolls back the entire backfill, though the additive schema remains.
BEGIN;
WITH candidates AS (
  SELECT p."id" AS promotion_id, c."id" AS campaign_id, slot.n AS slot_number
  FROM "promotions" p
  JOIN "listing_raise_campaigns" c
    ON c."listing_id" = p."listing_id" AND c."user_id" = p."user_id"
    AND c."price_per_raise" = p."cost_bonus"
    AND p."created_at" >= c."created_at"
  JOIN LATERAL generate_series(0, c."completed_raises" - 1) AS slot(n)
    ON p."starts_at" = c."started_at" + slot.n * INTERVAL '24 hours'
  WHERE p."type" = 'BUMP'
), counted AS (
  SELECT *,
    COUNT(*) OVER (PARTITION BY promotion_id) AS promotion_candidates,
    COUNT(*) OVER (PARTITION BY campaign_id, slot_number) AS slot_candidates
  FROM candidates
)
UPDATE "promotions" p SET "raise_campaign_id" = links.campaign_id
FROM counted links
WHERE p."id" = links.promotion_id
  AND links.promotion_candidates = 1 AND links.slot_candidates = 1;
COMMIT;

-- Historical campaign cancellation is deliberately deferred to a separately
-- reviewed cleanup; this migration never changes campaign status or scheduling.
-- Ordinary index creation allows reads but blocks writes while building. Assess
-- production size / maintenance window before deployment; no concurrent index
-- command is hidden inside a transaction here.
CREATE INDEX "promotions_raise_campaign_id_idx" ON "promotions"("raise_campaign_id");
ALTER TABLE "promotions" VALIDATE CONSTRAINT "promotions_raise_campaign_id_fkey";
