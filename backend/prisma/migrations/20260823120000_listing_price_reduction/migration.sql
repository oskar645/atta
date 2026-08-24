ALTER TABLE "listings"
  ADD COLUMN "previous_price" BIGINT,
  ADD COLUMN "price_reduced_at" TIMESTAMP(3);
