CREATE TABLE "zero_result_searches" (
  "id" UUID NOT NULL,
  "query" TEXT NOT NULL,
  "normalized_query" TEXT NOT NULL,
  "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "zero_result_searches_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "zero_result_searches_created_at_idx"
  ON "zero_result_searches"("created_at");
CREATE INDEX "zero_result_searches_normalized_query_created_at_idx"
  ON "zero_result_searches"("normalized_query", "created_at");
