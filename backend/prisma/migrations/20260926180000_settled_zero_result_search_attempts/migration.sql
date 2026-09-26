ALTER TABLE "zero_result_searches"
  ADD COLUMN "attempt_id" UUID,
  ADD COLUMN "updated_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

UPDATE "zero_result_searches" SET "attempt_id" = "id" WHERE "attempt_id" IS NULL;

ALTER TABLE "zero_result_searches" ALTER COLUMN "attempt_id" SET NOT NULL;

CREATE UNIQUE INDEX "zero_result_searches_attempt_id_key"
  ON "zero_result_searches"("attempt_id");
