ALTER TABLE "users" ADD COLUMN "push_notifications_enabled" BOOLEAN NOT NULL DEFAULT true;

CREATE TABLE "search_attempts" (
  "id" UUID NOT NULL,
  "attempt_id" UUID NOT NULL,
  "query" TEXT NOT NULL,
  "normalized_query" TEXT NOT NULL,
  "result_count" INTEGER NOT NULL,
  "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "search_attempts_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "search_attempts_attempt_id_key" ON "search_attempts"("attempt_id");
CREATE INDEX "search_attempts_created_at_idx" ON "search_attempts"("created_at");
CREATE INDEX "search_attempts_normalized_query_created_at_idx" ON "search_attempts"("normalized_query", "created_at");

INSERT INTO "search_attempts" ("id", "attempt_id", "query", "normalized_query", "result_count", "created_at", "updated_at")
SELECT "id", "attempt_id", "query", "normalized_query", 0, "created_at", "updated_at"
FROM "zero_result_searches";

CREATE TABLE "deleted_user_identities" (
  "user_id" UUID NOT NULL,
  "display_name" TEXT NOT NULL,
  "phone" TEXT,
  "deleted_at" TIMESTAMPTZ(3) NOT NULL,
  CONSTRAINT "deleted_user_identities_pkey" PRIMARY KEY ("user_id")
);
