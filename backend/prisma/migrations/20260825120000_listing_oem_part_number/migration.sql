ALTER TABLE "listings"
  ADD COLUMN "oem_part_number" TEXT,
  ADD COLUMN "oem_part_number_normalized" TEXT;

CREATE INDEX "listings_oem_part_number_normalized_idx"
  ON "listings"("oem_part_number_normalized");
